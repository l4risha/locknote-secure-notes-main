/// Platform-selected session storage.
///
/// Exactly one of the three implementations is compiled in:
///
/// * `session_store_web.dart` — `window.localStorage` (browser builds)
/// * `session_store_io.dart`  — in-memory (VM, widget tests)
/// * `session_store_stub.dart`— in-memory fallback
///
/// All three expose the same three functions: `readStoredToken`,
/// `storeToken`, and `clearStoredToken`.
library;

export 'session_store_stub.dart'
    if (dart.library.io) 'session_store_io.dart'
    if (dart.library.js_interop) 'session_store_web.dart';
