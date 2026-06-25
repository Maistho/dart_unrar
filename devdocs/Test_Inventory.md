# Test Inventory — dart_unrar

## Overview

The dart_unrar package has **103 passing tests** across two test files:

- **`test/unrar_ffi_test.dart`** — 15 tests (original core functionality)
- **`test/comprehensive_test.dart`** — 88 tests (gap fixes + new features)

Tests exercise all six extraction methods, archive metadata queries, password handling, multi-volume archives, and exception behavior.

---

## File: test/unrar_ffi_test.dart (15 tests)

### UnrarExtractor (8 tests)

| Test | Coverage |
|------|----------|
| `listFiles returns files from archive` | Basic RAR5, file count, names, not-directory flags |
| `testArchive validates archive successfully` | Archive integrity check returns successfully |
| `extractAll extracts all files` | Disk extraction writes files to output directory |
| `extractFile returns file data` | Single file extraction from disk |
| `listFiles throws exception for non-existent archive` | Error handling on missing file |
| `extractAll throws exception for non-existent archive` | Error handling on missing file |
| `testArchive throws exception for non-existent archive` | Error handling on missing file |
| `extractFileToMemory returns file contents without disk writes` | Memory extraction, `Uint8List` result type |
| `extractFileToMemory throws for non-existent file` | Error handling for missing entry |
| `extractAllToMemory returns map with all entries` | Memory extraction, map result type, multiple files |
| `extractAllToMemory content matches extractFile per-entry` | Cross-method consistency |
| `extractFileToMemory content matches extractFile` | Cross-method consistency |

### ArchiveEntry (1 test)

| Test | Coverage |
|------|----------|
| `toString returns correct format` | String representation includes `isEncrypted` |

### UnrarException (2 tests)

| Test | Coverage |
|------|----------|
| `toString without error code` | Exception message formatting |
| `toString with error code` | Exception message formatting with error code |

---

## File: test/comprehensive_test.dart (88 tests)

### listFiles (15 tests)

| Test | Coverage |
|------|----------|
| `basic RAR5: returns correct entry count and names` | File enumeration from standard archive |
| `basic RAR5: entries are not directories` | `isDirectory` flag for files |
| `basic RAR5: entry sizes match source files` | Unpacked and packed sizes |
| `basic RAR5: entries not encrypted` | `isEncrypted` flag for unencrypted archives |
| `basic RAR5: entries not split` | `isSplitBefore` and `isSplitAfter` flags |
| `with_dirs: directory entries present` | Nested path handling (subdir/nested.txt) |
| `solid: lists all files in solid archive` | Solid archive enumeration |
| `solid: entries report isSolid` | `isSolid` flag detection |
| `encrypted_data: entries show isEncrypted=true` | `isEncrypted` flag for encrypted-data archives |
| `encrypted_data: listing without password works` | Headers visible even without password |
| `encrypted_headers: listing without password throws` | Cannot read headers without password |
| `binary: binary file listed with correct size` | Binary data size accuracy |
| `non-existent archive throws UnrarException` | Error handling, missing file |
| `non-existent archive error has meaningful message` | Error code and message availability |
| `multi-volume first part: lists files spanning volumes` | Split file flag detection across volumes |

### archiveInfo (6 tests)

| Test | Coverage |
|------|----------|
| `basic archive: not volume, not solid, not encrypted headers` | Archive-level flag combinations |
| `solid archive: reports isSolid` | Solid compression detection |
| `multi-volume first part: isVolume and isFirstVolume` | Multi-volume first-part detection |
| `multi-volume second part: isVolume but not isFirstVolume` | Multi-volume non-first detection |
| `encrypted_headers archive: reports hasEncryptedHeaders` | Encrypted-header flag detection |
| `non-existent archive throws UnrarException` | Error handling, missing file |

### testArchive (7 tests)

