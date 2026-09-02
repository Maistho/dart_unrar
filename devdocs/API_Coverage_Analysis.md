# API Coverage Analysis: UnRAR Native API vs. Dart Bindings

**Date:** June 24, 2026  
**Scope:** Complete audit of `third_party/unrar/dll.hpp` native API vs. what's in `lib/src/unrar_bindings.dart` vs. what's actually used in `lib/src/unrar_extractor.dart`

---

## 1. EXPORTED C FUNCTIONS

| Function | Native Library | Bindings | Dart Implementation | Status |
|----------|---|---|---|---|
| **RAROpenArchive** | ✓ (line 176) | ✗ NOT in bindings | ✓ Used (via _rarOpenArchive, lines 176-180) | **USED BUT NOT FORMALLY BOUND** |
| **RAROpenArchiveEx** | ✓ (line 177) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |
| **RARReadHeader** | ✓ (line 179) | ✗ NOT in bindings | ✓ Used (via _rarReadHeader, lines 188-193) | **USED BUT NOT FORMALLY BOUND** |
| **RARReadHeaderEx** | ✓ (line 180) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |
| **RARProcessFile** | ✓ (line 181) | ✗ NOT in bindings | ✓ Used (via _rarProcessFile, lines 195-200) | **USED BUT NOT FORMALLY BOUND** |
| **RARProcessFileW** | ✓ (line 182) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |
| **RARSetCallback** | ✓ (line 183) | ✗ NOT in bindings | ✓ Used (via _rarSetCallback, lines 208-212) | **USED BUT NOT FORMALLY BOUND** |
| **RARSetChangeVolProc** | ✓ (line 184) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |
| **RARSetProcessDataProc** | ✓ (line 185) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |
| **RARSetPassword** | ✓ (line 186) | ✗ NOT in bindings | ✓ Used (via _rarSetPassword, lines 202-206) | **USED BUT NOT FORMALLY BOUND** |
| **RARCloseArchive** | ✓ (line 178) | ✗ NOT in bindings | ✓ Used (via _rarCloseArchive, lines 182-186) | **USED BUT NOT FORMALLY BOUND** |
| **RARGetDllVersion** | ✓ (line 187) | ✗ NOT in bindings | ✗ Never used | **MISSING FROM BINDINGS** |

**Summary:** 6 of 12 functions used; all 6 hand-coded in extractor.dart rather than generated; 6 missing entirely from bindings.

---

## 2. STRUCTS

| Struct | Native Library | Bindings | Dart Implementation | Status |
|--------|---|---|---|---|
| **RARHeaderData** | ✓ (lines 58-75) | ✓ (lines 12-56, but INCOMPLETE) | ✓ Used extensively | **BOUND - COMPLETE** |
| **RARHeaderDataEx** | ✓ (lines 78-117, 37 fields) | ✓ (line 58) **Opaque** | ✗ Never used | **BOUND BUT MARKED AS OPAQUE** |
| **RAROpenArchiveData** | ✓ (lines 120-129) | ✓ (lines 61-80) | ✓ Used extensively | **BOUND - COMPLETE** |
| **RAROpenArchiveDataEx** | ✓ (lines 145-162) | ✓ (line 93) **Opaque** | ✗ Never used | **BOUND BUT MARKED AS OPAQUE** |

### Note on Extended Structs

The bindings mark `RARHeaderDataEx` and `RAROpenArchiveDataEx` as `ffi.Opaque`, which means FFI cannot access their fields. This is a binding generation issue — they should be full struct bindings if they're meant to be used.

**Fields inaccessible from `RARHeaderDataEx`:**
- `FileNameW[1024]` — full Unicode filename (vs. 260 in base struct)
- `HashType` + `Hash[32]` — Blake2 checksum
- `RedirType` + `RedirName` — hard/soft link targets
- `UnpSizeHigh`, `PackSizeHigh` — high 32 bits for files > 4 GB
- `HostOS` — OS that created the file
- `FileVersion` — file version info
- Timestamp precision fields (`MtimeLow/High`, `AtimeLow/High`, `CtimeLow/High`)

**Fields inaccessible from `RAROpenArchiveDataEx`:**
- `ArcNameW` — Unicode archive path
- `Flags` — archive-level flags (volume, encryption, solid, etc.)
- `QOpenMaxSize` — quick-open cache tuning

---

## 3. CALLBACK TYPES

