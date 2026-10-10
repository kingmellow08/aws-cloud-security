#!/usr/bin/env python3
"""Static checks for Terraform state ownership boundaries.

Verifies, from the source tree alone (no AWS access, no terraform init):

  * every root module has its own backend.tf, bootstrap uses local state and
    every other root uses S3 with a unique key and use_lockfile = true;
  * no credentials appear in backend configuration;
  * account-level security resource types are reachable only from
    account-baseline, and per-account singletons are declared exactly once;
  * environments reuse the same modules and code without sharing state
    (no terraform_remote_state, no cross-root module sources);
  * bootstrap's state scopes match the backend keys;
  * docs/terraform-state-ownership.md and README.md quote the real keys.

Usage: python3 scripts/validate-ownership.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
KEY_PREFIX = "aws-cloud-security"

ROOTS = {
    "bootstrap": PROJECT / "bootstrap",
    "account-baseline": PROJECT / "account-baseline",
    "dev": PROJECT / "environments" / "dev",
    "staging": PROJECT / "environments" / "staging",
    "prod": PROJECT / "environments" / "prod",
}
ENVIRONMENTS = ("dev", "staging", "prod")
SHARED_ENV_FILES = ("main.tf", "variables.tf", "outputs.tf", "providers.tf", "versions.tf", "tests/ownership.tftest.hcl")

# Resource types that configure the account (or account+Region) as a whole.
ACCOUNT_LEVEL_TYPES = {
    "aws_guardduty_detector",
    "aws_guardduty_detector_feature",
    "aws_securityhub_account",
    "aws_securityhub_standards_subscription",
    "aws_securityhub_finding_aggregator",
    "aws_config_configuration_recorder",
    "aws_config_configuration_recorder_status",
    "aws_config_delivery_channel",
    "aws_config_config_rule",
    "aws_cloudtrail",
    "aws_s3_account_public_access_block",
    "aws_ebs_encryption_by_default",
    "aws_accessanalyzer_analyzer",
    "aws_sns_topic",
    "aws_cloudwatch_event_rule",
    "aws_cloudwatch_event_target",
}

# AWS allows only one of these per account (per Region). Two declarations in
# different states would fight over the same physical object.
SINGLETON_TYPES = {
    "aws_guardduty_detector",
    "aws_securityhub_account",
    "aws_securityhub_finding_aggregator",
    "aws_config_configuration_recorder",
    "aws_config_delivery_channel",
    "aws_s3_account_public_access_block",
    "aws_ebs_encryption_by_default",
}

FORBIDDEN_BACKEND_ATTRS = {
    "access_key",
    "secret_key",
    "token",
    "profile",
    "shared_credentials_file",
    "shared_credentials_files",
    "shared_config_files",
}

failures: list[str] = []


def check(ok: bool, message: str) -> None:
    print(f"  [{'PASS' if ok else 'FAIL'}] {message}")
    if not ok:
        failures.append(message)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"(^|\s)(#|//).*$", "", line) for line in text.splitlines())


def tf_text(directory: Path) -> str:
    return "\n".join(strip_comments(p.read_text()) for p in sorted(directory.glob("*.tf")))


def module_sources(directory: Path) -> list[Path]:
    sources = re.findall(r'^\s*source\s*=\s*"(\.{1,2}/[^"]+)"', tf_text(directory), flags=re.M)
    return [(directory / s).resolve() for s in sources]


def reachable_resources(directory: Path, seen: set[Path] | None = None) -> list[tuple[str, str, Path]]:
    """All (type, name, declaring dir) reachable from a root via local modules."""
    seen = seen if seen is not None else set()
    if directory in seen:
        return []
    seen.add(directory)
    found = [(t, n, directory) for t, n in re.findall(r'^\s*resource\s+"([^"]+)"\s+"([^"]+)"', tf_text(directory), flags=re.M)]
    for child in module_sources(directory):
        found += reachable_resources(child, seen)
    return found


def backend_block(directory: Path) -> tuple[str | None, dict[str, str]]:
    text = strip_comments((directory / "backend.tf").read_text())
    match = re.search(r'backend\s+"([^"]+)"\s*\{(.*?)\n\s*\}', text, flags=re.S)
    if not match:
        return None, {}
    attrs = dict(re.findall(r'^\s*([a-z_]+)\s*=\s*(.+?)\s*$', match.group(2), flags=re.M))
    return match.group(1), {k: v.strip('"') for k, v in attrs.items()}


def tfvar(directory: Path, name: str) -> str | None:
    match = re.search(rf'^\s*{name}\s*=\s*"([^"]*)"', (directory / "terraform.tfvars").read_text(), flags=re.M)
    return match.group(1) if match else None


def main() -> int:
    print("1. Backend configuration")
    keys: dict[str, str] = {}
    for scope, directory in ROOTS.items():
        backend_tf = directory / "backend.tf"
        check(backend_tf.is_file(), f"{scope}: has its own backend.tf")
        if not backend_tf.is_file():
            continue
        kind, attrs = backend_block(directory)
        forbidden = FORBIDDEN_BACKEND_ATTRS & attrs.keys()
        check(not forbidden, f"{scope}: no credentials in backend.tf {sorted(forbidden) or ''}".rstrip())
        others = [p.name for p in directory.glob("*.tf") if p.name != "backend.tf" and re.search(r'\bbackend\s+"', strip_comments(p.read_text()))]
        check(not others, f"{scope}: backend declared only in backend.tf {others or ''}".rstrip())
        if scope == "bootstrap":
            check(kind == "local", "bootstrap: uses local state (it creates the S3 backend)")
            continue
        check(kind == "s3", f"{scope}: uses the S3 backend")
        expected = f"{KEY_PREFIX}/{scope}/terraform.tfstate"
        check(attrs.get("key") == expected, f"{scope}: key = {expected}")
        check(attrs.get("use_lockfile") == "true", f"{scope}: use_lockfile = true")
        check(attrs.get("encrypt") == "true", f"{scope}: encrypt = true")
        keys[scope] = attrs.get("key", "")
    check(len(set(keys.values())) == len(keys), "every remote-state root has a unique key")

    for tfbackend in sorted((PROJECT / "backend-config").glob("*.tfbackend")):
        attrs = set(re.findall(r'^\s*([a-z_]+)\s*=', strip_comments(tfbackend.read_text()), flags=re.M))
        check(not (FORBIDDEN_BACKEND_ATTRS & attrs), f"{tfbackend.name}: no credentials")

    print("2. Account-level resource ownership")
    reachable = {scope: reachable_resources(directory.resolve()) for scope, directory in ROOTS.items()}
    for scope, resources in reachable.items():
        if scope == "account-baseline":
            continue
        leaked = sorted({f"{t} ({d.relative_to(PROJECT)})" for t, _, d in resources if t in ACCOUNT_LEVEL_TYPES})
        check(not leaked, f"{scope}: declares no account-level security resources {leaked or ''}".rstrip())
    baseline_types = {t for t, _, _ in reachable["account-baseline"]}
    for required in ("aws_guardduty_detector", "aws_securityhub_account", "aws_config_configuration_recorder", "aws_cloudtrail", "aws_sns_topic"):
        check(required in baseline_types, f"account-baseline: owns {required}")
    for singleton in sorted(SINGLETON_TYPES):
        owners = [s for s, res in reachable.items() if any(t == singleton for t, _, _ in res)]
        check(len(owners) <= 1, f"{singleton}: declared by at most one root {owners}")

    print("3. Shared modules, independent state")
    reference = ROOTS["dev"]
    for env in ENVIRONMENTS[1:]:
        for name in SHARED_ENV_FILES:
            same = (reference / name).read_text() == (ROOTS[env] / name).read_text()
            check(same, f"{env}/{name} is identical to dev/{name}")
    env_modules = {env: sorted(str(p.relative_to(PROJECT)) for p in module_sources(ROOTS[env])) for env in ENVIRONMENTS}
    check(len({tuple(m) for m in env_modules.values()}) == 1, f"environments call the same modules: {sorted(set(env_modules['dev']))}")
    for scope, directory in ROOTS.items():
        text = tf_text(directory)
        check("terraform_remote_state" not in text, f"{scope}: does not read another root's state")
        outside = [str(p.relative_to(PROJECT)) for p in module_sources(directory) if not str(p).startswith(str(PROJECT / "modules"))]
        check(not outside, f"{scope}: module sources only under modules/ {outside or ''}".rstrip())
    cidrs = {env: tfvar(ROOTS[env], "vpc_cidr") for env in ENVIRONMENTS}
    for env in ENVIRONMENTS:
        check(tfvar(ROOTS[env], "environment") == env, f"{env}: terraform.tfvars environment = \"{env}\"")
    check(len(set(cidrs.values())) == len(cidrs), f"environment VPC CIDRs do not overlap by value {cidrs}")

    print("4. Bootstrap scopes match backend keys")
    scopes_match = re.search(r"state_scopes\s*=\s*\[([^\]]*)\]", (ROOTS["bootstrap"] / "terraform.tfvars").read_text())
    scopes = re.findall(r'"([^"]+)"', scopes_match.group(1)) if scopes_match else []
    check(sorted(scopes) == sorted(keys), f"bootstrap state_scopes {scopes} == remote roots {sorted(keys)}")
    check(tfvar(ROOTS["bootstrap"], "project_name") == KEY_PREFIX, f"bootstrap project_name = {KEY_PREFIX}")
    prefixes = {scope: tfvar(directory, "name_prefix") for scope, directory in ROOTS.items()}
    check(len(set(prefixes.values())) == 1, f"name_prefix identical in every root {prefixes}")

    print("5. Destroy safety")
    for env in ENVIRONMENTS:
        data_types = set(re.findall(r'^\s*data\s+"([^"]+)"', tf_text(ROOTS[env]), flags=re.M))
        check({"aws_guardduty_detector", "aws_sns_topic"} <= data_types, f"{env}: baseline is referenced via data sources only")
    protected = [t for t, _, _ in reachable["account-baseline"] if t in SINGLETON_TYPES]
    check(bool(protected), "account-baseline singletons exist")
    for module in ("guardduty", "securityhub", "aws-config", "cloudtrail", "security-alerting"):
        check("prevent_destroy = true" in tf_text(PROJECT / "modules" / module), f"modules/{module}: prevent_destroy on the account-level resource")
    gitignore = (PROJECT / ".gitignore").read_text() if (PROJECT / ".gitignore").exists() else ""
    check("*.tfstate" in gitignore, ".gitignore excludes local state (bootstrap state never committed)")

    print("6. Documentation matches configuration")
    doc = PROJECT / "docs" / "terraform-state-ownership.md"
    readme = PROJECT / "README.md"
    for path in (doc, readme):
        check(path.is_file(), f"{path.relative_to(PROJECT)} exists")
    if doc.is_file() and readme.is_file():
        doc_text, readme_text = doc.read_text(), readme.read_text()
        for scope, key in keys.items():
            check(key in doc_text, f"doc names {scope} key {key}")
            check(key in readme_text, f"README names {scope} key {key}")
        check("Terraform State Ownership and Deployment Boundaries" in readme_text, "README has the state ownership section")
        check("docs/terraform-state-ownership.md" in readme_text, "README links to docs/terraform-state-ownership.md")
        check("```mermaid" in readme_text, "README contains a Mermaid diagram")
        for scope in ROOTS:
            role = f"acs-tf-{scope}"
            if scope != "bootstrap":
                check(role in doc_text, f"doc names deployer role {role}")
        check("use_lockfile" in doc_text, "doc explains use_lockfile")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed.")
        return 1
    print("All ownership checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
