"""Run or validate the Terraform-managed Canadian geospatial notebook."""

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import urlparse
from uuid import UUID

import requests

from bootstrap_onelake import credential_from_environment


ROOT = Path(__file__).resolve().parents[1]
FABRIC = "https://api.fabric.microsoft.com/v1"
FABRIC_SCOPE = "https://api.fabric.microsoft.com/.default"


def terraform_outputs(directory):
    result = subprocess.run(
        ["terraform", f"-chdir={directory}", "output", "-json"],
        text=True, capture_output=True, check=True,
    )
    return {key: value["value"] for key, value in json.loads(result.stdout).items()}


def request(session, credential, method, url, scope=FABRIC_SCOPE, **kwargs):
    allowed = {"api.fabric.microsoft.com", "onelake.dfs.fabric.microsoft.com", "api.powerbi.com"}
    if urlparse(url).hostname not in allowed or urlparse(url).scheme != "https":
        raise ValueError("Unexpected API origin.")
    headers = {"Authorization": f"Bearer {credential.get_token(scope).token}"}
    response = session.request(method, url, headers=headers, timeout=90, allow_redirects=False, **kwargs)
    response.raise_for_status()
    return response


def list_values(session, credential, url):
    values = []
    while url:
        page = request(session, credential, "GET", url).json()
        values.extend(page["value"])
        url = page.get("continuationUri")
    return values


def run_notebook(outputs, session, credential, timeout, new_run=False):
    workspace_id = outputs["workspace"]["id"]
    notebook_id = outputs["notebook"]["id"]
    base = f"{FABRIC}/workspaces/{workspace_id}"
    workspace = request(session, credential, "GET", base).json()
    if not workspace.get("capacityId"):
        raise RuntimeError("The workspace has no capacity.")
    capacities = list_values(session, credential, f"{FABRIC}/capacities")
    if not any(c["id"] == workspace["capacityId"] and c["state"] == "Active" for c in capacities):
        raise RuntimeError("The assigned capacity is not active/visible; refusing to run.")
    jobs_url = f"{base}/items/{notebook_id}/jobs/instances"
    recent = []
    threshold = datetime.now(timezone.utc) - timedelta(minutes=5)
    for job in list_values(session, credential, jobs_url):
        started = job.get("startTimeUtc")
        start_time = datetime.fromisoformat(started.replace("Z", "+00:00")) if started else None
        if start_time and start_time.tzinfo is None:
            start_time = start_time.replace(tzinfo=timezone.utc)
        if job["status"] in ("NotStarted", "InProgress") or (not new_run and start_time and start_time >= threshold):
            recent.append(job)
    if recent:
        job = max(recent, key=lambda value: value.get("startTimeUtc") or "")
        job_url = f"{jobs_url}/{job['id']}"
        print(f"Reusing recent job {job['id']}", flush=True)
    else:
        # Capture Location before any other operation; never blindly resubmit a job.
        started = request(
            session, credential, "POST", f"{base}/items/{notebook_id}/jobs/RunNotebook/instances",
            json={"executionData": {"parameters": {"_inlineInstallationEnabled": {"type": "bool", "value": True}}}},
        )
        job_url = started.headers.get("Location")
        if not job_url or not job_url.startswith(jobs_url + "/"):
            raise RuntimeError("Job submitted without an expected Location; inspect job history before retrying.")
        print(f"Submitted job {job_url.rsplit('/', 1)[-1]}", flush=True)
        time.sleep(int(started.headers.get("Retry-After", "0")))
    deadline = time.monotonic() + timeout
    previous = None
    while time.monotonic() < deadline:
        job = request(session, credential, "GET", job_url).json()
        status = job["status"]
        if status != previous:
            print(f"Notebook: {status}", flush=True)
            previous = status
        if status == "Completed":
            return
        if status in ("Failed", "Cancelled", "Deduped"):
            raise RuntimeError("Notebook did not complete: " + json.dumps(job.get("failureReason", job)))
        time.sleep(15)
    raise TimeoutError(f"Notebook still running; monitor existing job instead of resubmitting: {job_url}")


def verify_data(outputs, session, credential):
    workspace_id, lakehouse_id = outputs["workspace"]["id"], outputs["lakehouse"]["id"]
    url = f"https://onelake.dfs.fabric.microsoft.com/{workspace_id}/{lakehouse_id}/Files/geo/validation.json"
    quality = request(session, credential, "GET", url, scope="https://storage.azure.com/.default").json()
    if quality["gold_parks"] <= 0 or quality["gold_parks"] + len(quality["rejected"]) != quality["source_parks"]:
        raise RuntimeError("Gold/source row-count reconciliation failed.")
    if quality["source_local_areas"] <= 0:
        raise RuntimeError("No planning-area polygons.")
    print(json.dumps(quality, indent=2))


