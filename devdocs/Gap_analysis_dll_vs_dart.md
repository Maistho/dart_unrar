# Gap Analysis: UnRAR Native API vs. Dart Implementation

## Overview

This document audits the gap between the complete UnRAR C++ DLL API (`third_party/unrar/dll.hpp`) and what the Dart FFI wrapper actually uses and exposes.

---

## Gap 1 — Six used functions are hand-bound, not in the generated bindings

The auto-generated [`lib/src/unrar_bindings.dart`](lib/src/unrar_bindings.dart) is produced from `dll.hpp` by `ffigen`, but it **does not include any of the actual DLL function signatures**. Instead, `UnrarExtractor` re-declares all six used functions inline via `late final` + `lookupFunction` at [`unrar_extractor.dart:174–212`](lib/src/unrar_extractor.dart).

This means `ffigen` is only being used for structs, constants, and callback types — not for what it's best at. Any signature drift between the hand-coded bindings and the actual DLL goes undetected.

**Impact:** Manual maintenance burden; silent signature mismatches possible.

---

## Gap 2 — Six functions missing from bindings entirely

| Function | What it enables |
|---|---|
| `RAROpenArchiveEx` | Unicode archive paths, extended flags (`ROADOF_KEEPBROKEN`), larger comment buffers |
| `RARReadHeaderEx` | 1024-char filenames (RAR5), Blake2 hash, host OS, version, solid flag per-entry |
| `RARProcessFileW` | Wide-char (UTF-16) destination paths — needed on Windows for non-ASCII output dirs |
| `RARSetChangeVolProc` | Legacy volume-change callback (deprecated in favour of `RARSetCallback`) |
| `RARSetProcessDataProc` | Legacy data-processing callback (deprecated in favour of `RARSetCallback`) |
| `RARGetDllVersion` | Returns the loaded library's version integer (useful for runtime capability checks) |

The two highest-impact ones are `RAROpenArchiveEx` + `RARReadHeaderEx`. Without them, the wrapper is permanently limited to the RAR4-era API — 260-char filenames, no Blake2 integrity, no extended archive metadata. RAR5 archives work but at reduced fidelity.

**Impact:** RAR5 archives silently truncate long filenames; no integrity hash verification; missing archive metadata.

---

## Gap 3 — `RARHeaderDataEx` and `RAROpenArchiveDataEx` are opaque

The generated bindings declare both extended structs as `ffi.Opaque`, meaning their fields are inaccessible from Dart:

```dart
// lib/src/unrar_bindings.dart
final class RARHeaderDataEx extends ffi.Opaque {}
final class RAROpenArchiveDataEx extends ffi.Opaque {}
```

The `ffigen` config in `pubspec.yaml` needs to include these structs explicitly (with full field layouts) for them to be usable. Until then, `RAROpenArchiveEx` and `RARReadHeaderEx` can't be called meaningfully even if bound.

### Fields lost from `RARHeaderDataEx`

- `FileNameW[1024]` — full Unicode filename
- `HashType` + `Hash[32]` — Blake2 integrity hash
- `RedirType` + `RedirName` — hard/soft link targets
- `UnpSizeHigh` — high 32 bits of uncompressed size (files > 4 GB)
- `PackSizeHigh` — high 32 bits of packed size
- `MtimeLow/High`, `AtimeLow/High`, `CtimeLow/High` — full timestamp precision

### Fields lost from `RAROpenArchiveDataEx`

- `ArcNameW` — Unicode archive path
- `Flags` — archive-level flags (needed to check `ROADF_ENCHEADERS`, `ROADF_VOLUME`, etc.)
- `QOpenMaxSize` — quick-open cache size tuning

**Impact:** Cannot support RAR5 full fidelity; large file support limited to 4 GB.

---

## Gap 4 — Only `UCM_PROCESSDATA` handled in the callback; five messages silently dropped

The native callback fires six message types. The `_unrarCallback` function checks only `UCM_PROCESSDATA` and returns `0` for everything else:

```dart
// unrar_extractor.dart:42
int _unrarCallback(int msg, int userData, int p1, int p2) {
  if (msg == bindings.UNRARCALLBACK_MESSAGES.UCM_PROCESSDATA.value) { ... }
  return 0;  // silently ignores all other messages
}
```

### Ignored Messages

| Message | Consequence |
|---|---|
| `UCM_CHANGEVOLUME` / `UCM_CHANGEVOLUMEW` | Multi-volume archives (`.part1.rar`, `.part2.rar`, …) silently fail — the library asks for the next volume path and gets no answer |
| `UCM_NEEDPASSWORD` / `UCM_NEEDPASSWORDW` | If password is needed but wasn't set via `RARSetPassword`, the library requests it interactively via callback — currently returns `0` which is treated as "cancel", causing `ERAR_MISSING_PASSWORD` rather than a useful error |
| `UCM_LARGEDICT` | Large-dictionary archives (RAR5 with >128 MB dictionary) prompt for confirmation — returning `0` cancels extraction silently |

Multi-volume is the most impactful: it's a common archiving pattern and currently breaks silently at volume boundaries.

**Impact:** Multi-volume archives fail silently; password prompts treated as cancellations; large-dict archives rejected without clear error message.

