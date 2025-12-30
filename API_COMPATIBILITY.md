# API Compatibility Considerations for Web Support

## The Async Challenge

### Current State

The existing API for native platforms is synchronous:
```dart
class UnrarExtractor {
  List<ArchiveEntry> listFiles(String archivePath);
  void extractAll(String archivePath, String outputPath, {String? password});
  Uint8List extractFile(String archivePath, String fileName, {String? password});
  bool testArchive(String archivePath, {String? password});
}
```

### Web Requirements

The web implementation requires async methods because:
1. **WASM Module Loading**: The module must be loaded asynchronously
2. **File Loading**: Reading files from the browser File API is async
3. **Large Operations**: Long-running extractions should not block the UI

This means the web API would ideally be:
```dart
class UnrarExtractor {
  Future<List<ArchiveEntry>> listFiles(String archivePath);
  Future<void> extractAll(String archivePath, String outputPath, {String? password});
  Future<Uint8List> extractFile(String archivePath, String fileName, {String? password});
  Future<bool> testArchive(String archivePath, {String? password});
}
```

## Solutions

### Option 1: Make Everything Async (Breaking Change)

**Pros:**
- Consistent API across all platforms
- Future-proof for other async needs
- Better for large operations on all platforms

**Cons:**
- Breaking change for existing users
- Requires version bump to 1.0.0 or 0.3.0 with migration guide
- Native code runs synchronously but returns Future

**Implementation:**
```dart
// Native (IO)
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  return _listFilesSync(archivePath); // Wrap sync in Future
}

// Web
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  await _ensureInitialized();
  // Async WASM calls
}
```

### Option 2: Separate Async Methods (Deprecation Path)

**Pros:**
- Backward compatible
- Clear migration path
- Users can choose sync or async

**Cons:**
- Duplicate API surface
- Maintenance burden
- May confuse users

**Implementation:**
```dart
class UnrarExtractor {
  // Existing sync methods (native only)
  List<ArchiveEntry> listFiles(String archivePath) { ... }
  
  // New async methods (all platforms)
  Future<List<ArchiveEntry>> listFilesAsync(String archivePath) async { ... }
  
  // Deprecate sync methods
  @Deprecated('Use listFilesAsync instead')
  List<ArchiveEntry> listFiles(String archivePath) { ... }
}
```

### Option 3: Platform-Specific APIs

**Pros:**
- No breaking changes
- Each platform optimized

**Cons:**
- Different APIs per platform
- Code not portable between platforms
- Confusing documentation

**Implementation:**
```dart
// Export different implementations
export 'unrar_extractor_io.dart'    // Sync methods
    if (dart.library.js_interop) 'unrar_extractor_web.dart';  // Async methods
```

### Option 4: Isolate-Based Async for Native

**Pros:**
- Truly async on all platforms
- Non-blocking on native platforms
- Consistent API

**Cons:**
- More complex implementation
- Higher overhead for small operations
- Serialization costs

**Implementation:**
```dart
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  return await Isolate.run(() => _listFilesSync(archivePath));
}
```

## Recommendation

**For this PR**: Use **Option 1** (Make Everything Async) because:

1. **Modern Dart**: Async APIs are standard in modern Dart
2. **Consistency**: Same API works on all platforms
3. **Future-Proof**: Ready for web and other async scenarios
4. **User Experience**: Non-blocking operations are better UX
5. **Package Maturity**: Package is pre-1.0, so breaking changes are acceptable

### Migration Guide for Users

```dart
// Before (0.1.x)
final files = extractor.listFiles('archive.rar');

// After (0.2.0)
final files = await extractor.listFiles('archive.rar');
```

### Implementation Plan

1. Update all method signatures to return `Future<T>`
2. Wrap native FFI calls in `Future.value()` or use isolates
3. Implement true async for web platform
4. Update all examples and tests
5. Add migration guide to CHANGELOG
6. Document in README

### Code Changes Required

**lib/src/unrar_extractor_io.dart**:
```dart
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  // Option A: Simple wrap (doesn't unblock)
  return Future.value(_listFilesSync(archivePath));
  
  // Option B: Use isolate (truly async)
  return await Isolate.run(() => _listFilesSync(archivePath));
}
```

**lib/src/unrar_extractor_web.dart**:
```dart
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  await _ensureInitialized();
  // Actual async implementation
}
```

**lib/src/unrar_extractor_stub.dart**:
```dart
Future<List<ArchiveEntry>> listFiles(String archivePath) async {
  throw UnsupportedError('...');
}
```

## Alternative: Hybrid Approach

If breaking changes are not acceptable, implement:

1. Keep existing sync methods for native platforms
2. Add async methods that work on all platforms
3. Document that sync methods throw on web
4. Gradually deprecate sync methods

```dart
class UnrarExtractor {
  // Sync (native only, throws on web)
  List<ArchiveEntry> listFiles(String archivePath) {
    if (kIsWeb) {
      throw UnsupportedError('Use listFilesAsync on web');
    }
    return _listFilesSync(archivePath);
  }
  
  // Async (all platforms)
  Future<List<ArchiveEntry>> listFilesAsync(String archivePath) async {
    // Works everywhere
  }
}
```

## Feedback Needed

Before implementing, we should:
1. Discuss with package maintainer
2. Get community feedback
3. Consider compatibility requirements
4. Decide on version numbering

## Conclusion

Web support necessitates async APIs. The choice is between:
- Making a clean break with async-everywhere (recommended)
- Maintaining dual APIs during transition
- Having platform-specific behaviors

For a pre-1.0 package focused on modern Dart practices, **async-everywhere** is the best long-term solution.
