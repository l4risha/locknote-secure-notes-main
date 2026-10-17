import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/api_client.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'state/auth_controller.dart';
import 'state/notes_controller.dart';
import 'theme/app_theme.dart';

/// Root widget: owns the API client and the two controllers, gates between
/// splash → login/register → dashboard, and applies the Material 3 theme.
class LockNoteApp extends StatefulWidget {
  const LockNoteApp({super.key, this.client, this.baseUrl});

  /// Injectable HTTP client (tests use a mock backend).
  final http.Client? client;

  /// Injectable API base URL (defaults to [apiBaseUrl] / `--dart-define`).
  final String? baseUrl;

  @override
  State<LockNoteApp> createState() => _LockNoteAppState();
}

class _LockNoteAppState extends State<LockNoteApp> {
  late final ApiClient _api;
  late final AuthController _auth;
  late final NotesController _notes;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(
      baseUrl: widget.baseUrl ?? apiBaseUrl,
      client: widget.client,
    );
    _auth = AuthController(_api);
    _notes = NotesController(_api);

    // When the server rejects the session (expired/revoked token), bounce
    // back to the login screen automatically.
    _api.onUnauthorized = _auth.forceLogout;
    _auth.addListener(_handleAuthChanged);

    _auth.restoreSession();
  }

  void _handleAuthChanged() {
    // Wipe the previous account's notes as soon as we end up signed out.
    if (_auth.status == AuthStatus.unauthenticated &&
        (_notes.loaded || _notes.notes.isNotEmpty || _notes.summary != null)) {
      _notes.reset();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChanged);
    _auth.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LockNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
          return switch (_auth.status) {
            AuthStatus.unknown => const _SplashScreen(),
            AuthStatus.unauthenticated => AuthScreen(auth: _auth),
            AuthStatus.authenticated => HomeShell(
              key: ValueKey('home-${_auth.user?.id}'),
              auth: _auth,
              notes: _notes,
            ),
          };
        },
      ),
    );
  }
}

/// Shown while the stored session is being verified with the server.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, color: Colors.white, size: 52),
            SizedBox(height: 18),
            Text(
              'LockNote',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Restoring your session…',
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
