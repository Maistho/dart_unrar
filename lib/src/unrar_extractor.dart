import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'unrar_exception.dart';
import 'archive_entry.dart';
import 'unrar_bindings.dart' as bindings;

/// High-level interface for extracting RAR archives.
class UnrarExtractor {
  static DynamicLibrary? _dylib;

  static DynamicLibrary get _lib {
    if (_dylib != null) return _dylib!;

    // Try multiple paths to find the library
    final possiblePaths = <String>[];

    if (Platform.isMacOS) {
      possiblePaths.addAll([
        '.dart_tool/lib/libunrar.dylib',
        'libunrar.dylib',
        '../.dart_tool/lib/libunrar.dylib',
      ]);
    } else if (Platform.isLinux) {
      possiblePaths.addAll([
        '.dart_tool/lib/libunrar.so',
        'libunrar.so',
        '../.dart_tool/lib/libunrar.so',
      ]);
    } else if (Platform.isWindows) {
      possiblePaths.addAll([
        '.dart_tool/lib/unrar.dll',
        'unrar.dll',
        '../.dart_tool/lib/unrar.dll',
      ]);
    } else {
      throw UnsupportedError(
        'Unsupported platform: ${Platform.operatingSystem}',
      );
    }

    // Try each path
    for (final path in possiblePaths) {
      try {
        _dylib = DynamicLibrary.open(path);
        return _dylib!;
      } catch (_) {
        // Try next path
      }
    }

    throw UnrarException(
      'Failed to load native library. Please run "dart pub get" to build the library.',
    );
  }

