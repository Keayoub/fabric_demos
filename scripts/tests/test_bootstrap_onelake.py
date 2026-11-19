import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


MODULE = Path(__file__).resolve().parents[1] / "bootstrap_onelake.py"
SPEC = importlib.util.spec_from_file_location("bootstrap", MODULE)
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)


def response(status, resource_type=None):
    result = Mock(status_code=status, headers={})
    if resource_type:
        result.headers["x-ms-resource-type"] = resource_type
    return result


class DirectoryTests(unittest.TestCase):
    def setUp(self):
        self.credential = Mock()
        self.credential.get_token.return_value.token = "not-a-real-token"
        self.session = Mock()
        self.url = bootstrap.ONELAKE + "/workspace/item/Files/bronze"

    def test_existing_directory_is_a_noop(self):
        self.session.request.return_value = response(200, "directory")
        self.assertEqual(bootstrap.ensure_directory(self.session, self.credential, self.url), "exists")
        self.assertEqual(self.session.request.call_count, 1)

    def test_missing_directory_is_created_and_second_run_is_a_noop(self):
        self.session.request.side_effect = [response(404), response(201), response(200, "directory")]
        self.assertEqual(bootstrap.ensure_directory(self.session, self.credential, self.url), "created")
        self.assertEqual(bootstrap.ensure_directory(self.session, self.credential, self.url), "exists")
        self.assertEqual([call.args[0] for call in self.session.request.call_args_list], ["HEAD", "PUT", "HEAD"])
        self.assertFalse(self.session.request.call_args_list[1].kwargs["allow_redirects"])

    def test_access_denied_does_not_attempt_creation(self):
        self.session.request.return_value = response(403)
        with self.assertRaisesRegex(RuntimeError, "403"):
            bootstrap.ensure_directory(self.session, self.credential, self.url)
        self.assertEqual(self.session.request.call_count, 1)

    def test_file_collision_is_not_accepted(self):
        self.session.request.return_value = response(200, "file")
        with self.assertRaisesRegex(RuntimeError, "file exists"):
            bootstrap.ensure_directory(self.session, self.credential, self.url)

    def test_racing_creator_is_verified(self):
        self.session.request.side_effect = [response(404), response(409), response(200, "directory")]
        self.assertEqual(bootstrap.ensure_directory(self.session, self.credential, self.url), "exists")

    @patch.object(bootstrap.time, "sleep")
    def test_throttle_is_retried_without_exposing_credentials(self, sleep):
        throttled = response(429)
        throttled.headers["Retry-After"] = "2"
        self.session.request.side_effect = [throttled, response(200, "directory")]
        self.assertEqual(bootstrap.ensure_directory(self.session, self.credential, self.url), "exists")
        sleep.assert_called_once_with(2)

    def test_dry_run_never_authenticates(self):
        manifest = {"directory_bootstrap": {"value": {"DEV": {
            "workspace_id": "00000000-0000-4000-8000-000000000001",
            "lakehouse_id": "00000000-0000-4000-8000-000000000002",
            "directories": ["Files/bronze/permits/history"],
        }}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "outputs.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with patch.object(bootstrap, "credential_from_environment") as credential, contextlib.redirect_stdout(io.StringIO()) as output:
                bootstrap.main(["--outputs", str(path), "--dry-run"])
                credential.assert_not_called()
                self.assertIn("would ensure directory", output.getvalue())
            manifest["directory_bootstrap"]["value"]["DEV"]["directories"] = ["Files/bronze/../secure"]
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "outside"):
                bootstrap.load_manifest(path)
            with self.assertRaisesRegex(ValueError, "not found"):
                bootstrap.load_manifest(path, ["PROD"])

    @patch.dict(bootstrap.os.environ, {"FABRIC_CLIENT_ID": "incomplete"}, clear=True)
    def test_partial_credentials_do_not_fall_back_to_another_identity(self):
        with self.assertRaisesRegex(ValueError, "all three"):
            bootstrap.credential_from_environment()


if __name__ == "__main__":
    unittest.main()
