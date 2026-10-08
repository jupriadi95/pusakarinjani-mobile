/// Environment configuration for Pusaka app.
/// Manages API base URLs and authentication tokens.
/// Supports runtime switching between Online and Offline (LAN) modes.
class Env {
  Env._();

  // ── Mode ──
  static bool _isOffline = false;
  static bool get isOffline => _isOffline;

  // ── Backend URLs ──
  static const String _onlineUrl = 'https://be.pusakarinjani.my.id';
  static const String defaultOfflineUrl = 'http://be-local.pusakarinjani.my.id';
  static String _offlineUrl = defaultOfflineUrl;

  // ── Compile-time override (still supported via --dart-define) ──
  static const String _envOverrideUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Current active API Base URL (without /api suffix).
  /// Determined by mode selection or compile-time override.
  static String get apiBaseUrl {
    if (_envOverrideUrl.isNotEmpty) return _envOverrideUrl;
    return _isOffline ? _offlineUrl : _onlineUrl;
  }

  /// Current configured offline URL
  static String get offlineUrl => _offlineUrl;

  /// Full API URL (Strapi REST endpoint)
  static String get apiUrl => '$apiBaseUrl/api';

  // ── Authentication Tokens ──
  static const String _onlineTokenDefault =
      '544af768f8e7879cd3d0e912a31bed604ca787a4f045c5d2b4433dfd5098c8f4b929df9e70280f855ba96120b679afae5d890cd2ade192e0a653908e0aca179ec8410fefaeacb3dacedb7040471f59790c92302c10f7e9d86e58f9913a955f4a79ca6c8bee9e3808ccfff0321985dfa2041e5850baf0d8d2c13459d81e173f6e';

  static String _offlineToken = '';
  static String get offlineToken => _offlineToken;

  /// Dynamic protection token for API calls.
  /// Uses the online token when in online mode, or the custom entered/scanned token in offline mode.
  static String get tokenProtect {
    if (_isOffline) {
      return _offlineToken;
    }
    const envToken = String.fromEnvironment('TOKEN_PROTECT', defaultValue: '');
    if (envToken.isNotEmpty) return envToken;
    return _onlineTokenDefault;
  }

  /// Switch to Online mode
  static void setOnline() {
    _isOffline = false;
  }

  /// Switch to Offline / LAN mode with custom token and optional server URL
  static void setOffline({required String token, String? url}) {
    _isOffline = true;
    _offlineToken = token.trim();
    if (url != null && url.trim().isNotEmpty) {
      String clean = url.trim();
      // Ensure HTTP scheme is present if user entered raw host/ip
      if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
        clean = 'http://$clean';
      }
      // Remove trailing slash
      if (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      _offlineUrl = clean;
    } else {
      _offlineUrl = defaultOfflineUrl;
    }
  }
}
