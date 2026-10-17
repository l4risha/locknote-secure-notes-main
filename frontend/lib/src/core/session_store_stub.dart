/// Fallback (in-memory) session storage — used on unexpected platforms.
String? _token;

Future<String?> readStoredToken() async => _token;

Future<void> storeToken(String? token) async => _token = token;

Future<void> clearStoredToken() async => _token = null;
