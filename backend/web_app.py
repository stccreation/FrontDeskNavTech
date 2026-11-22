from dataclasses import dataclass
from hashlib import file_digest, sha256
from os import fstat
from pathlib import Path

from flask import Response, abort, request, send_file, send_from_directory


ONE_YEAR = 365 * 24 * 60 * 60


def file_identity(file):
    stat = fstat(file.fileno())
    return stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns


@dataclass(frozen=True)
class WebAsset:
    path: Path
    digest: str
    identity: tuple[int, int, int, int]

    @classmethod
    def read(cls, path):
        with path.open("rb") as file:
            identity = file_identity(file)
            digest = file_digest(file, "sha256").hexdigest()
            if identity != file_identity(file):
                raise RuntimeError(f"Web asset changed during startup: {path.name}")
        return cls(path, digest, identity)


def register_web_app(app, directory):
    index_path = directory / "index.html"
    index_body = index_path.read_bytes() if index_path.is_file() else None
    versioned = {}
    if index_body is not None:
        groups = {
            "app": directory.glob("main.dart.*"),
            "assets": (directory / "assets").rglob("*"),
            "renderer": (directory / "canvaskit").rglob("*"),
        }
        for group, paths in groups.items():
            assets = {
                path.relative_to(directory).as_posix(): WebAsset.read(path)
                for path in sorted(paths) if path.is_file()
            }
            fingerprint = sha256()
            for name, asset in sorted(assets.items()):
                fingerprint.update(f"{name}\0{asset.digest}\n".encode())
            version = fingerprint.hexdigest()[:24]
            versioned.setdefault(version, {}).update(assets)
            index_body = index_body.replace(
                f'data-{group}-version=""'.encode(),
                f'data-{group}-version="{version}"'.encode(),
                1,
            )
        index_etag = sha256(index_body).hexdigest()

    @app.get("/")
    @app.get("/index.html")
    def web_index():
        if index_body is None:
            abort(404)
        response = Response(index_body, mimetype="text/html")
        response.set_etag(index_etag)
        response.cache_control.no_cache = True
        return response.make_conditional(request)

    @app.get("/_web/<version>/<path:name>")
    def versioned_web_asset(version, name):
        asset = versioned.get(version, {}).get(name)
        if asset is None:
            abort(404)
        try:
            file = asset.path.open("rb")
        except FileNotFoundError:
            abort(404)
        # An in-place deployment can replace files before the server restarts.
        if file_identity(file) != asset.identity:
            file.close()
            abort(404)
        response = send_file(file, download_name=asset.path.name, etag=asset.digest, max_age=ONE_YEAR)
        response.content_length = asset.identity[2]
        response.cache_control.immutable = True
        return response

    @app.get("/<path:asset>")
    def web_asset(asset):
        return send_from_directory(directory, asset)
