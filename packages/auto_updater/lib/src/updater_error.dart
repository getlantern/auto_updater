class UpdaterError extends Error {
  UpdaterError(this.message, {this.code, this.domain});

  final String message;

  /// Native error code, when the updater provides one.
  final int? code;

  /// Native error domain, or the updater name when no domain is available.
  final String? domain;

  @override
  String toString() {
    return 'UpdaterError: $message';
  }
}
