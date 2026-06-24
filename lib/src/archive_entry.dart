/// Represents a single entry (file) in a RAR archive.
class ArchiveEntry {

  ArchiveEntry({
    required this.name,
    required this.size,
    required this.packedSize,
    required this.crc,
    required this.attributes,
    required this.modificationTime,
    required this.isDirectory,
  });
  /// The name of the file in the archive.
  final String name;

  /// The uncompressed size of the file in bytes.
  final int size;

  /// The compressed size of the file in bytes.
  final int packedSize;

  /// The CRC32 checksum of the file.
  final int crc;

  /// The file attributes.
  final int attributes;

  /// The modification time of the file.
  final DateTime modificationTime;

  /// Whether this entry is a directory.
  final bool isDirectory;

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
          isDirectory == other.isDirectory;

  @override
  int get hashCode => Object.hash(
        name,
        size,
        packedSize,
        crc,
        attributes,
        modificationTime,
        isDirectory,
      );

  @override
  String toString() =>
      'ArchiveEntry(name: $name, size: $size, isDirectory: $isDirectory)';
}
