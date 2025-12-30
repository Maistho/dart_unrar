import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'unrar_exception.dart';
import 'archive_entry.dart';
import 'unrar_bindings.dart' as bindings;
import 'unrar_constants.dart';

/// High-level interface for extracting RAR archives.
class UnrarExtractor {
  static DynamicLibrary? _dylib;

  static DynamicLibrary get _lib {
    if (_dylib != null) return _dylib!;

    // Try multiple paths to find the library. This covers common layouts:
    // - .dart_tool/lib next to the app
    // - current working directory
    // - alongside the executable
    // - bundle layout: ../lib relative to the executable (dart compile exe)
    // - directory of Platform.script (useful during tests)
    // - override via UNRAR_LIBRARY_PATH env var
    final possiblePaths = <String>[];
    void addPath(String path) {
      if (!possiblePaths.contains(path)) possiblePaths.add(path);
    }

    final libName = _libraryFileName();

    // Env override: exact file or directory
    final envPath = Platform.environment['UNRAR_LIBRARY_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      final envAsDir = Directory(envPath);
      addPath(envAsDir.existsSync() ? _join(envAsDir.path, libName) : envPath);
    }

    // Default working dir locations
    addPath(_join('.dart_tool/lib', libName));
    addPath(libName);

    // Resolved executable (dart or compiled binary)
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    addPath(_join(exeDir, libName));
    // Bundle layout: build/bundle/bin/<exe>, build/bundle/lib/<lib>
    addPath(_join(_join(exeDir, '..'), _join('lib', libName)));

    // Location of the running script (tests / `dart run`)
    if (Platform.script.isScheme('file')) {
      final scriptDir = File(Platform.script.toFilePath()).parent.path;
      addPath(_join(scriptDir, libName));
      addPath(_join(_join(scriptDir, '..'), _join('lib', libName)));
    }

    final attempted = <String>[];
    final errors = <String>[];
    for (final path in possiblePaths) {
      attempted.add(path);
      try {
        _dylib = DynamicLibrary.open(path);
        return _dylib!;
      } catch (e) {
        errors.add('$path => $e');
        // Try next path
      }
    }

    final debug = Platform.environment['UNRAR_DEBUG'] == '1';
    final msg = StringBuffer(
      'Failed to load native library. Please run "dart build" to build the library.',
    );
    if (debug) {
      msg.writeln();
      msg.writeln('Attempted paths:');
      for (final p in attempted) {
        final exists = File(p).existsSync();
        msg.writeln('- $p ${exists ? '(exists)' : '(missing)'}');
      }
      if (errors.isNotEmpty) {
        msg.writeln('dlopen errors:');
        for (final err in errors) {
          msg.writeln('- $err');
        }
      }
      final envPath = Platform.environment['UNRAR_LIBRARY_PATH'];
      if (envPath != null) {
        msg.writeln('UNRAR_LIBRARY_PATH=$envPath');
      }
      msg.writeln(
        'Executable dir: ${File(Platform.resolvedExecutable).parent.path}',
      );
      if (Platform.script.isScheme('file')) {
        msg.writeln(
          'Script dir: ${File(Platform.script.toFilePath()).parent.path}',
        );
      }
    }
    throw UnrarException(msg.toString());
  }

