# dart_unrar — Implementation Notes

## Overview

`dart_unrar` wraps the UnRAR C++ library via Dart FFI. It exposes six extraction
operations and one archive-metadata query. This document records implementation
decisions that are not obvious from reading the code, with particular emphasis on
the Dart–C boundary.

---

## wchar_t size is platform-specific

The most significant portability constraint.

- **Unix (macOS, Linux):** `wchar_t` is 4 bytes (UTF-32 code unit).
- **Windows:** `wchar_t` is 2 bytes (UTF-16 code unit).

The auto-generated `ffigen` bindings (`lib/src/unrar_bindings.dart`) mark
`RARHeaderDataEx` and `RAROpenArchiveDataEx` as `ffi.Opaque` because `ffigen`
cannot statically resolve `wchar_t` width. This makes both structs unusable for
field access.

`lib/src/unrar_bindings_ex.dart` provides manually written Dart `ffi.Struct`
subclasses for Unix. All `wchar_t` arrays are declared as
`ffi.Array<ffi.Uint32>` (4 bytes each) and all `wchar_t*` pointers as
`ffi.Pointer<ffi.Void>` (8 bytes on 64-bit). The struct is annotated
`@ffi.Packed(1)` to match the `#pragma pack(1)` in `dll.hpp`.

If Windows support is needed, a parallel `_win32` variant using `Uint16` for
`wchar_t` fields would be required.

---

## RARHeaderDataEx struct layout (Unix, #pragma pack(1))

Total: **14340 bytes**

| Offset | Field              | Type            | Bytes |
|-------:|--------------------|-----------------|------:|
|      0 | ArcName[1024]      | char[1024]      | 1024  |
|   1024 | ArcNameW[1024]     | wchar_t[1024]   | 4096  |
|   5120 | FileName[1024]     | char[1024]      | 1024  |
|   6144 | FileNameW[1024]    | wchar_t[1024]   | 4096  |
|  10240 | Flags              | unsigned int    |    4  |
|  10244 | PackSize           | unsigned int    |    4  |
|  10248 | PackSizeHigh       | unsigned int    |    4  |
|  10252 | UnpSize            | unsigned int    |    4  |
|  10256 | UnpSizeHigh        | unsigned int    |    4  |
|  10260 | HostOS             | unsigned int    |    4  |
|  10264 | FileCRC            | unsigned int    |    4  |
|  10268 | FileTime           | unsigned int    |    4  |
|  10272 | UnpVer             | unsigned int    |    4  |
|  10276 | Method             | unsigned int    |    4  |
|  10280 | FileAttr           | unsigned int    |    4  |
|  10284 | CmtBuf*            | pointer         |    8  |
|  10292 | CmtBufSize         | unsigned int    |    4  |
|  10296 | CmtSize            | unsigned int    |    4  |
|  10300 | CmtState           | unsigned int    |    4  |
|  10304 | DictSize           | unsigned int    |    4  |
|  10308 | HashType           | unsigned int    |    4  |
|  10312 | Hash[32]           | char[32]        |   32  |
|  10344 | RedirType          | unsigned int    |    4  |
|  10348 | RedirName*         | pointer         |    8  |
|  10356 | RedirNameSize      | unsigned int    |    4  |
|  10360 | DirTarget          | unsigned int    |    4  |
|  10364 | MtimeLow           | unsigned int    |    4  |
|  10368 | MtimeHigh          | unsigned int    |    4  |
|  10372 | CtimeLow           | unsigned int    |    4  |
|  10376 | CtimeHigh          | unsigned int    |    4  |
|  10380 | AtimeLow           | unsigned int    |    4  |
|  10384 | AtimeHigh          | unsigned int    |    4  |
|  10388 | ArcNameEx*         | pointer         |    8  |
|  10396 | ArcNameExSize      | unsigned int    |    4  |
|  10400 | FileNameEx*        | pointer         |    8  |
|  10408 | FileNameExSize     | unsigned int    |    4  |
|  10412 | Reserved[982]      | unsigned int[]  | 3928  |
| **14340** |                 |                 |       |

---

## RAROpenArchiveDataEx struct layout (Unix, #pragma pack(1))

Total: **176 bytes**

| Offset | Field           | Type          | Bytes |
|-------:|-----------------|---------------|------:|
|      0 | ArcName*        | char*         |    8  |
|      8 | ArcNameW*       | void*         |    8  |
|     16 | OpenMode        | unsigned int  |    4  |
|     20 | OpenResult      | unsigned int  |    4  |
|     24 | CmtBuf*         | char*         |    8  |
|     32 | CmtBufSize      | unsigned int  |    4  |
|     36 | CmtSize         | unsigned int  |    4  |
|     40 | CmtState        | unsigned int  |    4  |
|     44 | Flags           | unsigned int  |    4  |
|     48 | Callback*       | void*         |    8  |
|     56 | UserData        | long (64-bit) |    8  |
|     64 | OpFlags         | unsigned int  |    4  |
|     68 | CmtBufW*        | void*         |    8  |
|     76 | MarkOfTheWeb*   | void*         |    8  |
|     84 | Reserved[23]    | unsigned int[]|   92  |
|  **176** |               |               |       |

`Flags` is populated by UnRAR *after* `RAROpenArchiveEx` returns the handle.
Read it from the struct before calling any other function. The `ROADF_*`
constants in `unrar_bindings.dart` decode the bit fields.

---

## FileTime is DOS date format, not Unix time

