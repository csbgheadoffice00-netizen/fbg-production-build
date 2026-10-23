import 'package:shared_preferences/shared_preferences.dart';

/// Holds the login token issued by the backend and hands it to every request.
///
/// The token is the only thing that tells the server who the user is.
/// Nothing in the app should ever send a user id to prove identity.
class ApiAuth {
  static String? _token;
  static bool _expiring = false;

  /// Set from main() so a rejected token can bounce the user to Login.
  static void Function()? onSessionExpired;

  static String? get token => _token;
  static bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// Call once at startup, before the first network request.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString('auth_token');
      _token = (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      _token = null;
    }
    _expiring = false;
  }

  /// Call after a successful login / register / code verification.
  /// Accepts either key the backend may use, so a rename cannot break login.
  static Future<void> saveFromResponse(Map<String, dynamic> data) async {
    final raw = data['access_token'] ?? data['token'] ?? data['accessToken'];
    final t = raw?.toString();
    if (t == null || t.isEmpty) return;
    await save(t);
  }

  static Future<void> save(String token) async {
    _token = token;
    _expiring = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (_) {}
  }

  /// Logout, or the server rejected our token.
  static Future<void> clear() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}
  }

  /// Headers for any authenticated request.
  static Map<String, String> headers([Map<String, String>? extra]) {
    final h = <String, String>{};
    if (extra != null) h.addAll(extra);
    if (isLoggedIn) h['Authorization'] = 'Bearer $_token';
    return h;
  }

  /// The server answered 401: the token is expired or no longer valid.
  /// Clear it and send the user to Login once, not once per polling screen.
  static Future<void> handleUnauthorized() async {
    if (_expiring) return;
    _expiring = true;
    await clear();
    final cb = onSessionExpired;
    if (cb != null) cb();
  }
}