| Test | Coverage |
|------|----------|
| `basic RAR5 passes integrity check and returns true` | Successful verification |
| `solid archive passes integrity check` | Solid archive verification |
| `binary archive passes integrity check` | Binary data verification |
| `encrypted_data with correct password passes` | Password-protected archive verification |
| `encrypted_data without password throws` | Wrong/missing password error |
| `encrypted_data with wrong password throws` | Wrong password error |
| `non-existent archive throws UnrarException` | Error handling, missing file |

### extractAll (8 tests)

| Test | Coverage |
|------|----------|
| `basic RAR5: extracts all files to output directory` | Multi-file disk extraction |
| `basic RAR5: extracted content matches source` | Content integrity (ASCII) |
| `with_dirs: preserves directory structure` | Nested directory creation |
| `binary: extracts binary file with exact bytes` | Binary data integrity (0x00..0xFF pattern) |
| `encrypted_data with correct password extracts successfully` | Password-protected extraction |
| `encrypted_data without password throws` | Missing password error |
| `non-existent archive throws UnrarException` | Error handling, missing file |
| `multi-volume: extracts complete file from all volumes` | Multi-volume reassembly (3000-byte file across 4 volumes) |

### extractFile (10 tests)

| Test | Coverage |
|------|----------|
| `extracts first file by name and returns correct content` | Single-file disk extraction |
| `extracts second file by name and returns correct content` | UTF-8 filename handling (em dash in "world.txt") |
| `extracts binary file with correct bytes` | Binary data integrity |
| `extracts file from nested path in archive` | Nested path (subdir/nested.txt) |
| `extracts from solid archive` | Solid archive extraction |
| `extracts with correct password` | Password-protected file extraction |
| `throws for wrong password` | Invalid password error |
| `throws for missing password on encrypted file` | Missing password error |
| `throws when file name not found in archive` | Entry-not-found error |
| `throws for non-existent archive` | Error handling, missing file |

### extractFileToMemory (10 tests)

| Test | Coverage |
|------|----------|
| `returns Uint8List with correct content` | Memory extraction result type and content |
| `result matches extractFile for same file` | Cross-method consistency (disk vs. memory) |
| `extracts binary file to memory with exact bytes` | Binary data integrity |
| `extracts file from nested path in archive` | Nested path extraction to memory |
| `extracts from solid archive` | Solid archive memory extraction |
| `extracts with correct password` | Password-protected memory extraction |
| `throws when file not found` | Entry-not-found error |
| `throws for missing password on encrypted file` | Missing password error |
| `throws for non-existent archive` | Error handling, missing file |
| `consecutive calls with same extractor instance succeed` | State management across multiple extractions (`_nextId`, `_pendingData` cleanup) |

### extractAllToMemory (9 tests)

| Test | Coverage |
|------|----------|
| `returns map with all file entries` | Memory extraction result type (map of name → bytes) |
| `content matches source files` | UTF-8 decoding in assertions |
| `content matches extractFile for each entry` | Cross-method consistency per-entry |
| `includes nested paths from directory archive` | Nested path handling in memory extraction |
| `binary file bytes are exact` | Binary data integrity |
| `solid archive: all entries extracted correctly` | Multi-entry memory extraction from solid archive |
| `encrypted_data with correct password` | Password-protected multi-file extraction |
| `encrypted_data without password throws` | Missing password error |
| `non-existent archive throws` | Error handling, missing file |
| `returns empty map for archive with only directories` | Directory-only archive handling (directories skipped) |

### ArchiveEntry (8 tests)

| Test | Coverage |
|------|----------|
| `default flags are false` | Optional parameter defaults |
| `value equality: identical fields compare equal` | `operator==` implementation |
| `value equality: different name → not equal` | Inequality on name difference |
| `value equality: isEncrypted difference → not equal` | Inequality on flag difference |
| `toString includes isEncrypted` | String representation includes new flag |
| `fromListFiles: encrypted entry has isEncrypted=true` | Flag population from header |
| `fromListFiles: basic archive entries have correct sizes` | Size accuracy from header |
| `fromListFiles: modification time is plausible` | DOS date parsing (year >= 1980) |

### UnrarException (5 tests)

