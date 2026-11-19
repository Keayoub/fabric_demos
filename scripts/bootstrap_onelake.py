"""Idempotently create OneLake directories absent from the Fabric provider.

Uses the OneLake ADLS-compatible REST API, not an invented Fabric item resource.
Dry-run validates the Terraform output manifest without authenticating or writing.
"""

import argparse
import json
import os
from pathlib import Path
import re
import time
from uuid import UUID


ONELAKE = "https://onelake.dfs.fabric.microsoft.com"
STORAGE_SCOPE = "https://storage.azure.com/.default"


def load_manifest(path, environments=None):
    outputs = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    manifest = outputs["directory_bootstrap"]["value"]
    if not isinstance(manifest, dict) or not manifest:
        raise ValueError("directory_bootstrap must contain environment entries.")
    selected = set(environments or manifest)
    if selected - manifest.keys():
        raise ValueError("An environment was not found in the Terraform outputs.")
    directories = []
    for environment in sorted(selected):
        entry = manifest[environment]
        workspace = str(UUID(entry["workspace_id"]))
        lakehouse = str(UUID(entry["lakehouse_id"]))
        for directory in entry["directories"]:
            # Only the general permitting Bronze subtree is eligible for bootstrap.
            if not re.fullmatch(r"Files/bronze(?:/permits(?:/(?:history|api))?)?", directory):
                raise ValueError("Directory outside the permitted bootstrap subtree.")
            directories.append((environment, f"{ONELAKE}/{workspace}/{lakehouse}/{directory}"))
    return directories


def credential_from_environment():
    from azure.identity import AzureCliCredential, ClientSecretCredential

    fabric = [os.getenv(f"FABRIC_{key}") for key in ("TENANT_ID", "CLIENT_ID", "CLIENT_SECRET")]
    azure = [os.getenv(f"AZURE_{key}") for key in ("TENANT_ID", "CLIENT_ID", "CLIENT_SECRET")]
    if any(fabric) or any(azure):
        values = fabric if any(fabric) else azure
        if not all(values):
            raise ValueError("Supply all three credential environment variables, or clear them for Azure CLI.")
        return ClientSecretCredential(*values)
    return AzureCliCredential()


def storage_request(session, credential, method, url):
    for attempt in range(5):
        response = session.request(
            method,
            url,
            headers={
                "Authorization": f"Bearer {credential.get_token(STORAGE_SCOPE).token}",
                "x-ms-version": "2023-11-03",
            },
            timeout=60,
            allow_redirects=False,
        )
        if response.status_code not in (429, 500, 502, 503, 504) or attempt == 4:
            return response
        try:
            delay = min(60, max(1, int(response.headers.get("Retry-After", 2**attempt))))
        except ValueError:
            delay = 2**attempt
        response.close()
        time.sleep(delay)
    raise RuntimeError("Unreachable retry state.")


def ensure_directory(session, credential, url):
    response = storage_request(session, credential, "HEAD", url)
    if response.status_code == 200:
        if response.headers.get("x-ms-resource-type") != "directory":
            raise RuntimeError("A file exists where a directory is required.")
        return "exists"
    if response.status_code != 404:
        raise RuntimeError(f"Directory lookup failed (HTTP {response.status_code}).")
    response = storage_request(session, credential, "PUT", f"{url}?resource=directory")
    if response.status_code == 409:
        # A concurrent creator is safe only when the path is now a directory.
        check = storage_request(session, credential, "HEAD", url)
        if check.status_code == 200 and check.headers.get("x-ms-resource-type") == "directory":
            return "exists"
    if response.status_code != 201:
        raise RuntimeError(f"Directory creation failed (HTTP {response.status_code}).")
    return "created"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outputs", required=True, help="File produced by terraform output -json.")
    parser.add_argument("--environment", action="append", help="Repeat to limit environments; default is all.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print intent without auth/network/writes.")
    args = parser.parse_args(argv)
    directories = load_manifest(args.outputs, args.environment)
    if args.dry_run:
        for environment, url in directories:
            print(f"[{environment}] would ensure directory {url}")
        return
    import requests

    with credential_from_environment() as credential, requests.Session() as session:
        for environment, url in directories:
            print(f"[{environment}] {ensure_directory(session, credential, url)} {url}")


if __name__ == "__main__":
    main()
