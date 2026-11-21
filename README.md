# Frontdesk

Frontdesk is a support portal for Arvo Systems. Customers open tickets and share attachments. Agents claim tickets, reply, and leave private notes. Managers can review missed deadlines and trace changes through the ticket history.

The repository contains a Flutter Web client and a Flask API. Flask serves the compiled site from `backend/web/` and the API from the same address.

## Run locally

Both options require Git, Python 3.12, and a running MySQL server. See the [database setup](backend/README.md#database-setup) for the SQL to create the database and application account.

### Option 1 — Quick run

This downloads the backend and the prebuilt web app. You can run it without the Flutter SDK. The same commands work in Windows PowerShell and Linux Bash.

```sh
git clone --branch main --filter=blob:none --sparse https://github.com/stccreation/FrontDeskNavTech.git
cd FrontDeskNavTech
git sparse-checkout set backend
```

Continue with [Start the backend](#start-the-backend).

### Option 2 — Build and run

Install Flutter 3.41.5 to build from source. The build writes directly to `backend/web/`.

#### Windows (PowerShell)

```powershell
git clone https://github.com/stccreation/FrontDeskNavTech.git
cd FrontDeskNavTech/frontend
flutter pub get
$webOutput = Join-Path (Resolve-Path ../backend).Path web
flutter build web --no-web-resources-cdn --output $webOutput
cd ..
```

#### Linux (Bash)

```bash
git clone https://github.com/stccreation/FrontDeskNavTech.git
cd FrontDeskNavTech/frontend
flutter pub get
web_output="$(cd ../backend && pwd)/web"
flutter build web --no-web-resources-cdn --output "$web_output"
cd ..
```

### Start the backend

Use these commands from the repository root after either checkout option. On first setup, create the [database and application account](backend/README.md#database-setup) before running the migration.

#### Windows (PowerShell)

```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
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

#### Linux (Bash)

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
test -f .env || cp .env.example .env
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

Open [Frontdesk](http://127.0.0.1:5000/) to sign in. Use [the health endpoint](http://127.0.0.1:5000/api/health) to check the database connection. On subsequent runs, use your platform's `flask run` command.

Run the ticket lifecycle worker in a second terminal from `backend/` to process automatic inactivity closures and record overdue deadlines.

**Windows (PowerShell)**

```powershell
.\.venv\Scripts\python.exe -m flask --app app ticket-lifecycle --watch
```

**Linux (Bash)**

```bash
.venv/bin/python -m flask --app app ticket-lifecycle --watch
```

New customers verify their email before choosing a password. Configure SMTP to test signup locally. See the [backend guide](backend/README.md#staff-accounts-and-audit-history) for local email capture settings and the [notification worker](backend/README.md#dashboards-reports-and-notifications) for ticket replies.

## Assessment

See the [completion note](COMPLETION_NOTE.md) for decisions, verification, and outstanding work.
