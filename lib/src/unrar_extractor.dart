/// Platform-conditional export for UnrarExtractor
/// - Uses FFI implementation for native platforms (IO)
/// - Uses WASM implementation for web platform
/// - Falls back to stub for unsupported platforms
export 'unrar_extractor_stub.dart'
    if (dart.library.io) 'unrar_extractor_io.dart'
    if (dart.library.js_interop) 'unrar_extractor_web.dart';
