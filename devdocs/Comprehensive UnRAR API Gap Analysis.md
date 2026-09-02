Now I'll compile my comprehensive gap analysis report:

## Comprehensive UnRAR API Gap Analysis

Based on my thorough review of the three files, here's the complete audit of what the native library exposes vs. what the Dart wrapper uses:

---

### **1. EXPORTED C FUNCTIONS**

|Function|Native Library|Bindings|Dart Implementation|Status|
|---|---|---|---|---|
|**RAROpenArchive**|✓ (line 176)|✗ NOT in bindings|✓ Used (via _rarOpenArchive, lines 176-180)|**USED BUT NOT FORMALLY BOUND**|
|**RAROpenArchiveEx**|✓ (line 177)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|
|**RARReadHeader**|✓ (line 179)|✗ NOT in bindings|✓ Used (via _rarReadHeader, lines 188-193)|**USED BUT NOT FORMALLY BOUND**|
|**RARReadHeaderEx**|✓ (line 180)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|
|**RARProcessFile**|✓ (line 181)|✗ NOT in bindings|✓ Used (via _rarProcessFile, lines 195-200)|**USED BUT NOT FORMALLY BOUND**|
|**RARProcessFileW**|✓ (line 182)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|
|**RARSetCallback**|✓ (line 183)|✗ NOT in bindings|✓ Used (via _rarSetCallback, lines 208-212)|**USED BUT NOT FORMALLY BOUND**|
|**RARSetChangeVolProc**|✓ (line 184)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|
|**RARSetProcessDataProc**|✓ (line 185)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|
|**RARSetPassword**|✓ (line 186)|✗ NOT in bindings|✓ Used (via _rarSetPassword, lines 202-206)|**USED BUT NOT FORMALLY BOUND**|
|**RARCloseArchive**|✓ (line 178)|✗ NOT in bindings|✓ Used (via _rarCloseArchive, lines 182-186)|**USED BUT NOT FORMALLY BOUND**|
|**RARGetDllVersion**|✓ (line 187)|✗ NOT in bindings|✗ Never used|**MISSING FROM BINDINGS**|

---

### **2. STRUCTS**

|Struct|Native Library|Bindings|Dart Implementation|Status|
|---|---|---|---|---|
|**RARHeaderData**|✓ (lines 58-75)|✓ (lines 12-56, but INCOMPLETE)|✓ Used extensively|**BOUND - COMPLETE**|
|**RARHeaderDataEx**|✓ (lines 78-117, 37 fields)|✓ (line 58) **Opaque**|✗ Never used|**BOUND BUT MARKED AS OPAQUE**|
|**RAROpenArchiveData**|✓ (lines 120-129)|✓ (lines 61-80)|✓ Used extensively|**BOUND - COMPLETE**|
|**RAROpenArchiveDataEx**|✓ (lines 145-162)|✓ (line 93) **Opaque**|✗ Never used|**BOUND BUT MARKED AS OPAQUE**|

**Note on RARHeaderDataEx & RAROpenArchiveDataEx:** The bindings mark these as `ffi.Opaque` (lines 58 and 93), which means FFI cannot access their fields. This is a binding generation issue—they should be full struct bindings if they're meant to be used.

---

### **3. CALLBACK TYPES**

|Callback|Native Library|Bindings|Dart Implementation|Status|
|---|---|---|---|---|
|**UNRARCALLBACK**|✓ (line 131)|✓ (lines 82-91)|✓ Used (lines 43-55, 564, 672)|**USED**|
|**CHANGEVOLPROC**|✓ (line 169)|✓ (lines 119-123)|✗ Never used|**BOUND BUT UNUSED**|
|**PROCESSDATAPROC**|✓ (line 170)|✓ (lines 124-129)|✗ Never used|**BOUND BUT UNUSED**|

---

### **4. CONSTANTS**

