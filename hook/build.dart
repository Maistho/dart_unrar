import 'dart:io';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;

    // TODO: Dynamically get source files from the directory
    // Get all C++ source files from third_party/unrar directory
    final sources = [
      'third_party/unrar/rar.cpp',
      'third_party/unrar/strlist.cpp',
      'third_party/unrar/strfn.cpp',
      'third_party/unrar/pathfn.cpp',
      'third_party/unrar/smallfn.cpp',
      'third_party/unrar/global.cpp',
      'third_party/unrar/file.cpp',
      'third_party/unrar/filefn.cpp',
      'third_party/unrar/filcreat.cpp',
      'third_party/unrar/archive.cpp',
      'third_party/unrar/arcread.cpp',
      'third_party/unrar/unicode.cpp',
      'third_party/unrar/system.cpp',
      'third_party/unrar/crypt.cpp',
      'third_party/unrar/crc.cpp',
      'third_party/unrar/rawread.cpp',
      'third_party/unrar/encname.cpp',
      'third_party/unrar/resource.cpp',
      'third_party/unrar/match.cpp',
      'third_party/unrar/timefn.cpp',
      'third_party/unrar/rdwrfn.cpp',
      'third_party/unrar/consio.cpp',
      'third_party/unrar/options.cpp',
      'third_party/unrar/errhnd.cpp',
      'third_party/unrar/rarvm.cpp',
      'third_party/unrar/secpassword.cpp',
      'third_party/unrar/rijndael.cpp',
      'third_party/unrar/getbits.cpp',
      'third_party/unrar/sha1.cpp',
      'third_party/unrar/sha256.cpp',
      'third_party/unrar/blake2s.cpp',
      'third_party/unrar/hash.cpp',
      'third_party/unrar/extinfo.cpp',
      'third_party/unrar/extract.cpp',
      'third_party/unrar/volume.cpp',
      'third_party/unrar/list.cpp',
      'third_party/unrar/find.cpp',
      'third_party/unrar/unpack.cpp',
      'third_party/unrar/headers.cpp',
      'third_party/unrar/threadpool.cpp',
      'third_party/unrar/rs16.cpp',
      'third_party/unrar/cmddata.cpp',
      'third_party/unrar/ui.cpp',
      'third_party/unrar/filestr.cpp',
      'third_party/unrar/scantree.cpp',
      'third_party/unrar/qopen.cpp',
      'third_party/unrar/largepage.cpp',
      'third_party/unrar/dll.cpp',
    ];

    final flags = [
      // Suppress dangling-else warnings
      '-Wno-dangling-else',
      // Suppress switch warnings for unhandled enum values
      '-Wno-switch',
      // Define RARDLL to build as a library
      '-DRARDLL',
      // Use C++11 standard which is required for the code
      '-std=c++11',
      // Add defines from makefile
      '-D_FILE_OFFSET_BITS=64',
      '-D_LARGEFILE_SOURCE',
      '-DRAR_SMP',
      // Add pthread for threading support
      '-pthread',
    ];

    // Platform-specific flags
    if (Platform.isLinux) {
      // On Linux: link GNU libstdc++ and optionally static link runtime
      flags.addAll([
        '-lstdc++',
        '-static-libstdc++',
        '-static-libgcc',
      ]);
    } else if (Platform.isMacOS) {
      // On macOS: explicitly link libc++ (clang's default C++ library)
      flags.add('-lc++');
    }
    // On Windows: link the appropriate runtime via native_toolchain_c defaults

    final cBuilder = CBuilder.library(
      name: packageName,
      assetName: '$packageName.dart',
      sources: sources,
      flags: flags,
    );

    await cBuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
