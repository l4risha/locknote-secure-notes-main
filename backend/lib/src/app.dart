import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'config.dart';
import 'database.dart';
import 'handlers/auth_handlers.dart';
import 'handlers/notes_handlers.dart';
import 'http_utils.dart';
import 'session_store.dart';

/// Builds the complete HTTP handler: routes + CORS + security headers +
/// JSON error mapping + request logging, optionally serving the built Flutter
/// web app from the same origin.
///
/// Middleware order (outermost first): logging → CORS → error mapping →
/// router. That way every response — including error responses — receives
/// CORS headers and a request log line.
Handler buildHandler({required Database db, required Config config}) {
  final sessions = SessionStore(db, ttl: config.sessionTtl);
  final router = _buildRouter(db: db, sessions: sessions, config: config);

  final apiHandler = const Pipeline()
      .addMiddleware(logRequests(
        // shelf logs only "METHOD /path STATUS duration" — never headers or
        // bodies — so bearer tokens and passwords cannot leak into log files.
        logger: (String message, bool isError) {
          if (isError) {
            stderr.writeln(message);
          } else {
            // ignore: avoid_print
            print(message);
          }
        },
      ))
      .addMiddleware(securityHeadersMiddleware)
      .addMiddleware(corsMiddleware(config.allowedOrigins))
      .addMiddleware(errorMappingMiddleware)
      .addHandler(router.call);

  final staticDirPath = config.staticDir;
  if (staticDirPath == null) return apiHandler;

  final staticHandler =
      createStaticHandler(staticDirPath, defaultDocument: 'index.html');
  final indexFile = File('$staticDirPath${Platform.pathSeparator}index.html');

  // Single-origin deployment: the API for /api/*, static files for anything
  // else, and index.html as the SPA fallback so deep links keep working.
  return (Request request) async {
    final path = request.url.path;
    final isApi = path.startsWith('api/');
    final isGetLike = request.method == 'GET' || request.method == 'HEAD';

    if (!isApi && isGetLike) {
      final response = await staticHandler(request);
      if (response.statusCode == 404 &&
          !path.startsWith('assets/') &&
          indexFile.existsSync()) {
        return Response(
          200,
          body: indexFile.openRead(),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return response;
    }
    return apiHandler(request);
  };
}

/// Registers every API endpoint.
Router _buildRouter({
  required Database db,
  required SessionStore sessions,
  required Config config,
}) {
  final auth = AuthHandlers(db: db, sessions: sessions, config: config);
  final notes = NotesHandlers(db: db, sessions: sessions);

  final router = Router();

  // Health check (used by docker-compose healthchecks and the README).
  router.get(
      '/api/health', (Request request) => jsonResponse({'status': 'ok'}));

  // Authentication.
  router.post('/api/auth/register', auth.register);
  router.post('/api/auth/login', auth.login);
  router.post('/api/auth/logout', auth.logout);
  router.get('/api/auth/me', auth.me);

  // Notes (all require a valid session and only touch the caller's rows).
  router.get('/api/notes', notes.list);
  router.post('/api/notes', notes.create);
  router.get('/api/notes/<id>', notes.get);
  router.put('/api/notes/<id>', notes.update);
  router.delete('/api/notes/<id>', notes.delete);

  // Dashboard summary.
  router.get('/api/dashboard', notes.dashboard);

  // Anything else under /api → JSON 404 (instead of shelf's plain text).
  router.all('/<path|.*>', (Request request) {
    throw ApiException(404, 'The requested endpoint does not exist.',
        code: 'not_found');
  });

  return router;
}

/// Adds basic browser hardening headers to every response.
Middleware get securityHeadersMiddleware => (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        final headers = Map<String, String>.from(response.headers);
        headers['x-content-type-options'] = 'nosniff';
        headers['x-frame-options'] = 'DENY';
        headers['referrer-policy'] = 'no-referrer';
        if (request.url.path.startsWith('api/')) {
          // User data must never be cached by proxies or the browser.
          headers['cache-control'] = 'no-store';
        }
        return response.change(headers: headers);
      };
    };

/// Allows browser clients on other origins (the Flutter dev server) to call
/// the API. Safe without `Access-Control-Allow-Credentials` because the API
/// authenticates with a Bearer header, never with cookies.
Middleware corsMiddleware(List<String> allowedOrigins) => (Handler inner) {
      return (Request request) async {
        final origin = request.headers['origin'];
        final exposeHeaders = {
          'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'access-control-allow-headers': 'authorization, content-type',
          'vary': 'origin',
        };

        String? allowedOrigin;
        if (origin != null) {
          if (allowedOrigins.isEmpty) {
            allowedOrigin = origin; // Development: allow any origin.
          } else if (allowedOrigins.contains(origin)) {
            allowedOrigin = origin;
          }
        }

        if (request.method == 'OPTIONS') {
          return Response(
            204,
            headers: {
              ...exposeHeaders,
              if (allowedOrigin != null)
                'access-control-allow-origin': allowedOrigin,
            },
          );
        }

        final response = await inner(request);
        return response.change(
          headers: {
            ...response.headers,
            ...exposeHeaders,
            if (allowedOrigin != null)
              'access-control-allow-origin': allowedOrigin,
          },
        );
      };
    };

/// Converts thrown [ApiException]s (and unexpected errors) into the JSON
/// error envelope. Unexpected errors are logged server-side but their details
/// are never sent to clients.
Middleware get errorMappingMiddleware => (Handler inner) {
      return (Request request) async {
        try {
          return await inner(request);
        } on ApiException catch (error) {
          return errorResponse(
            error.statusCode,
            error.message,
            code: error.code,
            details: error.details,
          );
        } catch (error, stackTrace) {
          stderr.writeln(
              'Unhandled error on ${request.method} ${request.url.path}');
          stderr.writeln('$error\n$stackTrace');
          return errorResponse(
            500,
            'An unexpected server error occurred. Please try again.',
            code: 'internal_error',
          );
        }
      };
    };
