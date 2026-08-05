# DESIGN-001: dart_unrar-compatible Facade over neoasis_unrar

| | |
|---|---|
| Status | **Draft for review** (design only — no implementation) |
| Author | opencode session |
| Date | 2026-08-05 |
| Related | `Dart_unrar_vs_neoasis_unrar_Gap_Analysis.md`, `ARCH-001`, `ISSUE-001` |
| Scope | A new public API surface that mirrors `dart_unrar`'s `UnrarExtractor` API, backed by the pure-Dart `neoasis_unrar` core, upgraded to idiomatic async Dart/Flutter |

## 1. Context

`dart_unrar` exposes a synchronous, path-string, FFI-backed API (`UnrarExtractor`,
`ArchiveEntry`, `ArchiveInfo`, `UnrarException`). Its FFI design blocks the calling
isolate, carries module-level global state, and is native-only. `neoasis_unrar`
is a pure-Dart port with a richer, async API, but a *different* shape — so callers
cannot switch backends without rewriting.

This design defines a **facade**: a thin, dart_unrar-shaped API over
neoasis_unrar. It gives existing `dart_unrar` consumers a drop-in source-level
replacement that is async, portable, cancellable, and concurrency-safe, while
also offering idiomatic extensions (streams, progress, isolate parallelism).

Design only. No implementation is produced by this document.

## 2. Goals

1. **Source compatibility**: code written against `unrar`'s public API
   (`UnrarExtractor`, `ArchiveEntry`, `ArchiveInfo`, `UnrarException`) compiles
   and behaves the same after swapping the import to the facade.
2. **Async by default**: every blocking operation returns a `Future`.
3. **Portable & safe**: inherits neoasis's platform reach (web/Wasm included)
   and its concurrency model (no shared native state).
4. **Idiomatic extras**: optional streaming (`Stream`), progress reporting, and
   cooperative cancellation — without breaking goal 1.

## 3. Non-goals

- Re-implementing `dart_unrar`'s internals or its exact sync/`dart:ffi` behavior.
- Pixel-perfect behavioral parity for every edge case (noted in §9).
- Exposing neoasis's deep metadata through the compat types (a separate richer
  API already exists in the core).
- Binary or reflection-level compatibility (source-level only).
- Adding recovery (`*.rev`) *into* the compat surface — it stays a
  neoasis-only capability (gap analysis §6.2.1).

## 4. Requirements

- Facade must live in a `dart:io`-importing library so the core stays pure
  (it opens files by path, like dart_unrar).
- Each call must be **stateless-per-call** (open → operate → close), mirroring
  dart_unrar, so concurrent calls cannot interfere.
- No new runtime dependencies.
- Multi-volume archives must be followed implicitly (dart_unrar does this via
  the C volume callback; the facade does it via `openRarFile`'s default
  `fileVolumeResolver`).

## 5. Placement (Decision D1 — recommend A)

- **A. In-package compat library** — `neoasis_unrar/lib/unrar_compat.dart`,
  importing the core (`lib/neoasis_unrar.dart`) + `lib/io.dart`. Consumers swap
  `import 'package:unrar/unrar.dart';` → `import 'package:neoasis_unrar/unrar_compat.dart';`.
  Simplest to ship and test; one repo.
- B. Separate package (`unrar_compat`) depending on `neoasis_unrar`. Cleaner
  isolation and versioning, but more ceremony.

**Recommendation: A.** Keep the compat surface clearly separated from the main
library's export list (`lib/neoasis_unrar.dart` must NOT export the compat types,
to avoid `ArchiveEntry`/`ArchiveInfo` name clashes for mixed imports).

## 6. Public API design

### 6.1 `UnrarExtractor` (compat class)

```dart
/// Drop-in replacement for `package:unrar`'s `UnrarExtractor`, backed by the
/// pure-Dart neoasis_unrar core. All operations are async and stateless-per-call.
class UnrarExtractor {
  UnrarExtractor({int concurrency = 1});          // see §8.4

  Future<ArchiveInfo> archiveInfo(
    String archivePath, {
    String? password,
  });

  Future<List<ArchiveEntry>> listFiles(
    String archivePath, {
    String? password,
  });

  Future<void> extractAll(
    String archivePath,
    String outputPath, {
    String? password,
    void Function(RarExtractProgress progress)? onProgress,
    RarCancelToken? cancelToken,
  });

  Future<Uint8List> extractFile(
    String archivePath,
    String fileName, {
    String? password,
  });

  Future<Uint8List> extractFileToMemory(
    String archivePath,
    String fileName, {
    String? password,
  });

  Future<Map<String, Uint8List>> extractAllToMemory(
    String archivePath, {
    String? password,
    void Function(RarExtractProgress progress)? onProgress,
    RarCancelToken? cancelToken,
  });

  Future<bool> testArchive(
    String archivePath, {
    String? password,
  });

  // ---- idiomatic extensions (additive, not required by compat) ------------

  /// Streams each entry's fully-unpacked bytes as it completes.
  Stream<RarEntryData> extractAllStream(
    String archivePath, {
    String? password,
    RarCancelToken? cancelToken,
  });
}
```

