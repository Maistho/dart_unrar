# GAP-001: neoasis_unrar vs UnRAR C++ — Functional Gap Analysis

| | |
|---|---|
| Status | **Reference** |
| Date | 2026-08-05 |
| C library | UnRAR 7.20 Beta 3 (2025-12-18), `/dart_unrar/third_party/unrar/` |
| Dart port | neoasis_unrar, `/neoasis_unrar/lib/src/` |
| Related | `DESIGN-001-Dart_unrar_compatible_Facade.md`, `Dart_unrar_vs_neoasis_unrar_Gap_Analysis.md` |
| Method | Two independent agent reviews (Dart source + C++ source) cross-referenced |

---

## Severity legend

| Level | Meaning |
|---|---|
| **CRITICAL** | Produces wrong output or throws where the C succeeds; archives in the wild will fail |
| **HIGH** | Silent data loss, security gap, or feature that breaks common workflows |
| **MEDIUM** | Feature gap or metadata loss; rare archives or niche use-cases |
| **LOW** | Performance, future-compat, or cosmetic; no current correctness impact |

---

## 1. Compression / Decompression

### GAP-001-C1 — RAR 1.5 compressed extraction not implemented `CRITICAL`

- **C library**: `unpack15.cpp` (`Unpack15()`) handles all RAR 1.5 Huffman+LZ compressed files. Any archive created with `rar a -ma1` or pre-dating RAR 2.0 uses this path.
- **neoasis**: `unpacker.dart:187` throws `UnsupportedMethodException` for unpVer 15. `unpack4.dart:1-6` docstring explicitly states "RAR 1.5 is not ported."
- **Impact**: All RAR 1.5 compressed (non-stored) entries fail at runtime. RAR 1.5 archives are old but still found in archives from the 1990s/early 2000s.
- **Files**: `neoasis_unrar/lib/src/unpacker.dart:187`, `unpack4.dart:168`

### GAP-001-C2 — RAR 3.x Virtual Machine filters silently truncate output `CRITICAL`

- **C library**: `rarvm.cpp` implements a Turing-complete virtual machine executing post-processing filters attached to compressed data (x86 E8/E9, delta, audio, RGB, ITANIUM, text, etc.). Filters apply before CRC verification. Any file compressed at RAR 3.x Normal or above **may** embed VM filter programs.
- **neoasis**: `_readVmCode()` and `_readVmCodePpm()` in `unpack4.dart:1026-1032` always return `false`. When a VM code block appears, the LZ decompressor hits `break` at `unpack4.dart:647-651` and the PPMd path hits `break` at `unpack4.dart:545-549`. Extraction silently stops mid-stream with no exception.
- **Impact**: Any RAR 3.x archive using VM-based filters produces **truncated, corrupt output without error**. This is a silent data-corruption class bug. Prevalence is high — most `.r00`/`.r01`/`part1.rar` archives from the 2003–2010 era use Normal or higher compression and thus embed at least the E8/E9 x86 filter.
- **Files**: `unpack4.dart:545-549`, `647-651`, `1026-1032`
- **Note**: Porting the RAR VM is substantial work (the VM is ~1400 lines in C). An alternative is porting only the named filter types (E8, Delta, Audio, RGB — 4 functions, ~200 lines each in `unpack30.cpp`) and rejecting archives with arbitrary VM bytecode.

### GAP-001-C3 — RAR 7.0 dictionary size fraction bits not handled `HIGH`

- **C library**: `arcread.cpp:870-882` — for `CompAlgo == 1` (RAR 7.0), the window size calculation includes `FCI_DICT_FRACT*` bits (bits 15–19) that add fractional increments: `WinSize += WinSize / 32 * fractBits`. This allows non-power-of-2 dictionary sizes. The `FCI_RAR5_COMPAT` flag (bit 20) also allows RAR7 headers with RAR5 algorithm.
- **neoasis**: `archive_reader.dart:1118-1119` — `windowSize = 0x20000 << ((compInfo >> 10) & (unpVerRaw == 0 ? 0x0f : 0x1f))`. The `& 0x1f` extends the shift range for RAR 7.0 but the fraction bits are never applied. `FCI_RAR5_COMPAT` is defined in `header_constants.dart:103` but never read.
- **Impact**: RAR 7.0 archives with non-power-of-2 dictionaries allocate an undersized window, causing extraction failures or silent output corruption.
- **Files**: `neoasis_unrar/lib/src/archive_reader.dart:1118-1119`, `header_constants.dart:103`