#### Error Codes

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|ERAR_SUCCESS|✓ (6)|✓ (131)|✓ Used|**USED**|
|ERAR_END_ARCHIVE|✓ (10)|✓ (133)|✓ Used|**USED**|
|ERAR_NO_MEMORY|✓ (11)|✓ (135)|✓ Used (214)|**USED**|
|ERAR_BAD_DATA|✓ (12)|✓ (137)|✓ Used (216)|**USED**|
|ERAR_BAD_ARCHIVE|✓ (13)|✓ (139)|✓ Used (217)|**USED**|
|ERAR_UNKNOWN_FORMAT|✓ (14)|✓ (141)|✓ Used (218)|**USED**|
|ERAR_EOPEN|✓ (15)|✓ (143)|✓ Used (219)|**USED**|
|ERAR_ECREATE|✓ (16)|✓ (145)|✗ Unused|**BOUND BUT UNUSED**|
|ERAR_ECLOSE|✓ (17)|✓ (147)|✗ Unused|**BOUND BUT UNUSED**|
|ERAR_EREAD|✓ (18)|✓ (149)|✓ Used (222)|**USED**|
|ERAR_EWRITE|✓ (19)|✓ (151)|✓ Used (223)|**USED**|
|ERAR_SMALL_BUF|✓ (20)|✓ (153)|✓ Used (224)|**USED**|
|ERAR_UNKNOWN|✓ (21)|✓ (155)|✗ Unused|**BOUND BUT UNUSED**|
|ERAR_MISSING_PASSWORD|✓ (22)|✓ (157)|✓ Used (226)|**USED**|
|ERAR_EREFERENCE|✓ (23)|✓ (159)|✓ Used (835)|**USED**|
|ERAR_BAD_PASSWORD|✓ (24)|✓ (161)|✓ Used (837)|**USED**|
|ERAR_LARGE_DICT|✓ (25)|✓ (163)|✓ Used (839)|**USED**|

#### Open Modes

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RAR_OM_LIST|✓ (24)|✓ (165)|✓ Used (258)|**USED**|
|RAR_OM_EXTRACT|✓ (25)|✓ (167)|✓ Used (346, 428, 542, 650, 751)|**USED**|
|RAR_OM_LIST_INCSPLIT|✓ (26)|✓ (169)|✗ Unused|**BOUND BUT UNUSED**|

#### Process Actions

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RAR_SKIP|✓ (28)|✓ (171)|✓ Used (305, 481, 601, 691)|**USED**|
|RAR_TEST|✓ (29)|✓ (173)|✓ Used (585, 709, 784)|**USED**|
|RAR_EXTRACT|✓ (30)|✓ (175)|✓ Used (380, 467, 707)|**USED**|

#### Volume Flags

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RAR_VOL_ASK|✓ (32)|✓ (177)|✗ Unused|**BOUND BUT UNUSED**|
|RAR_VOL_NOTIFY|✓ (33)|✓ (179)|✗ Unused|**BOUND BUT UNUSED**|

#### Hash Types

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RAR_HASH_NONE|✓ (37)|✓ (183)|✗ Unused|**BOUND BUT UNUSED**|
|RAR_HASH_CRC32|✓ (38)|✓ (185)|✗ Unused|**BOUND BUT UNUSED**|
|RAR_HASH_BLAKE2|✓ (39)|✓ (187)|✗ Unused|**BOUND BUT UNUSED**|

#### DLL Version

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RAR_DLL_VERSION|✓ (35)|✓ (181)|✗ Unused|**BOUND BUT UNUSED**|

#### File Header Flags (RHDF_*)

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|RHDF_SPLITBEFORE|✓ (51)|✓ (189)|✗ Unused|**BOUND BUT UNUSED**|
|RHDF_SPLITAFTER|✓ (52)|✓ (191)|✗ Unused|**BOUND BUT UNUSED**|
|RHDF_ENCRYPTED|✓ (53)|✓ (193)|✗ Unused|**BOUND BUT UNUSED**|
|RHDF_SOLID|✓ (54)|✓ (195)|✗ Unused|**BOUND BUT UNUSED**|
|RHDF_DIRECTORY|✓ (55)|✓ (197)|✓ Used (282, 686)|**USED**|

