from contextlib import contextmanager
from unicodedata import category
from uuid import uuid4

from flask import current_app, request

from auth import json_object


MAX_FILES = 5
MAX_FILE_BYTES = 15 * 1024 * 1024
MAX_REQUEST_BYTES = MAX_FILES * MAX_FILE_BYTES + 256 * 1024


class AttachmentError(ValueError):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def message_submission():
    if request.mimetype != "multipart/form-data":
        return json_object(128 * 1024), []

    request.max_content_length = MAX_REQUEST_BYTES
    request.max_form_parts = MAX_FILES + 8
    request.max_form_memory_size = 256 * 1024
    payload = request.form.to_dict()
    for field in ("customer_blocked", "wait_for_customer"):
        if payload.get(field) in ("true", "false"):
            payload[field] = payload[field] == "true"
    version = payload.get("ownership_version", "")
    if len(version) <= 20 and version.isascii() and version.isdecimal():
        payload["ownership_version"] = int(version)
    if any(key != "attachments" for key in request.files):
        raise AttachmentError("Use the attachments field to upload files.")
    return payload, request.files.getlist("attachments")


def display_name(filename):
    basename = (filename or "").replace("\\", "/").rsplit("/", 1)[-1]
    clean = "".join(char for char in basename if category(char) not in ("Cc", "Cf", "Cs"))
    return clean.strip(" .")[:240].rstrip(" .") or "attachment"


class AttachmentBatch:
    def __init__(self):
        self.metadata = []
        self.paths = []
        self.keep_files = False

    def add(self, directory, uploaded):
        key = uuid4().hex
        path = directory / key
        size = 0
        with path.open("xb") as destination:
            self.paths.append(path)
            for chunk in iter(lambda: uploaded.stream.read(64 * 1024), b""):
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise AttachmentError("Each attachment must be 15 MB or smaller.", 413)
                destination.write(chunk)
        self.metadata.append((key, display_name(uploaded.filename), size))

    def link(self, connection, message_id):
        if self.metadata:
            with connection.cursor() as cursor:
                cursor.executemany(
                    """
                    INSERT INTO ticket_attachments (message_id, storage_key, filename, size_bytes)
                    VALUES (%s, %s, %s, %s)
                    """,
                    [(message_id, *entry) for entry in self.metadata],
                )

    def commit(self, connection):
        # Losing the database connection during commit can leave its outcome unknown.
        # Keep the files so a successfully committed message can still serve them.
        self.keep_files = True
        connection.commit()


@contextmanager
def stage_attachments(files):
    if len(files) > MAX_FILES:
        raise AttachmentError("Attach up to 5 files per message.")

    batch = AttachmentBatch()
    try:
        if files:
            directory = current_app.config["ATTACHMENT_DIRECTORY"]
            directory.mkdir(parents=True, exist_ok=True)
            for uploaded in files:
                batch.add(directory, uploaded)
        yield batch
    finally:
        if not batch.keep_files:
            for path in batch.paths:
                path.unlink(missing_ok=True)
