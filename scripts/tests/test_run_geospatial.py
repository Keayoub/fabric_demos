from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import run_geospatial as runner


OUTPUTS = {"workspace": {"id": "workspace"}, "notebook": {"id": "notebook"}, "model": {"id": "model"}}


class RunnerTests(unittest.TestCase):
    def test_existing_job_is_reused_with_naive_utc_or_older_active_timestamp(self):
        for started in (datetime.now(timezone.utc).isoformat().replace("+00:00", ""), "2000-01-01T00:00:00"):
            with self.subTest(started=started), patch.object(runner, "request") as request, patch.object(runner, "list_values") as values:
                request.side_effect = [
                    Mock(**{"json.return_value": {"capacityId": "capacity"}}),
                    Mock(**{"json.return_value": {"status": "Completed"}}),
                ]
                values.side_effect = [
                    [{"id": "capacity", "state": "Active"}],
                    [{"id": "existing-job", "status": "InProgress", "startTimeUtc": started}],
                ]
                runner.run_notebook(OUTPUTS, Mock(), Mock(), 60, new_run=True)
                self.assertEqual([call.args[2] for call in request.call_args_list], ["GET", "GET"])
                self.assertTrue(request.call_args.args[3].endswith("/existing-job"))

    def test_explicit_new_run_skips_only_terminal_jobs(self):
        with patch.object(runner, "request") as request, patch.object(runner, "list_values") as values:
            request.side_effect = [
                Mock(**{"json.return_value": {"capacityId": "capacity"}}),
                Mock(headers={"Location": runner.FABRIC + "/workspaces/workspace/items/notebook/jobs/instances/new-job"}),
                Mock(**{"json.return_value": {"status": "Completed"}}),
            ]
            values.side_effect = [
                [{"id": "capacity", "state": "Active"}],
                [{"id": "completed", "status": "Completed", "startTimeUtc": datetime.now(timezone.utc).isoformat()}],
            ]
            runner.run_notebook(OUTPUTS, Mock(), Mock(), 60, new_run=True)
            self.assertEqual([call.args[2] for call in request.call_args_list], ["GET", "POST", "GET"])
            parameters = request.call_args_list[1].kwargs["json"]["executionData"]["parameters"]
            self.assertEqual(parameters, {"_inlineInstallationEnabled": {"type": "bool", "value": True}})

    def test_refresh_reuses_in_progress_request_and_surfaces_failure(self):
        with patch.object(runner, "request") as request:
            request.side_effect = [
                Mock(**{"json.return_value": {"value": [{"requestId": "existing", "status": "Unknown"}]}}),
                Mock(**{"json.return_value": {"value": [{"requestId": "existing", "status": "Failed"}]}}),
            ]
            with self.assertRaisesRegex(RuntimeError, "refresh failed"):
                runner.refresh_model(OUTPUTS, Mock(), Mock(), 60)
            self.assertTrue(all(call.args[2] == "GET" for call in request.call_args_list))

    def test_refresh_accepts_request_id_without_location(self):
        with patch.object(runner, "request") as request:
            request.side_effect = [
                Mock(**{"json.return_value": {"value": []}}),
                Mock(headers={"x-ms-request-id": "refresh"}),
                Mock(**{"json.return_value": {"value": [{"requestId": "refresh", "status": "Completed"}]}}),
            ]
            runner.refresh_model(OUTPUTS, Mock(), Mock(), 60)
            self.assertEqual([call.args[2] for call in request.call_args_list], ["GET", "POST", "GET"])

    def test_headerless_refresh_is_discovered_without_resubmitting(self):
        complete = {"requestId": "refresh", "status": "Completed", "refreshType": "ViaApi"}
        with patch.object(runner, "request") as request:
            request.side_effect = [
                Mock(**{"json.return_value": {"value": []}}),
                Mock(headers={}),
                Mock(**{"json.return_value": {"value": [complete]}}),
                Mock(**{"json.return_value": {"value": [complete]}}),
            ]
            runner.refresh_model(OUTPUTS, Mock(), Mock(), 60)
            self.assertEqual(sum(call.args[2] == "POST" for call in request.call_args_list), 1)

    def test_dry_run_does_not_authenticate(self):
        with patch.object(sys, "argv", ["run_geospatial.py", "run-notebook", "--dry-run"]), \
             patch.object(runner, "terraform_outputs", return_value=OUTPUTS), \
             patch.object(runner, "credential_from_environment") as credential:
            runner.main()
            credential.assert_not_called()


if __name__ == "__main__":
    unittest.main()