| Callback | Native Library | Bindings | Dart Implementation | Status |
|----------|---|---|---|---|
| **UNRARCALLBACK** | ✓ (line 131) | ✓ (lines 82-91) | ✓ Used (lines 43-55, 564, 672) | **USED** |
| **CHANGEVOLPROC** | ✓ (line 169) | ✓ (lines 119-123) | ✗ Never used | **BOUND BUT UNUSED** |
| **PROCESSDATAPROC** | ✓ (line 170) | ✓ (lines 124-129) | ✗ Never used | **BOUND BUT UNUSED** |

---

## 4. CONSTANTS

### Error Codes

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| ERAR_SUCCESS (6) | ✓ | ✓ (131) | ✓ Used | **USED** |
| ERAR_END_ARCHIVE (10) | ✓ | ✓ (133) | ✓ Used | **USED** |
| ERAR_NO_MEMORY (11) | ✓ | ✓ (135) | ✓ Used (214) | **USED** |
| ERAR_BAD_DATA (12) | ✓ | ✓ (137) | ✓ Used (216) | **USED** |
| ERAR_BAD_ARCHIVE (13) | ✓ | ✓ (139) | ✓ Used (217) | **USED** |
| ERAR_UNKNOWN_FORMAT (14) | ✓ | ✓ (141) | ✓ Used (218) | **USED** |
| ERAR_EOPEN (15) | ✓ | ✓ (143) | ✓ Used (219) | **USED** |
| ERAR_ECREATE (16) | ✓ | ✓ (145) | ✗ Unused | **BOUND BUT UNUSED** |
| ERAR_ECLOSE (17) | ✓ | ✓ (147) | ✗ Unused | **BOUND BUT UNUSED** |
| ERAR_EREAD (18) | ✓ | ✓ (149) | ✓ Used (222) | **USED** |
| ERAR_EWRITE (19) | ✓ | ✓ (151) | ✓ Used (223) | **USED** |
| ERAR_SMALL_BUF (20) | ✓ | ✓ (153) | ✓ Used (224) | **USED** |
| ERAR_UNKNOWN (21) | ✓ | ✓ (155) | ✗ Unused | **BOUND BUT UNUSED** |
| ERAR_MISSING_PASSWORD (22) | ✓ | ✓ (157) | ✓ Used (226) | **USED** |
| ERAR_EREFERENCE (23) | ✓ | ✓ (159) | ✓ Used (835) | **USED** |
| ERAR_BAD_PASSWORD (24) | ✓ | ✓ (161) | ✓ Used (837) | **USED** |
| ERAR_LARGE_DICT (25) | ✓ | ✓ (163) | ✓ Used (839) | **USED** |

**Summary:** 14 of 16 error codes used; 2 bound but unused.

### Open Modes

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RAR_OM_LIST (24) | ✓ | ✓ (165) | ✓ Used (258) | **USED** |
| RAR_OM_EXTRACT (25) | ✓ | ✓ (167) | ✓ Used (346, 428, 542, 650, 751) | **USED** |
| RAR_OM_LIST_INCSPLIT (26) | ✓ | ✓ (169) | ✗ Unused | **BOUND BUT UNUSED** |

### Process Actions

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RAR_SKIP (28) | ✓ | ✓ (171) | ✓ Used (305, 481, 601, 691) | **USED** |
| RAR_TEST (29) | ✓ | ✓ (173) | ✓ Used (585, 709, 784) | **USED** |
| RAR_EXTRACT (30) | ✓ | ✓ (175) | ✓ Used (380, 467, 707) | **USED** |

### Volume Flags

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RAR_VOL_ASK (32) | ✓ | ✓ (177) | ✗ Unused | **BOUND BUT UNUSED** |
| RAR_VOL_NOTIFY (33) | ✓ | ✓ (179) | ✗ Unused | **BOUND BUT UNUSED** |

### Hash Types

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RAR_HASH_NONE (37) | ✓ | ✓ (183) | ✗ Unused | **BOUND BUT UNUSED** |
| RAR_HASH_CRC32 (38) | ✓ | ✓ (185) | ✗ Unused | **BOUND BUT UNUSED** |
| RAR_HASH_BLAKE2 (39) | ✓ | ✓ (187) | ✗ Unused | **BOUND BUT UNUSED** |

### Version Constant

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RAR_DLL_VERSION (35) | ✓ | ✓ (181) | ✗ Unused | **BOUND BUT UNUSED** |

### File Header Flags (RHDF_*)

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| RHDF_SPLITBEFORE (51) | ✓ | ✓ (189) | ✗ Unused | **BOUND BUT UNUSED** |
| RHDF_SPLITAFTER (52) | ✓ | ✓ (191) | ✗ Unused | **BOUND BUT UNUSED** |
| RHDF_ENCRYPTED (53) | ✓ | ✓ (193) | ✗ Unused | **BOUND BUT UNUSED** |
| RHDF_SOLID (54) | ✓ | ✓ (195) | ✗ Unused | **BOUND BUT UNUSED** |
| RHDF_DIRECTORY (55) | ✓ | ✓ (197) | ✓ Used (282, 686) | **USED** |

