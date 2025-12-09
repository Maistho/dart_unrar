/// Exception thrown when UnRAR operations fail.
class UnrarException implements Exception {

  UnrarException(this.message, [this.errorCode]);
  final String message;
  final int? errorCode;

  @override
  String toString() => errorCode != null
      ? 'UnrarException: $message (code: $errorCode)'
      : 'UnrarException: $message';
}