### GAP-001-C4 — RAR 5.0 filters: unknown type silently drops block `LOW`

- **C library**: All current RAR 5.0 filter types (delta, E8, E8E9, ARM) are handled. Future filter types are skipped with a logged warning.
- **neoasis**: `unpack5.dart:774` — `return null` for unrecognized filter type. Output for the filtered block is silently discarded.
- **Impact**: Currently no archives use filter types beyond the 4 known ones. Becomes CRITICAL for any future RAR 5.0 filter type added in WinRAR.
- **Files**: `neoasis_unrar/lib/src/unpack5.dart:774`

---

## 2. Header Parsing

### GAP-001-H1 — RAR 4.x special header types not dispatched `HIGH`

- **C library** (`arcread.cpp:459-522`): The following RAR 4.x header types each have dedicated parsing paths:
  - `HEAD3_CMT` (0x75) — old standalone comment: reads `UnpSize`, `UnpVer`, `Method`, `CommCRC`
  - `HEAD3_AV` (0x76) — authenticity verification: CRC check intentionally skipped; `Signed=true`
  - `HEAD3_OLDSERVICE` (0x77) — RAR 2.x subblock: dispatches `NTACL_HEAD` → `ExtractACL20()`, `STREAM_HEAD` → `ExtractStreams20()`
  - `HEAD3_PROTECT` (0x78) — recovery record: reads `Version`, `RecSectors`, `TotalBlocks`, `Mark[8]`
  - `HEAD3_SIGN` (0x79) — digital signature: CRC check skipped
- **neoasis** (`archive_reader.dart:1404-1418`): `_mapHeaderType15()` maps only `0x73`, `0x74`, `0x7a`, `0x7b`, `0x78` — the rest map to `headUnknown`. `head3Cmt` (0x75), `head3Av` (0x76), `head3OldService` (0x77), and `head3Sign` (0x79) all fall to the `default:` branch which only advances position if `longBlock` flag is set.
- **Impact**: For these block types without `longBlock` set, `_nextBlockPos` is not advanced past the data area — any subsequent header read will misinterpret the data bytes as a new header, causing a cascade of parse failures. Practically: any RAR 2.x–3.x archive with comment, AV header, or old-style subheaders **may corrupt the reading position**.
- **Files**: `archive_reader.dart:1404-1418`, `archive_reader.dart:709-713`

### GAP-001-H2 — End-of-archive flags not parsed `MEDIUM`

- **C library**:
  - RAR 4.x (`arcread.cpp:513-535`): reads `EARC_NEXT_VOLUME`, `EARC_DATACRC`, `EARC_REVSPACE`, `EARC_VOLNUMBER` flags. `EARC_REVSPACE` reads and discards 7 bytes reserved for REV file metadata. Without this, the reader mispositions itself.
  - RAR 5.0: `ehflNextVolume` (0x0001) indicates next volume exists.
- **neoasis**: `archive_reader.dart:703-704` — `case HeaderType.headEndArc: break;` (RAR 4.x). `archive_reader.dart:994` — falls to `default: break;` (RAR 5.0). No flags read, no `EARC_REVSPACE` skip.
- **Impact**: In RAR 4.x archives with `EARC_REVSPACE` set (archives that also have a `.rev` recovery file), the 7 reserved bytes are not skipped. If the reader tries to continue after this, it misreads. Also: volume continuation state is not confirmed from the end-of-archive block.
- **Files**: `archive_reader.dart:703-704`, `archive_reader.dart:994`

### GAP-001-H3 — `head3Protect` (recovery record) data not read `MEDIUM`

