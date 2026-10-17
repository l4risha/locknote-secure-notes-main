import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _secureRandom = Random.secure();

/// Creates a cryptographically random, URL-safe bearer token (256 bits).
String generateToken() {
  final bytes = Uint8List.fromList(
    List<int>.generate(32, (_) => _secureRandom.nextInt(256)),
  );
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Hashes a token with SHA-256 for storage/lookup.
///
/// The database only ever stores this digest, so even if the `sessions` table
/// leaks, the stolen rows cannot be replayed as login tokens.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();