  static String _libraryFileName() {
    if (Platform.isMacOS) return 'libunrar.dylib';
    if (Platform.isLinux) return 'libunrar.so';
    if (Platform.isWindows) return 'unrar.dll';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static String _join(String base, String name) {
    if (base.isEmpty) return name;
    final sep = Platform.pathSeparator;
    final normalizedBase = base.endsWith(sep)
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalizedBase$sep$name';
  }

  // FFI function signatures
  late final Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>)
  _rarOpenArchive = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>),
        Pointer<Void> Function(Pointer<bindings.RAROpenArchiveData>)
      >('RAROpenArchive');

  late final int Function(Pointer<Void>) _rarCloseArchive = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('RARCloseArchive');

  late final int Function(Pointer<Void>, Pointer<bindings.RARHeaderData>)
  _rarReadHeader = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<bindings.RARHeaderData>),
        int Function(Pointer<Void>, Pointer<bindings.RARHeaderData>)
      >('RARReadHeader');

  late final int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>)
  _rarProcessFile = _lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>)
      >('RARProcessFile');

  late final void Function(Pointer<Void>, Pointer<Utf8>) _rarSetPassword = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>)
      >('RARSetPassword');

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
        archiveData.ref.OpenMode = RAR_OM_LIST;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != ERAR_SUCCESS) {
          throw UnrarException(
            getErrorMessage(archiveData.ref.OpenResult),
            archiveData.ref.OpenResult,
          );
        }

        try {
          final headerData = calloc<bindings.RARHeaderData>();
          try {
            while (true) {
              final result = _rarReadHeader(handle, headerData);
              if (result == ERAR_END_ARCHIVE) break;
              if (result != ERAR_SUCCESS) {
                throw UnrarException(getErrorMessage(result), result);
              }

              final fileNameChars = <int>[];
              for (var i = 0; i < 260; i++) {
                final char = headerData.ref.FileName[i];
                if (char == 0) break;
                fileNameChars.add(char);
              }
              final fileNameStr = String.fromCharCodes(fileNameChars);
              final isDirectory =
                  (headerData.ref.Flags & RHDF_DIRECTORY) != 0;

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
                RAR_SKIP,
                nullptr,
                nullptr,
              );
              if (processResult != ERAR_SUCCESS) {
                throw UnrarException(
                  getErrorMessage(processResult),
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
        archiveData.ref.OpenMode = RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != ERAR_SUCCESS) {
          throw UnrarException(
            getErrorMessage(archiveData.ref.OpenResult),
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
              if (result == ERAR_END_ARCHIVE) break;
              if (result != ERAR_SUCCESS) {
                throw UnrarException(getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                RAR_EXTRACT,
                destPathPtr,
                nullptr,
              );
              if (processResult != ERAR_SUCCESS) {
                throw UnrarException(
                  getErrorMessage(processResult),
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
          archiveData.ref.OpenMode = RAR_OM_EXTRACT;
          archiveData.ref.CmtBuf = nullptr;
          archiveData.ref.CmtBufSize = 0;

          final handle = _rarOpenArchive(archiveData);
          if (archiveData.ref.OpenResult != ERAR_SUCCESS) {
            throw UnrarException(
              getErrorMessage(archiveData.ref.OpenResult),
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
                if (result == ERAR_END_ARCHIVE) break;
                if (result != ERAR_SUCCESS) {
                  throw UnrarException(getErrorMessage(result), result);
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
                    RAR_EXTRACT,
                    destPathPtr,
                    nullptr,
                  );
                  if (processResult != ERAR_SUCCESS) {
                    throw UnrarException(
                      getErrorMessage(processResult),
                      processResult,
                    );
                  }
                  break;
                } else {
                  final processResult = _rarProcessFile(
                    handle,
                    RAR_SKIP,
                    nullptr,
                    nullptr,
                  );
                  if (processResult != ERAR_SUCCESS) {
                    throw UnrarException(
                      getErrorMessage(processResult),
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
        archiveData.ref.OpenMode = RAR_OM_EXTRACT;
        archiveData.ref.CmtBuf = nullptr;
        archiveData.ref.CmtBufSize = 0;

        final handle = _rarOpenArchive(archiveData);
        if (archiveData.ref.OpenResult != ERAR_SUCCESS) {
          throw UnrarException(
            getErrorMessage(archiveData.ref.OpenResult),
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
              if (result == ERAR_END_ARCHIVE) break;
              if (result != ERAR_SUCCESS) {
                throw UnrarException(getErrorMessage(result), result);
              }

              final processResult = _rarProcessFile(
                handle,
                RAR_TEST,
                nullptr,
                nullptr,
              );
              if (processResult != ERAR_SUCCESS) {
                throw UnrarException(
                  getErrorMessage(processResult),
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
}
