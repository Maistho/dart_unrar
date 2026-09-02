// ignore_for_file: camel_case_types, non_constant_identifier_names

// Manually maintained bindings for RARHeaderDataEx and RAROpenArchiveDataEx.
//
// RARHeaderDataEx contains wchar_t arrays whose element size is
// platform-specific:
//   - macOS / Linux (Unix): wchar_t = 4 bytes
//   - Windows:              wchar_t = 2 bytes
//
// Because Dart FFI struct field types must be compile-time constants,
// we cannot use a single ffi.Struct subclass that works on both platforms.
// Instead, RARHeaderDataEx is declared as ffi.Opaque (matching the
// auto-generated stub) and field access goes through RARHeaderDataExView,
// which computes byte offsets at runtime using Platform.isWindows.
//
// RAROpenArchiveDataEx contains only pointer fields (no wchar_t arrays),
// so its layout is identical on all 64-bit platforms and is defined as a
// normal ffi.Struct below.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart' show calloc;
import 'unrar_bindings.dart' as b;

// ---------------------------------------------------------------------------
// RARHeaderDataEx — opaque marker + platform-aware view
// ---------------------------------------------------------------------------

/// Opaque marker for the native RARHeaderDataEx struct.
///
/// Allocate with [RARHeaderDataExView.allocate] and access fields through
/// [RARHeaderDataExView]. Do not allocate with `calloc<RARHeaderDataEx>()`
/// (Opaque types have no compile-time size).
final class RARHeaderDataEx extends ffi.Opaque {}

/// Platform-aware field accessor for the native RARHeaderDataEx struct.
///
/// Handles the wchar_t size difference between platforms by computing byte
/// offsets at runtime:
///
///   Platform  | wchar_t | struct size
///   ----------|---------|------------
///   Unix      | 4 bytes | 14,340 bytes
///   Windows   | 2 bytes | 10,244 bytes
///
/// Struct layout (with #pragma pack(1)):
///
///   [0]                ArcName[1024]      char[1024]
///   [1024]             ArcNameW[1024]     wchar_t[1024]  (2048 or 4096 bytes)
///   [3072 / 5120]      FileName[1024]     char[1024]
///   [4096 / 6144]      FileNameW[1024]    wchar_t[1024]  (2048 or 4096 bytes)
///   [6144 / 10240]     Flags              unsigned int
///   [6148 / 10244]     PackSize           unsigned int
///   [6152 / 10248]     PackSizeHigh       unsigned int
///   [6156 / 10252]     UnpSize            unsigned int
///   [6160 / 10256]     UnpSizeHigh        unsigned int
///   [6164 / 10260]     HostOS             unsigned int
///   [6168 / 10264]     FileCRC            unsigned int
///   [6172 / 10268]     FileTime           unsigned int   (DOS date/time)
///   [6176 / 10272]     UnpVer             unsigned int
///   [6180 / 10276]     Method             unsigned int
///   [6184 / 10280]     FileAttr           unsigned int
///   [6188 / 10284]     CmtBuf*            pointer (8 bytes)
///   [6196 / 10292]     CmtBufSize         unsigned int
///   [6200 / 10296]     CmtSize            unsigned int
///   [6204 / 10300]     CmtState           unsigned int
///   [6208 / 10304]     DictSize           unsigned int
///   [6212 / 10308]     HashType           unsigned int   (0=none 1=CRC32 2=Blake2)
///   [6216 / 10312]     Hash[32]           char[32]
///   [6248 / 10344]     RedirType          unsigned int
///   [6252 / 10348]     RedirName*         pointer (8 bytes)
///   [6260 / 10356]     RedirNameSize      unsigned int
///   [6264 / 10360]     DirTarget          unsigned int
///   [6268 / 10364]     MtimeLow           unsigned int
///   [6272 / 10368]     MtimeHigh          unsigned int
///   [6276 / 10372]     CtimeLow           unsigned int
///   [6280 / 10376]     CtimeHigh          unsigned int
///   [6284 / 10380]     AtimeLow           unsigned int
///   [6288 / 10384]     AtimeHigh          unsigned int
///   [6292 / 10388]     ArcNameEx*         pointer (8 bytes)
///   [6300 / 10396]     ArcNameExSize      unsigned int
///   [6304 / 10400]     FileNameEx*        pointer (8 bytes)
///   [6308 / 10408]     FileNameExSize     unsigned int
///   [6312 / 10412]     Reserved[982]      unsigned int[982] = 3928 bytes
///   Total:             10,244 bytes (Windows) / 14,340 bytes (Unix)
class RARHeaderDataExView {
  /// bytes per wchar_t character: 2 on Windows, 4 on Unix.
  static final int _wcharSize = Platform.isWindows ? 2 : 4;

