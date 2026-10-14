import json
import os
import unittest
from unittest.mock import patch

os.environ["EDESK_LOCAL_MODE"] = "true"
from cloud_run.main import app, automation_lock, _automation_failure_message
from local_edesk.authentication import verify_token

ORIGIN = "https://gerenciador-horas.web.app"
HEADERS = {"Origin": ORIGIN, "Authorization": "Bearer test-token"}


class LocalIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def post(self, action="horas", data=None):
        return self.client.post(f"/api/edesk/{action}", headers=HEADERS,
                                json=data or {"request": {
                                    "edeskCredenciais": {"email": "test@example.com", "senha": "test"},
                                    "trabalhos": [{}]}, "enviar": False})

    def test_preflight_allows_only_app_and_loopback_host(self):
        response = self.client.options("/api/edesk/horas", headers={"Origin": ORIGIN})
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.headers["Access-Control-Allow-Origin"], ORIGIN)
        self.assertEqual(response.headers["Access-Control-Allow-Private-Network"], "true")
        self.assertEqual(self.client.options("/api/edesk/horas", headers={"Origin": "https://evil.example"}).status_code, 403)
        self.assertEqual(self.client.get("/healthz", headers={"Host": "evil.example:8765"}).status_code, 403)

    def test_authentication_is_required_and_bad_tokens_fail(self):
        self.assertEqual(self.client.post("/api/edesk/horas", headers={"Origin": ORIGIN}, json={}).status_code, 401)
        self.assertEqual(self.client.post("/api/edesk/horas", json={}).status_code, 403)
        with patch("local_edesk.authentication.verify_token", side_effect=ValueError()):
            self.assertEqual(self.post().status_code, 401)

    def test_validation_never_starts_process_or_leaves_lock(self):
        with patch("local_edesk.authentication.verify_token", return_value={"sub": "test"}), patch("cloud_run.main.subprocess.Popen") as process:
            self.assertEqual(self.post(data={"request": {}, "enviar": True}).status_code, 400)
            invalid = {"request": {"edeskCredenciais": {"email": "test", "senha": "test"}, "trabalhos": [{}], "url": "https://evil.example"}, "enviar": True}
            self.assertEqual(self.post(data=invalid).status_code, 400)
            process.assert_not_called()
        self.assertTrue(automation_lock.acquire(False))
        automation_lock.release()

    def test_busy_operation_is_not_queued_or_repeated(self):
        automation_lock.acquire()
        try:
            with patch("local_edesk.authentication.verify_token", return_value={"sub": "test"}), patch("cloud_run.main.subprocess.Popen") as process:
                self.assertEqual(self.post().status_code, 409)
                process.assert_not_called()
        finally:
            automation_lock.release()

    def test_all_routes_pass_intent_and_require_success(self):
        for action in ["horas", "comentarios", "fases"]:
            body = {"request": {"edeskCredenciais": {"email": "test", "senha": "test"},
                                "trabalhos": [{}], "fases": [{}], "solicitacao": "1", "idTrabalho": "1", "texto": "teste"}, "enviar": action == "fases"}
            with patch("local_edesk.authentication.verify_token", return_value={"sub": "test"}), patch("cloud_run.main.subprocess.Popen") as process:
                def create(*args, **kwargs):
                    with open(args[0][-1], encoding="utf-8") as file:
                        request = json.load(file)
                    self.assertEqual(request["enviar"], body["enviar"])
                    self.assertIn(f"edesk_{'comentario' if action == 'comentarios' else action}.py", args[0][1])
                    self.assertEqual(kwargs["env"]["EDESK_HEADLESS"], "false")
                    return process.return_value
                process.side_effect = create
                process.return_value.communicate.return_value = ('{"ok":true}', "")
                process.return_value.returncode = 0
                response = self.post(action, body)
                self.assertEqual(response.status_code, 200)
                self.assertTrue(response.json["confirmed"])
                process.return_value.returncode = 1
                self.assertEqual(self.post(action, body).status_code, 502)
        self.assertTrue(automation_lock.acquire(False))
        automation_lock.release()

    def test_login_failure_returns_actionable_message_without_private_logs(self):
        message = _automation_failure_message('Tempo limite de autenticação excedido. senha=private https://example.com/?token=private')
        self.assertIn('login no E-Desk', message)
        self.assertIn('janela', message)
        self.assertNotIn('private', message)
        self.assertTrue(self.client.get('/healthz').json['browserVisible'])

    def test_token_verifier_enforces_project_issuer_and_subject(self):
        with patch("local_edesk.authentication.id_token.verify_firebase_token", return_value={"iss": "https://securetoken.google.com/gerenciador-horas", "sub": "test"}) as verifier:
            self.assertEqual(verify_token("test")["sub"], "test")
            self.assertEqual(verifier.call_args.kwargs["audience"], "gerenciador-horas")
        for claims in [{"iss": "other", "sub": "test"}, {"iss": "https://securetoken.google.com/gerenciador-horas", "sub": ""}]:
            with patch("local_edesk.authentication.id_token.verify_firebase_token", return_value=claims):
                with self.assertRaises(ValueError): verify_token("test")

    def test_signed_token_checks_signature_expiry_and_audience(self):
        import time
        from datetime import datetime, timedelta, timezone
        from types import SimpleNamespace
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID
        from google.auth import crypt, jwt

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "test")])
        now = datetime.now(timezone.utc)
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                .public_key(key.public_key()).serial_number(1)
                .not_valid_before(now - timedelta(minutes=1))
                .not_valid_after(now + timedelta(days=1)).sign(key, hashes.SHA256()))
        signer = crypt.RSASigner.from_string(key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption()), key_id="test-key")
        claims = {"iss": "https://securetoken.google.com/gerenciador-horas", "sub": "test-user",
                  "aud": "gerenciador-horas", "iat": int(time.time()) - 1,
                  "exp": int(time.time()) + 300}
        response = SimpleNamespace(status=200, data=json.dumps({"test-key": cert.public_bytes(serialization.Encoding.PEM).decode()}).encode())
        with patch("local_edesk.authentication._fetch_certificates", return_value=response):
            token = jwt.encode(signer, claims).decode()
            self.assertEqual(verify_token(token)["sub"], "test-user")
            for invalid in [{**claims, "aud": "other-project"}, {**claims, "exp": int(time.time()) - 1},
                            {**claims, "iss": "https://securetoken.google.com/other-project"}]:
                with self.assertRaises(ValueError): verify_token(jwt.encode(signer, invalid).decode())
            payload = token.split(".")
            payload[2] = ("A" if payload[2][0] != "A" else "B") + payload[2][1:]
            with self.assertRaises(ValueError): verify_token(".".join(payload))


if __name__ == "__main__":
    unittest.main()