  // FFI function signatures
  late final Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>)
      _rarOpenArchive = _lib.lookupFunction<
          Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>),
          Pointer<Void> Function(
              Pointer<bindings.RAROpenArchiveData>)>('RAROpenArchive');

  late final int Function(Pointer<Void>) _rarCloseArchive = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('RARCloseArchive');

  late final int Function(Pointer<Void>, Pointer<bindings.RARHeaderData>)
      _rarReadHeader = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<bindings.RARHeaderData>),
          int Function(
              Pointer<Void>, Pointer<bindings.RARHeaderData>)>('RARReadHeader');

  late final int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>)
      _rarProcessFile = _lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, int, Pointer<Utf8>,
              Pointer<Utf8>)>('RARProcessFile');

  late final void Function(Pointer<Void>, Pointer<Utf8>) _rarSetPassword =
      _lib.lookupFunction<Void Function(Pointer<Void>, Pointer<Utf8>),
          void Function(Pointer<Void>, Pointer<Utf8>)>('RARSetPassword');
  // Constants from dll.hpp
  static const int ERAR_END_ARCHIVE = 10;
  static const int ERAR_NO_MEMORY = 11;
  static const int ERAR_BAD_DATA = 12;
  static const int ERAR_BAD_ARCHIVE = 13;
  static const int ERAR_UNKNOWN_FORMAT = 14;
  static const int ERAR_EOPEN = 15;
  static const int ERAR_ECREATE = 16;
  static const int ERAR_ECLOSE = 17;
  static const int ERAR_EREAD = 18;
  static const int ERAR_EWRITE = 19;
  static const int ERAR_SMALL_BUF = 20;
  static const int ERAR_UNKNOWN = 21;
  static const int ERAR_MISSING_PASSWORD = 22;

  static const int RAR_OM_LIST = 0;
  static const int RAR_OM_EXTRACT = 1;
  static const int RAR_OM_LIST_INCSPLIT = 2;

  static const int RAR_SKIP = 0;
  static const int RAR_TEST = 1;
  static const int RAR_EXTRACT = 2;

  // RARHeaderDataEx structure size and offsets
  static const int HEADER_SIZE = 560;

  /// Lists all files in a RAR archive.
  ///
  /// Returns a list of [ArchiveEntry] objects representing each file.
  /// Throws [UnrarException] if the archive cannot be opened or read.
  List<ArchiveEntry> listFiles(String archivePath) {
    final entries = <ArchiveEntry>[];
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_LIST;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          final headerData = calloc<bindings.RARHeaderData>();
          try {
            while (true) {
              final result = _rarReadHeader(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final fileNameChars = <int>[];
              for (var i = 0; i < 260; i++) {
                final char = headerData.ref.FileName[i];
                if (char == 0) break;
                fileNameChars.add(char);
              }
              final fileNameStr = String.fromCharCodes(fileNameChars);
              final isDirectory =
                  (headerData.ref.Flags & bindings.RHDF_DIRECTORY) != 0;

              final unixTime = headerData.ref.FileTime;
              final modTime = DateTime.fromMillisecondsSinceEpoch(
                unixTime * 1000,
                isUtc: true,
              );

              entries.add(
                ArchiveEntry(
                  name: fileNameStr,
                  size: headerData.ref.UnpSize,
                  packedSize: headerData.ref.PackSize,
                  crc: headerData.ref.FileCRC,
                  attributes: headerData.ref.FileAttr,
                  modificationTime: modTime,
                  isDirectory: isDirectory,
                ),
              );

              // Skip to next file
              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_SKIP,
                nullptr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }

    return entries;
  }

  /// Extracts all files from a RAR archive to the specified output directory.
  ///
  /// [archivePath]: Path to the RAR archive file.
  /// [outputPath]: Directory where files will be extracted.
  /// [password]: Optional password for encrypted archives.
  ///
  /// Throws [UnrarException] if extraction fails.
  void extractAll(String archivePath, String outputPath, {String? password}) {
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          if (password != null) {
            final passwordPtr = password.toNativeUtf8();
            try {
              _rarSetPassword(handle, passwordPtr);
            } finally {
              calloc.free(passwordPtr);
            }
          }

          final headerData = calloc<bindings.RARHeaderData>();
          final destPathPtr = outputPath.toNativeUtf8();
          try {
            while (true) {
              final result = _rarReadHeader(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_EXTRACT,
                destPathPtr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(destPathPtr);
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }
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
    final tempDir = Directory.systemTemp.createTempSync('unrar_');
    try {
      final tempOutputPath = tempDir.path;

      final archiveData = calloc<bindings.RAROpenArchiveData>();
      try {
        final archiveNamePtr = archivePath.toNativeUtf8();
        try {
          archiveData.ref.ArcName = archiveNamePtr.cast();
          archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
          archiveData.ref.CmtBuf = nullptr;
          archiveData.ref.CmtBufSize = 0;

          final handle = _rarOpenArchive(archiveData);
          if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
            throw UnrarException(
              _getErrorMessage(archiveData.ref.OpenResult),
              archiveData.ref.OpenResult,
            );
          }

          try {
            if (password != null) {
              final passwordPtr = password.toNativeUtf8();
              try {
                _rarSetPassword(handle, passwordPtr);
              } finally {
                calloc.free(passwordPtr);
              }
            }

            final headerData = calloc<bindings.RARHeaderData>();
            final destPathPtr = tempOutputPath.toNativeUtf8();
            try {
              var found = false;
              while (true) {
                final result = _rarReadHeader(handle, headerData);
                if (result == bindings.ERAR_END_ARCHIVE) break;
                if (result != bindings.ERAR_SUCCESS) {
                  throw UnrarException(_getErrorMessage(result), result);
                }

                final fileNameChars = <int>[];
                for (var i = 0; i < 260; i++) {
                  final char = headerData.ref.FileName[i];
                  if (char == 0) break;
                  fileNameChars.add(char);
                }
                final currentFileName = String.fromCharCodes(fileNameChars);

                if (currentFileName == fileName) {
                  found = true;
                  final processResult = _rarProcessFile(
                    handle,
                    bindings.RAR_EXTRACT,
                    destPathPtr,
                    nullptr,
                  );
                  if (processResult != bindings.ERAR_SUCCESS) {
                    throw UnrarException(
                      _getErrorMessage(processResult),
                      processResult,
                    );
                  }
                  break;
                } else {
                  final processResult = _rarProcessFile(
                    handle,
                    bindings.RAR_SKIP,
                    nullptr,
                    nullptr,
                  );
                  if (processResult != bindings.ERAR_SUCCESS) {
                    throw UnrarException(
                      _getErrorMessage(processResult),
                      processResult,
                    );
                  }
                }
              }

              if (!found) {
                throw UnrarException('File not found in archive: $fileName');
              }

              final extractedFile = File('$tempOutputPath/$fileName');
              if (!extractedFile.existsSync()) {
                throw UnrarException('Failed to extract file: $fileName');
              }

              return extractedFile.readAsBytesSync();
            } finally {
              calloc.free(destPathPtr);
              calloc.free(headerData);
            }
          } finally {
            _rarCloseArchive(handle);
          }
        } finally {
          calloc.free(archiveNamePtr);
        }
      } finally {
        calloc.free(archiveData);
      }
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  /// Tests a RAR archive for integrity.
  ///
  /// Returns true if the archive is valid and can be extracted.
  /// Throws [UnrarException] if the archive is corrupted or cannot be opened.
  bool testArchive(String archivePath, {String? password}) {
    final archiveData = calloc<bindings.RAROpenArchiveData>();

    try {
      final archiveNamePtr = archivePath.toNativeUtf8();
      try {
        archiveData.ref.ArcName = archiveNamePtr.cast();
        archiveData.ref.OpenMode = bindings.RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != bindings.ERAR_SUCCESS) {
          throw UnrarException(
            _getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          if (password != null) {
            final passwordPtr = password.toNativeUtf8();
            try {
              _rarSetPassword(handle, passwordPtr);
            } finally {
              calloc.free(passwordPtr);
            }
          }

          final headerData = calloc<bindings.RARHeaderData>();
          try {
            while (true) {
              final result = _rarReadHeader(handle, headerData);
              if (result == bindings.ERAR_END_ARCHIVE) break;
              if (result != bindings.ERAR_SUCCESS) {
                throw UnrarException(_getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                bindings.RAR_TEST,
                nullptr,
                nullptr,
              );
              if (processResult != bindings.ERAR_SUCCESS) {
                throw UnrarException(
                  _getErrorMessage(processResult),
                  processResult,
                );
              }
            }
          } finally {
            calloc.free(headerData);
          }
        } finally {
          _rarCloseArchive(handle);
        }
      } finally {
        calloc.free(archiveNamePtr);
      }
    } finally {
      calloc.free(archiveData);
    }

    return true;
  }

  String _getErrorMessage(int errorCode) {
    switch (errorCode) {
      case ERAR_NO_MEMORY:
        return 'Not enough memory';
      case ERAR_BAD_DATA:
        return 'Archive header or data is broken';
      case ERAR_BAD_ARCHIVE:
        return 'File is not a valid RAR archive';
      case ERAR_UNKNOWN_FORMAT:
        return 'Unknown archive format';
      case ERAR_EOPEN:
        return 'Cannot open file';
      case ERAR_ECREATE:
        return 'Cannot create file';
      case ERAR_ECLOSE:
        return 'Cannot close file';
      case ERAR_EREAD:
        return 'Read error';
      case ERAR_EWRITE:
        return 'Write error';
      case ERAR_SMALL_BUF:
        return 'Buffer too small';
      case ERAR_MISSING_PASSWORD:
        return 'Password required';
      case ERAR_UNKNOWN:
      default:
        return 'Unknown error';
    }
  }
}
