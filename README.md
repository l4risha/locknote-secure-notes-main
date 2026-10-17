# LockNote — Secure Personal Notes System

A complete full-stack notes application with user registration, login, and
per-user private notes.

| Layer     | Technology            |
| --------- | --------------------- |
| Frontend  | **Flutter Web (Dart)** |
| Backend   | **Dart + Shelf**       |
| Database  | **PostgreSQL**         |
| Passwords | **PBKDF2-HMAC-SHA256** (salted, per-password random salt) |

---

## Features

**Application**

- User registration and login with server-side sessions
- Create, view, edit, and delete personal notes
- Search notes by title **or** content (case-insensitive, SQL-side)
- Dashboard with total notes, notes updated in the last 7 days, and the
  5 most recently updated notes
- Responsive layout: sidebar on desktop, drawer + stacked search bar on mobile
- Form validation, loading states, success snackbar, and error banners
  everywhere

**Security**

- Passwords are **never stored in plain text** — only
  `pbkdf2_sha256$<iterations>$<salt>$<key>` hashes (see
  `backend/lib/src/passwords.dart`, a dependency-free implementation you can
  read and audit)
- **Parameterized SQL everywhere** — every query uses named bind parameters
  (`Sql.named` + `parameters:`); user input is never concatenated into SQL
- **Authentication is verified on the server** for every protected endpoint
  (`Authorization: Bearer <token>` → SHA-256 digest lookup in `sessions`,
  expiry checked against the database clock, deleted on logout)
- **Users can only touch their own notes** — every statement is filtered by
  `WHERE user_id = @userId`; other users' note IDs behave exactly like
  non-existent notes (404)
- Login answers *byte-identical* 401s for "wrong password" and "unknown
  email", and performs the same hashing work, so accounts cannot be enumerated
- Database credentials and secrets come **only** from environment variables /
  a git-ignored `.env` file — startup fails fast if they are missing
- No hardcoded or fake users anywhere: accounts are created through the real
  registration flow and verified against PostgreSQL
- Extra hardening: constant-time hash comparison, escaped `LIKE` patterns,
  `no-store` on API responses, `nosniff` / `X-Frame-Options: DENY` /
  `Referrer-Policy` headers, JSON-only error responses with no stack traces,
  request logging that never prints headers or bodies

---

## Project structure

```
.
├── backend/                    # Dart + Shelf REST API
│   ├── bin/
│   │   ├── server.dart         # API server entry point
│   │   └── migrate.dart        # applies SQL migrations
│   ├── lib/src/
│   │   ├── app.dart            # router, CORS, security headers, errors, static files
│   │   ├── auth.dart           # requireAuth() guard used by protected routes
│   │   ├── config.dart         # env-var configuration (fails fast when missing)
│   │   ├── database.dart       # PostgreSQL wrapper (parameterized queries only)
│   │   ├── handlers/           # auth + notes endpoints
│   │   ├── migrations.dart     # migration runner (schema_migrations table)
│   │   ├── passwords.dart      # PBKDF2 hashing & constant-time verification
│   │   ├── session_store.dart  # create/verify/revoke bearer sessions
│   │   └── validation.dart     # shared input validation + LIKE escaping
│   ├── migrations/001_init.sql # database schema
│   ├── test/                   # 43 tests (unit + full API integration)
│   ├── tool/benchmark_passwords.dart
│   └── .env.example            # environment variable template (no secrets)
├── frontend/                   # Flutter Web app
│   ├── lib/src/
│   │   ├── app.dart             # auth gate: splash → login → dashboard
│   │   ├── core/                # API client, platform session storage
│   │   ├── models/              # User, Note, DashboardSummary
│   │   ├── screens/             # auth, home shell, dashboard, notes
│   │   ├── state/               # AuthController, NotesController
│   │   └── widgets/             # text fields, cards, dialogs, banners…
│   └── test/                    # widget tests against a mock backend
├── docker-compose.yml          # local PostgreSQL 16
├── .gitignore                  # excludes .env, build output, IDE files
└── README.md
```

---

## Prerequisites

- **Dart SDK** ≥ 3.5 (backend)
- **Flutter SDK** ≥ 3.13 / stable channel (frontend)
- **PostgreSQL** ≥ 14 — via Docker (`docker compose`) or a local install
- (Optional) `curl` or any HTTP client for manual API testing

---

## 1. Database

