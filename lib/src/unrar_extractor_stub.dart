import 'dart:typed_data';
import 'archive_entry.dart';

/// Stub implementation for UnrarExtractor
/// This will be replaced by platform-specific implementations:
/// - unrar_extractor_io.dart for native platforms (using FFI)
/// - unrar_extractor_web.dart for web platform (using WASM)
/// 
/// This stub ensures the interface is defined but throws if called.
class UnrarExtractor {
  /// Lists all files in a RAR archive.
  ///
  /// Returns a list of [ArchiveEntry] objects representing each file.
  /// Throws [UnrarException] if the archive cannot be opened or read.
  List<ArchiveEntry> listFiles(String archivePath) {
    throw UnsupportedError(
      'UnrarExtractor is not supported on this platform. '
      'Please use a supported platform (Windows, macOS, Linux, or Web).',
    );
  }

  /// Extracts all files from a RAR archive to the specified output directory.
  ///
  /// [archivePath]: Path to the RAR archive file.
  /// [outputPath]: Directory where files will be extracted.
  /// [password]: Optional password for encrypted archives.
  ///
  /// Throws [UnrarException] if extraction fails.
  void extractAll(String archivePath, String outputPath, {String? password}) {
    throw UnsupportedError(
      'UnrarExtractor is not supported on this platform. '
      'Please use a supported platform (Windows, macOS, Linux, or Web).',
    );
  }

  /// Extracts a single file from a RAR archive and returns its contents.
  ///
  /// [archivePath]: Path to the RAR archive file.
  /// [fileName]: Name of the file to extract from the archive.
  /// [password]: Optional password for encrypted archives.
  ///
  /// Returns the file contents as a [Uint8List].
  /// Throws [UnrarException] if the file is not found or extraction fails.
  Uint8List extractFile(
    String archivePath,
    String fileName, {
    String? password,
  }) {
    throw UnsupportedError(
      'UnrarExtractor is not supported on this platform. '
      'Please use a supported platform (Windows, macOS, Linux, or Web).',
    );
  }

  /// Tests a RAR archive for integrity.
  ///
  /// Returns true if the archive is valid and can be extracted.
  /// Throws [UnrarException] if the archive is corrupted or cannot be opened.
  bool testArchive(String archivePath, {String? password}) {
    throw UnsupportedError(
      'UnrarExtractor is not supported on this platform. '
      'Please use a supported platform (Windows, macOS, Linux, or Web).',
    );
  }
}