Method names, parameter names, and return types match `dart_unrar`
(`lib/src/unrar_extractor.dart`) exactly, with three deliberate changes:

1. **`Future<...>` return types** on every method (the whole point).
2. `extractFile` returns bytes directly via the memory path — dart_unrar's
   version writes to a temp dir and reads it back; behaviorally identical.
3. Optional `onProgress` / `cancelToken` named params are additive.

### 6.2 `ArchiveEntry` (compat type)

Mirror `dart_unrar`'s shape (constructor, field names, `==`/`hashCode`,
`toString`) so callers and tests that construct or compare entries keep
compiling:

```dart
class ArchiveEntry {
  ArchiveEntry({
    required this.name,
    required this.size,          // unpacked size
    required this.packedSize,
    required this.crc,           // crc32
    required this.attributes,    // OS-specific attr bitmask
    required this.modificationTime,
    required this.isDirectory,
    this.isEncrypted = false,
    this.isSplitBefore = false,
    this.isSplitAfter = false,
    this.isSolid = false,
    this.hashType = 0,           // 0 = none, 1 = crc32, 2 = blake2
  });

  final String name;
  final int size;
  final int packedSize;
  final int crc;
  final int attributes;
  final DateTime modificationTime;
  final bool isDirectory;
  final bool isEncrypted;
  final bool isSplitBefore;
  final bool isSplitAfter;
  final bool isSolid;
  final int hashType;

  // ==, hashCode, toString as in dart_unrar.
}
```

**Decision D2 (recommend A).** Define facade-owned compat types rather than
reusing neoasis's `ArchiveEntry`. neoasis's richer fields (`redirectType`,
`unixOwner`, `blake2Digest`, …) are deliberately *not* in the compat type; they
remain reachable only through the core API. This keeps the facade a faithful
dart_unrar stand-in.

### 6.3 `ArchiveInfo` (compat type)

Mirror dart_unrar's field set and `fromFlags`-style construction:

```dart
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

  final bool isVolume, hasComment, isSolid, hasEncryptedHeaders;
  final bool isFirstVolume, isLocked, hasSigned, hasRecovery;
}
```

**Derivation from neoasis** (see §7.3 for the mapping table). All three
formerly-gapped fields are now implemented in the core (see D3):

| dart_unrar field | Source in neoasis | Faithfulness |
|---|---|---|
| `isVolume` | `info.volume` | exact |
| `isSolid` | `info.solid` | exact |
| `hasEncryptedHeaders` | `info.encrypted` | exact |
| `isFirstVolume` | `info.firstVolume` | exact |
| `isLocked` | `info.locked` | exact |
| `hasComment` | `info.comment` | exact (RAR 4.x `MHD_COMMENT` flag or `CMT` service sub-header; RAR 5.0 `CMT` sub-header) |
| `hasSigned` | `info.signed` | exact for RAR 4.x (`PosAV != 0 \|\| HighPosAV != 0`, as `arcread.cpp`); always `false` for RAR 5.0 |
| `hasRecovery` | `info.protected` | exact (`MHD_PROTECT` flag) |

**Decision D3 — RESOLVED (implemented 2026-08-05).** The core
(`neoasis_unrar/lib/src/archive_info.dart`, `archive_reader.dart`) was extended
with two new fields (`comment`, `signed`); `hasRecovery` maps to the
pre-existing `protected` field, which is the same bit the C library reports
(`ROADF_RECOVERY` ← `Arc.Protected` ← `MHD_PROTECT`). RAR 5.0 always reports
`signed = false` (matching `arcread.cpp:771`). Covered by 4 new tests
(`real_archive_test.dart` "RAR 4.x archive info flags") over generated fixtures
(`rar4_comment.rar`, `rar4_protected.rar`, `rar4_signed.rar`).

### 6.4 `UnrarException` (compat type)

Mirror exactly (`message` + nullable `errorCode`):