`RARHeaderDataEx.FileTime` stores a **DOS date/time** value, the same format
used in ZIP and FAT file systems.

Bit layout (32-bit value):
```
Bits 31-25: year - 1980   (0..127 → 1980..2107)
Bits 24-21: month         (1..12)
Bits 20-16: day           (1..31)
Bits 15-11: hour          (0..23)
Bits 10-5:  minute        (0..59)
Bits  4-0:  second / 2    (0..29, multiply by 2)
```

**Do not** pass this value directly to `DateTime.fromMillisecondsSinceEpoch`.
The extractor's `_dosTimeToDateTime` helper converts it correctly.

For sub-second precision, `RARHeaderDataEx` also provides `MtimeLow` and
`MtimeHigh` as a Windows FILETIME (100-nanosecond intervals since 1601-01-01).
These are not currently used, but would be the right source for a precise
`modificationTime`.

---

## Filename encoding

RAR5 archives store filenames as UTF-8 in the `FileName` (char[1024]) field.
Reading it with `String.fromCharCodes` treats each byte as a Unicode code
point, producing mojibake for any multi-byte character (e.g., accented
letters, CJK, emoji).

The correct decoder is `utf8.decode(chars, allowMalformed: true)`. The
`allowMalformed: true` flag prevents a `FormatException` on corrupt or
RAR4-style Latin-1 filenames while still decoding valid UTF-8 accurately.

Both `_readFileNameEx` helpers in `unrar_extractor.dart` use this approach.

---

## Callback: UCM_PROCESSDATA delivers decompressed data

The library invokes the registered `UNRARCALLBACK` with `msg=1`
(`UCM_PROCESSDATA`) during extraction. The callback receives:

- `p1`: address of a native buffer containing the current data chunk
- `p2`: length of that chunk in bytes

The buffer belongs to the library and is only valid during the callback. Data
must be copied immediately into Dart-owned memory (the `_Buffer` class).

To route callbacks to the correct in-progress extraction, each
`extractFileToMemory` / `extractAllToMemory` call claims a unique integer `id`
(from the module-level `_nextId` counter) and registers it as the `userData`
parameter via `RARSetCallback`. The callback uses `_pendingData[userData]` to
look up the target buffer.

---

## Callback: multi-volume and password handling

| msg | Constant            | Action taken                                      |
|-----|---------------------|---------------------------------------------------|
| 0   | UCM_CHANGEVOLUME    | Return 1 (accept) for `RAR_VOL_ASK`; 0 for notify |
| 1   | UCM_PROCESSDATA     | Copy chunk into `_pendingData[userData]`          |
| 2   | UCM_NEEDPASSWORD    | Return -1 (cancel); callers must pass password up-front |
| 5   | UCM_LARGEDICT       | Return 1 (consent to large dictionary)            |

For multi-volume archives, the library suggests the next volume path itself.
Returning 1 to `UCM_CHANGEVOLUME` + `RAR_VOL_ASK` (p2=0) accepts that
suggestion. Volumes must be co-located and named with the standard
`.part01.rar` / `.part02.rar` … convention.

---

## Memory extraction uses RAR_TEST, not RAR_EXTRACT

`extractFileToMemory` and `extractAllToMemory` pass `RAR_TEST` as the
operation code rather than `RAR_EXTRACT`. `RAR_TEST` decompresses the file and
verifies its CRC but writes nothing to disk. All decompressed bytes arrive
through the `UCM_PROCESSDATA` callback, which is where the Dart code captures
them.

`RAR_EXTRACT` with a null destination path would also trigger callbacks but
additionally tries to create files on disk — which is unexpected behavior for a
memory-only operation.

---

## RARGetDllVersion validation

`_lib` calls `RARGetDllVersion` immediately after loading the dynamic library
and throws `UnrarException` if the returned version is less than
`RAR_DLL_VERSION` (10 as of this writing). This catches mismatches where an
old pre-installed system `libunrar` is found before the freshly compiled one.

---

## ArchiveInfo and RAROpenArchiveEx

`archiveInfo()` opens the archive with `RAROpenArchiveEx` (the extended
variant), reads the `Flags` field from `RAROpenArchiveDataEx`, and immediately
closes it. Archive-level flags (solid, volume, encrypted headers, etc.) are
available in `Flags` immediately after open without reading any file headers.

For encrypted-header archives (`ROADF_ENCHEADERS`), `RAROpenArchiveEx` can
return the flags without a password because the archive header itself is
readable. Individual file entries cannot be listed without the password.

---

## Test archives

All archives live in `test_data/` and were created with RAR 7.22 (RAR5 format
by default). Source files are in `test_data/sources/`.

| Archive                | Contents / Notes                                     |
|------------------------|------------------------------------------------------|
| `basic_rar5.rar`       | hello.txt + world.txt, default compression           |
| `with_dirs.rar`        | Adds subdir/nested.txt                               |
| `solid.rar`            | `-s` flag, solid compression                         |
| `binary.rar`           | binary.bin (512 bytes, 0x00..0xFF repeated), `-m0`   |
| `encrypted_data.rar`   | `-p test123`, data encrypted, headers visible        |
| `encrypted_headers.rar`| `-hp test123`, both headers and data encrypted       |
| `unicode_names.rar`    | café.txt — UTF-8 filename                            |
| `multi.part01..04.rar` | `-v300b` split into ~300-byte volumes                |

RAR 7.22 trial does not support the `-ma4` switch; all test archives are RAR5.
