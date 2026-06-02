#!/usr/bin/env python3
import json
import sys
import subprocess
import os

environment = sys.argv[1]
image_tag   = sys.argv[2]
git_sha     = sys.argv[3]
deployed_by = sys.argv[4]
region      = sys.argv[5]
bucket      = "gitflow-analyzer-tfstate-153772056450"
key         = f"deployments/{environment}/history.json"

timestamp = subprocess.check_output(
    ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"]
).decode().strip()

try:
    result = subprocess.check_output(
        ["aws", "s3", "cp", f"s3://{bucket}/{key}", "-",
         "--region", region],
        stderr=subprocess.DEVNULL
    )
    existing = json.loads(result.decode())
except Exception:
    existing = []

new_entry = {
    "timestamp":   timestamp,
    "environment": environment,
    "image_tag":   image_tag,
    "git_sha":     git_sha,
    "deployed_by": deployed_by
}

history = [new_entry] + existing
history = history[:20]

updated = json.dumps(history, indent=2)

proc = subprocess.Popen(
    ["aws", "s3", "cp", "-", f"s3://{bucket}/{key}",
     "--content-type", "application/json",
     "--region", region],
    stdin=subprocess.PIPE
)
proc.communicate(input=updated.encode())

print(f"Recorded deployment: {environment} / {image_tag} / {timestamp}")
