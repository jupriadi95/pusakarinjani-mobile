/// Environment configuration for Pusaka app.
/// Manages API base URLs and authentication tokens.
class Env {
  // ── Strapi Backend URLs ──
  static const String _defaultUrl = 'https://be.pusakarinjani.my.id';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultUrl,
  );

  /// Full API URL (Strapi REST endpoint)
  static const String apiUrl = '$apiBaseUrl/api';

  /// Static protection token for API calls without user login.
  /// Updated to authorization token for be.pusakarinjani.my.id
  static const String tokenProtect = String.fromEnvironment(
    'TOKEN_PROTECT',
    defaultValue:
        'be06a16908020950f47afa5c5a8bef1b83682d9309cf2a73702348212037020490b45f84f727a4395dc6638f0845f9bb4b7ca53cb3f3c98f8beb97a022ccf3c9237c6dbd1515c4c8a0bd806527465ed91775f879b23fbbc28fd7381326bedd742cba5d7f7e53b10d7c7ec2a6b7c9f827eba90151fe5ccb59878080349e6ffa79',
  );
}
