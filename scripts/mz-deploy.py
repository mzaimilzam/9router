#!/usr/bin/env python3
"""Arahkan app Coolify ke tag image 9Router lalu deploy + tunggu versi live cocok.

Pakai:  python3 scripts/mz-deploy.py 0.5.119-mz.1
Butuh:  /opt/data/.secrets/coolify.env (COOLIFY_URL, COOLIFY_TOKEN, COOLIFY_UUID)
        /opt/data/.secrets/router9.env (ROUTER_URL)
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

env = {}
for path in ("/opt/data/.secrets/coolify.env", "/opt/data/.secrets/router9.env"):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip("'\""))

base = env["COOLIFY_URL"].rstrip("/")
uuid = env["COOLIFY_UUID"]
rurl = env["ROUTER_URL"].rstrip("/")
target = sys.argv[1] if len(sys.argv) > 1 else sys.exit("pakai: mz-deploy.py <tag-image>")


def req(url, method="GET", payload=None, headers=None, timeout=120):
    data = json.dumps(payload).encode() if payload is not None else None
    h = {"Accept": "application/json"}
    h.update(headers or {})
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    with urllib.request.urlopen(r, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8", "replace") or "{}")


auth = {"Authorization": f"Bearer {env['COOLIFY_TOKEN']}", "Content-Type": "application/json"}
st, _ = req(f"{base}/api/v1/applications/{uuid}", "PATCH",
            {"docker_registry_image_tag": target}, auth)
print(f"[1] PATCH tag -> {target}: HTTP {st}")
st, body = req(f"{base}/api/v1/deploy?uuid={uuid}&force=true", "POST", None, auth)
dep = (body.get("deployments") or [{}])[0].get("deployment_uuid", "?")
print(f"[2] deploy queued: HTTP {st} ({dep})")

for i in range(18):
    time.sleep(20)
    try:
        _, ver = req(rurl + "/api/version", timeout=20)
        cur = ver.get("currentVersion")
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        cur = f"err:{exc}"
    print(f"    [{i}] live={cur}")
    if cur == target:
        print(f">>> ROLLOUT {target} LIVE")
        break
else:
    sys.exit("rollout tidak terdeteksi — cek log deployment di Coolify")