- **C library** (`arcread.cpp:466-474`): reads `ProtectHead`: `DataSize(4)`, `Version(1)`, `RecSectors(2)`, `TotalBlocks(4)`, `Mark[8]`. Sets `Archive::Protected=true`. Data area contains Reed-Solomon recovery data.
- **neoasis** (`archive_reader.dart:705-707`): `case HeaderType.head3Protect: head.dataSize = raw.get4(); _nextBlockPos = …` — reads data size and skips. No `Version`, `RecSectors`, `TotalBlocks`, or `Mark` are read. `_info.protected` is set from `MHD_PROTECT` flag (correct) but the recovery record metadata itself is discarded.
- **Impact**: Recovery record metadata (sector count, total blocks, mark bytes) unavailable. Not needed for extraction, but relevant for archive integrity tools.
- **Files**: `archive_reader.dart:705-707`

---

## 3. Encryption

### GAP-001-E1 — `FHEXTRA_CRYPT_HASHMAC` not implemented `HIGH`

- **C library** (`crypt5.cpp:193-212`, `extract.cpp:933`): When `UseHashKey=true` (set by `FHEXTRA_CRYPT_HASHMAC` flag in the CRYPT extra record), checksums stored in the header are not plain CRC32/BLAKE2 but HMACs:
  ```
  HashKey = PBKDF2(password, salt, lg2+16 iterations)
  StoredCRC32  = HMAC-SHA256(HashKey, raw_crc32_bytes)[0:4]
  StoredBLAKE2 = HMAC-SHA256(HashKey, blake2_digest)[0:32]
  ```
  The HMAC key is derived with 16 extra PBKDF2 iterations beyond the encryption key.
- **neoasis** (`archive_reader.dart:1225-1247`, `unpacker.dart`): `useHashKey` / `fhExtraCryptHashMac` is parsed into `CryptInfo` (`kdf5.dart:21-38` documents it) but the post-extraction checksum step does not convert the stored hash to/from HMAC before comparison.
- **Impact**: Any RAR 5.0 archive encrypted with per-file `FHEXTRA_CRYPT` that uses HMAC checksums (the default for WinRAR 5.0+ file-level encryption) **will fail CRC verification even with the correct password** — or worse, pass with a wrong password if HMAC comparison is skipped entirely.
- **Files**: `neoasis_unrar/lib/src/kdf5.dart:21-38`, `archive_reader.dart:1237-1247`; investigate `unpacker.dart` checksum verification path

### GAP-001-E2 — RAR 1.x/2.x encryption not implemented `MEDIUM`

- **C library** supports four legacy ciphers beyond RAR 3.0/5.0 AES:
  - `CRYPT_RAR13`: 3-byte XOR key (`crypt1.cpp:1-12`)
  - `CRYPT_RAR15`: CRC32-of-password → 4×16-bit keys (`crypt1.cpp:15-28`)
  - `CRYPT_RAR20`: Custom 128-bit block cipher (`crypt2.cpp`)
  - `CRYPT_RAR30`: AES-128-CBC with SHA-1 KDF and 8-byte salt (`crypt3.cpp`)
- **neoasis**: Only `CRYPT_RAR30` (AES-128-CBC) and `CRYPT_RAR50` (AES-256-CBC) are implemented. Archives encrypted with `CRYPT_RAR13/15/20` will fail with no ciphertext decryption — producing garbled data or a CRC error.
- **Files**: `neoasis_unrar/lib/src/aes.dart` (only AES-128/256), `kdf3.dart` (only SHA-1 KDF for RAR 3.0)

### GAP-001-E3 — PBKDF2 iteration count up to 2^24 `LOW`

- **C library** (`crypt.hpp:18`): `CRYPT5_KDF_LG2_COUNT_MAX = 24` (2^24 ≈ 16M iterations).
- **neoasis** (`archive_reader.dart:1015-1017`, `1231-1233`): `if (_rar5CryptLg2 > 24) { return; }` — correct guard exists. No time-out protection for very high iteration counts (may cause long processing on legitimate archives).
- **Impact**: Not a correctness bug. Very high `lg2` counts are rare but valid; the return silently disables decryption instead of throwing a descriptive error.

---

## 4. Integrity Verification

### GAP-001-V1 — RAR 1.4 CRC verification entirely skipped `HIGH`