### Archive Flags (ROADF_*)

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| ROADF_VOLUME (133) | ✓ | ✓ (199) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_COMMENT (134) | ✓ | ✓ (201) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_LOCK (135) | ✓ | ✓ (203) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_SOLID (136) | ✓ | ✓ (205) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_NEWNUMBERING (137) | ✓ | ✓ (207) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_SIGNED (138) | ✓ | ✓ (209) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_RECOVERY (139) | ✓ | ✓ (211) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_ENCHEADERS (140) | ✓ | ✓ (213) | ✗ Unused | **BOUND BUT UNUSED** |
| ROADF_FIRSTVOLUME (141) | ✓ | ✓ (215) | ✗ Unused | **BOUND BUT UNUSED** |

### Open Archive Flags (ROADOF_*)

| Constant | Native | Bindings | Dart Impl | Status |
|----------|---|---|---|---|
| ROADOF_KEEPBROKEN (143) | ✓ | ✓ (217) | ✗ Unused | **BOUND BUT UNUSED** |

---

## 5. CALLBACK MESSAGE ENUM (UNRARCALLBACK_MESSAGES)

| Message | Native (line 164-167) | Bindings (lines 95-117) | Dart Implementation | Status |
|---------|---|---|---|---|
| UCM_CHANGEVOLUME (0) | ✓ | ✓ | ✗ Unused | **BOUND BUT UNUSED** |
| UCM_PROCESSDATA (1) | ✓ | ✓ | ✓ Used (line 44) | **USED** |
| UCM_NEEDPASSWORD (2) | ✓ | ✓ | ✗ Unused | **BOUND BUT UNUSED** |
| UCM_CHANGEVOLUMEW (3) | ✓ | ✓ | ✗ Unused | **BOUND BUT UNUSED** |
| UCM_NEEDPASSWORDW (4) | ✓ | ✓ | ✗ Unused | **BOUND BUT UNUSED** |
| UCM_LARGEDICT (5) | ✓ | ✓ | ✗ Unused | **BOUND BUT UNUSED** |

**Summary:** Only 1 of 6 callback message types handled; 5 silently ignored.

---

## Summary Statistics

| Category | Total in Native | In Bindings | Used in Dart | Coverage |
|----------|---|---|---|---|
| **Functions** | 12 | 0 (hand-coded instead) | 6 | 50% |
| **Structs** | 4 | 4 (2 opaque) | 2 | 50% |
| **Callback Types** | 3 | 3 | 1 | 33% |
| **Error Codes** | 16 | 16 | 14 | 88% |
| **Open Modes** | 3 | 3 | 2 | 67% |
| **Process Actions** | 3 | 3 | 3 | 100% |
| **Flags (all types)** | 19 | 19 | 1 | 5% |
| **Callback Messages** | 6 | 6 | 1 | 17% |

---

## Coverage by Usage Pattern

### Fully Used (✓)
- Core extraction flow: open → read header → process file → close
- Single-file extraction (disk and memory variants)
- Password support via `RARSetPassword`
- Error handling for 14 error codes
- Process actions: skip, test, extract
- Data callback processing via `UCM_PROCESSDATA`

### Bound But Unused (⊘)
- 3 extended/deprecated functions (`RAROpenArchiveEx`, `RARReadHeaderEx`, legacy callbacks)
- Volume change handling (5 messages + `RARSetChangeVolProc`)
- Password prompts via callback (`UCM_NEEDPASSWORD`)
- Archive flags (9 types + all callback variants)
- File flags (4 of 5)
- Legacy hash/version constants
- Large-dictionary handling (`UCM_LARGEDICT`)

### Missing Entirely (✗)
- `RARProcessFileW` (wide-char paths on Windows)
- `RARGetDllVersion` (version validation)
- Field access to extended structs (`RARHeaderDataEx`, `RAROpenArchiveDataEx`)

---

## Implications

**Breadth:** 50% function coverage, 50% struct coverage. Wrapper covers the happy path well but lacks extended/edge-case handling.

**Depth:** Single extraction mode (RAR4, 260-char names, CRC32 only); no multi-volume, no RAR5 metadata, no alternate output path handling.

**API Clarity:** Many constants bound but unused — unclear to users what's actually supported. Missing flags (encryption, split, solid) mean callers can't make informed decisions.

**Maintenance:** Hand-coded functions = manual signature management; opaque structs = inaccessible fields; ignored callbacks = silent failures for multi-volume and password prompts.
