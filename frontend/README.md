# Frontdesk web

Build from this directory with Flutter 3.41.5 on your PATH.

```sh
flutter pub get
flutter build web --no-web-resources-cdn
```

Flask serves `build/web` at the same origin as the API. See the [backend setup](../backend/README.md) for how to start the local services.