- **C library** (`hash.hpp:4`): `HASH_RAR14` is the 16-bit checksum stored in RAR 1.4 file headers. It is computed and verified after extraction.
- **neoasis** (`archive_reader.dart:574-575, 618`): The 16-bit hash is read but discarded. `crc32: 0` is hardcoded in the resulting `ArchiveEntry`. The CRC verifier never fires for any RAR 1.4 entry.
- **Impact**: Silent integrity bypass — a corrupt RAR 1.4 file extracts without error.
- **Files**: `archive_reader.dart:618`

### GAP-001-V2 — Packed data hash not verified across volume boundaries `MEDIUM`

- **C library** (`volume.cpp:21-26`): For files split across volumes, `DataIO.PackedDataHash` verifies the packed (compressed) bytes per volume separately, before full decompression across all volumes completes. Error: `UIERROR_CHECKSUMPACKED`.
- **neoasis**: No per-volume packed-data checksum verification. The only check is the final post-decompression CRC32/BLAKE2 of the fully assembled file.
- **Impact**: A corrupt middle-volume may produce garbled decompressed data that coincidentally passes the final CRC (extremely unlikely but possible for stored files, zero probability for compressed files). More practically, the corrupt volume is not pinpointed — the error message cannot identify which volume is bad.

### GAP-001-V3 — RAR 5.0 entries without `FHFL_CRC32` have no integrity check `LOW`

- **C library**: Directories and service blocks have `HASH_NONE`; regular files always have at least `HASH_CRC32`. This is enforced by the packer.
- **neoasis** (`unpacker.dart:255-256`): `if (storedMac == 0) { return; }` — silently skips CRC check. Valid for directories/service blocks, but also silently skips any future regular-file entry that somehow lacks a hash.

---

## 5. Service Subheaders

### GAP-001-S1 — `SUBHEAD_TYPE_QO` (Quick Open) not detected `LOW`

- **C library** (`arcread.cpp:783-798`, `qopen.cpp`): Loads a pre-built file-header index stored at the end of the archive, allowing O(1) directory listing without scanning from start.
- **neoasis** (`header_constants.dart:110`): `subheadTypeQOpen` defined but never checked in any service-block dispatch. All archives are scanned linearly.
- **Impact**: No correctness impact. Performance: large archives (10,000+ entries) take longer to list.

### GAP-001-S2 — `SUBHEAD_TYPE_RR` percent uses legacy byte read `MEDIUM`

- **C library** (`arcread.cpp:906-916`): Since RAR 6.10, the recovery percent is stored as a variable-length integer (`vint`) supporting up to 1000%. The `SubData` payload is `RawPercent.GetV()`.
- **neoasis** (`header_constants.dart:111`): `subheadTypeRr` defined but no service-block handler checks for it. Recovery record presence is inferred only from `MHD_PROTECT` / `MHFL_PROTECT` flags. The percent value is never read.
- **Impact**: Recovery percent unavailable. Relevant only if exposing recovery metadata to callers.

### GAP-001-S3 — `SUBHEAD_TYPE_UOW` (Unix owner, RAR 3.x) not detected `MEDIUM`

- **C library** (`extinfo.cpp:46-48`): `SUBHEAD_TYPE_UOWNER` triggers `ExtractUnixOwner30()` to apply UID/GID from a RAR 3.x service header. Separate from RAR 5.0 `FHEXTRA_UOWNER` which *is* implemented.
- **neoasis**: Only `FHEXTRA_UOWNER` (RAR 5.0) is handled. RAR 3.x Unix owner subheaders are silently dropped.
- **Impact**: Unix owner/group metadata from RAR 3.x archives is lost.

### GAP-001-S4 — Comment text content never read or stored `LOW`

- **C library** (`arccmt.cpp`, `dll.cpp:114-141`): Comment data is decompressed and returned in `CmtBuf` / `CmtBufW` fields. `CmtState` indicates truncation.
- **neoasis** (`archive_reader.dart:762-763`, `1118-1121`): `_info.comment = true` is set when a CMT sub-header is found, but the comment text bytes are never decompressed or stored. No `ArchiveInfo.commentText` field exists.
- **Impact**: Callers cannot read archive comments, only detect their presence.
- **Files**: `archive_reader.dart:762-763`, `1118-1121`

