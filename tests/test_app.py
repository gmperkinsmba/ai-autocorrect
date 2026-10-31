import json
import os
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

TEMP = tempfile.TemporaryDirectory()
os.environ["SLOPPYTYPE_HOME"] = TEMP.name
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import server


class AppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.http = server.ThreadingHTTPServer(("127.0.0.1", 8351), server.Handler)
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join(timeout=2)
        TEMP.cleanup()

    def request(self, path, body=None, token=None, origin="http://127.0.0.1:8351"):
        headers = {"Origin": origin}
        raw = None
        if body is not None:
            raw = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
            if token is not None: headers["X-Request-Token"] = token
        req = Request("http://127.0.0.1:8351"+path, data=raw, headers=headers)
        return urlopen(req)

    def token(self):
        page = self.request("/").read().decode()
        return page.split('window.REQUEST_TOKEN="',1)[1].split('"',1)[0]

    def test_corrects_known_typo_and_preserves_case(self):
        self.assertEqual(server.correct("Teh team will RECIEVE it.", set(), set()),
                         ("The team will RECEIVE it.", [{"from":"Teh","to":"The"},{"from":"RECIEVE","to":"RECEIVE"}]))

    def test_dictionary_and_exception_are_applied_and_export_is_selected_only(self):
        token = self.token()
        self.request("/api/dictionary", {"word":"teh","kind":"exception"}, token).read()
        self.request("/api/dictionary", {"word":"Widget","kind":"word"}, token).read()
        fixed = json.loads(self.request("/api/correct", {"text":"teh Widget recieve","context":"editor"}, token).read())
        self.assertEqual(fixed["text"], "teh Widget receive")
        self.request("/api/dictionary", {"word":"acount","kind":"correction","replacement":"account"}, token).read()
        fixed = json.loads(self.request("/api/correct", {"text":"acount","context":"editor"}, token).read())
        self.assertEqual(fixed["text"], "account")
        exported = json.loads(self.request("/api/export", {"words":["acount"]}, token).read())
        self.assertEqual(exported["entries"], [{"word":"acount","kind":"correction","replacement":"account"}])

    def test_sensitive_surface_and_pause_skip_without_changing_text(self):
        token = self.token()
        for context in ("password", "excluded-app"):
            data=json.loads(self.request("/api/correct", {"text":"teh secret","context":context}, token).read())
            self.assertTrue(data["skipped"]); self.assertEqual(data["text"],"teh secret")
        self.request("/api/settings", {"paused":True}, token).read()
        data=json.loads(self.request("/api/correct", {"text":"teh","context":"editor"}, token).read())
        self.assertTrue(data["skipped"]); self.assertEqual(data["text"],"teh")
        self.request("/api/settings", {"paused":False}, token).read()

    def test_invalid_word_is_rejected(self):
        token=self.token()
        with self.assertRaises(HTTPError) as err: self.request("/api/dictionary", {"word":"x<script>","kind":"word"}, token)
        self.assertEqual(err.exception.code,400)
        err.exception.close()

    def test_missing_token_and_bad_origin_are_rejected(self):
        with self.assertRaises(HTTPError) as missing: self.request("/api/settings", {"paused":True})
        self.assertEqual(missing.exception.code,403)
        missing.exception.close()
        with self.assertRaises(HTTPError) as origin: self.request("/api/settings", {"paused":True}, self.token(), "http://evil.test")
        self.assertEqual(origin.exception.code,403)
        origin.exception.close()

    def test_large_body_is_rejected(self):
        req=Request("http://127.0.0.1:8351/api/correct",data=b"x"*16001,headers={"Origin":"http://127.0.0.1:8351","X-Request-Token":self.token()})
        with self.assertRaises(HTTPError) as err: urlopen(req)
        self.assertEqual(err.exception.code,413)
        err.exception.close()

    def test_malformed_content_length_is_rejected(self):
        req=Request("http://127.0.0.1:8351/api/correct",data=b"{}",headers={"Origin":"http://127.0.0.1:8351","X-Request-Token":self.token(),"Content-Length":"bogus"})
        with self.assertRaises(HTTPError) as err: urlopen(req)
        self.assertEqual(err.exception.code,400)
        err.exception.close()


if __name__ == "__main__": unittest.main()
