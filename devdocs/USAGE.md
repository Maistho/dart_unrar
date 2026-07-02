# dart_unrar Usage Guide

Complete reference for using the `dart_unrar` package to extract and inspect RAR archives in Dart/Flutter applications.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [API Reference](#api-reference)
4. [Common Tasks](#common-tasks)
5. [Advanced Usage](#advanced-usage)
6. [Archive Flags](#archive-flags)
7. [Error Handling](#error-handling)
8. [Troubleshooting](#troubleshooting)

---

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  unrar:
    path: ../path/to/dart_unrar
```

**Requirements:**
- UnRAR library 7.0+ (checked at runtime)
- macOS, Linux, or Windows with `libunrar.so`/`.dylib`/`.dll` available
- Dart 3.0+

**On macOS (Homebrew):**
```bash
brew install unrar
```

**On Linux (Ubuntu/Debian):**
```bash
sudo apt-get install unrar
```

---

## Quick Start

### List files in an archive

```dart
import 'package:unrar/unrar.dart';

void main() {
  final extractor = UnrarExtractor();
  
  try {
    final entries = extractor.listFiles('archive.rar');
    for (final entry in entries) {
      print('${entry.name} (${entry.size} bytes)');
    }
  } on UnrarException catch (e) {
    print('Error: ${e.message}');
  }
}
```

### Extract all files

```dart
final extractor = UnrarExtractor();
extractor.extractAll('archive.rar', '/path/to/output');
```

### Extract a single file

```dart
final extractor = UnrarExtractor();
final bytes = extractor.extractFile('archive.rar', 'hello.txt');
print(String.fromCharCodes(bytes)); // decode if text
```

### Extract to memory (no disk writes)

```dart
final extractor = UnrarExtractor();
final content = extractor.extractFileToMemory('archive.rar', 'data.json');
final json = jsonDecode(utf8.decode(content));
```

---

## API Reference

### `UnrarExtractor`

Main class for all extraction and archive operations.

#### `listFiles(archivePath, {password})`

Lists all entries in a RAR archive.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `password` (String?): Optional password for encrypted archives

**Returns:** `List<ArchiveEntry>` — list of all files and directories

**Throws:** `UnrarException` on error

**Example:**
```dart
final entries = extractor.listFiles('secret.rar', password: 'mypassword');
for (final entry in entries) {
  print('File: ${entry.name}, Encrypted: ${entry.isEncrypted}');
}
```

#### `archiveInfo(archivePath, {password})`

Queries archive-level metadata without reading file headers.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `password` (String?): Optional password for encrypted-header archives

**Returns:** `ArchiveInfo` — metadata about the archive

**Throws:** `UnrarException` on error

**Example:**
```dart
final info = extractor.archiveInfo('archive.rar');
if (info.hasEncryptedHeaders) {
  print('This archive requires a password to list files');
}
if (info.isVolume) {
  print('Multi-volume archive detected');
}
```

#### `extractAll(archivePath, outputPath, {password})`

Extracts all files to disk, preserving directory structure.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `outputPath` (String): Directory where files will be extracted
- `password` (String?): Optional password for encrypted files

**Returns:** `void`

**Throws:** `UnrarException` on error

**Example:**
```dart
extractor.extractAll('archive.rar', '/tmp/extracted');
```

#### `extractFile(archivePath, fileName, {password})`

Extracts a single file by name to a temporary location and returns the bytes.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `fileName` (String): Path of the file in the archive (e.g., `subdir/file.txt`)
- `password` (String?): Optional password for encrypted files

**Returns:** `Uint8List` — file contents as bytes

**Throws:** `UnrarException` on error (file not found, wrong password, etc.)

**Example:**
```dart
final bytes = extractor.extractFile('archive.rar', 'document.pdf');
await File('output.pdf').writeAsBytes(bytes);
```

#### `extractFileToMemory(archivePath, fileName, {password})`

Extracts a single file directly to memory without disk writes.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `fileName` (String): Path of the file in the archive
- `password` (String?): Optional password for encrypted files

**Returns:** `Uint8List` — file contents as bytes

**Throws:** `UnrarException` on error

**Example:**
```dart
final imageBytes = extractor.extractFileToMemory('images.rar', 'photo.jpg');
final image = Image.memory(imageBytes);
```

#### `extractAllToMemory(archivePath, {password})`

Extracts all files directly to memory, skipping directories.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `password` (String?): Optional password for encrypted files

**Returns:** `Map<String, Uint8List>` — map of filename → file bytes

**Throws:** `UnrarException` on error

**Example:**
```dart
final files = extractor.extractAllToMemory('configs.rar');
for (final entry in files.entries) {
  print('${entry.key}: ${entry.value.length} bytes');
}
```

#### `testArchive(archivePath, {password})`

Verifies archive integrity by decompressing and checking CRC for all files.

**Parameters:**
- `archivePath` (String): Path to the `.rar` file
- `password` (String?): Optional password for encrypted files

**Returns:** `bool` — always `true` on success

**Throws:** `UnrarException` if archive is corrupted or password is wrong

**Example:**
```dart
try {
  extractor.testArchive('archive.rar');
  print('Archive is valid');
} on UnrarException catch (e) {
  print('Archive is corrupted: ${e.message}');
}
```

---

### `ArchiveEntry`

Represents a single file or directory in an archive.

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Filename, including relative paths (e.g., `subdir/file.txt`) |
| `size` | int | Uncompressed size in bytes |
| `packedSize` | int | Compressed size in bytes |
| `crc` | int | CRC32 checksum (or Blake2 hash when `hashType == 2`) |
| `attributes` | int | OS-specific file attributes (Unix mode, Windows attrs) |
| `modificationTime` | DateTime | Last modified timestamp |
| `isDirectory` | bool | Whether entry is a directory |
| `isEncrypted` | bool | Whether file data is encrypted |
| `isSplitBefore` | bool | Whether file continues from previous volume |
| `isSplitAfter` | bool | Whether file continues into next volume |
| `isSolid` | bool | Whether file is part of solid compression block |
| `hashType` | int | Hash algorithm: 0 = none, 1 = CRC32, 2 = Blake2 |

**Example:**
```dart
final entries = extractor.listFiles('archive.rar');
for (final entry in entries) {
  if (entry.isDirectory) continue;  // skip dirs
  
  print('${entry.name}');
  print('  Size: ${entry.size} → ${entry.packedSize} (compressed)');
  print('  Modified: ${entry.modificationTime}');
  
  if (entry.isEncrypted) {
    print('  ⚠ This file is encrypted');
  }
  if (entry.isSolid) {
    print('  • Part of solid block');
  }
}
```

---

### `ArchiveInfo`

Archive-level metadata about a RAR archive.

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `isVolume` | bool | Archive is part of a multi-volume set |
| `hasComment` | bool | Archive contains a comment |
| `isSolid` | bool | Archive uses solid compression |
| `hasEncryptedHeaders` | bool | Headers are encrypted (password needed even to list files) |
| `isFirstVolume` | bool | This is the first volume in a multi-volume set |
| `isLocked` | bool | Archive is locked against modification |
| `hasSigned` | bool | Archive has an authenticity signature |
| `hasRecovery` | bool | Archive contains a recovery record |

**Example:**
```dart
final info = extractor.archiveInfo('archive.rar');

if (info.hasEncryptedHeaders) {
  // Cannot list files without password
  final entries = extractor.listFiles('archive.rar', password: userPassword);
} else {
  // Can list files freely
  final entries = extractor.listFiles('archive.rar');
}

if (info.isVolume && info.isFirstVolume) {
  print('First volume of multi-volume archive');
  // extractAll() automatically reassembles files across volumes
}
```

---

### `UnrarException`

Exception thrown by all extraction methods.

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `message` | String | Human-readable error message |
| `errorCode` | int? | UnRAR library error code (nullable) |

**Example:**
```dart
try {
  extractor.extractFile('archive.rar', 'missing.txt');
} on UnrarException catch (e) {
  print('Error: ${e.message}');
  if (e.errorCode != null) {
    print('Code: ${e.errorCode}');
  }
}
```

---

## Common Tasks

### Check if archive exists and is valid

```dart
import 'dart:io';

final file = File('archive.rar');
if (!file.existsSync()) {
  print('Archive not found');
  return;
}

final extractor = UnrarExtractor();
try {
  extractor.testArchive('archive.rar');
  print('Archive is valid');
} on UnrarException catch (e) {
  print('Archive is corrupted: ${e.message}');
}
```

### List and filter files

```dart
final extractor = UnrarExtractor();
final entries = extractor.listFiles('archive.rar');

// Find all text files
final textFiles = entries.where((e) => e.name.endsWith('.txt'));
for (final f in textFiles) {
  print('${f.name} (${f.size} bytes)');
}

// Find large files
final large = entries.where((e) => e.size > 10 * 1024 * 1024);
for (final f in large) {
  print('${f.name} is ${f.size ~/ (1024*1024)} MB');
}
```

### Extract only if password is correct

```dart
final extractor = UnrarExtractor();

try {
  extractor.extractAll('secret.rar', '/tmp/out', password: 'test123');
  print('Extraction successful');
} on UnrarException catch (e) {
  if (e.message.contains('password')) {
    print('Wrong password');
  } else {
    print('Extraction failed: ${e.message}');
  }
}
```

### Count files without extracting

```dart
final extractor = UnrarExtractor();
final entries = extractor.listFiles('archive.rar');
final fileCount = entries.where((e) => !e.isDirectory).length;
final dirCount = entries.where((e) => e.isDirectory).length;

print('Files: $fileCount, Directories: $dirCount');
```

### Get total uncompressed size

```dart
final extractor = UnrarExtractor();
final entries = extractor.listFiles('archive.rar');
final totalSize = entries.fold<int>(0, (sum, e) => sum + e.size);

print('Total size: ${totalSize ~/ (1024*1024)} MB');
```

### Extract with progress tracking

```dart
import 'dart:io';

final extractor = UnrarExtractor();
final entries = extractor.listFiles('archive.rar');
final totalSize = entries.fold<int>(0, (sum, e) => sum + e.size);
int extracted = 0;

for (final entry in entries) {
  if (entry.isDirectory) continue;
  
  final bytes = extractor.extractFile('archive.rar', entry.name);
  await File('/tmp/out/${entry.name}').writeAsBytes(bytes);
  
  extracted += entry.size;
  final percent = (extracted * 100) ~/ totalSize;
  print('Progress: $percent% ($extracted / $totalSize bytes)');
}
```

---

## Advanced Usage

### Multi-volume archives

Multi-volume archives (`.part01.rar`, `.part02.rar`, etc.) are automatically reassembled:

```dart
final extractor = UnrarExtractor();

// Volumes must be co-located and follow naming convention:
// archive.part01.rar
// archive.part02.rar
// archive.part03.rar

// Extract from first volume; the library handles the rest
extractor.extractAll('archive.part01.rar', '/tmp/out');

// List files from first volume (includes files split across volumes)
final entries = extractor.listFiles('archive.part01.rar');
for (final e in entries) {
  if (e.isSplitBefore || e.isSplitAfter) {
    print('${e.name} spans multiple volumes');
  }
}
```

### Solid archives

Solid archives concatenate files before compression for better ratios. Extraction works the same way:

```dart
final extractor = UnrarExtractor();
final info = extractor.archiveInfo('archive.rar');

if (info.isSolid) {
  print('This is a solid archive — extraction may be slower');
}

// Extraction is automatic; no special handling needed
extractor.extractAll('archive.rar', '/tmp/out');
```

### Encrypted data vs. encrypted headers

**Encrypted data:** File listing is possible without password, but extracting requires it.

```dart
final extractor = UnrarExtractor();

// Can list files without password
final entries = extractor.listFiles('archive.rar');
print('Found ${entries.length} encrypted files');

// But extraction requires password
try {
  extractor.extractFile('archive.rar', 'secret.txt');
} on UnrarException catch (e) {
  print('Need password: ${e.message}');
}

// With password, extraction works
final bytes = extractor.extractFile(
  'archive.rar', 'secret.txt',
  password: 'correct_password'
);
```

**Encrypted headers:** File listing itself requires a password.

```dart
final extractor = UnrarExtractor();
final info = extractor.archiveInfo('archive.rar');

if (info.hasEncryptedHeaders) {
  // Cannot list without password
  try {
    extractor.listFiles('archive.rar');
  } on UnrarException {
    print('Headers are encrypted — need password');
  }
  
  // Must supply password to even see what's inside
  final entries = extractor.listFiles(
    'archive.rar',
    password: 'correct_password'
  );
  print('Found ${entries.length} files');
}
```

### Large files and 64-bit sizes

The library supports files larger than 4 GB:

```dart
final extractor = UnrarExtractor();
final entries = extractor.listFiles('huge.rar');

for (final entry in entries) {
  // size and packedSize are 64-bit integers
  final gb = entry.size / (1024 * 1024 * 1024);
  print('${entry.name}: ${gb.toStringAsFixed(2)} GB');
}
```

### Integrity verification with hash checking

Files can be verified using CRC32 or Blake2:

```dart
final extractor = UnrarExtractor();
final entries = extractor.listFiles('archive.rar');

for (final entry in entries) {
  final hashName = {
    0: 'none',
    1: 'CRC32',
    2: 'Blake2',
  }[entry.hashType] ?? 'unknown';
  
  print('${entry.name}: $hashName (${entry.crc.toRadixString(16)})');
}
```

---

## Archive Flags

### File-level flags (`ArchiveEntry`)

| Flag | Property | Meaning |
|------|----------|---------|
| `RHDF_ENCRYPTED` | `isEncrypted` | File requires password to extract |
| `RHDF_SPLITBEFORE` | `isSplitBefore` | File started in previous volume |
| `RHDF_SPLITAFTER` | `isSplitAfter` | File continues into next volume |
| `RHDF_SOLID` | `isSolid` | File is part of solid compression block |

### Archive-level flags (`ArchiveInfo`)

| Flag | Property | Meaning |
|------|----------|---------|
| `ROADF_VOLUME` | `isVolume` | Multi-volume set |
| `ROADF_ENCHEADERS` | `hasEncryptedHeaders` | Headers encrypted (need password to list) |
| `ROADF_SOLID` | `isSolid` | Solid compression used |
| `ROADF_FIRSTVOLUME` | `isFirstVolume` | This is first volume |
| `ROADF_COMMENT` | `hasComment` | Archive has a comment |
| `ROADF_LOCK` | `isLocked` | Archive is locked/read-only |
| `ROADF_SIGNED` | `hasSigned` | Authenticity signature present |
| `ROADF_RECOVERY` | `hasRecovery` | Recovery record present |

---

## Error Handling

### Common error scenarios

```dart
import 'dart:io';
import 'package:unrar/unrar.dart';

Future<void> safeExtract(String archivePath, String outputPath) async {
  final extractor = UnrarExtractor();
  
  try {
    extractor.extractAll(archivePath, outputPath);
    print('✓ Extraction successful');
  } on UnrarException catch (e) {
    if (e.message.contains('not found') || e.message.contains('No such')) {
      print('✗ Archive file not found: $archivePath');
    } else if (e.message.contains('password')) {
      print('✗ This archive requires a password');
    } else if (e.message.contains('Bad CRC') || 
               e.message.contains('corrupted')) {
      print('✗ Archive is corrupted');
    } else if (e.message.contains('ERAR_NO_MEMORY')) {
      print('✗ Not enough memory to extract');
    } else {
      print('✗ Extraction failed: ${e.message}');
    }
  } catch (e) {
    print('✗ Unexpected error: $e');
  }
}
```

### Type-safe password handling

```dart
Future<void> extractWithPrompt(String archivePath) async {
  final extractor = UnrarExtractor();
  
  // Check if password is needed before attempting extraction
  final info = extractor.archiveInfo(archivePath);
  
  String? password;
  if (info.hasEncryptedHeaders) {
    print('This archive is password-protected');
    // Prompt user for password
    password = getUserPassword(); // your implementation
  }
  
  try {
    extractor.extractAll(archivePath, '/tmp/out', password: password);
  } on UnrarException catch (e) {
    if (e.message.contains('password')) {
      print('Wrong password');
    } else {
      print('Extraction failed: ${e.message}');
    }
  }
}
```

---

## Troubleshooting

### "Cannot open shared library libunrar"

**Cause:** UnRAR library is not installed or not in the system library path.

**Solution:**
```bash
# macOS
brew install unrar

# Linux (Ubuntu/Debian)
sudo apt-get install libunrar5

# Linux (Fedora/RHEL)
sudo dnf install unrar
```

### "Loaded unrar library version X is older than required"

**Cause:** System has an old version of UnRAR (<7.0).

**Solution:** Update UnRAR to 7.0 or newer (see above).

### "Wrong password" errors with encrypted archives

**Cause:** Incorrect password or encoded incorrectly.

**Solution:**
```dart
// Ensure password is passed as a plain string
final bytes = extractor.extractFile(
  'archive.rar', 'file.txt',
  password: 'correct_password',  // not base64, not encoded
);
```

### Memory exhaustion on large archives

**Cause:** `extractAllToMemory()` loads all files into RAM simultaneously.

**Solution:** Use streaming or disk extraction for large archives:
```dart
// Good for small archives
final files = extractor.extractAllToMemory('small.rar');

// Better for large archives
extractor.extractAll('large.rar', '/tmp/out');
// Now process files from disk as needed
```

### File permissions after extraction (Linux/macOS)

**Cause:** Extracted files may have different permissions than originals.

**Solution:** Adjust permissions after extraction:
```dart
import 'dart:io';

extractor.extractAll('archive.rar', '/tmp/out');

// Make extracted files world-readable
for (final f in Directory('/tmp/out').listSync(recursive: true)) {
  if (f is File) {
    // Set to -rw-r--r-- (644 in octal)
    Process.runSync('chmod', ['644', f.path]);
  }
}
```

### Performance is slow

**Cause:** Solid archives or large files require sequential decompression.

**Solution:**
- Use `testArchive()` sparingly (verifies entire archive)
- Extract only needed files instead of all at once
- For batch processing, use `extractAll()` once rather than repeated single-file calls

### Archives with non-ASCII filenames

**Cause:** UTF-8 filenames may require special encoding handling.

**Solution:** The library handles UTF-8 automatically:
```dart
final entries = extractor.listFiles('archive.rar');
for (final entry in entries) {
  // entry.name is automatically UTF-8 decoded
  print(entry.name); // handles é, ñ, 中文, etc.
}
```

---

## See Also

- [Gap Analysis](Gap_analysis_dll_vs_dart.md) — API completeness vs. native DLL
- [Implementation Notes](Implementation_Notes.md) — Technical details (wchar_t, DOS dates, etc.)
- [Test Inventory](Test_Inventory.md) — Comprehensive test coverage reference
- [RAR 5.0 Format](RAR%205.0%20archive%20format.md) — Archive format specification