### GAP-001-S5 — `SUBHEAD_TYPE_ACL` / `SUBHEAD_TYPE_STREAM` silently dropped `LOW`

- **C library** (`extinfo.cpp:50-54`): NTFS ACL and alternate data stream subheaders are applied on Windows extraction.
- **neoasis**: These subheader types are never detected. Relevant only for Windows-target extraction tools.

---

## 6. Extra Record Types (`FHEXTRA_*`)

### GAP-001-X1 — `FHEXTRA_VERSION` (file versioning) silently dropped `MEDIUM`

- **C library** (`arcread.cpp:1160-1169`): `FHEXTRA_VERSION` (0x04) appends `;N` to the filename and sets `FileHead.Version=true`. `VersionControl` selects latest / all / specific version during extraction.
- **neoasis** (`archive_reader.dart:1199-1220`): No `case fhExtraVersion:` branch in `_processExtra50`. Version extra records are silently skipped.
- **Impact**: File version information is lost. Archives created with `rar a -ver` will have entries with truncated names (missing `;N` suffix).
- **Files**: `header_constants.dart:93`, `archive_reader.dart:1199-1220`

### GAP-001-X2 — `FHEXTRA_SUBDATA` (service header payload) silently dropped `LOW`

- **C library** (`arcread.cpp`): `FHEXTRA_SUBDATA` (0x07) stores the data payload of service (sub)headers inline in the extra area. Used by `CMT`, `RR`, and other service blocks.
- **neoasis**: No `case fhExtraSubdata:` branch. Service header payloads arriving via extra area are discarded.
- **Files**: `header_constants.dart:96`, `archive_reader.dart:1199-1220`

### GAP-001-X3 — `MHEXTRA_LOCATOR` (archive locator) not parsed `LOW`

- **C library** (`arcread.cpp:1025-1051`, `headers5.hpp:68-73`): `MHEXTRA_LOCATOR` (0x01) in the main header's extra area stores `QOpenOffset` and `RROffset` — direct byte offsets to the Quick Open index and Recovery Record blocks.
- **neoasis**: No main-header extra area parsing at all. The `_parseMainHeader50` function reads only the flags vint and optional volume number.
- **Files**: `archive_reader.dart:1051-1064`

### GAP-001-X4 — `MHEXTRA_METADATA` (original archive name/time) not parsed `LOW`

- **C library** (`headers5.hpp:75-79`): `MHEXTRA_METADATA` (0x02) stores the original archive filename and creation timestamp. Used for archive metadata tools.
- **neoasis**: Same as X3 — no main-header extra area parsing.

### GAP-001-X5 — Nanosecond timestamp precision silently truncated `LOW`

- **C library** (`arcread.cpp` FHEXTRA_HTIME processing): `FHEXTRA_HTIME_UNIX_NS` flag (0x10) adds 4-byte nanosecond fields to each present timestamp, calling `RarTime::Adjust(ns)`.
- **neoasis** (`archive_reader.dart` `_parseFhExtraHtime`): The nanosecond flag bit and extra bytes are not handled. Timestamps are accurate to 1 second for Unix timestamps and 100 ns for Windows FILETIME, but nanosecond precision (when present) is discarded.
- **Impact**: Sub-second precision available in many modern archives is lost.

---

## 7. Multi-Volume

### GAP-001-M1 — Volume reader has no recursive volume resolver `MEDIUM`

- **C library** (`volume.cpp:10-193`): `MergeArchive()` opens the next volume, which itself is a full `Archive` object with its own `VolumeResolver`. Volume chains of arbitrary length are handled.
- **neoasis** (`archive_reader.dart:406-411`): The `ArchiveReader` constructed for the next volume is created **without** a `_volumeResolver`. A file split across more than two volumes (parts 1 → 2 → 3) fails when the second volume tries to continue into the third.
- **Impact**: Any archive split into 3+ volumes fails mid-extraction with an `UnrarException` ("provide a VolumeResolver").
- **Files**: `archive_reader.dart:406-411`

### GAP-001-M2 — Encrypted-header volume consistency not checked `HIGH`

