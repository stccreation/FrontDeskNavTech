# Frontdesk

Frontdesk is a support portal for Arvo Systems. Customers open tickets and share attachments. Agents claim tickets, reply, and leave private notes. Managers can review missed deadlines and trace changes through the ticket history.

The repository contains a Flutter Web client and a Flask API. Flask serves the compiled site from `backend/web/` and the API from the same address.

## Run locally

Use Python 3.12 and a running MySQL server. See the [database setup](backend/README.md#database-setup) for the SQL to create the database and application account. If you have a prebuilt bundle, place the complete web build under `backend/web/`, with `index.html` directly inside that folder. Build from source with Flutter 3.41.5 if you need to generate the bundle.

### Windows (PowerShell)

From the repository root, run this build step if you need to generate the web bundle.

```powershell
cd frontend
flutter pub get
$webOutput = Join-Path (Resolve-Path ../backend).Path web
flutter build web --no-web-resources-cdn --output $webOutput
cd ..
```

Set up the backend from the repository root.

```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_hex(32))"
```

Edit `.env` with your database credentials, set `SECRET_KEY` to the generated value, and keep `SESSION_COOKIE_SECURE=false` for local HTTP. Run the migration using your database administrator account. Replace `root` if your account uses a different name. Then apply the [application account grants](backend/README.md#application-account-grants).

```powershell
.\.venv\Scripts\python.exe -m flask --app app db-upgrade --user root --ask-password
```

Create the first administrator and start the server.

```powershell
.\.venv\Scripts\python.exe -m flask --app app staff-create --role admin --name "Frontdesk Admin" --email admin@example.com
.\.venv\Scripts\python.exe -m flask --app app run --host 127.0.0.1 --port 5000
```

### Linux (Bash)

From the repository root, run this build step if you need to generate the web bundle.

```bash
cd frontend
flutter pub get
web_output="$(cd ../backend && pwd)/web"
flutter build web --no-web-resources-cdn --output "$web_output"
cd ..
```

Set up the backend from the repository root.

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
cp .env.example .env
.venv/bin/python -c "import secrets; print(secrets.token_hex(32))"
```

Edit `.env` with your database credentials, set `SECRET_KEY` to the generated value, and keep `SESSION_COOKIE_SECURE=false` for local HTTP. The migration command needs a database administrator account that can sign in over TCP. Use your TCP account name if your local `root` account signs in only over a Unix socket. After migrating, apply the [application account grants](backend/README.md#application-account-grants).

```bash
.venv/bin/python -m flask --app app db-upgrade --user root --ask-password
```

Create the first administrator and start the server.

```bash
.venv/bin/python -m flask --app app staff-create --role admin --name "Frontdesk Admin" --email admin@example.com
.venv/bin/python -m flask --app app run --host 127.0.0.1 --port 5000
```

### Verify the local app

Open [Frontdesk](http://127.0.0.1:5000/) to sign in. Use [the health endpoint](http://127.0.0.1:5000/api/health) to check the database connection. See the [backend guide](backend/README.md) for SLA and email workers.
