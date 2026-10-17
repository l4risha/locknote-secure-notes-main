import 'package:locknote_backend/locknote_backend.dart';
import 'package:test/test.dart';

void main() {
  group('validateRegister', () {
    test('accepts valid input', () {
      final errors = validateRegister(
        name: 'Ada Lovelace',
        email: 'ada@example.com',
        password: 'secret123',
      );
      expect(errors, isEmpty);
    });

    test('requires every field', () {
      final errors = validateRegister(name: '', email: '', password: '');
      expect(errors.keys, containsAll(['name', 'email', 'password']));
    });

    test('rejects malformed emails', () {
      for (final email in [
        'plain',
        'a@b',
        'a@b.',
        '@example.com',
        'a b@c.com'
      ]) {
        final errors =
            validateRegister(name: 'Ada', email: email, password: 'secret123');
        expect(errors.containsKey('email'), isTrue,
            reason: 'should reject $email');
      }
    });

    test('rejects short or oversized passwords', () {
      expect(validatePassword('short').keys, contains('password'));
      expect(validatePassword('x' * 201).keys, contains('password'));
      expect(validatePassword('eight8chr'), isEmpty);
    });

    test('rejects names that are too long', () {
      final errors = validateRegister(
        name: 'x' * 81,
        email: 'ada@example.com',
        password: 'secret123',
      );
      expect(errors['name'], contains('80'));
    });
  });

  group('validateLogin', () {
    test('requires email and password', () {
      final errors = validateLogin(email: ' ', password: '');
      expect(errors.keys, containsAll(['email', 'password']));
    });

    test('accepts filled fields', () {
      expect(validateLogin(email: 'a@b.co', password: 'x'), isEmpty);
    });
  });

  group('validateNote', () {
    test('requires a title and caps its length', () {
      expect(validateNote(title: '   ', content: ''),
          containsPair('title', isNotNull));
      expect(validateNote(title: 'x' * 121, content: ''),
          containsPair('title', isNotNull));
      expect(validateNote(title: 'ok', content: ''), isEmpty);
    });

    test('caps content length', () {
      expect(
          validateNote(title: 'ok', content: 'y' * 20001)
              .containsKey('content'),
          isTrue);
    });
  });

  group('normalizeEmail', () {
    test('trims and lower-cases', () {
      expect(normalizeEmail('  Ada@Example.COM '), 'ada@example.com');
    });
  });

  group('toLikePattern', () {
    test('wraps the query in wildcards', () {
      expect(toLikePattern('hello'), '%hello%');
    });

    test('escapes LIKE metacharacters so they stay literal', () {
      expect(toLikePattern('100%'), r'%100\%%');
      expect(toLikePattern('a_b'), r'%a\_b%');
      expect(toLikePattern(r'c:\tmp'), r'%c:\\tmp%');
      expect(toLikePattern(r'50%_off\deal'), r'%50\%\_off\\deal%');
    });

    test('empty query matches everything', () {
      expect(toLikePattern(''), '%%');
    });
  });
}