- **C library** (`volume.cpp:148-156`): After opening the next volume, `Arc.Encrypted != PrevVolEncrypted` triggers an abort. This prevents an attacker from replacing a later volume with an unencrypted one (volume injection / header stripping attack).
- **neoasis**: No such check. A volume chain where encryption is toggled between volumes will be silently accepted.

### GAP-001-M3 — Old-style volume naming edge case `LOW`

- **C library**: `VolNameToFirstName()` and `NextVolumeName()` handle both old (`.r00`, `.r01`) and new (`part1.rar`, `part2.rar`) naming with full Unicode path awareness.
- **neoasis** (`volume.dart`): `nextVolumeName()` and `firstVolumeName()` implement both schemes. The implementations appear correct, but do not handle the edge case where the `rarFmt15` flag and `_info.newNumbering` disagree (e.g., a RAR 2.x archive with the `MHD_NEWNUMBERING` bit set).

---

## 8. File System Redirects / Links

### GAP-001-L1 — `FSREDIR_FILECOPY` (file deduplication) not handled `HIGH`

- **C library** (`extract.cpp:1090-1166`, `dll.hpp:35`): `FSREDIR_FILECOPY` (value 5) marks an entry as a reference to an identical file already in the archive. The C code maintains a `RefList`, extracts the source to a temp file, then copies/hard-links to all reference targets. Error code `ERAR_EREFERENCE` (23) is returned when the source is missing.
- **neoasis** (`header_constants.dart:210`, `archive_reader.dart`): `FileSystemRedirect.fsRedirFileCopy` is defined and its `redirectType` is stored in `ArchiveEntry`. However, there is no extraction path that resolves `fsRedirFileCopy` — the entry has no data area and `extractFile` would return empty bytes.
- **Impact**: Archives using `rar a -df` (deduplicated file references) silently extract zero-byte files for all secondary references.
- **Files**: `header_constants.dart:210`, archive reader/extractor

### GAP-001-L2 — RAR 3.x Unix symlink target read from data stream `MEDIUM`

- **C library** (`extinfo.cpp:158-184`): For RAR 3.x (`RARFMT15`) Unix symlinks, the symlink target is stored as the file's compressed data, not in the header. `ExtractUnixLink30()` reads and decompresses the data to get the target string, then calls `symlink()`.
- **neoasis** (`archive_reader.dart:782-787`): `isUnixSymlink` is correctly detected from `fileAttr`. `redirectType = fsRedirUnixSymlink` is set. However, `redirectTarget` is NOT populated from the data stream — it's only populated from `FHEXTRA_REDIR` in RAR 5.0. RAR 3.x symlinks have a null `redirectTarget`.
- **Files**: `archive_reader.dart:782-787`, `ArchiveEntry.redirectTarget`

### GAP-001-L3 — Symlink path traversal safety checks absent `HIGH`

- **C library** (`extinfo.cpp:107-155`): `IsRelativeSymlinkSafe()` counts `..` levels in symlink targets vs the path depth of the link itself, rejecting targets that would escape the extraction root. `LinksToDirs()` resolves symlink components in the destination path to prevent exploitation via pre-created symlinks.
- **neoasis**: No equivalent safety checks. The extraction API (`lib/io.dart` `openRarFile`) does not perform on-disk extraction at all — this is a gap in the facade design, not the current core. When the facade (`DESIGN-001`) implements `extractAll`, it must implement these checks (documented in `DESIGN-001 §8.2`).
- **Priority elevated**: Noted here for completeness; DESIGN-001 already acknowledges this.

---

## 9. Timestamp Handling

### GAP-001-T1 — RAR 4.x `ctime` and `atime` parsed but discarded `HIGH`

- **C library** (`arcread.cpp:392-426`): The `LHD_EXTTIME` flag triggers parsing of extended timestamps (ctime, atime, optional arctime) in addition to mtime. All are stored in the `FileHeader` struct.
- **neoasis** (`archive_reader.dart:868-871`): Comment explicitly states "ctime/atime (i == 1, 2) are not exposed by the entry model yet." The parse loop reads and discards these timestamp bytes. `ArchiveEntry` has no `createdTime` or `accessedTime` fields for RAR 4.x entries (only RAR 5.0 via `FHEXTRA_HTIME` has these).
- **Impact**: Creation and access times from RAR 4.x archives are silently lost.
- **Files**: `archive_reader.dart:868-871`

