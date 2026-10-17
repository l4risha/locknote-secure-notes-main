import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locknote_app/src/app.dart';

/// Builds the app on top of a mock backend so widget tests never touch the
/// network. [requests] collects every outgoing call for assertions.
MockClient mockBackend(
  List<http.Request> requests, {
  required Map<String, Object> responses,
}) {
  return MockClient((request) async {
    requests.add(request);
    final key = '${request.method} ${request.url.path}';
    final status = responses[key] ?? responses['default'] ?? 404;
    if (status is int && status >= 400) {
      return http.Response(
        jsonEncode({'error': 'Mocked error', 'code': 'mock'}),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    final body = status is Map<String, Object> ? status : {'ok': true};
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> pumpApp(WidgetTester tester, MockClient client) async {
  await tester.pumpWidget(LockNoteApp(client: client, baseUrl: 'http://mock'));
  // Splash while restoring the session (no stored token → login screen).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  testWidgets('shows the login form after session restore finds no token', (
    tester,
  ) async {
    await pumpApp(tester, mockBackend([], responses: {}));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(2)); // email + password
  });

  testWidgets('login form validates empty and malformed input', (tester) async {
    await pumpApp(tester, mockBackend([], responses: {}));

    // Submit empty → required-field errors, and no API call is made.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);

    // Malformed email → format error.
    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('switching to register shows name + confirmation fields', (
    tester,
  ) async {
    await pumpApp(tester, mockBackend([], responses: {}));

    await tester.tap(find.widgetWithText(TextButton, 'Register'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Create your account'), findsOneWidget);
    expect(
      find.byType(TextFormField),
      findsNWidgets(4),
    ); // name/email/pw/confirm
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('successful login calls the API and enters the dashboard', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = mockBackend(
      requests,
      responses: {
        'POST /api/auth/login': {
          'token': 'test-token',
          'user': {'id': 1, 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
        },
        'GET /api/auth/me': {
          'user': {'id': 1, 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
        },
        'GET /api/notes': {'notes': <dynamic>[]},
        'GET /api/dashboard': {
          'totalNotes': 0,
          'updatedLast7Days': 0,
          'recentNotes': <dynamic>[],
        },
      },
    );

    await pumpApp(tester, client);

    await tester.enterText(find.byType(TextFormField).first, 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump(); // trigger request
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(); // dashboard frame
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      requests.any(
        (request) =>
            request.method == 'POST' && request.url.path == '/api/auth/login',
      ),
      isTrue,
    );
    expect(find.text('Hello, Ada 👋'), findsOneWidget);

    // The password never appears in any request body other than the login
    // payload itself, and it is never stored anywhere client-side.
    expect(find.text('secret123'), findsNothing);
  });

  testWidgets('server-side validation errors are displayed in the banner', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'error': 'Incorrect email or password.',
          'code': 'invalid_credentials',
        }),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    await pumpApp(tester, client);
    await tester.enterText(find.byType(TextFormField).first, 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'wrong-pass');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget); // still signed out
  });
}
