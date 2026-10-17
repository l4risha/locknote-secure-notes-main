/// In-memory session storage for VM runs and Flutter widget tests.
String? _token;

Future<String?> readStoredToken() async => _token;

Future<void> storeToken(String? token) async => _token = token;

Future<void> clearStoredToken() async => _token = null;