def refresh_model(outputs, session, credential, timeout):
    if not outputs.get("model"):
        raise RuntimeError("Enable publish_analytics and apply the reviewed analytics plan first.")
    scope = "https://analysis.windows.net/powerbi/api/.default"
    url = f"https://api.powerbi.com/v1.0/myorg/groups/{outputs['workspace']['id']}/datasets/{outputs['model']['id']}/refreshes"
    history = request(session, credential, "GET", url + "?$top=10", scope=scope).json()["value"]
    pending = [refresh for refresh in history if refresh["status"] == "Unknown"]
    if pending:
        refresh_id = pending[0]["requestId"]
    else:
        previous_ids = {refresh["requestId"] for refresh in history}
        started = request(session, credential, "POST", url, scope=scope, json={"notifyOption": "NoNotification"})
        location = started.headers.get("Location")
        refresh_id = location.rsplit("/", 1)[-1] if location else started.headers.get("x-ms-request-id")
        if not refresh_id:
            # Standard refresh can return no correlation headers; discover it, never POST again.
            for attempt in range(6):
                history = request(session, credential, "GET", url + "?$top=10", scope=scope).json()["value"]
                created = [r for r in history if r["requestId"] not in previous_ids and r.get("refreshType") == "ViaApi"]
                if len(created) == 1:
                    refresh_id = created[0]["requestId"]
                    break
                if len(created) > 1:
                    break
                time.sleep(5)
            if not refresh_id:
                raise RuntimeError("Refresh submitted but not uniquely identified; inspect history before retrying.")
    print(f"Monitoring model refresh {refresh_id}", flush=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        history = request(session, credential, "GET", url + "?$top=10", scope=scope).json()["value"]
        refresh = next((r for r in history if r["requestId"] == refresh_id), None)
        if refresh and refresh["status"] == "Completed":
            print("Semantic model refresh: Completed", flush=True)
            return
        if refresh and refresh["status"] in ("Failed", "Cancelled", "Disabled"):
            raise RuntimeError("Semantic model refresh failed: " + json.dumps(refresh))
        time.sleep(10)
    raise TimeoutError("Refresh still pending; monitor history instead of resubmitting.")


def sync_sql(outputs, session, credential, timeout):
    endpoint = outputs["lakehouse"]["sql_endpoint"]["id"]
    url = f"{FABRIC}/workspaces/{outputs['workspace']['id']}/sqlEndpoints/{endpoint}/refreshMetadata"
    response = request(session, credential, "POST", url, json={"recreateTables": False})
    if response.status_code == 202:
        operation = response.headers.get("x-ms-operation-id") or urlparse(response.headers["Location"]).path.rsplit("/", 1)[-1]
        operation_url = f"{FABRIC}/operations/{UUID(operation)}"
        print(f"Monitoring SQL metadata sync {operation}", flush=True)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            time.sleep(int(response.headers.get("Retry-After", "10")))
            response = request(session, credential, "GET", operation_url)
            status = response.json()["status"]
            if status == "Succeeded":
                response = request(session, credential, "GET", operation_url + "/result")
                break
            if status == "Failed":
                raise RuntimeError("SQL metadata sync failed: " + json.dumps(response.json()))
        else:
            raise TimeoutError(f"SQL sync pending; monitor {operation_url}, do not resubmit.")
    tables = response.json()["value"]
    if not tables or any(table["status"] != "Success" for table in tables):
        raise RuntimeError("SQL table sync incomplete: " + json.dumps(tables))
    print(json.dumps({"sql_tables": tables}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["run-notebook", "verify-data", "sync-sql", "refresh-model"])
    parser.add_argument("--terraform-dir", type=Path, default=ROOT / "infra" / "geospatial")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--dry-run", action="store_true", help="Describe the action without authentication or API calls.")
    parser.add_argument("--new-run", action="store_true", help="Rerun updated code despite recent terminal jobs; active jobs are always reused.")
    args = parser.parse_args()
    outputs = terraform_outputs(args.terraform_dir.resolve())
    if args.dry_run:
        print(f"Would execute {args.action} for workspace {outputs['workspace']['id']}; no API calls made.")
        return
    with credential_from_environment() as credential, requests.Session() as session:
        if args.action == "run-notebook":
            run_notebook(outputs, session, credential, args.timeout, args.new_run)
        elif args.action == "refresh-model":
            refresh_model(outputs, session, credential, args.timeout)
        elif args.action == "sync-sql":
            sync_sql(outputs, session, credential, args.timeout)
        else:
            verify_data(outputs, session, credential)


if __name__ == "__main__":
    main()