---

## Gap 5 — Header flags never surfaced in `ArchiveEntry`

These flags are bound and readable from `RARHeaderData.Flags` but not exposed to callers:

| Flag | Value | What it means |
|---|---|---|
| `RHDF_ENCRYPTED` | `0x04` | File is encrypted — callers can't check this without extracting |
| `RHDF_SPLITBEFORE` | `0x01` | Entry continues from previous volume |
| `RHDF_SPLITAFTER` | `0x02` | Entry continues into next volume |
| `RHDF_SOLID` | `0x10` | Entry is part of a solid block |

`RHDF_ENCRYPTED` is the most useful — callers currently have no way to know whether a specific file needs a password before attempting extraction.

**Impact:** Cannot identify encrypted files; no split/solid archive metadata available to callers.

---

## Gap 6 — Archive-level flags never read or surfaced

`RAROpenArchiveData.OpenResult` is checked for errors, but the `Flags` field (available on the `Ex` variant) is never read. Callers can't know:

- `ROADF_VOLUME` — whether this is a multi-volume set
- `ROADF_ENCHEADERS` — whether archive headers are encrypted (meaning `listFiles` itself needs a password)
- `ROADF_SOLID` — solid archive (affects extraction strategy)
- `ROADF_FIRSTVOLUME` — whether this is the first volume in a set

**Impact:** Cannot warn callers about encrypted headers; no archive-level metadata available.

---

## Gap 7 — `RARGetDllVersion` unused

`RARGetDllVersion` returns an integer matching `RAR_DLL_VERSION` (currently `10`). Not calling it means the library can't verify at runtime that the loaded `.dylib`/`.so`/`.dll` matches the API version it was compiled against — version skew between the compiled hook output and a system-installed `unrar.dll` (Windows) would produce silent misbehaviour rather than a clear error.

**Impact:** Silent version skew between bindings expectations and runtime library.

---

## Gap 8 — `RARProcessFileW` not used (Windows-specific)

On Windows, passing non-ASCII destination paths to `RARProcessFile` (ANSI version) silently fails or mangles the path. The wide-char version `RARProcessFileW` exists but is never called. The extraction methods always use `RARProcessFile` with UTF-8 encoded paths, which works on Unix/macOS but may fail on Windows with non-ASCII output directories.

**Impact:** Windows users cannot extract to non-ASCII paths.

---

## Unused (Bloat in Bindings)

The generated bindings include many constants and types that are not used anywhere:

### Error Codes
- `ERAR_ECREATE` (16), `ERAR_ECLOSE` (17), `ERAR_UNKNOWN` (21)

### Open Modes
- `RAR_OM_LIST_INCSPLIT` (2)

### Constants
- `RAR_VOL_ASK` (32), `RAR_VOL_NOTIFY` (33)
- `RAR_HASH_NONE`, `RAR_HASH_CRC32`, `RAR_HASH_BLAKE2`
- `RAR_DLL_VERSION`
- All `RHDF_*` except `RHDF_DIRECTORY`
- All `ROADF_*` flags
- `ROADOF_KEEPBROKEN`

### Types
- `CHANGEVOLPROC`, `PROCESSDATAPROC` callback types
- 5 of 6 callback message types (only `UCM_PROCESSDATA` is used)

**Impact:** Bloats the public API surface; unclear to users what's actually supported.

---

## Priority Roadmap

| Priority | Gap | Effort | Impact |
|---|---|---|---|
| **High** | Fix `RARHeaderDataEx` + `RAROpenArchiveDataEx` in ffigen config | Low | Unblocks RAR5 support |
| **High** | Implement `RAROpenArchiveEx` + `RARReadHeaderEx` | Medium | RAR5 full fidelity + large files |
| **High** | Handle `UCM_CHANGEVOLUME` in callback | Medium | Multi-volume support |
| **Medium** | Surface `RHDF_ENCRYPTED` in `ArchiveEntry` | Low | Better UX for encrypted files |
| **Medium** | Handle `UCM_NEEDPASSWORD` in callback | Low | Better password error messages |
| **Medium** | Use `RARProcessFileW` on Windows | Low | Non-ASCII output paths on Windows |
| **Medium** | Call `RARGetDllVersion` at load time | Low | Version validation |
| **Low** | Surface archive-level flags | Low | Better archive metadata |
| **Low** | Clean up unused constants/types from public API | Trivial | API clarity |

---

## Recommendations

### Short Term
1. Fix `ffigen` config to bind `RARHeaderDataEx` and `RAROpenArchiveDataEx` as full structs, not opaque
2. Document current limitations in README (no RAR5 long filenames, no multi-volume, no Blake2)

### Medium Term
3. Implement `RAROpenArchiveEx` + `RARReadHeaderEx` to enable RAR5 full fidelity
4. Handle `UCM_CHANGEVOLUME` callback to support multi-volume archives
5. Add `isEncrypted` flag to `ArchiveEntry`
6. Use `RARProcessFileW` on Windows for non-ASCII paths

### Long Term
7. Move all six core functions from hand-coded bindings to `ffigen` generation
8. Surface archive-level flags in a new `ArchiveMetadata` class
9. Add version validation via `RARGetDllVersion`
