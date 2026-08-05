# Dart_unrar vs neoasis_unrar — Gap Analysis

*Status: current as of 2026-08-05. Sources reviewed: `dart_unrar` (FFI wrapper,
`unrar` 0.1.3) `lib/`, `devdocs/`, `test/`; `neoasis_unrar` (pure-Dart port,
0.1.0) `lib/`, `MILESTONES.md`, `test/`.*

## 1. Purpose

Both packages provide RAR archive reading for Dart, but from opposite ends:

- **dart_unrar** is an **FFI wrapper** around the official RARLAB C UnRAR
  library (vendored in `third_party/unrar`), exposing only what the C DLL API
  (`dll.hpp`) provides.
- **neoasis_unrar** is a **from-scratch pure-Dart port** of the same C source
  (unrarsrc 7.2.3), reimplementing the decompressor, crypto, and utilities in
  Dart with no native code and no `dart:io` in the core.

This document compares their public APIs, feature coverage, platform reach,
correctness posture, and where each one leads. It is intended to help decide
which to use (or both, in combination) and to track convergence opportunities.

## 2. Executive summary

| Dimension | dart_unrar (`unrar`) | neoasis_unrar |
|---|---|---|
| Approach | FFI to vendored C UnRAR | Pure-Dart port of the C source |
| Runtime deps | `ffi`, `native_toolchain_c`, `code_assets`, `hooks` | none |
| Platforms | Windows, macOS, Linux (needs C toolchain at build) | every Dart target incl. web/Wasm |
| Core `dart:io` | yes (required) | no (core is platform-agnostic) |
| API style | synchronous, path-string/file based | async, `ByteSource` + callbacks |
| Formats | RAR 1.4 / 4.x / 5.0 (whatever C supports) | RAR 1.4 / 4.x / 5.0 (+7.0 unpacker) |
| Encryption | via C (`RARSetPassword`) | full Dart port (KDF3/KDF5, AES, HMAC, BLAKE2 MAC) |
| `.rev` recovery rebuild | **not available** | **available** (`restoreRevArchive`) |
| Metadata depth | header flags, DOS mtime, crc | + high-precision times, symlinks, owners, BLAKE2 digest |
| To-memory extraction | `extractFileToMemory`, `extractAllToMemory` | streaming callbacks (equivalent) |
| On-disk extraction | `extractAll(dir)` (C creates files, links, dirs) | none built in (callback gives bytes) |
| Test count | ~129 (native) | ~137 (unit + real corpus + rev) |

## 3. Architecture

### 3.1 dart_unrar

- Vendors the official RARLAB source in `third_party/unrar` and compiles it
  with Dart 3.10 **build hooks** (`native_toolchain_c` + `code_assets`) during
  the consumer's build; `ffigen` generates `unrar_bindings.dart` from
  `dll.hpp`.
- `UnrarExtractor` hand-wires the FFI function pointers and a module-level
  native callback (`_unrarCallback`) that handles `UCM_PROCESSDATA`,
  `UCM_CHANGEVOLUME`, `UCM_NEEDPASSWORD` and `UCM_LARGEDICT`. Extracted data
  is buffered in a global `_pendingData` map keyed by a callback id.
- `RARHeaderDataEx` is `ffi.Opaque`; fields are read through
  `RARHeaderDataExView`, which computes byte offsets at runtime to bridge the
  `wchar_t` size difference between Windows (2) and Unix (4).
- All operations block the calling isolate (synchronous FFI).

### 3.2 neoasis_unrar

- Every C subsystem is reimplemented in Dart and unit-tested against its own
  primitives: `crc`, `raw_int`, `bit_input`, `raw_reader`, `enc_name`,
  `unpack4` (v20/26/29 + PPMd), `unpack5` (+ RISC-V/delta/filter variants),
  `aes`, `sha1`, `sha256`, `hmac`, `kdf3`, `kdf5`, `blake2s`, `rs16`,
  `recvol`, `volume`, `archive_reader`.
- IO is abstracted behind `ByteSource` (`MemoryByteSource`, and a `dart:io`
  `FileByteSource` in `lib/io.dart`), so the same code runs on VM, Flutter and
  web/Wasm.
- Everything is `async`; decompressed data is streamed through callbacks.

## 4. Public API surface

| Concern | dart_unrar | neoasis_unrar |
|---|---|---|
| Open/close | `UnrarExtractor` (stateless per call) | `RarArchive.open(ByteSource, …)` + `close()` |
| Archive info | `archiveInfo(path)` → `ArchiveInfo` (flags) | `archive.format`, `archive.info`, `archive.sfxSize`, `archive.isBroken` |
| Listing | `listFiles(path)` → `List<ArchiveEntry>` | `archive.list()` → `List<ArchiveEntry>` |
| Extract all | `extractAll(path, dir)` (disk) | `archive.extractAll((entry, bytes) {})` (memory callback) |
| Extract one | `extractFile`, `extractFileToMemory` | `archive.extractFile(name)` → `Uint8List?` |
| To memory (all) | `extractAllToMemory` | `extractAll` callback |
| Test | `testArchive` | `archive.testArchive()` |
| Volumes | implicit via C `UCM_CHANGEVOLUME` | `VolumeResolver` + `openRarFile` auto-chain |
| Recovery | — | `restoreVolumes`, `restoreRevArchive`, `readRevHeader` |
| Errors | `UnrarException(code)` | `UnrarException` family |

