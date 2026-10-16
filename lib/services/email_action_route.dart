class EmailActionRoute {
  const EmailActionRoute({
    required this.mode,
    required this.oobCode,
    required this.continueUrl,
    required this.apiKey,
    required this.lang,
  });

  final String mode;
  final String oobCode;
  final String? continueUrl;
  final String? apiKey;
  final String? lang;

  bool get isEmailVerification => mode == 'verifyEmail' && oobCode.isNotEmpty;
  bool get isPasswordResetMode => mode == 'resetPassword';
  bool get isPasswordReset => mode == 'resetPassword' && oobCode.isNotEmpty;

  static EmailActionRoute? fromUri(Uri uri) {
    final mode = uri.queryParameters['mode']?.trim() ?? '';
    final oobCode = uri.queryParameters['oobCode']?.trim() ?? '';

    if (mode != 'verifyEmail' && mode != 'resetPassword') {
      return null;
    }

    return EmailActionRoute(
      mode: mode,
      oobCode: oobCode,
      continueUrl: uri.queryParameters['continueUrl']?.trim(),
      apiKey: uri.queryParameters['apiKey']?.trim(),
      lang: uri.queryParameters['lang']?.trim(),
    );
  }
}
