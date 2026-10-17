# LockNote — Secure Personal Notes System

LockNote is a full-stack personal notes application with user registration, authentication, and private notes for each account.

## Technology Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter Web (Dart) |
| Backend | Dart + Shelf REST API |
| Database | PostgreSQL |
| Password hashing | PBKDF2-HMAC-SHA256 with a random salt per password |

## Features

### Application
- Register an account and sign in.
- Create, view, edit, and delete personal notes.
- Search notes by title or content, case-insensitively.
- View a dashboard with total notes, notes updated in the last 7 days, and recently updated notes.
- Use a responsive interface with desktop navigation and a mobile-friendly layout.
- Get form validation, loading states, success messages, and error feedback.

### Security
- Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes, not as plain text.
- SQL queries use parameters instead of concatenating user input into SQL.
- Protected API routes verify the user's server-side session.
- Notes are scoped to their owner; one user cannot access another user's notes.
- Login responses are designed to avoid revealing whether an email address exists.
- Database credentials and other secrets are configured through environment variables or a local, ignored `.env` file.
- Session tokens can be revoked on logout.
- API responses include security-focused headers, and error responses do not expose stack traces.

> Security features depend on the code and configuration in the checked-out version. Do not commit real passwords, tokens, or `.env` files.

## Project Structure

```text
.
├── backend/
│   ├── bin/                  # Backend server and migration entry points
│   ├── lib/src/              # API, authentication, database, and application logic
│   ├── migrations/           # SQL database migrations
│   ├── test/                 # Backend tests
│   ├── tool/                 # Developer tools
│   └── .env.example          # Environment-variable template
├── frontend/
│   ├── lib/src/              # Flutter application source
│   └── test/                 # Frontend tests
├── docker-compose.yml        # Local PostgreSQL configuration
├── .gitignore
└── README.md
```

## Prerequisites

Install the following before running the project:

- [Dart SDK](https://dart.dev/get-dart) (backend)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (frontend)
- [PostgreSQL](https://www.postgresql.org/download/) 14 or newer, or Docker with the Docker Compose plugin

## Setup

### 1. Configure PostgreSQL

The repository includes a Docker Compose configuration for local development.

From the project root, copy the environment template:

```sh
cp .env.example .env
```

Set a strong local database password in `.env`, then start PostgreSQL:

```sh
docker compose up -d
```

The supplied configuration is intended to create a local database named `locknote` with a `locknote` database user. Check `docker-compose.yml` and the environment template for the exact variable names and values expected by your version of the project.

If you use a locally installed PostgreSQL server instead, create a database and user, then configure the backend to connect to them.

**Windows PowerShell note:** If `cp` is unavailable in your shell, use:

```powershell
Copy-Item .env.example .env
```

### 2. Configure and run the backend

Open a terminal in the backend folder:

```sh
cd backend
```

Copy the backend environment template if needed:

```sh
cp .env.example .env
```

Edit `backend/.env` with the connection settings for your PostgreSQL database. Keep this file private and do not commit it.

Install dependencies and apply database migrations:

```sh
dart pub get
dart run bin/migrate.dart
```

Start the API server:

```sh
dart run bin/server.dart
```

The default API address is `http://localhost:8080`, unless your environment configuration specifies another host or port.

### 3. Run the frontend

Open a separate terminal:

```sh
cd frontend
flutter pub get
flutter run -d web-server --web-port 5273
```

Open `http://localhost:5273` in your browser.

By default, the frontend is configured to use the API at `http://localhost:8080`. If your project uses the `API_BASE_URL` Dart define, you can set it explicitly:

```sh
flutter run -d web-server --web-port 5273 --dart-define=API_BASE_URL=http://localhost:8080
```

Make sure the backend's allowed CORS origins include `http://localhost:5273` if your backend configuration requires it.

## API Overview

The backend provides authentication, notes, and dashboard endpoints. The exact response shapes should be checked in the current backend handlers.

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/auth/register` | Register a new account |
| `POST` | `/api/auth/login` | Sign in |
| `POST` | `/api/auth/logout` | End the current session |
| `GET` | `/api/auth/me` | Get the authenticated user |
| `GET` | `/api/notes?search=` | List the authenticated user's notes, optionally filtered |
| `POST` | `/api/notes` | Create a note |
| `GET` | `/api/notes/{id}` | Get one of the authenticated user's notes |
| `PUT` | `/api/notes/{id}` | Update one of the authenticated user's notes |
| `DELETE` | `/api/notes/{id}` | Delete one of the authenticated user's notes |
| `GET` | `/api/dashboard` | Get dashboard summary information |
| `GET` | `/api/health` | Check whether the API is running |

Protected endpoints require the authentication token returned by the login endpoint, typically in this header:

```http
Authorization: Bearer <token>
```

## Database Tables

The initial migration defines the core application tables. In the supplied schema, these include:

- **`users`** — account information and password hashes.
- **`notes`** — note content associated with an owner account.
- **`sessions`** — server-side session records and expiration information.

To inspect registered accounts in PostgreSQL, you can run:

```sql
SELECT id, name, email, created_at
FROM users
ORDER BY id DESC;
```

This query shows registered accounts; it does **not** provide a history of every login. Login history requires a dedicated logging table and backend code to record login events.

## Tests and Code Quality

Run the commands relevant to the part of the project you are checking.

Backend:

```sh
cd backend
dart format lib bin test tool
dart analyze
dart test
```

Frontend:

```sh
cd frontend
dart format lib test
flutter analyze
flutter test
```

Some integration tests may require a reachable PostgreSQL database and appropriate test database configuration. Check the test output and project configuration rather than assuming every test ran.

## Environment and Secrets

- Use `.env.example` as a template for local configuration.
- Keep real `.env` files, database passwords, access tokens, and other secrets out of Git.
- Check `.gitignore` before staging files.
- If a secret was accidentally pushed to a repository, remove it from the repository and rotate the affected credential; deleting the file in a later commit does not invalidate an exposed secret.

## License

This project is provided as a college project template. Check with your instructor or project team before choosing a license for public redistribution.
