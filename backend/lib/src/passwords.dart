import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Default work factor for PBKDF2-HMAC-SHA256.
///
/// The value can be tuned per deployment with the `PBKDF2_ITERATIONS`
/// environment variable; it is stored inside every hash, so raising it never
/// breaks existing passwords.
const int defaultPbkdf2Iterations = 100000;

const int _saltBytes = 16;
const int _keyBytes = 32;
const String _algorithm = 'pbkdf2_sha256';

/// Computes a PBKDF2-HMAC-SHA256 derived key (RFC 8018 §5.2).
///
/// Kept dependency-free on purpose: only `package:crypto`'s HMAC is used, so a
/// student can read and audit the whole implementation.
Uint8List pbkdf2(
    String password, List<int> salt, int iterations, int keyLength) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
  }
  if (keyLength < 1) {
    throw ArgumentError.value(keyLength, 'keyLength', 'must be >= 1');
  }

  const int digestBytes = 32; // SHA-256 output size (hLen in RFC 8018).
  final hmac = Hmac(sha256, utf8.encode(password));
  final blockCount = (keyLength / digestBytes).ceil();
  final output = BytesBuilder();

  for (var block = 1; block <= blockCount; block++) {
    final index = Uint8List(4)..buffer.asByteData().setUint32(0, block);

    var u = hmac.convert(<int>[...salt, ...index]).bytes;
    final t = Uint8List.fromList(u);

    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < t.length; i++) {
        t[i] ^= u[i];
      }
    }
    output.add(t);
  }

  return Uint8List.sublistView(output.toBytes(), 0, keyLength);
}

/// Hashes a password for storage.
///
/// Returns an encoded string that carries everything verification needs:
/// `pbkdf2_sha256$<iterations>$<base64 salt>$<base64 key>` — no plaintext
/// password ever leaves this function.
String hashPassword(String password, {int? iterations, List<int>? salt}) {
  final rounds = iterations ?? defaultPbkdf2Iterations;
  final random = Random.secure();
  final actualSalt = salt ??
      Uint8List.fromList(
          List<int>.generate(_saltBytes, (_) => random.nextInt(256)));
  final key = pbkdf2(password, actualSalt, rounds, _keyBytes);
  return '$_algorithm\$$rounds\$${base64Encode(actualSalt)}\$${base64Encode(key)}';
}

/// Verifies a password against a stored hash in constant time.
///
/// Returns `false` (never throws) for malformed or unknown hash formats.
bool verifyPassword(String password, String? storedHash) {
  if (storedHash == null) return false;
  final parts = storedHash.split('\$');
  if (parts.length != 4 || parts[0] != _algorithm) return false;

  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;

  final List<int> salt;
  final List<int> expected;
  try {
    salt = base64Decode(parts[2]);
    expected = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  if (salt.isEmpty || expected.isEmpty) return false;

  final actual = pbkdf2(password, salt, iterations, expected.length);
  return constantTimeEquals(actual, expected);
}

/// Byte comparison that takes the same time regardless of where the first
/// difference is, which stops attackers from guessing hash bytes one by one.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
