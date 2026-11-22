import re
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase

from flask import Flask

from web_app import register_web_app


class WebAppTests(TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.files = {
            "index.html": (b'<html data-app-version="" data-assets-version="" '
                           b'data-renderer-version="">Frontdesk</html>'),
            "main.dart.js": b"old release",
            "canvaskit/chromium/canvaskit.wasm": b"renderer",
            "assets/FontManifest.json": b"[]",
        }
        for name, body in self.files.items():
            path = self.directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)

    def client(self):
        app = Flask(__name__, static_folder=None)
        register_web_app(app, self.directory)
        return app.test_client()

    def versions(self, response):
        return dict(re.findall(r'data-(\w+)-version="([0-9a-f]+)"', response.text))

    def test_index_revalidates_and_known_versions_are_immutable(self):
        client = self.client()
        index = client.get("/")
        self.assertTrue(index.cache_control.no_cache)
        self.assertEqual(index.data, client.get("/index.html").data)
        self.assertEqual(client.get("/", headers={"If-None-Match": index.headers["ETag"]}).status_code, 304)
        versions = self.versions(index)
        for group, name in (
            ("app", "main.dart.js"),
            ("assets", "assets/FontManifest.json"),
            ("renderer", "canvaskit/chromium/canvaskit.wasm"),
        ):
            with client.get(f"/_web/{versions[group]}/{name}") as response:
                self.assertEqual(response.data, self.files[name])
                self.assertTrue(response.cache_control.immutable)
                self.assertEqual(response.cache_control.max_age, 31536000)
        self.assertEqual(client.get(f"/_web/{versions['app']}/index.html").status_code, 404)
        with client.get("/main.dart.js") as response:
            self.assertTrue(response.cache_control.no_cache)

    def test_new_bundle_keeps_the_unchanged_renderer_cached(self):
        previous = self.client()
        original = self.versions(previous.get("/"))
        (self.directory / "main.dart.js").write_bytes(b"new release with changes")
        updated = self.client()
        current = self.versions(updated.get("/"))
        self.assertNotEqual(original["app"], current["app"])
        self.assertEqual(original["renderer"], current["renderer"])
        self.assertEqual(original["assets"], current["assets"])
        previous_url = f"/_web/{original['app']}/main.dart.js"
        self.assertEqual(previous.get(previous_url).status_code, 404)
        self.assertEqual(updated.get(previous_url).status_code, 404)
        with updated.get(f"/_web/{current['app']}/main.dart.js") as response:
            self.assertEqual(response.data, b"new release with changes")
