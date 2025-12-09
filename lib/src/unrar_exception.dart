/// Exception thrown when UnRAR operations fail.
class UnrarException implements Exception {
  final String message;
  final int? errorCode;

  UnrarException(this.message, [this.errorCode]);

  @override
  String toString() => errorCode != null
      ? 'UnrarException: $message (code: $errorCode)'
      : 'UnrarException: $message';
}