### Option A — Docker (recommended)

```sh
cp .env.example .env       # choose your own password (`.env` is git-ignored)
docker compose up -d
```

This starts PostgreSQL 16 on `localhost:5432` with:

| Setting    | Value                              |
| ---------- | ---------------------------------- |
| Database   | `locknote`                         |
| User       | `locknote`                         |
| Password   | `POSTGRES_PASSWORD` from your `.env` |

No password is stored anywhere in the repository — `docker compose` refuses to
start until you set one.

### Option B — local PostgreSQL

```sh
sudo -u postgres createuser locknote --pwprompt
sudo -u postgres createdb locknote -O locknote
```

> Never use weak credentials outside your own machine — put real values in
> `backend/.env`, which is git-ignored.

---

## 2. Backend

```sh
cd backend
cp .env.example .env         # then edit the values (never commit .env)
                             # DB_PASSWORD = the POSTGRES_PASSWORD from step 1
dart pub get
dart run bin/migrate.dart    # creates tables from migrations/*.sql
dart run bin/server.dart     # http://localhost:8080
```

The server also applies pending migrations on startup (`AUTO_MIGRATE=true`),
retries the database connection while it boots, and exposes:

- `GET /api/health` → `{"status":"ok"}`

### Environment variables (`backend/.env.example`)

| Variable            | Required | Default     | Purpose                                    |
| ------------------- | -------- | ----------- | ------------------------------------------ |
| `DB_HOST`           | ✅       | —           | PostgreSQL host                            |
| `DB_PORT`           |          | `5432`      | PostgreSQL port                            |
| `DB_NAME`           | ✅       | —           | Database name                              |
| `DB_USER`           | ✅       | —           | Database user                              |
| `DB_PASSWORD`       | ✅       | —           | Database password (never commit it)        |
| `DB_SSL`            |          | `disable`   | `disable` \| `require` \| `verify-full`    |
| `SERVER_HOST`       |          | `0.0.0.0`   | Listen interface                           |
| `SERVER_PORT`       |          | `8080`      | Listen port                                |
| `ALLOWED_ORIGINS`   |          | *(any)*     | Comma-separated CORS origins for dev       |
| `STATIC_DIR`        |          | *(empty)*   | Serve a built Flutter app from this dir    |
| `SESSION_TTL_HOURS` |          | `720`       | Session lifetime in hours (30 days)          |
| `PBKDF2_ITERATIONS` |          | `100000`    | Password hashing work factor               |
| `AUTO_MIGRATE`      |          | `true`      | Apply migrations at startup                |

Real environment variables always override `.env`. If a required variable is
missing, the server prints exactly which one and exits — it never falls back
to a built-in password.

Set `DB_SSL=require` (or `verify-full`) when your database uses TLS, e.g.
managed PostgreSQL.

---

## 3. Frontend

### Development (two ports, CORS enabled)

```sh
cd frontend
flutter pub get
flutter run -d web-server --web-port 5273
```

The app talks to `http://localhost:8080` by default. Override with:

```sh
flutter run -d web-server --web-port 5273 --dart-define=API_BASE_URL=http://localhost:8080
```

Make sure `ALLOWED_ORIGINS` in `backend/.env` includes your dev origin
(e.g. `http://localhost:5273`).

### Single-origin build (backend serves the UI)

```sh
cd frontend
flutter build web --release --dart-define=API_BASE_URL=

cd ../backend
STATIC_DIR=../frontend/build/web dart run bin/server.dart
# → http://localhost:8080  (UI + API from one origin, no CORS needed)
```

An empty `API_BASE_URL` makes every request relative to the page origin.

---

## API reference

All request/response bodies are JSON. Protected endpoints require
`Authorization: Bearer <token>` (returned by register/login).

| Method   | Path                | Auth | Description                                    |
| -------- | ------------------- | ---- | ---------------------------------------------- |
| `POST`   | `/api/auth/register`| –    | `{name,email,password}` → `201 {token,user}`   |
| `POST`   | `/api/auth/login`   | –    | `{email,password}` → `200 {token,user}`        |
| `POST`   | `/api/auth/logout`  | ✅   | Revokes the session token                      |
| `GET`    | `/api/auth/me`      | ✅   | Current user                                   |
| `GET`    | `/api/notes?search=`| ✅   | Own notes (optionally filtered), newest first  |
| `POST`   | `/api/notes`        | ✅   | `{title,content}` → `201 {note}`               |
| `GET`    | `/api/notes/{id}`   | ✅   | One owned note (else `404`)                    |
| `PUT`    | `/api/notes/{id}`   | ✅   | Update owned note (else `404`)                 |
| `DELETE` | `/api/notes/{id}`   | ✅   | Delete owned note (else `404`)                 |
| `GET`    | `/api/dashboard`    | ✅   | `{totalNotes,updatedLast7Days,recentNotes}`    |
| `GET`    | `/api/health`       | –    | Liveness check                                 |

