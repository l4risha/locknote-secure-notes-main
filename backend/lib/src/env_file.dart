import 'dart:io';

/// Loads `KEY=VALUE` pairs from a dotenv-style file.
///
/// * Lines that start with `#` are comments.
/// * Values may be wrapped in single or double quotes.
/// * A missing file simply yields an empty map.
Map<String, String> loadEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return <String, String>{};

  final result = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;

    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1);
      }
    }
    result[key] = value;
  }
  return result;
}
