/// Represents a single entry (file or directory) in a RAR archive.
class ArchiveEntry {

  ArchiveEntry({
    required this.name,
    required this.size,
    required this.packedSize,
    required this.crc,
    required this.attributes,
    required this.modificationTime,
    required this.isDirectory,
    this.isEncrypted = false,
    this.isSplitBefore = false,
    this.isSplitAfter = false,
    this.isSolid = false,
    this.hashType = 0,
  });
  /// The name of the file in the archive.
  final String name;

  /// The uncompressed size of the file in bytes.
  final int size;

  /// The compressed size of the file in bytes.
  final int packedSize;

  /// The CRC32 checksum of the file (or Blake2 when [hashType] == 2).
  final int crc;

  /// The file attributes (OS-specific bitmask).
  final int attributes;

  /// The modification time of the file.
  final DateTime modificationTime;

  /// Whether this entry is a directory.
  final bool isDirectory;

  /// Whether this file's data is encrypted. Requires a password to extract.
  final bool isEncrypted;

  /// Whether this file continues from the previous volume in a multi-volume set.
  final bool isSplitBefore;

  /// Whether this file continues into the next volume in a multi-volume set.
  final bool isSplitAfter;

  /// Whether this entry is part of a solid compression block.
  final bool isSolid;

  /// Hash algorithm used for integrity checking.
  /// 0 = none, 1 = CRC32, 2 = Blake2.
  final int hashType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArchiveEntry &&
          name == other.name &&
          size == other.size &&
          packedSize == other.packedSize &&
          crc == other.crc &&
          attributes == other.attributes &&
          modificationTime == other.modificationTime &&
          isDirectory == other.isDirectory &&
          isEncrypted == other.isEncrypted &&
          isSplitBefore == other.isSplitBefore &&
          isSplitAfter == other.isSplitAfter &&
          isSolid == other.isSolid &&
          hashType == other.hashType;

  @override
  int get hashCode => Object.hash(
        name,
        size,
        packedSize,
        crc,
        attributes,
        modificationTime,
        isDirectory,
        isEncrypted,
        isSplitBefore,
        isSplitAfter,
        isSolid,
        hashType,
      );

  @override
  String toString() =>
      'ArchiveEntry(name: $name, size: $size, isDirectory: $isDirectory, '
      'isEncrypted: $isEncrypted)';
}