```dart
class UnrarException implements Exception {
  UnrarException(this.message, [this.errorCode]);
  final String message;
  final int? errorCode;   // ERAR_* values, as in dart_unrar
}
```

The facade maps neoasis exceptions to RAR error codes (§8.1) so callers matching
on `e.errorCode` keep working. No new subtype hierarchy for the compat layer.

## 7. Behavior mapping (dart_unrar → facade)

### 7.1 Operations

| dart_unrar call | Facade behavior |
|---|---|
| `archiveInfo(path)` | Open via `openRarFile` (`RAR_OM_LIST`-equivalent), read main + RAR4 flags (D3), close. |
| `listFiles(path)` | `openRarFile(...).list()` → map each entry to compat `ArchiveEntry`. |
| `extractAll(path, dir)` | `openRarFile(...).list()` then per-entry `extractFile`, **writing the tree to disk** (§8.2), with CRC already verified by the core. |
| `extractFile(path, name)` | `openRarFile(...).extractFile(name)`; throw compat `UnrarException` (`ERAR_BAD_DATA`-mapped) if not found/CRC-fails. |
| `extractFileToMemory(path, name)` | Same as `extractFile` (memory path, no temp file). |
| `extractAllToMemory(path)` | `list()` → skip `isDirectory` → `extractFile` each → `Map<name, Uint8List>`. |
| `testArchive(path)` | `openRarFile(...).testArchive()`. |
| Volumes | Implicit, via `openRarFile` auto-volume resolver (no user action). |
| Encrypted headers (`-hp`) | Handled by core (password supplied at open) — **fixes** dart_unrar's §5 caveat. |

### 7.2 `ArchiveEntry` field mapping

| compat field | neoasis source | Notes |
|---|---|---|
| `size` | `unpSize` | |
| `packedSize` | `packSize` | |
| `crc` | `crc32` | |
| `attributes` | `fileAttr` | |
| `modificationTime` | `modifiedTime ?? DateTime.utc(1980)` | matches dart_unrar's DOS-0 fallback |
| `isEncrypted` | `isEncrypted` | |
| `isSplitBefore/After` | `splitBefore`/`splitAfter` | |
| `isSolid` | `isSolid` | |
| `hashType` | `hashType == FileHashType.blake2 ? 2 : 0` | int enum mapping |

### 7.3 `ArchiveInfo` mapping

All eight fields map 1:1 from `neoasis_unrar.ArchiveInfo` (see §6.3): five
directly, `hasComment`/`hasSigned` via the D3 additions, and `hasRecovery` via
the existing `protected` field. No facade-side approximation remains.

## 8. Idiomatic additions

### 8.1 Error-code mapping

| neoasis condition | compat `errorCode` |
|---|---|
| No password / password needed for listing | `ERAR_MISSING_PASSWORD` (22) |
| Wrong password | `ERAR_BAD_PASSWORD` (24) |
| Not a RAR / bad signature | `ERAR_BAD_ARCHIVE` (13) / `ERAR_UNKNOWN_FORMAT` (14) |
| Header checksum mismatch / CRC failure | `ERAR_BAD_DATA` (12) |
| Missing volume / volume resolver failed | `ERAR_EOPEN` (15) (informational) |
| Unsupported compression method | `ERAR_UNKNOWN` (21) |
| Anything else | `ERAR_UNKNOWN` (21) |

Mapping happens at the facade boundary; the core keeps its typed exceptions
(`UnrarException`, `UnsupportedMethodException`, …).

### 8.2 On-disk extraction semantics (the big new piece)

dart_unrar's `extractAll(dir)` delegates tree-writing to the C library. The
facade must reimplement it from neoasis metadata. Required behavior:

- **Path safety (zip-slip)**: reject entry names that are absolute, contain
  `..`, drive letters, or NUL; reject path traversal through symlinked parents.
  The C library does *not* fully guard this — the facade deliberately does
  (behavior difference, documented, security-positive).
- **Directories**: `createDirectory(recursive: true)`.
- **Files**: create parents, stream bytes to disk, then apply
  `modifiedTime`/`createdTime` and the executable bit from `fileAttr` where the
  platform allows.
- **Redirects (symlink/junction/hard link)**: when `redirectType != none` and
  the platform supports it, create the link from `redirectTarget`; otherwise
  fall back to writing the target file or skip (Decision D6 — default: write a
  small marker/`skip`, never a dangling external write).
- **Unix owner/group**: best-effort; silently skipped on non-POSIX or without
  privileges.
- **Overwrite**: replace by default (matches `rar x` semantics).