  // Offset of FileName[] (char[1024]) within the native struct.
  // Layout before it: ArcName[1024] + ArcNameW[1024*w]
  static final int _fileNameOff = 1024 + 1024 * _wcharSize;

  // Offset of the first fixed field (Flags) after the four char/wchar arrays.
  // Layout before it: ArcName + ArcNameW + FileName + FileNameW
  static final int _fixedOff = _fileNameOff + 1024 + 1024 * _wcharSize;

  // Offsets of fixed fields relative to _fixedOff — identical on all platforms.
  // (All are uint32 or pointer-sized and happen to fall at 4-byte aligned offsets.)
  static const int _oFlags = 0;
  static const int _oPackSize = 4;
  static const int _oPackSizeHigh = 8;
  static const int _oUnpSize = 12;
  static const int _oUnpSizeHigh = 16;
  static const int _oFileCRC = 24;
  static const int _oFileTime = 28;
  static const int _oFileAttr = 40;
  // CmtBuf* (pointer, 8 bytes) at +44
  static const int _oHashType = 68; // after CmtBuf*(8)+CmtBufSize+CmtSize+CmtState+DictSize
  static const int _oMtimeLow = 124;
  static const int _oMtimeHigh = 128;

  /// Size in bytes to allocate for the native struct on the current platform.
  ///
  ///   Windows: 10,244 bytes  (wchar_t = 2)
  ///   Unix:    14,340 bytes  (wchar_t = 4)
  static final int structSize = _fixedOff + 4100;

  // 4100 = total bytes of the fixed-field region after the four arrays:
  // 11×4 (uint32s before CmtBuf) + 8 (CmtBuf*) + 4×4 (Cmt*/Dict) +
  // 4 (HashType) + 32 (Hash) + 4 (RedirType) + 8 (RedirName*) +
  // 8 (RedirNameSize+DirTarget) + 6×4 (timestamps) + 8 (ArcNameEx*) +
  // 4+8+4 (ArcNameExSize+FileNameEx*+FileNameExSize) + 982×4 (Reserved)
  // = 44+8+20+32+4+8+8+24+8+4+8+4+3928 = 4100

  final ffi.Pointer<ffi.Uint8> _p;

  RARHeaderDataExView.fromOpaque(ffi.Pointer<RARHeaderDataEx> ptr)
      : _p = ptr.cast<ffi.Uint8>();

  // ---- little-endian field readers ----------------------------------------

  int _u32(int absOff) =>
      _p[absOff] |
      (_p[absOff + 1] << 8) |
      (_p[absOff + 2] << 16) |
      (_p[absOff + 3] << 24);

  // ---- public field accessors ----------------------------------------------

