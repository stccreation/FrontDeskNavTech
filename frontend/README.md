# Frontdesk web

Build from this directory with Flutter 3.41.5 on your PATH. Pass an absolute output path so the build tools can write all assets.

```powershell
flutter pub get
$webOutput = Join-Path (Resolve-Path ../backend).Path web
flutter build web --no-web-resources-cdn --output $webOutput
```

```bash
flutter pub get
web_output="$(cd ../backend && pwd)/web"
flutter build web --no-web-resources-cdn --output "$web_output"
```

Flask serves the compiled files in `backend/web/` at the same origin as the API. See the [local setup guide](../README.md#run-locally) for Windows and Linux commands.