### 8.3 Progress + cancellation

```dart
class RarExtractProgress {
  final String entryName;   // current entry
  final int processedBytes;
  final int totalBytes;     // unpacked size of current entry
  final int entriesDone;
  final int totalEntries;
}

class RarCancelToken {
  bool get isCancelled;
  void cancel();            // cooperative
}
```

- `onProgress` is invoked per entry and (when cheap) per unpacked chunk,
  throttled to ~every 256 KiB to avoid callback flooding.
- Cancellation is **cooperative**: the facade checks `cancelToken.isCancelled`
  between entries and between chunk callbacks, then throws a compat
  `UnrarException` with a distinct marker message (callers can treat it like
  dart_unrar's user-break). No isolate killing.

### 8.4 Concurrency / isolates

- The facade is **stateless per call**, so N calls across N archives can run
  concurrently with zero shared state (gap analysis §9).
- `UnrarExtractor({int concurrency = 1})`: when `concurrency > 1`, individual
  operations are routed through a small **isolate pool** (`Isolate.run` per
  op), since the neoasis core is isolate-safe. Design notes:
  - File paths (not `ByteSource`s) cross the boundary; each worker opens the
    archive itself.
  - Large buffers use `TransferableTypedData` when returning bytes.
  - `concurrency == 1` (default) keeps dart_unrar's sequential semantics and
    avoids isolate message overhead.

## 9. Behavior differences vs dart_unrar (accepted)

1. `extractAll` guards against path traversal (C does not).
2. Symlink/hard-link recreation depends on platform + metadata; the C path
   always attempts it.
3. `hasSigned` is always `false` for RAR 5.0 archives (core matches C
   `arcread.cpp`; not a facade limitation).
4. `extractFile`/`extractFileToMemory` never touch the temp directory.
5. Header-encrypted archives work (core handles them).
6. RAR 4.x compression fidelity inherits the (younger) Dart port's behavior.

## 10. Testing strategy (design)

- **Drop-in conformance**: copy `dart_unrar`'s 129 tests (they compile against
  the compat API unchanged) and run them against the facade over the shared
  corpus (`dart_unrar/test_data`, `neoasis_unrar/test/fixtures`). This is the
  gap analysis §7 "shared oracle" harness made concrete.
- **Differential**: run both `dart_unrar` and the facade over the same fixture
  files; diff `ArchiveEntry` lists, `testArchive`, and extracted bytes.
- **Disk extraction**: symlink/hard-link creation, mtime application, zip-slip
  rejection (crafted `../` and absolute names).
- **Async**: progress monotonicity, cancellation mid-file and between files,
  concurrent archives via `Future.wait`, isolate-pool correctness.
- **Error codes**: table §8.1 pinned by tests (bad password, missing volume,
  corrupt archive, unsupported method).

## 11. Open questions

| # | Question | Recommended answer |
|---|---|---|
| Q1 | Ship inside `neoasis_unrar` or as a package? | D1-A: in-package `lib/unrar_compat.dart` |
| Q2 | Compat types or reuse core types? | D2-A: facade-owned compat types |
| Q3 | Comment/signed/recovery flags: core extension or scan? | **RESOLVED** — D3: `comment`/`signed` fields added to core; `hasRecovery` reuses `protected` |
| Q4 | Should `extractAll` return written paths? | `Future<void>` (compat); a `List<String>` in the streaming variant |
| Q5 | Isolate pool on by default? | No — opt-in via `concurrency` |

## 12. Risks

- **Type-name collision** if a consumer imports both `neoasis_unrar.dart` and
  `unrar_compat.dart` — mitigated by never exporting compat types from the main
  library, and documenting "import only one".
- **Behavior drift** between C and Dart port for exotic RAR 4.x inputs (fidelity
  gap §6.1.1) — surfaced loudly by the differential harness.
- **Disk-extraction reimplementation** is the largest new code surface and
  needs its own security review (path handling).
- **Per-call open** means repeated `extractFile` on one archive re-parses
  headers; acceptable (matches dart_unrar), optimizable later with an open-handle
  facade mode.

## 13. Delivery sketch (non-goal here, for scoping)

1. `lib/unrar_compat.dart` + compat types + async signatures.
2. Behavior mapping (§7) + error mapping (§8.1).
3. Disk extraction with path safety (§8.2).
4. Progress/cancellation (§8.3).
5. ~~D3 core flags + `hasComment/hasSigned/hasRecovery`.~~ **done** (2026-08-05).
6. Optional isolate pool (§8.4).
7. Conformance + differential test suite (§10).
