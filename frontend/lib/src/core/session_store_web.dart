import 'package:web/web.dart' as web;

/// Browser session storage backed by `window.localStorage`.
///
/// The stored value is only the opaque bearer token (already useless without
/// the account password), never the password itself.
const String _key = 'locknote.token';

Future<String?> readStoredToken() async =>
    web.window.localStorage.getItem(_key);

Future<void> storeToken(String? token) async {
  if (token == null) {
    web.window.localStorage.removeItem(_key);
  } else {
    web.window.localStorage.setItem(_key, token);
  }
}

Future<void> clearStoredToken() async =>
    web.window.localStorage.removeItem(_key);