---

## 10. Archive Format Metadata

### GAP-001-A1 — RAR 2.x `HEAD3_OLDSERVICE` NTFS streams and ACLs dropped `MEDIUM`

- **C library** (`arcread.cpp:475-506`): `HEAD3_OLDSERVICE` (0x77) dispatches on `SubType`:
  - `NTACL_HEAD` (0x104) → `ExtractACL20()` (Windows NTFS ACLs)
  - `STREAM_HEAD` (0x105) → `ExtractStreams20()` (NTFS alternate data streams)
  - `EA_HEAD` (0x100), `UO_HEAD` (0x101), `MAC_HEAD` (0x102), `BEEA_HEAD` (0x103) → silently skipped
- **neoasis**: `head3OldService` (0x77) is not in `_mapHeaderType15()`. Falls to `headUnknown` → `default:` branch. The block is skipped if `longBlock` is set; otherwise the reader potentially mispositions (see GAP-001-H1).
- **Impact**: NTFS ACLs and alternate data streams from RAR 2.x archives are lost. Reader may misposition on archives with these blocks (depends on whether `longBlock` flag is set).
- **Files**: `archive_reader.dart:1404-1418`

### GAP-001-A2 — RAR 4.x large-file reassembly `HIGH`

- **C library** (`arcread.cpp:319-337`): `LHD_LARGE` triggers reading `HighPackSize(4)` and `HighUnpSize(4)` after the filename. 64-bit sizes assembled as `INT32TO64(HighPackSize, DataSize)`.
- **neoasis** (`archive_reader.dart:735-750`): `largeFile = (head.flags & lhdLarge) != 0`. `highPackSize` and `highUnpSize` are read and assembled correctly: `packSize = ((highPackSize << 32) | dataSize)`. This appears **correctly implemented** — flagging here only because the DLL API's `PackSizeHigh` / `UnpSizeHigh` fields (for dart_unrar consumers) need to be surfaced in any facade layer.
- **Status**: ✅ Correctly implemented in neoasis. Facade note: consumers expecting `PackSizeHigh` from the C DLL need a mapping.

---

## 11. Miscellaneous / Platform

### GAP-001-P1 — No `RAR_OM_LIST_INCSPLIT` equivalent `LOW`

- **C library** (`dll.hpp:26`): `RAR_OM_LIST_INCSPLIT` (2) reports all volume segments of a split file including continuation parts (those with `SplitBefore=true`). `RAR_OM_LIST` (0) auto-skips these.
- **neoasis**: `archive.list()` always returns all entries including split-before segments. There is no mode to auto-skip continuation segments. Callers may be surprised to see multiple entries for the same logical file.

### GAP-001-P2 — `ERAR_EREFERENCE` error code not emitted `LOW`

- **C library** (`dll.hpp:22`): `ERAR_EREFERENCE` (23) is returned when a `FSREDIR_FILECOPY` target's source file is not found in the archive.
- **neoasis**: No error code mapping for this case. When `FSREDIR_FILECOPY` is encountered, zero bytes are returned rather than an error. See GAP-001-L1.

### GAP-001-P3 — `UCM_LARGEDICT` callback not signalled `LOW`

- **C library** (`dll.hpp:167`): `UCM_LARGEDICT` is sent when the decompression dictionary size exceeds a threshold (large RAR 7.0 archives). Allows applications to warn users or abort before OOM.
- **neoasis** (`unpack5.dart:158-159`): Throws `UnrarException('Unsupported window size $winSize')` for windows > 64 GB. No pre-allocation callback mechanism exists.

### GAP-001-P4 — `ROADOF_KEEPBROKEN` not supported `LOW`

- **C library** (`dll.hpp:143`): `ROADOF_KEEPBROKEN` instructs extraction to preserve partially extracted files even on CRC failure — useful for corrupt-archive triage.
- **neoasis**: No equivalent option. On CRC failure, no output is produced (bytes are returned from memory; no partial file state).

---

## 12. Known Non-Issues (Correctly Implemented or By Design)

