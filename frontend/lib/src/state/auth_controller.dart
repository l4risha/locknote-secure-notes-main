import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../core/session_store.dart';
import '../models/user.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._api);

  final ApiClient _api;

  AuthStatus status = AuthStatus.unknown;
  User? user;
  bool busy = false;

  String? get token => _api.token;

  Future<void> restoreSession() async {
    final stored = await readStoredToken();

    if (stored == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _api.token = stored;

    try {
      final response = await _api.get('/api/auth/me');
      user = User.fromJson(response['user'] as Map<String, dynamic>);
      status = AuthStatus.authenticated;
    } on ApiException {
      _api.token = null;
      await clearStoredToken();
      status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _runAuthAction(() async {
      final response = await _api.post(
        '/api/auth/login',
        body: {
          'email': email.trim(),
          'password': password,
        },
      );

      await _adoptSession(response);
    });
  }

  /// Creates an account without automatically signing in.
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _runAuthAction(() async {
      // Ensure registration is not sent with an existing bearer token.
      _api.token = null;
      user = null;
      status = AuthStatus.unauthenticated;
      await clearStoredToken();

      await _api.post(
        '/api/auth/register',
        body: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      // Do not adopt or store a session after registration.
      _api.token = null;
      user = null;
      status = AuthStatus.unauthenticated;
      await clearStoredToken();
    });
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } on ApiException {
      // Continue clearing the local session if the request fails.
    }

    _api.token = null;
    user = null;
    status = AuthStatus.unauthenticated;

    await clearStoredToken();
    notifyListeners();
  }

  void forceLogout() {
    if (status != AuthStatus.authenticated) return;

    _api.token = null;
    user = null;
    status = AuthStatus.unauthenticated;

    clearStoredToken();
    notifyListeners();
  }

  Future<void> _adoptSession(Map<String, dynamic> response) async {
    final newToken = response['token'] as String?;

    if (newToken == null) {
      throw ApiException(
        500,
        'The server did not return a session token.',
      );
    }

    _api.token = newToken;
    await storeToken(newToken);

    user = User.fromJson(response['user'] as Map<String, dynamic>);
    status = AuthStatus.authenticated;
  }

  Future<void> _runAuthAction(
    Future<void> Function() action,
  ) async {
    busy = true;
    notifyListeners();

    try {
      await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}