  /// UTF-8 null-terminated file name (up to 1024 chars).
  String get fileName {
    final bytes = <int>[];
    for (var i = 0; i < 1024; i++) {
      final b = _p[_fileNameOff + i];
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Per-file flags (RHDF_* bitmask).
  int get flags => _u32(_fixedOff + _oFlags);

  int get packSize => _u32(_fixedOff + _oPackSize);
  int get packSizeHigh => _u32(_fixedOff + _oPackSizeHigh);
  int get unpSize => _u32(_fixedOff + _oUnpSize);
  int get unpSizeHigh => _u32(_fixedOff + _oUnpSizeHigh);

  /// CRC32 (or Blake2 if hashType == 2).
  int get fileCRC => _u32(_fixedOff + _oFileCRC);

  /// Modification time in DOS date/time format.
  int get fileTime => _u32(_fixedOff + _oFileTime);

  /// OS-specific file attributes.
  int get fileAttr => _u32(_fixedOff + _oFileAttr);

  /// Hash algorithm: 0 = none, 1 = CRC32, 2 = Blake2.
  int get hashType => _u32(_fixedOff + _oHashType);

  /// Low 32 bits of Windows FILETIME modification timestamp (100-ns since 1601).
  int get mtimeLow => _u32(_fixedOff + _oMtimeLow);

  /// High 32 bits of Windows FILETIME modification timestamp.
  int get mtimeHigh => _u32(_fixedOff + _oMtimeHigh);

  // ---- allocation helpers -------------------------------------------------

  /// Allocates a zeroed native buffer of the correct platform-specific size.
  ///
  /// Caller must free with `calloc.free(ptr)`.
  static ffi.Pointer<RARHeaderDataEx> allocate() {
    // Use calloc<ffi.Uint8>(structSize) to allocate exactly the right bytes,
    // then cast to the opaque type for use with RARReadHeaderEx.
    final raw = calloc<ffi.Uint8>(structSize);
    return raw.cast<RARHeaderDataEx>();
  }
}

// ---------------------------------------------------------------------------
// RAROpenArchiveDataEx — concrete struct (same layout on all 64-bit platforms)
// ---------------------------------------------------------------------------

/// Extended archive open data for RAROpenArchiveEx.
///
/// Layout (64-bit, #pragma pack(1)):
///   [0]   ArcName*         char* (8 bytes)
///   [8]   ArcNameW*        void* (8 bytes) — wchar_t*
///   [16]  OpenMode         unsigned int
///   [20]  OpenResult       unsigned int
///   [24]  CmtBuf*          char* (8 bytes)
///   [32]  CmtBufSize       unsigned int
///   [36]  CmtSize          unsigned int
///   [40]  CmtState         unsigned int
///   [44]  Flags            unsigned int  ← ROADF_* bits set by RAROpenArchiveEx
///   [48]  Callback*        void* (8 bytes)
///   [56]  UserData         long
///           Unix 64-bit:   8 bytes (long = 64-bit)
///           Windows 64-bit: 4 bytes (long = 32-bit on Windows even with /LP64)
///   [64/60] OpFlags        unsigned int
///   ...
///
/// Note: On Windows, `long` is 4 bytes (not 8), so fields after UserData
/// shift by 4 bytes. The struct below targets Unix. Windows support requires
/// a separate layout (tracked in Gap_analysis_dll_vs_dart.md Gap 8).
@ffi.Packed(1)
final class RAROpenArchiveDataEx extends ffi.Struct {
  external ffi.Pointer<ffi.Char> ArcName;

  external ffi.Pointer<ffi.Void> ArcNameW; // wchar_t*

  @ffi.UnsignedInt()
  external int OpenMode;

  @ffi.UnsignedInt()
  external int OpenResult;

  external ffi.Pointer<ffi.Char> CmtBuf;

  @ffi.UnsignedInt()
  external int CmtBufSize;

  @ffi.UnsignedInt()
  external int CmtSize;

  @ffi.UnsignedInt()
  external int CmtState;

  /// Archive-level flags (ROADF_*). Populated by RAROpenArchiveEx after open.
  @ffi.UnsignedInt()
  external int Flags;

  external ffi.Pointer<ffi.Void> Callback; // UNRARCALLBACK — use RARSetCallback instead

  /// LPARAM UserData. On Unix 64-bit, `long` = 8 bytes.
  @ffi.Long()
  external int UserData;

  /// Optional flags (ROADOF_*). ROADOF_KEEPBROKEN = 1 to extract from damaged archives.
  @ffi.UnsignedInt()
  external int OpFlags;

  external ffi.Pointer<ffi.Void> CmtBufW; // wchar_t*

  external ffi.Pointer<ffi.Void> MarkOfTheWeb; // wchar_t*

  @ffi.Array.multi([23])
  external ffi.Array<ffi.Uint32> Reserved;
}

// ---------------------------------------------------------------------------
// ArchiveInfo — decoded from RAROpenArchiveDataEx.Flags
// ---------------------------------------------------------------------------

/// Archive-level metadata returned by [UnrarExtractor.archiveInfo].
class ArchiveInfo {
  const ArchiveInfo({
    required this.isVolume,
    required this.hasComment,
    required this.isSolid,
    required this.hasEncryptedHeaders,
    required this.isFirstVolume,
    required this.isLocked,
    required this.hasSigned,
    required this.hasRecovery,
  });

  /// Archive is part of a multi-volume set.
  final bool isVolume;

  /// Archive contains a comment.
  final bool hasComment;

  /// Archive uses solid compression.
  final bool isSolid;

  /// Archive headers are encrypted (password needed even for listing).
  final bool hasEncryptedHeaders;

  /// This is the first volume in a multi-volume set.
  final bool isFirstVolume;

  /// Archive is locked (protected against modification).
  final bool isLocked;

  /// Archive has an authenticity verification signature.
  final bool hasSigned;

  /// Archive contains a recovery record.
  final bool hasRecovery;

  factory ArchiveInfo.fromFlags(int flags) => ArchiveInfo(
        isVolume: (flags & b.ROADF_VOLUME) != 0,
        hasComment: (flags & b.ROADF_COMMENT) != 0,
        isSolid: (flags & b.ROADF_SOLID) != 0,
        hasEncryptedHeaders: (flags & b.ROADF_ENCHEADERS) != 0,
        isFirstVolume: (flags & b.ROADF_FIRSTVOLUME) != 0,
        isLocked: (flags & b.ROADF_LOCK) != 0,
        hasSigned: (flags & b.ROADF_SIGNED) != 0,
        hasRecovery: (flags & b.ROADF_RECOVERY) != 0,
      );

  @override
  String toString() => 'ArchiveInfo('
      'isVolume: $isVolume, '
      'isSolid: $isSolid, '
      'hasEncryptedHeaders: $hasEncryptedHeaders, '
      'isFirstVolume: $isFirstVolume)';
}