### `ArchiveEntry` fields

| Field | dart_unrar | neoasis_unrar |
|---|---|---|
| name / packSize / unpSize | `size` (unp) + `packedSize` | `packSize`, `unpSize` |
| crc | `crc` (int) | `crc32` |
| attributes | `attributes` | `fileAttr`, raw `flags`, `hostOs`, `method`, `unpVer`, `windowSize` |
| directory | `isDirectory` | `isDirectory` |
| encrypted / split / solid | `isEncrypted`, `isSplitBefore/After`, `isSolid` | `isEncrypted`, `splitBefore/After`, `isSolid` |
| mtime | `modificationTime` (DOS) | `modifiedTime` (DOS, **or high-precision from HTIME**) |
| created / accessed | — | `createdTime`, `accessedTime` |
| symlink / hard link | — | `redirectType`, `redirectTarget`, `redirectTargetIsDir`, `isRedirect` |
| unix owner/group | — | `unixOwner` (`UnixOwnerInfo`) |
| hash | `hashType` (int 0/1/2) | `hashType` (`FileHashType`) + `blake2Digest` (32 bytes) |
| encryption params | — | `cryptInfo` (salt, iv, KDF params, pswCheck) |
| service records | — | `isService` |

**Note:** the C `RARHeaderDataEx` struct that dart_unrar reads *contains*
`RedirType`/`RedirName`, `Hash[32]`, and high-precision `Mtime/Ctime/Atime`
fields, but the Dart wrapper does not surface them — they are a latent,
easy-to-add capability (see §7).

## 5. Feature matrix

| Feature | dart_unrar | neoasis_unrar |
|---|---|---|
| RAR 1.4 archives | ✓ (via C) | ✓ (headers; stored) |
| RAR 4.x stored + compressed | ✓ (via C) | ✓ (unpack20/26/29, PPMd) |
| RAR 5.0 / 7.0 compressed | ✓ (via C) | ✓ (unpack5 + filters) |
| Encryption (RAR4/5 data) | ✓ (`RARSetPassword`) | ✓ (KDF3/5, AES, HMAC) |
| Encrypted headers (`-hp`) | ⚠ caveat (password set after open; `UCM_NEEDPASSWORD` returns −1) | ✓ |
| Multi-volume | ✓ (via C volume callback) | ✓ (resolver + assembly + last-part CRC) |
| CRC verification | ✓ (via C) | ✓ (+ BLAKE2sp digest verify, MAC for encrypted) |
| Symlinks / hard links / junctions | partial (created on disk by C; metadata not surfaced) | ✓ (full metadata via `FHEXTRA_REDIR`) |
| High-precision / extra timestamps | — | ✓ (`FHEXTRA_HTIME`) |
| Unix owner/group | — | ✓ (`FHEXTRA_UOWNER`) |
| Archive comments | flag only (`hasComment`) | — |
| BLAKE2 hashes | flag only | ✓ (digest + verification) |
| **`.rev` recovery rebuild** | — | ✓ (REV5 + RS over GF(2^16)) |
| Test integrity | ✓ | ✓ (+ `isBroken`) |
| On-disk tree extraction | ✓ | — (helper needed) |
| Web / Wasm | — | ✓ |
| Streaming progress | — | ✓ (per-chunk callbacks in rev restore; per-file callback) |

## 6. One-sided gaps

### 6.1 Features only in dart_unrar

1. **Fidelity for RAR 4.x / exotic archives.** Decompression is executed by
   the unmodified upstream C; correctness for rare corners (old PPMd variants,
   huge dictionaries, damaged-but-recoverable streams, `ROADOF_KEEPBROKEN`)
   inherits the reference implementation's behavior. neoasis re-implements
   these paths in Dart and is the less battle-tested of the two.
2. **Native performance.** C code runs at native speed; the Dart port is a
   byte-at-a-time loop in the same isolate.
3. **On-disk extraction that recreates structure** (`extractAll(dir)`): the C
   creates directories, symlinks, junctions, and preserves attributes, so disk
   output matches `rar x` semantics. neoasis hands back bytes and metadata; a
   caller must write the tree themselves.
4. **Comment and archive-flag metadata** (`archiveInfo` → `isVolume`,
   `hasRecovery`, `hasSigned`, `hasComment`, …) in one call without
   enumerating entries.
