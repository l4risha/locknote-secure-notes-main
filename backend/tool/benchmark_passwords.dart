import 'dart:io';

import 'package:locknote_backend/locknote_backend.dart';

/// Measures how long one password hash takes on this machine.
///
/// Run from `backend/`:
/// ```sh
/// dart run tool/benchmark_passwords.dart
/// ```
///
/// Use the result to pick a `PBKDF2_ITERATIONS` value that keeps logins around
/// 0.3–1.0 seconds on your hardware (the built-in default is
/// `$defaultPbkdf2Iterations`).
void main(List<String> args) {
  final candidates = args.isEmpty
      ? <int>[10000, 50000, defaultPbkdf2Iterations, 300000, 600000]
      : args.map(int.parse).toList();

  stdout.writeln('PBKDF2-HMAC-SHA256 hash cost (lower = faster login, higher = '
      'harder to crack):');
  for (final iterations in candidates) {
    // One warm-up hash so JIT compilation does not skew the first number.
    hashPassword('warm-up', iterations: 1000);

    final stopwatch = Stopwatch()..start();
    hashPassword('benchmark-password-123', iterations: iterations);
    stopwatch.stop();

    stdout.writeln(
      '  $iterations iterations -> ${stopwatch.elapsedMilliseconds} ms',
    );
  }
  stdout.writeln('');
  stdout
      .writeln('Default in this project: $defaultPbkdf2Iterations iterations.');
}