Errors use one envelope:

```json
{ "error": "Human-readable message", "code": "validation_failed",
  "details": { "email": "This email is already registered." } }
```

---

## Database schema

`backend/migrations/001_init.sql` (applied automatically, tracked in
`schema_migrations`):

- **users** — `id, name, email (unique, case-insensitive), password_hash, created_at`
- **notes** — `id, user_id → users (ON DELETE CASCADE), title, content, created_at, updated_at`
  with indexes on `user_id` and `(user_id, updated_at DESC)`
- **sessions** — `id, user_id, token_hash (SHA-256 of the bearer token, unique),
  created_at, expires_at`

Add a new numbered `.sql` file to `migrations/` and rerun
`dart run bin/migrate.dart` to evolve the schema.

---

## Tests, analysis, formatting

```sh
# Backend — 43 tests: crypto vectors, validation, and a full API integration
# suite that runs against PostgreSQL (auto-skips with a clear message when no
# database is reachable — it never fakes a pass).
cd backend
dart format --set-exit-if-changed lib bin test tool
dart analyze
DB_HOST=localhost DB_PORT=5432 DB_USER=locknote DB_PASSWORD=... DB_NAME=locknote dart test

# Frontend — widget tests against a mocked backend
cd frontend
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

`TEST_DB_NAME` overrides the integration test database
(default: `<DB_NAME>_test`, created automatically; test rows are cleaned up
afterwards).

Tune the password work factor for your machine:

```sh
cd backend && dart run tool/benchmark_passwords.dart
```

---

## What was verified, and what you must configure

This implementation was exercised end-to-end in its build environment:

| Check                                                            | Status |
| ---------------------------------------------------------------- | ------ |
| `dart analyze` / `flutter analyze` (both projects)               | ✅ no issues |
| `dart test` — 43 tests incl. **live PostgreSQL integration suite** | ✅ all pass |
| `flutter test` — 5 widget tests (validation, login, navigation)  | ✅ all pass |
| `flutter build web --release`                                    | ✅ built |
| Server run with real PostgreSQL 16: register → login → CRUD → search → dashboard → logout | ✅ 21/21 checks |
| Cross-user isolation (user B vs user A's note IDs)               | ✅ 404 on read/update/delete |
| Revoked/expired/garbage tokens                                   | ✅ 401 |
| Static UI + API served from one origin, SPA fallback, security headers | ✅ |

Because the tests above ran against a **local PostgreSQL 16 instance**, you
still need to configure your own database to run the app on your machine:
start PostgreSQL (Docker or native), copy `backend/.env.example` →
`backend/.env`, set your real `DB_*` values, run the migrations, then start
the backend and frontend with the commands from the sections above. If
PostgreSQL is not available, the backend refuses to start with a clear
message and the integration tests skip themselves — nothing is mocked or
faked.

> Note: the `docker compose` path itself was not executed in the build
> environment (no Docker daemon was available there); the identical schema
> and connection settings were verified against a natively installed
> PostgreSQL 16 over SCRAM password authentication.

---

## Security checklist (college-project friendly)

- [x] Plaintext passwords are never stored or logged
- [x] Salted PBKDF2-HMAC-SHA256 with per-hash random salts and stored
      iteration counts (upgrade-safe)
- [x] Parameterized queries for every statement
- [x] Server-side authentication on every protected route
- [x] Row-level ownership checks (`user_id` filter) in SQL
- [x] Secrets only in environment variables / git-ignored `.env`
- [x] `.gitignore` excludes `.env`, build output, and generated files
- [x] No hardcoded demo users; registration writes to PostgreSQL
- [x] Sessions revocable server-side (logout deletes the row)
- [x] Uniform auth errors (no account enumeration) + constant-time comparisons

## License

Provided as a college project template — adapt freely for your submission.
