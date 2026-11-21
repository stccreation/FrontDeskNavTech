# Frontdesk

Frontdesk is a support portal for Arvo Systems. Customers open tickets and share attachments. Agents claim tickets, reply, and leave private notes. Managers can review missed deadlines and trace changes through the ticket history.

The repository contains a Flutter Web client and a Flask API. Flask serves the compiled client and API from the same address. Local development was tested with MariaDB through XAMPP.

## Run locally

1. Install Python 3.12, Flutter 3.41.5, and start your local database server.
2. From the repository root, build the web client.

   ```sh
   cd frontend
   flutter pub get
   flutter build web --no-web-resources-cdn
   cd ..
   ```

   If you already have a compiled web bundle, place its contents in `frontend/build/web/` and continue with the backend setup. The Flutter SDK is only needed to build from source.

3. Follow the [backend setup](backend/README.md) to configure `.env`, create and migrate the database, grant the application account access, and start Flask. The same guide covers creating an administrator and running the workers.
4. Open [Frontdesk](http://127.0.0.1:5000/) to sign in or register a customer account.