The following items from the C library are **correctly handled** in neoasis or are **by-design exclusions**:

| Item | Status |
|---|---|
| RAR 5.0 / 7.0 main compression (`unpack50.cpp`) | ✅ Fully ported (`unpack5.dart`, `unpack7.dart`) |
| RAR 2.9/3.x LZ + PPMd (`unpack30.cpp`) | ✅ Ported (except VM filters — see GAP-001-C2) |
| AES-256-CBC + PBKDF2-SHA256 (RAR 5.0) | ✅ Implemented (`aes.dart`, `kdf5.dart`) |
| AES-128-CBC + SHA-1 KDF (RAR 3.0) | ✅ Implemented (`aes.dart`, `kdf3.dart`) |
| BLAKE2sp hash verification | ✅ Implemented (`blake2s.dart`) |
| CRC32 verification (RAR 3.x / 5.0) | ✅ Implemented |
| Multi-volume with `VolumeResolver` | ✅ Works for 2-part archives; 3+ fail (GAP-001-M1) |
| Old-style volume naming (`.r00`) | ✅ Implemented (`volume.dart`) |
| SFX detection (`sfxSize`) | ✅ Implemented |
| RAR 5.0 `FHEXTRA_HTIME` (without ns) | ✅ Implemented |
| RAR 5.0 `FHEXTRA_UOWNER` | ✅ Implemented |
| RAR 5.0 `FHEXTRA_REDIR` (links) | ✅ Stored; on-disk application in facade scope |
| RAR 5.0 `FHEXTRA_CRYPT` (structure) | ✅ Parsed; HMAC variant incomplete (GAP-001-E1) |
| RAR 5.0 Delta / E8 / E8E9 / ARM filters | ✅ Implemented (`unpack5.dart`) |
| `ArchiveInfo.comment`, `.signed`, `.protected` | ✅ Implemented (2026-08-05) |
| Recovery volumes (`.rev`) — RAR 5.0 | ✅ Fully ported (`recvol.dart`) |
| Unicode filenames — RAR 5.0 (UTF-8) | ✅ Implemented |
| Unicode filenames — RAR 4.x encoded | ✅ Implemented (`enc_name.dart`) |
| RAR 4.x symlink detection via `fileAttr` | ✅ Detected; target not populated (GAP-001-L2) |
| RAR 1.4 format detection + listing | ✅ Headers parsed; extraction method=0 only |

---

## Priority Matrix

### Fix immediately (blocks production use of common archives)

| ID | Summary |
|---|---|
| GAP-001-C2 | RAR 3.x VM filters silently corrupt output |
| GAP-001-E1 | FHEXTRA_CRYPT_HASHMAC: correct password fails CRC |
| GAP-001-H1 | RAR 4.x special headers misposition reader |
| GAP-001-M2 | Volume encryption consistency not checked |
| GAP-001-L1 | FSREDIR_FILECOPY extracts zero bytes |

### Fix before facade ships

| ID | Summary |
|---|---|
| GAP-001-C1 | RAR 1.5 compressed extraction throws |
| GAP-001-M1 | 3+-part multi-volume fails |
| GAP-001-T1 | RAR 4.x ctime/atime discarded |
| GAP-001-V1 | RAR 1.4 CRC never verified |
| GAP-001-L2 | RAR 3.x symlink target not populated |
| GAP-001-H2 | End-of-archive flags not parsed |

### Nice-to-have / future

| ID | Summary |
|---|---|
| GAP-001-C3 | RAR 7.0 dict fraction bits |
| GAP-001-E2 | RAR 1.x/2.x encryption |
| GAP-001-X1 | FHEXTRA_VERSION (file versioning) |
| GAP-001-X3/X4 | MHEXTRA_LOCATOR / MHEXTRA_METADATA |
| GAP-001-X5 | Nanosecond timestamp precision |
| GAP-001-S2 | RR recovery percent |
| GAP-001-S3 | RAR 3.x Unix owner subheader |
| GAP-001-S4 | Archive comment text |
| GAP-001-S1 | Quick Open index |
| GAP-001-A1 | HEAD3_OLDSERVICE NTFS streams/ACLs |
| GAP-001-P1-P4 | API/mode gaps |
