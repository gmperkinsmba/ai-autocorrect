from __future__ import annotations

import json
import os
import re
import secrets
import sqlite3
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).parent
STORE = Path(os.environ.get("SLOPPYTYPE_HOME", Path.home() / ".local/share/sloppytype"))
STORE.mkdir(parents=True, exist_ok=True, mode=0o700)
STORE.chmod(0o700)
DB = STORE / "sloppytype.sqlite3"
TOKEN = secrets.token_urlsafe(24)
FIXES = {"teh": "the", "recieve": "receive", "seperate": "separate", "adress": "address", "occured": "occurred"}


def connect():
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row
    db.execute("CREATE TABLE IF NOT EXISTS dictionary (word TEXT PRIMARY KEY, kind TEXT NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    columns={r[1] for r in db.execute("PRAGMA table_info(dictionary)")}
    if "replacement" not in columns: db.execute("ALTER TABLE dictionary ADD COLUMN replacement TEXT NOT NULL DEFAULT ''")
    db.commit()
    DB.chmod(0o600)
    return db


@contextmanager
def database():
    db=connect()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def correct(text: str, words: set[str], exceptions: set[str], custom: dict[str,str] | None = None) -> tuple[str, list[dict]]:
    changes = []
    custom=custom or {}
    def sub(match):
        token = match.group(0)
        key = token.casefold()
        if (key not in FIXES and key not in custom) or key in words or key in exceptions:
            return token
        replacement = custom.get(key, FIXES.get(key, ""))
        if token.isupper(): replacement = replacement.upper()
        elif token[:1].isupper(): replacement = replacement.capitalize()
        changes.append({"from": token, "to": replacement})
        return replacement
    return re.sub(r"\b[A-Za-z]+\b", sub, text), changes


class Handler(BaseHTTPRequestHandler):
    server_version = "SloppyType/1.0"
    def log_message(self, *_): pass
    def send_json(self, data, status=200):
        raw = json.dumps(data).encode()
        self.send_response(status); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(raw)
    def valid_origin(self):
        host = self.headers.get("Host", "")
        if host not in {"127.0.0.1:8351", "localhost:8351"}: return False
        origin = self.headers.get("Origin")
        return not origin or origin in {"http://127.0.0.1:8351", "http://localhost:8351"}
    def do_GET(self):
        if not self.valid_origin(): return self.send_json({"error":"invalid host"}, 403)
        if self.path == "/":
            body=(ROOT/"index.html").read_text().replace("__TOKEN__", TOKEN).encode()
            self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8"); self.send_header("Content-Length",str(len(body))); self.send_header("Cache-Control","no-store"); self.end_headers(); self.wfile.write(body); return
        if self.path in {"/style.css", "/app.js"}:
            name = self.path[1:]
            body=(ROOT/name).read_bytes()
            self.send_response(200); self.send_header("Content-Type", "text/css; charset=utf-8" if name.endswith("css") else "text/javascript; charset=utf-8"); self.send_header("Content-Length",str(len(body))); self.send_header("Cache-Control","no-store"); self.end_headers(); self.wfile.write(body); return
        if self.path != "/api/state": return self.send_json({"error":"not found"},404)
        with database() as db:
            entries=[dict(r) for r in db.execute("SELECT word,kind,replacement FROM dictionary ORDER BY word COLLATE NOCASE")]
            paused=db.execute("SELECT value FROM settings WHERE key='paused'").fetchone()
        return self.send_json({"entries":entries,"paused":bool(paused and paused[0]=='1')})
    def do_POST(self):
        if not self.valid_origin() or self.headers.get("X-Request-Token") != TOKEN: return self.send_json({"error":"request rejected"},403)
        try: length=int(self.headers.get("Content-Length","0"))
        except ValueError: return self.send_json({"error":"invalid length"},400)
        if length <= 0: return self.send_json({"error":"request body required"},400)
        if length > 16000: return self.send_json({"error":"request too large"},413)
        try: data=json.loads(self.rfile.read(length) or b"{}")
        except Exception: return self.send_json({"error":"invalid JSON"},400)
        if not isinstance(data,dict): return self.send_json({"error":"JSON object required"},400)
        with database() as db:
            if self.path == "/api/dictionary":
                word=str(data.get("word",""))
                kind=data.get("kind"); replacement=str(data.get("replacement","")).strip()
                if len(word)>60 or not re.fullmatch(r"[\w'-]+",word) or kind not in {"word","exception","correction"}: return self.send_json({"error":"enter a valid word"},400)
                if kind=="correction" and (not re.fullmatch(r"[A-Za-z]+",word) or not re.fullmatch(r"[A-Za-z]+",replacement) or len(replacement)>60): return self.send_json({"error":"custom corrections use one English word on each side"},400)
                if kind!="correction": replacement=""
                db.execute("INSERT INTO dictionary(word,kind,replacement) VALUES(?,?,?) ON CONFLICT(word) DO UPDATE SET kind=excluded.kind,replacement=excluded.replacement",(word,kind,replacement)); db.commit()
                return self.send_json({"ok":True})
            if self.path == "/api/delete": db.execute("DELETE FROM dictionary WHERE word=?",(str(data.get("word","")),)); db.commit(); return self.send_json({"ok":True})
            if self.path == "/api/settings":
                if not isinstance(data.get("paused"),bool): return self.send_json({"error":"paused must be true or false"},400)
                db.execute("INSERT INTO settings(key,value) VALUES('paused',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",('1' if data['paused'] else '0',)); db.commit(); return self.send_json({"ok":True})
            if self.path == "/api/correct":
                text=data.get("text","")
                context=data.get("context","")
                if not isinstance(text,str) or len(text)>12000: return self.send_json({"error":"text too long"},413)
                if context not in {"editor","password","excluded-app"}: return self.send_json({"error":"unknown context"},400)
                paused=db.execute("SELECT value FROM settings WHERE key='paused'").fetchone()
                if (paused and paused[0]=='1') or context in {"password","excluded-app"}: return self.send_json({"text":text,"changes":[],"skipped":True})
                entries=db.execute("SELECT word,kind,replacement FROM dictionary").fetchall()
                words={r['word'].casefold() for r in entries if r['kind']=='word'}; exceptions={r['word'].casefold() for r in entries if r['kind']=='exception'}
                custom={r['word'].casefold():r['replacement'] for r in entries if r['kind']=='correction'}
                fixed,changes=correct(text,words,exceptions,custom)
                return self.send_json({"text":fixed,"changes":changes,"skipped":False})
            if self.path == "/api/export":
                selected=data.get("words",[])
                if not isinstance(selected,list) or len(selected)>500: return self.send_json({"error":"invalid selection"},400)
                selected=[str(w)[:60] for w in selected]
                rows=[dict(r) for r in db.execute("SELECT word,kind,replacement FROM dictionary WHERE word IN (%s) ORDER BY word COLLATE NOCASE" % (','.join('?' for _ in selected) or "NULL"),selected)]
                return self.send_json({"entries":rows})
        return self.send_json({"error":"not found"},404)


if __name__ == "__main__":
    server=ThreadingHTTPServer(("127.0.0.1",8351),Handler)
    print("SloppyType ready at http://127.0.0.1:8351")
    server.serve_forever()
