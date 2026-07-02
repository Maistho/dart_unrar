import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'unrar_exception.dart';
import 'archive_entry.dart';
import 'unrar_bindings.dart' as bindings;
import 'unrar_bindings_ex.dart' as ex;

// ---------------------------------------------------------------------------
// Module-level callback state
// ---------------------------------------------------------------------------

final _pendingData = <int, _Buffer>{};
int _nextId = 0;

class _Buffer {
  final List<int> _data;
  int _offset = 0;
  final bool _isFixed;

  _Buffer.fixed(int size)
      : _data = List<int>.filled(size, 0, growable: true),
        _isFixed = true;

  _Buffer() : _data = <int>[], _isFixed = false;

  void addChunk(List<int> chunk) {
    final end = _offset + chunk.length;
    if (_isFixed && end <= _data.length) {
      _data.setRange(_offset, end, chunk);
      _offset = end;
    } else {
      _data.addAll(chunk);
      _offset = _data.length;
    }
  }

  Uint8List toBytes() {
    if (_offset == 0) return Uint8List(0);
    return Uint8List.fromList(
      _offset == _data.length ? _data : _data.sublist(0, _offset),
    );
  }
}

int _unrarCallback(int msg, int userData, int p1, int p2) {
  switch (msg) {
    case 1: // UCM_PROCESSDATA
      final buf = _pendingData[userData];
      if (buf != null) {
        final ptr = Pointer<Uint8>.fromAddress(p1);
        buf.addChunk(ptr.asTypedList(p2));
      }
      return 0;

    case 0: // UCM_CHANGEVOLUME
      // p2 = RAR_VOL_ASK (0) or RAR_VOL_NOTIFY (1).
      // For ASK: return 1 to accept the library's suggested next-volume path.
      // For NOTIFY: return 0 (informational only).
      return p2 == bindings.RAR_VOL_ASK ? 1 : 0;

    case 2: // UCM_NEEDPASSWORD
      // Password requested interactively via callback — cannot supply it here.
      // Callers should pass a password via the password parameter instead.
      return -1;

    case 5: // UCM_LARGEDICT
      // Consent to using a large dictionary (>128 MB).
      return 1;

    default: // UCM_CHANGEVOLUMEW (3), UCM_NEEDPASSWORDW (4)
      return 0;
  }
}

final _nativeCallback =
    Pointer.fromFunction<bindings.UNRARCALLBACKFunction>(_unrarCallback, 0);

// ---------------------------------------------------------------------------
// UnrarExtractor
// ---------------------------------------------------------------------------

/// High-level interface for extracting RAR archives.
class UnrarExtractor {
  static DynamicLibrary? _dylib;

  static DynamicLibrary get _lib {
    if (_dylib != null) return _dylib!;

    final possiblePaths = <String>[];
    void addPath(String path) {
      if (!possiblePaths.contains(path)) possiblePaths.add(path);
    }

    final libName = _libraryFileName();

    final envPath = Platform.environment['UNRAR_LIBRARY_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      final envAsDir = Directory(envPath);
      addPath(envAsDir.existsSync() ? _join(envAsDir.path, libName) : envPath);
    }

    addPath(_join('.dart_tool/lib', libName));
    addPath(libName);

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    addPath(_join(exeDir, libName));
    addPath(_join(_join(exeDir, '..'), _join('lib', libName)));

    if (Platform.isMacOS) {
      final frameworksDir = _join(File(exeDir).parent.path, 'Frameworks');
      addPath(_join(frameworksDir, 'unrar.framework', 'unrar'));
    }

    if (Platform.script.isScheme('file')) {
      final scriptDir = File(Platform.script.toFilePath()).parent.path;
      addPath(_join(scriptDir, libName));
      addPath(_join(_join(scriptDir, '..'), _join('lib', libName)));
    }

    final attempted = <String>[];
    final errors = <String>[];
    for (final path in possiblePaths) {
      attempted.add(path);
      try {
        _dylib = DynamicLibrary.open(path);

        // Validate DLL version before use.
        final getVersion =
            _dylib!.lookupFunction<Int32 Function(), int Function()>(
          'RARGetDllVersion',
        );
        final version = getVersion();
        if (version < bindings.RAR_DLL_VERSION) {
          _dylib = null;
          throw UnrarException(
            'Loaded unrar library version $version is older than the '
            'required version ${bindings.RAR_DLL_VERSION}. '
            'Please rebuild with "dart build".',
          );
        }

        return _dylib!;
      } catch (e) {
        if (e is UnrarException) rethrow;
        errors.add('$path => $e');
      }
    }

    final debug = Platform.environment['UNRAR_DEBUG'] == '1';
    final attemptedPaths = possiblePaths.join(', ');
    final msg = StringBuffer(
      'Failed to load native unrar library. '
      'Please run "dart build" to build the library. '
      'Attempted paths: $attemptedPaths',
    );
    if (debug) {
      msg.writeln();
      for (final p in attempted) {
        final exists = File(p).existsSync();
        msg.writeln('- $p ${exists ? '(exists)' : '(missing)'}');
      }
      if (errors.isNotEmpty) {
        msg.writeln('dlopen errors:');
        for (final err in errors) {
          msg.writeln('- $err');
        }
      }
      if (envPath != null) msg.writeln('UNRAR_LIBRARY_PATH=$envPath');
      msg.writeln('Executable dir: ${File(Platform.resolvedExecutable).parent.path}');
      if (Platform.script.isScheme('file')) {
        msg.writeln('Script dir: ${File(Platform.script.toFilePath()).parent.path}');
      }
    }
    throw UnrarException(msg.toString());
  }

