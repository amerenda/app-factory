#!/usr/bin/env python3
"""Validate an app-factory TOML spec.

Usage:
    python3 validate.py apps/myapp.toml
"""
import re
import sys
import tomllib

KEBAB_RE = re.compile(r"^[a-z][a-z0-9-]{2,29}$")
DOMAIN_SUFFIX = ".amer.dev"


def validate(spec: dict) -> list[str]:
    errors = []

    # --- [app] ---
    app = spec.get("app")
    if not app:
        return ["Missing [app] section"]

    name = app.get("name", "")
    if not KEBAB_RE.match(name):
        errors.append(f"app.name '{name}' must be kebab-case, 3-30 chars")

    domain = app.get("domain", "")
    if not domain.endswith(DOMAIN_SUFFIX):
        errors.append(f"app.domain '{domain}' must end with {DOMAIN_SUFFIX}")

    namespace = app.get("namespace", name)
    if namespace != name:
        errors.append(f"app.namespace '{namespace}' should match app.name '{name}'")

    # --- [[components]] ---
    components = spec.get("components", [])
    if not components:
        errors.append("At least one [[components]] entry is required")

    comp_names = set()
    for i, comp in enumerate(components):
        cn = comp.get("name", "")
        if not cn:
            errors.append(f"components[{i}].name is required")
        elif cn in comp_names:
            errors.append(f"Duplicate component name: {cn}")
        comp_names.add(cn)

        image = comp.get("image", "")
        if not image.startswith("amerenda/"):
            errors.append(f"components[{i}].image must start with 'amerenda/'")

        port = comp.get("port", 0)
        if not (1 <= port <= 65535):
            errors.append(f"components[{i}].port {port} out of range")

        if not comp.get("health_path"):
            errors.append(f"components[{i}].health_path is required")

        if not comp.get("resources"):
            errors.append(f"components[{i}].resources is required")

        # Check secret_ref entries reference defined secrets
        for e in comp.get("env", []):
            ref = e.get("secret_ref")
            if ref:
                k8s_secret = ref.get("name")
                k8s_key = ref.get("key")
                found = any(
                    s["k8s_secret"] == k8s_secret and s["k8s_key"] == k8s_key
                    for s in spec.get("secrets", [])
                )
                if not found:
                    errors.append(
                        f"components[{i}].env '{e['name']}' references "
                        f"secret '{k8s_secret}.{k8s_key}' which is not defined in [[secrets]]"
                    )

    # --- [[secrets]] ---
    bws_names = set()
    for i, s in enumerate(spec.get("secrets", [])):
        bws = s.get("bws_name", "")
        if not bws:
            errors.append(f"secrets[{i}].bws_name is required")
        elif bws in bws_names:
            errors.append(f"Duplicate bws_name: {bws}")
        elif not bws.startswith(f"{name}-"):
            errors.append(f"secrets[{i}].bws_name '{bws}' should start with '{name}-'")
        bws_names.add(bws)

        if not s.get("k8s_secret"):
            errors.append(f"secrets[{i}].k8s_secret is required")
        if not s.get("k8s_key"):
            errors.append(f"secrets[{i}].k8s_key is required")

    # --- [database] ---
    db = spec.get("database")
    if db:
        if db.get("type") not in ("postgres",):
            errors.append(f"database.type '{db.get('type')}' not supported (use 'postgres')")
        if db.get("name") != name:
            errors.append(f"database.name '{db.get('name')}' should match app.name '{name}'")
        pw_secret = db.get("password_secret", "")
        if pw_secret and pw_secret not in bws_names:
            errors.append(
                f"database.password_secret '{pw_secret}' not found in [[secrets]]"
            )

    # --- [uat] ---
    uat = spec.get("uat", {})
    if uat.get("enabled"):
        if not uat.get("replicas"):
            errors.append("uat.replicas is required when uat.enabled = true")
        if not uat.get("resources"):
            errors.append("uat.resources is required when uat.enabled = true")

    # --- [cicd] ---
    cicd = spec.get("cicd", {})
    if cicd:
        repo = cicd.get("repo", "")
        if repo and not repo.startswith("amerenda/"):
            errors.append(f"cicd.repo '{repo}' should start with 'amerenda/'")
        label = cicd.get("label", "")
        if label and not label.startswith("deploy:"):
            errors.append(f"cicd.label '{label}' should start with 'deploy:'")

    return errors


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <spec.toml>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        spec = tomllib.load(f)

    errors = validate(spec)
    if errors:
        print("VALIDATION FAILED:")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print("VALID")


if __name__ == "__main__":
    main()
