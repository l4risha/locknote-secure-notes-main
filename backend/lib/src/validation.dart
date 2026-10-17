/// Input validation for every user-supplied field.
///
/// Returns a map of `field -> message`; an empty map means the input is valid.
/// The same rules power the API's `422 validation_failed` responses, so the
/// Flutter client can show messages directly under the right form field.
library;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Lower-cases and trims an email so `Alice@Example.com` and
/// `alice@example.com` always refer to the same account.
String normalizeEmail(String email) => email.trim().toLowerCase();

Map<String, String> validateRegister({
  required String name,
  required String email,
  required String password,
}) {
  final errors = <String, String>{};

  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    errors['name'] = 'Name is required.';
  } else if (trimmedName.length < 2) {
    errors['name'] = 'Name must be at least 2 characters.';
  } else if (trimmedName.length > 80) {
    errors['name'] = 'Name must be at most 80 characters.';
  }

  final trimmedEmail = email.trim();
  if (trimmedEmail.isEmpty) {
    errors['email'] = 'Email is required.';
  } else if (trimmedEmail.length > 255) {
    errors['email'] = 'Email must be at most 255 characters.';
  } else if (!_emailPattern.hasMatch(trimmedEmail)) {
    errors['email'] = 'Enter a valid email address, e.g. you@example.com.';
  }

  errors.addAll(validatePassword(password));

  return errors;
}

Map<String, String> validateLogin(
    {required String email, required String password}) {
  final errors = <String, String>{};
  if (email.trim().isEmpty) {
    errors['email'] = 'Email is required.';
  }
  if (password.isEmpty) {
    errors['password'] = 'Password is required.';
  }
  return errors;
}

Map<String, String> validatePassword(String password) {
  final errors = <String, String>{};
  if (password.isEmpty) {
    errors['password'] = 'Password is required.';
  } else if (password.length < 8) {
    errors['password'] = 'Password must be at least 8 characters.';
  } else if (password.length > 200) {
    // bcrypt-style limits do not apply to PBKDF2, but an unbounded password
    // would let a caller force arbitrary amounts of hashing work.
    errors['password'] = 'Password must be at most 200 characters.';
  }
  return errors;
}

Map<String, String> validateNote(
    {required String title, required String content}) {
  final errors = <String, String>{};
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) {
    errors['title'] = 'Title is required.';
  } else if (trimmedTitle.length > 120) {
    errors['title'] = 'Title must be at most 120 characters.';
  }
  if (content.length > 20000) {
    errors['content'] = 'Note content must be at most 20,000 characters.';
  }
  return errors;
}

/// Escapes a user query for use inside a SQL `LIKE ... ESCAPE '\'` pattern,
/// so `%` and `_` typed by the user stay literal characters instead of
/// becoming wildcards.
String toLikePattern(String query) {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}