#### Archive Flags (ROADF_*)

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|ROADF_VOLUME|✓ (133)|✓ (199)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_COMMENT|✓ (134)|✓ (201)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_LOCK|✓ (135)|✓ (203)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_SOLID|✓ (136)|✓ (205)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_NEWNUMBERING|✓ (137)|✓ (207)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_SIGNED|✓ (138)|✓ (209)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_RECOVERY|✓ (139)|✓ (211)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_ENCHEADERS|✓ (140)|✓ (213)|✗ Unused|**BOUND BUT UNUSED**|
|ROADF_FIRSTVOLUME|✓ (141)|✓ (215)|✗ Unused|**BOUND BUT UNUSED**|

#### Open Archive Flags (ROADOF_*)

|Constant|Native|Bindings|Dart Impl|Status|
|---|---|---|---|---|
|ROADOF_KEEPBROKEN|✓ (143)|✓ (217)|✗ Unused|**BOUND BUT UNUSED**|

---

### **5. CALLBACK MESSAGE ENUM (UNRARCALLBACK_MESSAGES)**

|Message|Native (line 164-167)|Bindings (lines 95-117)|Dart Implementation|Status|
|---|---|---|---|---|
|UCM_CHANGEVOLUME|✓ (value 0)|✓ (value 0)|✗ Unused|**BOUND BUT UNUSED**|
|UCM_PROCESSDATA|✓ (value 1)|✓ (value 1)|✓ Used (line 44)|**USED**|
|UCM_NEEDPASSWORD|✓ (value 2)|✓ (value 2)|✗ Unused|**BOUND BUT UNUSED**|
|UCM_CHANGEVOLUMEW|✓ (value 3)|✓ (value 3)|✗ Unused|**BOUND BUT UNUSED**|
|UCM_NEEDPASSWORDW|✓ (value 4)|✓ (value 4)|✗ Unused|**BOUND BUT UNUSED**|
|UCM_LARGEDICT|✓ (value 5)|✓ (value 5)|✗ Unused|**BOUND BUT UNUSED**|

---

## Summary of Gaps

### **Critical Issues**

1. **Functions NOT in FFI bindings but manually looked up in Dart:**
    - RAROpenArchive, RARReadHeader, RARProcessFile, RARSetCallback, RARSetPassword, RARCloseArchive
    - These are hand-coded FFI function lookups (lines 175-212 in extractor.dart) rather than auto-generated bindings
    - This means they're not in the auto-generated `unrar_bindings.dart` at all
2. **Completely Missing Functions:**
    - RAROpenArchiveEx
    - RARReadHeaderEx
    - RARProcessFileW
    - RARSetChangeVolProc
    - RARSetProcessDataProc
    - RARGetDllVersion
3. **Opaque Structs (unusable from Dart):**
    - RARHeaderDataEx (marked as `ffi.Opaque` in bindings, cannot access fields)
    - RAROpenArchiveDataEx (marked as `ffi.Opaque` in bindings, cannot access fields)

### **Bound But Unused (Bloat)**

- 9 error code constants
- 1 open mode (RAR_OM_LIST_INCSPLIT)
- 2 volume flags (RAR_VOL_ASK, RAR_VOL_NOTIFY)
- 3 hash type constants (RAR_HASH_NONE, RAR_HASH_CRC32, RAR_HASH_BLAKE2)
- 4 file header flags (RHDF_SPLITBEFORE, RHDF_SPLITAFTER, RHDF_ENCRYPTED, RHDF_SOLID)
- 9 archive flags (all ROADF_* except ROADF_VOLUME is unused)
- 1 open flag (ROADOF_KEEPBROKEN)
- 2 callback types (CHANGEVOLPROC, PROCESSDATAPROC)
- 5 callback message types (all except UCM_PROCESSDATA)
- RAR_DLL_VERSION constant

### **Actually Used**

- **Functions:** RAROpenArchive, RARCloseArchive, RARReadHeader, RARProcessFile, RARSetCallback, RARSetPassword (6 of 12)
- **Structs:** RARHeaderData, RAROpenArchiveData (2 of 4)
- **Callbacks:** UNRARCALLBACK (1 of 3)
- **Constants:** Most core error codes, the three process actions (RAR_SKIP, RAR_TEST, RAR_EXTRACT), two open modes (RAR_OM_LIST, RAR_OM_EXTRACT), RHDF_DIRECTORY (heavily filtered set)
- **Callback messages:** UCM_PROCESSDATA only (1 of 6)