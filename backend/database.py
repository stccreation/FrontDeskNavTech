from flask import current_app, g
import pymysql
from pymysql.cursors import DictCursor


def utc_iso(timestamp):
    return timestamp.isoformat(timespec="microseconds") + "Z"


def get_db():
    if "db" not in g:
        g.db = pymysql.connect(**current_app.config["DATABASE_SETTINGS"], cursorclass=DictCursor)
    return g.db


def close_db(_error=None):
    connection = g.pop("db", None)
    if connection is not None and connection.open:
        connection.close()
