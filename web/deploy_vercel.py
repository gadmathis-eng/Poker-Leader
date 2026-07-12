#!/usr/bin/env python3
"""Deploy the web/ folder to Vercel using VERCEL_TOKEN."""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.vercel.com"
ROOT = Path(__file__).resolve().parent
PROJECT_NAME = "potmaster-web"
DOMAIN = "potmaster.app"
WWW_DOMAIN = "www.potmaster.app"
SKIP_NAMES = {".DS_Store", ".env.vercel"}


def load_local_env():
    env_file = ROOT / ".env.vercel"
    if not env_file.exists():
        return

    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def request(method, path, body=None, params=None):
    token = os.environ.get("VERCEL_TOKEN")
    if not token:
        print("VERCEL_TOKEN is not set. Create one at https://vercel.com/account/tokens")
        sys.exit(1)

    url = f"{API}{path}"
    if params:
        query = "&".join(f"{key}={value}" for key, value in params.items())
        url = f"{url}?{query}"

    data = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read().decode()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        raise RuntimeError(f"Vercel API error {error.code} on {method} {path}: {detail}") from error


def collect_files():
    files = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.name in SKIP_NAMES:
            continue
        relative = path.relative_to(ROOT).as_posix()
        files.append(
            {
                "file": relative,
                "data": path.read_text(encoding="utf-8"),
            }
        )
    return files


def deploy():
    files = collect_files()
    print(f"Uploading {len(files)} files from {ROOT}")

    deployment = request(
        "POST",
        "/v13/deployments",
        {
            "name": PROJECT_NAME,
            "files": files,
            "projectSettings": {
                "framework": None,
            },
            "target": "production",
        },
    )

    url = deployment.get("url")
    alias = deployment.get("alias", [])
    project_id = deployment.get("projectId")
    print(f"Deployed: https://{url}")
    if alias:
        print(f"Aliases: {', '.join(alias)}")

    return project_id


def ensure_domain(project_id, domain):
    if not project_id:
        return

    try:
        request(
            "POST",
            f"/v10/projects/{project_id}/domains",
            {"name": domain},
        )
        print(f"Added domain: {domain}")
    except RuntimeError as error:
        print(f"Domain {domain}: {error}")


def main():
    load_local_env()
    try:
        project_id = deploy()
    except RuntimeError as error:
        print(error)
        sys.exit(1)
    ensure_domain(project_id, DOMAIN)
    ensure_domain(project_id, WWW_DOMAIN)
    print()
    print("Next step at your domain registrar for potmaster.app:")
    print("  A     @    -> 76.76.21.21")
    print("  CNAME www  -> cname.vercel-dns.com")
    print()
    print("App Store URLs after DNS propagates:")
    print(f"  Privacy: https://{DOMAIN}/privacy/")
    print(f"  Support: https://{DOMAIN}/support/")


if __name__ == "__main__":
    main()
