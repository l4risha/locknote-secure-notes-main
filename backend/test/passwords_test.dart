import 'dart:convert';

import 'package:locknote_backend/locknote_backend.dart';
import 'package:test/test.dart';

/// Reference values produced by an independent implementation
/// (`hashlib.pbkdf2_hmac('sha256', ...)` / RFC 7914 test vectors).
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2 (RFC 8018 known answers)', () {
    test('password / salt / 1 iteration / 32 bytes', () {
      final dk = pbkdf2('password', ascii.encode('salt'), 1, 32);
      expect(
        _hex(dk),
        '120fb6cffcf8b32c43e7225256c4f837'
        'a86548c92ccc35480805987cb70be17b',
      );
    });

    test('password / salt / 4096 iterations / 32 bytes', () {
      final dk = pbkdf2('password', ascii.encode('salt'), 4096, 32);
      expect(
        _hex(dk),
        'c5e478d59288c841aa530db6845c4c8d'
        '962893a001ce4e11a4963873aa98134a',
      );
    });

    test('shorter derived key is a prefix of the longer one', () {
      final salt = ascii.encode('salt');
      final short = pbkdf2('password', salt, 1, 16);
      final long = pbkdf2('password', salt, 1, 32);
      expect(_hex(short), _hex(long).substring(0, 32));
    });

    test('rejection of invalid work factors', () {
      expect(
          () => pbkdf2('pw', ascii.encode('salt'), 0, 32), throwsArgumentError);
      expect(
          () => pbkdf2('pw', ascii.encode('salt'), 1, 0), throwsArgumentError);
    });
  });

  group('hashPassword / verifyPassword', () {
    test('stores no plaintext password', () {
      const password = 'correct horse battery staple';
      final stored = hashPassword(password, iterations: 1000);
      expect(stored, isNot(contains(password)));
      expect(stored, startsWith('pbkdf2_sha256\$1000\$'));
      // Encodes as algorithm$iterations$salt$key.
      expect(stored.split('\$'), hasLength(4));
    });

    test('round-trips the correct password', () {
      final stored = hashPassword('Str0ng-pass!', iterations: 1000);
      expect(verifyPassword('Str0ng-pass!', stored), isTrue);
    });

    test('rejects wrong passwords', () {
      final stored = hashPassword('Str0ng-pass!', iterations: 1000);
      expect(verifyPassword('Str0ng-pass', stored), isFalse);
      expect(verifyPassword('', stored), isFalse);
      expect(verifyPassword('STR0NG-PASS!', stored), isFalse);
    });

    test('same password hashes differently every time (random salt)', () {
      final a = hashPassword('same-password', iterations: 1000);
      final b = hashPassword('same-password', iterations: 1000);
      expect(a, isNot(b));
      expect(verifyPassword('same-password', a), isTrue);
      expect(verifyPassword('same-password', b), isTrue);
    });

    test('handles malformed stored hashes without throwing', () {
      expect(verifyPassword('pw', null), isFalse);
      expect(verifyPassword('pw', ''), isFalse);
      expect(verifyPassword('pw', 'not-a-hash'), isFalse);
      expect(verifyPassword('pw', 'pbkdf2_sha256\$abc\$xx\$yy'), isFalse);
      expect(verifyPassword('pw', 'bcrypt\$10\$abc\$def'), isFalse);
    });
  });

  group('constantTimeEquals', () {
    test('matches equal lists and rejects different ones', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
      expect(constantTimeEquals(const [], const []), isTrue);
    });
  });

  group('generateToken / hashToken', () {
    test('tokens are unique and hash deterministically', () {
      final a = generateToken();
      final b = generateToken();
      expect(a, isNot(b));
      expect(a.length, greaterThanOrEqualTo(40));
      expect(hashToken(a), hashToken(a));
      expect(hashToken(a), isNot(hashToken(b)));
      // Hashing is one-way-ish: the digest never contains the raw token.
      expect(hashToken(a), isNot(contains(a)));
    });
  });
}
