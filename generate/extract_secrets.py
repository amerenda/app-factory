#!/usr/bin/env python3
"""Print a JSON array of {bws_name, generate} dicts from a TOML app spec.
Used by Makefile to pass secrets to tofu without inline tab issues."""
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    spec = tomllib.load(f)

secrets = [
    {"bws_name": s["bws_name"], "generate": s["generate"]}
    for s in spec.get("secrets", [])
    if not s.get("shared", False)
]
print(json.dumps(secrets))
