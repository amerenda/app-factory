#!/usr/bin/env python3
"""Generate k8s manifests from an app-factory TOML spec.

Usage:
    python3 generate.py apps/myapp.toml /path/to/k3s-dean-gitops
"""
import os
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

TEMPLATE_DIR = Path(__file__).parent / "templates"


def load_spec(path: str) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def build_secret_groups(secrets: list, component_env: list) -> dict:
    """Group secrets by k8s_secret name for ExternalSecret resources.
    Only include secrets that are actually referenced by this component's env."""
    referenced = set()
    for e in component_env:
        ref = e.get("secret_ref")
        if ref:
            referenced.add(ref["name"])

    grouped = defaultdict(list)
    for s in secrets:
        if s["k8s_secret"] in referenced:
            grouped[s["k8s_secret"]].append(s)
    return dict(grouped)


def write_file(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    print(f"  wrote {path}")


def generate(spec: dict, gitops_dir: Path):
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATE_DIR)),
        keep_trailing_newline=True,
        trim_blocks=False,
        lstrip_blocks=False,
    )

    app = spec["app"]
    app_name = app["name"]
    namespace = app.get("namespace", app_name)
    domain = app["domain"]
    secrets = spec.get("secrets", [])
    uat = spec.get("uat", {})
    cicd = spec.get("cicd", {})
    components = spec.get("components", [])

    apps_dir = gitops_dir / "apps" / app_name

    for component in components:
        comp_name = component["name"]
        comp_env = component.get("env", [])

        # --- Prod manifests ---
        prod_dir = apps_dir / comp_name

        # Deployment
        tmpl = env.get_template("deployment.yaml.j2")
        content = tmpl.render(
            app_name=app_name,
            namespace=namespace,
            component=component,
        )
        write_file(prod_dir / "deployment.yaml", content)

        # Service
        tmpl = env.get_template("service.yaml.j2")
        content = tmpl.render(
            service_name=f"{app_name}-{comp_name}",
            namespace=namespace,
            selector=f"{app_name}-{comp_name}",
            port=component["port"],
        )
        write_file(prod_dir / "service.yaml", content)

        # ExternalSecrets (only if component references secrets)
        grouped = build_secret_groups(secrets, comp_env)
        if grouped:
            tmpl = env.get_template("externalsecret.yaml.j2")
            content = tmpl.render(
                namespace=namespace,
                grouped_secrets=grouped,
            )
            write_file(prod_dir / "externalsecret.yaml", content)

        # Ingress (only for the component marked with ingress=true)
        if component.get("ingress"):
            tmpl = env.get_template("ingress.yaml.j2")
            content = tmpl.render(
                app_name=app_name,
                namespace=namespace,
                domain=domain,
                service_name=f"{app_name}-{comp_name}",
                port=component["port"],
            )
            write_file(prod_dir / "ingress.yaml", content)

        # --- UAT manifests ---
        if uat.get("enabled", False):
            uat_dir = apps_dir / f"{comp_name}-uat"

            tmpl = env.get_template("deployment-uat.yaml.j2")
            content = tmpl.render(
                app_name=app_name,
                namespace=namespace,
                component=component,
                uat=uat,
            )
            write_file(uat_dir / "deployment.yaml", content)

            tmpl = env.get_template("service.yaml.j2")
            content = tmpl.render(
                service_name=f"{app_name}-{comp_name}-uat",
                namespace=namespace,
                selector=f"{app_name}-{comp_name}-uat",
                port=component["port"],
            )
            write_file(uat_dir / "service.yaml", content)

    # --- ARC runner ---
    if cicd.get("repo"):
        runner_dir = gitops_dir / "infra" / f"arc-runners-{app_name}"
        tmpl = env.get_template("arc-runner-values.yaml.j2")
        content = tmpl.render(
            app_name=app_name,
            cicd_repo=cicd["repo"],
        )
        write_file(runner_dir / "values.yaml", content)

    # --- ArgoCD entries (append to root-app.yaml) ---
    root_app = gitops_dir / "root-app.yaml"
    argocd_tmpl = env.get_template("argocd-app.yaml.j2")

    new_entries = []
    for component in components:
        entry = argocd_tmpl.render(
            app_name=app_name,
            component_name=component["name"],
            namespace=namespace,
        )
        new_entries.append(entry)

    # ARC runner ArgoCD app
    if cicd.get("repo"):
        arc_tmpl = env.get_template("arc-runner-app.yaml.j2")
        entry = arc_tmpl.render(app_name=app_name)
        new_entries.append(entry)

    # Check if entries already exist before appending
    existing = root_app.read_text() if root_app.exists() else ""
    appended = []
    for entry in new_entries:
        # Extract the app name from the entry to check for duplicates
        for line in entry.splitlines():
            if "name: app-" in line or "name: infra-arc-runners-" in line:
                marker = line.strip()
                if marker in existing:
                    print(f"  skipped (already exists): {marker}")
                    break
        else:
            appended.append(entry)

    if appended:
        with open(root_app, "a") as f:
            for entry in appended:
                f.write("\n" + entry)
        print(f"  appended {len(appended)} entries to root-app.yaml")

    # --- UAT ApplicationSet entry ---
    if uat.get("enabled", False) and cicd.get("label"):
        appset_path = gitops_dir / "infra" / "argocd-config" / "uat-applicationset.yaml"
        appset_tmpl = env.get_template("uat-appset-entry.yaml.j2")
        entry = appset_tmpl.render(
            app_name=app_name,
            namespace=namespace,
            label=cicd["label"],
            components=components,
        )

        existing_appset = appset_path.read_text() if appset_path.exists() else ""
        if f"# --- {app_name} ---" in existing_appset:
            print(f"  skipped UAT ApplicationSet (already exists for {app_name})")
        else:
            # Insert before the template: section
            marker = "\n  template:"
            if marker in existing_appset:
                updated = existing_appset.replace(
                    marker,
                    "\n" + entry + marker,
                    1,
                )
                with open(appset_path, "w") as f:
                    f.write(updated)
                print(f"  inserted UAT ApplicationSet entry for {app_name}")
            else:
                print(f"  WARNING: could not find template: marker in {appset_path}")

    print(f"\nDone. Generated manifests for {app_name}.")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <spec.toml> <gitops-dir>")
        sys.exit(1)

    spec_path = sys.argv[1]
    gitops_dir = Path(sys.argv[2])

    if not os.path.exists(spec_path):
        print(f"Error: spec file not found: {spec_path}")
        sys.exit(1)

    if not gitops_dir.is_dir():
        print(f"Error: gitops dir not found: {gitops_dir}")
        sys.exit(1)

    spec = load_spec(spec_path)
    generate(spec, gitops_dir)


if __name__ == "__main__":
    main()