  static String _libraryFileName() {
    if (Platform.isMacOS) return 'libunrar.dylib';
    if (Platform.isLinux) return 'libunrar.so';
    if (Platform.isWindows) return 'unrar.dll';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static String _join(String base, String name, [String? third]) {
    if (base.isEmpty) return name;
    final sep = Platform.pathSeparator;
    final normalizedBase =
        base.endsWith(sep) ? base.substring(0, base.length - 1) : base;
    final joined = '$normalizedBase$sep$name';
    return third != null ? '$joined$sep$third' : joined;
  }

  // -------------------------------------------------------------------------
  // FFI function bindings
  // -------------------------------------------------------------------------

  late final Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>)
      _rarOpenArchive = _lib.lookupFunction<
          Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>),
          Pointer<Void> Function(
              Pointer<bindings.RAROpenArchiveData>)>('RAROpenArchive');

  late final Pointer<Void> Function(Pointer<ex.RAROpenArchiveDataEx>)
      _rarOpenArchiveEx = _lib.lookupFunction<
          Pointer<Void> Function(Pointer<ex.RAROpenArchiveDataEx>),
          Pointer<Void> Function(
              Pointer<ex.RAROpenArchiveDataEx>)>('RAROpenArchiveEx');

  late final int Function(Pointer<Void>) _rarCloseArchive =
      _lib.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('RARCloseArchive');

  late final int Function(Pointer<Void>, Pointer<ex.RARHeaderDataEx>)
      _rarReadHeaderEx = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<ex.RARHeaderDataEx>),
          int Function(
              Pointer<Void>, Pointer<ex.RARHeaderDataEx>)>('RARReadHeaderEx');

  late final int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>)
      _rarProcessFile = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, int, Pointer<Utf8>,
              Pointer<Utf8>)>('RARProcessFile');

  late final void Function(Pointer<Void>, Pointer<Utf8>) _rarSetPassword =
      _lib.lookupFunction<Void Function(Pointer<Void>, Pointer<Utf8>),
          void Function(Pointer<Void>, Pointer<Utf8>)>('RARSetPassword');

  late final void Function(Pointer<Void>, bindings.UNRARCALLBACK, int)
      _rarSetCallback = _lib.lookupFunction<
          Void Function(Pointer<Void>, bindings.UNRARCALLBACK, Int64),
          void Function(Pointer<Void>, bindings.UNRARCALLBACK,
              int)>('RARSetCallback');

  // -------------------------------------------------------------------------
  // Constants (mirrored from bindings for convenience)
  // -------------------------------------------------------------------------

  static const int ERAR_END_ARCHIVE = bindings.ERAR_END_ARCHIVE;
  static const int ERAR_NO_MEMORY = bindings.ERAR_NO_MEMORY;
  static const int ERAR_BAD_DATA = bindings.ERAR_BAD_DATA;
  static const int ERAR_BAD_ARCHIVE = bindings.ERAR_BAD_ARCHIVE;
  static const int ERAR_UNKNOWN_FORMAT = bindings.ERAR_UNKNOWN_FORMAT;
  static const int ERAR_EOPEN = bindings.ERAR_EOPEN;
  static const int ERAR_ECREATE = bindings.ERAR_ECREATE;
  static const int ERAR_ECLOSE = bindings.ERAR_ECLOSE;
  static const int ERAR_EREAD = bindings.ERAR_EREAD;
  static const int ERAR_EWRITE = bindings.ERAR_EWRITE;
  static const int ERAR_SMALL_BUF = bindings.ERAR_SMALL_BUF;
  static const int ERAR_UNKNOWN = bindings.ERAR_UNKNOWN;
  static const int ERAR_MISSING_PASSWORD = bindings.ERAR_MISSING_PASSWORD;

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Converts a DOS date/time value to [DateTime].
  ///
  /// DOS format: bits 31-25 = year-1980, 24-21 = month, 20-16 = day,
  /// 15-11 = hour, 10-5 = minute, 4-0 = second/2.
  static DateTime _dosTimeToDateTime(int dosTime) {
    if (dosTime == 0) return DateTime.utc(1980);
    final year = 1980 + ((dosTime >> 25) & 0x7F);
    final month = (dosTime >> 21) & 0x0F;
    final day = (dosTime >> 16) & 0x1F;
    final hour = (dosTime >> 11) & 0x1F;
    final minute = (dosTime >> 5) & 0x3F;
    final second = (dosTime & 0x1F) * 2;
    return DateTime.utc(
      year,
      month.clamp(1, 12),
      day.clamp(1, 31),
      hour,
      minute,
      second,
    );
  }

  /// Builds an [ArchiveEntry] from an extended header view.
  static ArchiveEntry _entryFromView(ex.RARHeaderDataExView v) {
    final flags = v.flags;
    final modTime = _dosTimeToDateTime(v.fileTime);
    final unpackedSize = v.unpSize + (v.unpSizeHigh * 0x100000000);
    final packedSize = v.packSize + (v.packSizeHigh * 0x100000000);

    return ArchiveEntry(
      name: v.fileName,
      size: unpackedSize,
      packedSize: packedSize,
      crc: v.fileCRC,
      attributes: v.fileAttr,
      modificationTime: modTime,
      isDirectory: (flags & bindings.RHDF_DIRECTORY) != 0,
      isEncrypted: (flags & bindings.RHDF_ENCRYPTED) != 0,
      isSplitBefore: (flags & bindings.RHDF_SPLITBEFORE) != 0,
      isSplitAfter: (flags & bindings.RHDF_SPLITAFTER) != 0,
      isSolid: (flags & bindings.RHDF_SOLID) != 0,
      hashType: v.hashType,
    );
  }

  void _setPassword(Pointer<Void> handle, String? password) {
    if (password != null) {
      final passwordPtr = password.toNativeUtf8();
      try {
        _rarSetPassword(handle, passwordPtr);
      } finally {
        calloc.free(passwordPtr);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns archive-level metadata without reading individual file headers.
  ///
  /// Uses [RAROpenArchiveEx] to read archive flags (solid, volume, encrypted
  /// headers, etc.) without enumerating entries.
  ///
  /// Throws [UnrarException] if the archive cannot be opened.
  ex.ArchiveInfo archiveInfo(String archivePath, {String? password}) {
    final archiveData = calloc<ex.RAROpenArchiveDataEx>();
    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.ArcNameW = nullptr;
        archiveData.ref.OpenMode = bindings.RAR_OM_LIST;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;
        archiveData.ref.Callback = nullptr;
        archiveData.ref.UserData = 0;
        archiveData.ref.OpFlags = 0;

        final handle = _rarOpenArchiveEx(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }
        try {
          _setPassword(handle, password);
          return ex.ArchiveInfo.fromFlags(archiveData.ref.Flags);
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }
  }

  /// Lists all entries in a RAR archive.
  ///
  /// Returns a list of [ArchiveEntry] objects with full metadata including
  /// encryption, split, and solid flags. Filenames up to 1024 characters.
  ///
  /// Throws [UnrarException] if the archive cannot be opened or read.
  List<ArchiveEntry> listFiles(String archivePath, {String? password}) {
    final entries = <ArchiveEntry>[];
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_LIST;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          _setPassword(handle, password);

          final headerData = ex.RARHeaderDataExView.allocate();
          try {
            while (true) {
              final result = _rarReadHeaderEx(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              entries.add(_entryFromView(ex.RARHeaderDataExView.fromOpaque(headerData)));

              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_SKIP,
                nullptr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }

    return entries;
  }

  /// Extracts all files from a RAR archive to [outputPath].
  ///
  /// [password]: Optional password for encrypted archives.
  ///
  /// Throws [UnrarException] if extraction fails.
  void extractAll(String archivePath, String outputPath, {String? password}) {
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          _setPassword(handle, password);
          _rarSetCallback(handle, _nativeCallback, 0);

          final headerData = ex.RARHeaderDataExView.allocate();
          final destPathPtr = outputPath.toNativeUtf8();
          try {
            while (true) {
              final result = _rarReadHeaderEx(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_EXTRACT,
                destPathPtr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(destPathPtr);
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }
  }

  /// Extracts a single file from a RAR archive and returns its contents.
  ///
  /// [fileName]: Name of the file as it appears in the archive listing.
  /// [password]: Optional password for encrypted archives.
  ///
  /// Returns the file contents as a [Uint8List].
  /// Throws [UnrarException] if the file is not found or extraction fails.
  Uint8List extractFile(
    String archivePath,
    String fileName, {
    String? password,
  }) {
    final tempDir = Directory.systemTemp.createTempSync('unrar_');
    try {
      final tempOutputPath = tempDir.path;
      final archiveData = calloc<bindings.RAROpenArchiveData>();
      try {
        final archiveNamePtr = archivePath.toNativeUtf8();
        try {
          archiveData.ref.ArcName = archiveNamePtr.cast();
          archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
          archiveData.ref.CmtBuf = nullptr;
          archiveData.ref.CmtBufSize = 0;

          final handle = _rarOpenArchive(archiveData);
          if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
            throw UnrarException(
              _getErrorMessage(archiveData.ref.OpenResult),
              archiveData.ref.OpenResult,
            );
          }

          try {
            _setPassword(handle, password);
            _rarSetCallback(handle, _nativeCallback, 0);

            final headerData = ex.RARHeaderDataExView.allocate();
            final destPathPtr = tempOutputPath.toNativeUtf8();
            try {
              var found = false;
              while (true) {
                final result = _rarReadHeaderEx(handle, headerData);
                if (result == bindings.ERAR_END_ARCHIVE) break;
                if (result != bindings.ERAR_SUCCESS) {
                  throw UnrarException(_getErrorMessage(result), result);
                }

                final view = ex.RARHeaderDataExView.fromOpaque(headerData);
                final currentFileName = view.fileName;

                if (currentFileName == fileName) {
                  found = true;
                  final processResult = _rarProcessFile(
                    handle,
                    bindings.RAR_EXTRACT,
                    destPathPtr,
                    nullptr,
                  );
                  if (processResult != bindings.ERAR_SUCCESS) {
                    throw UnrarException(
                      _getErrorMessage(processResult),
                      processResult,
                    );
                  }
                  break;
                } else {
                  final processResult = _rarProcessFile(
                    handle,
                    bindings.RAR_SKIP,
                    nullptr,
                    nullptr,
                  );
                  if (processResult != bindings.ERAR_SUCCESS) {
                    throw UnrarException(
                      _getErrorMessage(processResult),
                      processResult,
                    );
                  }
                }
              }

              if (!found) {
                throw UnrarException('File not found in archive: $fileName');
              }

              final extractedFile = File('$tempOutputPath/$fileName');
              if (!extractedFile.existsSync()) {
                throw UnrarException('Failed to extract file: $fileName');
              }
              return extractedFile.readAsBytesSync();
            } finally {
              calloc.free(destPathPtr);
              calloc.free(headerData);
            }
          } finally {
            _rarCloseArchive(handle);
          }
        } finally {
          calloc.free(archiveNamePtr);
        }
      } finally {
        calloc.free(archiveData);
      }
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  /// Extracts a single file directly to memory without writing to disk.
  ///
  /// [password]: Optional password for encrypted archives.
  ///
  /// Returns the file contents as a [Uint8List].
  /// Throws [UnrarException] if the file is not found or extraction fails.
  Uint8List extractFileToMemory(
    String archivePath,
    String fileName, {
    String? password,
  }) {
    final id = _nextId++;
    final archiveData = calloc<bindings.RAROpenArchiveData>();
    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          _setPassword(handle, password);
          _rarSetCallback(handle, _nativeCallback, id);

          final headerData = ex.RARHeaderDataExView.allocate();
          try {
            while (true) {
              final result = _rarReadHeaderEx(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final view = ex.RARHeaderDataExView.fromOpaque(headerData);
              final currentFileName = view.fileName;

              if (currentFileName == fileName) {
                final unpSize = view.unpSize + (view.unpSizeHigh * 0x100000000);
                _pendingData[id] =
                    unpSize > 0 ? _Buffer.fixed(unpSize) : _Buffer();

                final processResult = _rarProcessFile(
                  handle,
                  bindings.RAR_TEST,
                  nullptr,
                  nullptr,
                );
                if (processResult != bindings.ERAR_SUCCESS) {
                  _pendingData.remove(id);
                  throw UnrarException(
                    _getErrorMessage(processResult),
                    processResult,
                  );
                }
                final resultData = _pendingData[id]!.toBytes();
                _pendingData.remove(id);
                return resultData;
              } else {
                final processResult = _rarProcessFile(
                  handle,
                  bindings.RAR_SKIP,
                  nullptr,
                  nullptr,
                );
                if (processResult != bindings.ERAR_SUCCESS) {
                  throw UnrarException(
                    _getErrorMessage(processResult),
                    processResult,
                  );
                }
              }
            }
            _pendingData.remove(id);
            throw UnrarException('File not found in archive: $fileName');
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      _pendingData.remove(id);
      calloc.free(archiveData);
    }
  }

  /// Extracts all files from a RAR archive directly to memory.
  ///
  /// Directories are skipped. Returns a map of filename → decompressed bytes.
  /// [password]: Optional password for encrypted archives.
  ///
  /// Throws [UnrarException] if extraction fails.
  Map<String, Uint8List> extractAllToMemory(
    String archivePath, {
    String? password,
  }) {
    final id = _nextId++;
    final archiveData = calloc<bindings.RAROpenArchiveData>();
    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          _setPassword(handle, password);
          _rarSetCallback(handle, _nativeCallback, id);

          final headerData = ex.RARHeaderDataExView.allocate();
          try {
            final results = <String, Uint8List>{};
            while (true) {
              final result = _rarReadHeaderEx(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final view = ex.RARHeaderDataExView.fromOpaque(headerData);
              final currentFileName = view.fileName;
              final isDirectory =
                  (view.flags & bindings.RHDF_DIRECTORY) != 0;

              if (isDirectory) {
                _rarProcessFile(handle, bindings.RAR_SKIP, nullptr, nullptr);
              } else {
                final unpSize = view.unpSize + (view.unpSizeHigh * 0x100000000);
                _pendingData[id] =
                    unpSize > 0 ? _Buffer.fixed(unpSize) : _Buffer();

                final processResult = _rarProcessFile(
                  handle,
                  bindings.RAR_TEST,
                  nullptr,
                  nullptr,
                );
                if (processResult != bindings.ERAR_SUCCESS) {
                  _pendingData.remove(id);
                  throw UnrarException(
                    _getErrorMessage(processResult),
                    processResult,
                  );
                }
                results[currentFileName] = _pendingData[id]!.toBytes();
              }
            }
            _pendingData.remove(id);
            return results;
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      _pendingData.remove(id);
      calloc.free(archiveData);
    }
  }

  /// Tests a RAR archive for integrity.
  ///
  /// Returns `true` if the archive passes verification.
  /// Throws [UnrarException] if the archive is corrupted or cannot be opened.
  bool testArchive(String archivePath, {String? password}) {
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          _setPassword(handle, password);

          final headerData = ex.RARHeaderDataExView.allocate();
          try {
            while (true) {
              final result = _rarReadHeaderEx(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_TEST,
                nullptr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }

    return true;
  }

  // -------------------------------------------------------------------------
  // Error mapping
  // -------------------------------------------------------------------------

  String _getErrorMessage(int errorCode) {
    switch (errorCode) {
      case bindings.ERAR_NO_MEMORY:
        return 'Not enough memory';
      case bindings.ERAR_BAD_DATA:
        return 'Archive header or data is broken';
      case bindings.ERAR_BAD_ARCHIVE:
        return 'File is not a valid RAR archive';
      case bindings.ERAR_UNKNOWN_FORMAT:
        return 'Unknown archive format';
      case bindings.ERAR_EOPEN:
        return 'Cannot open file';
      case bindings.ERAR_ECREATE:
        return 'Cannot create file';
      case bindings.ERAR_ECLOSE:
        return 'Cannot close file';
      case bindings.ERAR_EREAD:
        return 'Read error';
      case bindings.ERAR_EWRITE:
        return 'Write error';
      case bindings.ERAR_SMALL_BUF:
        return 'Buffer too small';
      case bindings.ERAR_MISSING_PASSWORD:
        return 'Password required';
      case bindings.ERAR_EREFERENCE:
        return 'Cannot open file reference';
      case bindings.ERAR_BAD_PASSWORD:
        return 'Wrong password';
      case bindings.ERAR_LARGE_DICT:
        return 'Need larger dictionary size';
      case bindings.ERAR_UNKNOWN:
      default:
        return 'Unknown error (code: $errorCode)';
    }
  }
}