| Test | Coverage |
|------|----------|
| `toString without error code` | Exception formatting without code |
| `toString with error code` | Exception formatting with code |
| `message is accessible` | Message and error code properties |
| `error code is null when not supplied` | Optional error code |
| `implements Exception` | Exception interface compliance |

### ArchiveInfo (5 tests)

| Test | Coverage |
|------|----------|
| `basic archive: all false except expected` | Archive-level flag combinations |
| `solid archive: isSolid true` | Solid flag detection |
| `multi-volume part 1: isVolume and isFirstVolume true` | Multi-volume first-part flags |
| `multi-volume part 2: isVolume true, isFirstVolume false` | Multi-volume non-first flags |
| `toString includes key fields` | String representation |

### multi-volume (4 tests)

| Test | Coverage |
|------|----------|
| `listFiles on first part returns entries with split flags` | Split flags on entries spanning volumes |
| `extractAll from first part reassembles file across volumes` | Multi-volume file assembly |
| `extracted multi-volume content matches source` | Multi-volume content integrity |
| `testArchive on first part verifies complete content` | Multi-volume integrity verification |

---

## Test Archive Coverage

| Archive Type | Tests Using It |
|--------------|---|
| `basic_rar5.rar` | 28 tests (basic functionality baseline) |
| `with_dirs.rar` | 5 tests (directory structure) |
| `solid.rar` | 6 tests (solid compression) |
| `binary.rar` | 5 tests (binary data integrity) |
| `encrypted_data.rar` | 10 tests (password-protected data) |
| `encrypted_headers.rar` | 1 test (header encryption) |
| `unicode_names.rar` | 0 tests (reserved for future UTF-8 filename tests) |
| `multi.part01..04.rar` | 8 tests (multi-volume) |

---

## Feature Coverage Map

| Feature | Tests | Status |
|---------|-------|--------|
| **File Enumeration** | `listFiles`: 15 | ✓ Comprehensive |
| **Archive Metadata** | `archiveInfo`: 6 | ✓ All flags covered |
| **Disk Extraction** | `extractAll`: 8, `extractFile`: 10 | ✓ Comprehensive |
| **Memory Extraction** | `extractFileToMemory`: 10, `extractAllToMemory`: 9 | ✓ Comprehensive |
| **Integrity Testing** | `testArchive`: 7 | ✓ All scenarios |
| **Password Handling** | 7 tests across methods | ✓ Correct/wrong/missing |
| **Multi-Volume** | 8 tests | ✓ Volume assembly |
| **Encryption** | 10 tests | ✓ Data + headers |
| **Binary Data** | 5 tests | ✓ Byte-exact verification |
| **Directory Structure** | 5 tests | ✓ Nesting + skipping |
| **UTF-8 Filenames** | 2 tests | ✓ Em dash in world.txt |
| **DOS Date Parsing** | 1 test | ✓ Year >= 1980 |
| **Error Handling** | 12 tests (missing file, missing password) | ✓ All major paths |
| **Cross-Method Consistency** | 3 tests (disk vs. memory) | ✓ Verified |
| **State Management** | 1 test (`_nextId`, `_pendingData` cleanup) | ✓ Multiple calls |

---

## Gaps

- **Unicode filename extraction**: Archive `unicode_names.rar` exists but no test actively extracts café.txt to verify round-trip.
- **Sub-second timestamps**: `RARHeaderDataEx` has `MtimeLow/High` (FILETIME) but tests only verify DOS-date format.
- **Large dictionary consent**: `UCM_LARGEDICT` callback is implemented but not tested (no test archive uses it).
- **Corrupted archive detection**: No test for files with truncated/corrupted data payloads (only file-not-found tested).

---

## Running Tests

```bash
# All tests
dart test

# Single file
dart test test/unrar_ffi_test.dart
dart test test/comprehensive_test.dart

# Single group
dart test -k "listFiles"
dart test -k "multi-volume"

# With verbose output
dart test -v
```

All 103 tests pass on macOS 14.x with Dart 3.5.x and UnRAR 7.22 trial.