5. **Existing corpus/tooling**: 129 native tests and a maintained
   build-hook distribution pipeline.

### 6.2 Features only in neoasis_unrar

1. **`*.rev` recovery reconstruction** (`restoreVolumes`,
   `restoreRevArchive`, `readRevHeader`) — REV5 header parse + Reed–Solomon
   over GF(2^16), verified byte-exact against RAR 7.23 fixtures. The C DLL API
   used by dart_unrar exposes no recovery capability at all (recovery is a
   console-utility feature), so dart_unrar cannot add this without a C change.
2. **Deep metadata**: created/accessed times, symlink targets, Unix owner/group,
   per-file KDF parameters, BLAKE2 digests, `isBroken`, raw flags.
3. **True portability**: no FFI, no `dart:io` in core → runs on web/Wasm and
   in any isolate; trivially testable without native toolchains; smaller
   dependency footprint.
4. **Async / stream-friendly API** and memory-first extraction.
5. **Transparent, testable core**: every primitive has a Dart unit test, and
   the archive reader is exercised against real fixtures; easy to instrument
   or port further C features (RAR 4.x `.rev`, NTFS ADS).

### 6.3 Parity

Listing, single-file and full extraction, testing, multi-volume chaining,
RAR4/RAR5 encryption, CRC32 verification, and both RAR 4.x and RAR 5.0
compression coverage are essentially at parity.

## 7. Cross-pollination opportunities

- **neoasis → dart_unrar (metadata)**: `RARHeaderDataEx` already carries
  `RedirName`, `Hash[32]`, and `Ctime/Atime/MtimeHigh` — surfacing these in
  `RARHeaderDataExView` + `ArchiveEntry` would close most of the metadata gap
  with little effort.
- **neoasis → dart_unrar (recovery)**: only viable by vendoring the C
  `RecVolumes5` restore path or the `unrar` console `t`/`r` logic; the DLL API
  does not expose it.
- **dart_unrar → neoasis**: an `extractAllToDisk` helper (recreate dirs,
  symlinks, permissions from `ArchiveEntry` metadata) and comment extraction
  are the notable items.
- **Shared oracle**: `neoasis_unrar/test/real_archive_test.dart` already uses
  the dart_unrar corpus as ground truth. Dart code can be cross-checked
  against the FFI extractor on the same fixture bytes for a strong
  conformance harness.

## 8. Platform & distribution

| | dart_unrar | neoasis_unrar |
|---|---|---|
| Windows | ✓ | ✓ |
| macOS / iOS | ✓ | ✓ |
| Linux / Android | ✓ | ✓ |
| Web / Wasm | ✗ (no FFI) | ✓ |
| Build requirement | C toolchain via build hooks (`dart build`) | none |
| Runtime lib loading | search of env var / `.dart_tool/lib` / exe dir | n/a |

## 9. Performance, concurrency, robustness

- **Performance**: dart_unrar wins on raw decompression throughput (native
  C). neoasis is competitive for stored/small archives and benefits from its
  `Uint8List`-backed buffers, but hot decompression loops are Dart.
- **Concurrency**: dart_unrar's sync FFI calls block the isolate and its
  extracted-data state is a module-level global (single-flight). neoasis is
  `async`, stateless per `RarArchive`, and can be used across isolates /
  `Isolate.run` without shared mutable state.
- **Robustness on bad input**: dart_unrar inherits upstream error handling
  (`ERAR_BAD_DATA`, keep-broken). neoasis exposes `isBroken`, validates header
  checksums, and throws typed `UnrarException`s; its error paths are younger.

## 10. Maintenance & licensing

- Both are derived from RARLAB UnRAR source and are subject to the UnRAR
  license (RAR *decompression* is allowed; re-creating the RAR compression
  algorithm is prohibited).
- dart_unrar tracks upstream C releases (rebuild + `ffigen`); neoasis must
  re-port C changes into Dart, so C-version drift is a real cost.
- dart_unrar's `RARHeaderDataExView` relies on hand-maintained struct offsets
  across `wchar_t` platforms (a Windows `long`-width caveat is tracked in
  `devdocs/Gap_analysis_dll_vs_dart.md`).

## 11. Recommendations

- **Choose dart_unrar** when running on native targets, extraction
  performance matters, RAR 4.x corpus breadth/fidelity is critical, or you
  want on-disk extraction identical to `rar x` with zero Dart-side effort.
- **Choose neoasis_unrar** when portability (web/Wasm, any isolate) matters,
  you need `.rev` recovery or deep metadata (symlinks, owners, extra times,
  BLAKE2 digests), or you want a dependency-free, testable pure-Dart reader.
- **Use both together** for maximal coverage: neoasis for metadata, recovery,
  and portability; dart_unrar as a conformance oracle (shared corpus) and for
  high-throughput native extraction.
