/// Nagsubay sa sayop nga login attempts kada email.
/// Naa ra sa memory: mo-reset kung i-restart ang server.
class LoginAttemptLimiter {
  LoginAttemptLimiter({
    this.maxAttempts = 5,
    this.lockDurations = const [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ],
    this.resetAfter = const Duration(minutes: 30),
  });

  final int maxAttempts;
  final List<Duration> lockDurations;
  final Duration resetAfter;

  final Map<String, _Entry> _entries = {};

  String _key(String email) => email.trim().toLowerCase();

  /// Returns the remaining lock time in seconds, or null if unlocked.
  int? lockedSeconds(String email) {
    final entry = _entries[_key(email)];
    final until = entry?.lockedUntil;

    if (until == null) return null;

    final left = until.difference(DateTime.now());

    if (left <= Duration.zero) {
      entry!.lockedUntil = null;
      return null;
    }

    return (left.inMilliseconds / 1000).ceil();
  }

  /// Records a failed login and returns remaining attempts.
  /// Returns 0 when the account is locked.
  int recordFailure(String email) {
    final now = DateTime.now();
    _purgeStale(now);

    final entry = _entries.putIfAbsent(
      _key(email),
      () => _Entry(now),
    );

    if (now.difference(entry.lastActivity) > resetAfter) {
      entry.failures = 0;
      entry.lockLevel = 0;
    }

    entry.lastActivity = now;
    entry.failures++;

    if (entry.failures >= maxAttempts) {
      final index = entry.lockLevel < lockDurations.length
          ? entry.lockLevel
          : lockDurations.length - 1;

      entry.lockedUntil = now.add(lockDurations[index]);
      entry.lockLevel++;
      entry.failures = 0;

      return 0;
    }

    return maxAttempts - entry.failures;
  }

  /// Clears failed attempts after a successful login.
  void recordSuccess(String email) {
    _entries.remove(_key(email));
  }

  /// Removes stale entries to limit memory usage.
  void _purgeStale(DateTime now) {
    if (_entries.length < 5000) return;

    _entries.removeWhere(
      (_, entry) =>
          entry.lockedUntil == null &&
          now.difference(entry.lastActivity) > resetAfter,
    );
  }
}

class _Entry {
  _Entry(this.lastActivity);

  int failures = 0;
  int lockLevel = 0;
  DateTime? lockedUntil;
  DateTime lastActivity;
}

String lockedMessage(int seconds) =>
    'Too many failed attempts. Please try again in $seconds seconds.';

String failedMessage(int remaining) => remaining == 1
    ? 'Incorrect email or password. 1 attempt remaining.'
    : 'Incorrect email or password. $remaining attempts remaining.';
