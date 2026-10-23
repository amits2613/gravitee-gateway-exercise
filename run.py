#!/usr/bin/env python3
"""Entrypoint for the stack.

    python run.py up     create the cluster and deploy everything, then check /ping
    python run.py test   call /ping through the gateway and check the body
    python run.py down   remove everything

Standard library only. Ports and versions are set in terraform/terraform.tfvars.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TF_DIR = ROOT / "terraform"
WAIT_SECONDS = int(os.environ.get("PONG_WAIT_SECONDS", "180"))

INSTALL_HINTS = {
    "docker": "Install Docker Desktop (Windows, macOS) or Docker Engine (Linux) and start it.",
    "terraform": "Windows: winget install Hashicorp.Terraform | macOS: brew install hashicorp/tap/terraform",
}


def die(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def check_tools(*names: str) -> None:
    missing = [n for n in names if shutil.which(n) is None]
    if missing:
        die("missing on PATH:\n" + "\n".join(f"  - {n}: {INSTALL_HINTS[n]}" for n in missing))
    if "docker" in names and subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
        die("Docker is not running. Start it and try again.")


def terraform(*args: str, capture: bool = False, check: bool = True) -> subprocess.CompletedProcess:
    cmd = ["terraform", f"-chdir={TF_DIR}", *args]
    if not capture:
        print("+ " + " ".join(cmd), flush=True)
    result = subprocess.run(cmd, capture_output=capture, text=True)
    if result.returncode != 0 and check and not capture:
        die(f"terraform {args[0]} failed (exit {result.returncode})", result.returncode)
    return result


def ping_url() -> str:
    """The URL comes from the Terraform output, so the port is set in one place."""
    result = terraform("output", "-raw", "ping_url", capture=True)
    if result.returncode != 0 or not result.stdout.strip():
        die("no ping_url yet. Run: python run.py up")
    return result.stdout.strip()


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.read().decode("utf-8")


def wait_for_pong(url: str) -> str:
    print(f"Waiting up to {WAIT_SECONDS}s for {url} ...", flush=True)
    deadline = time.monotonic() + WAIT_SECONDS
    last = "no response"
    while time.monotonic() < deadline:
        try:
            body = fetch(url)
            if body == "pong":
                return body
            last = f"unexpected body {body!r}"
        except OSError as exc:  # URLError and HTTPError are OSError subclasses
            last = str(exc)
        time.sleep(5)
    die(f"no 'pong' from {url} after {WAIT_SECONDS}s: {last}\nSee Troubleshooting in README.md.")


def apply_with_retry() -> None:
    """Apply once, and once more if it fails.

    Some resources depend on pods that are still starting (for example GKO's
    admission webhook calling the Management API). A second apply is safe and
    picks up where the first stopped.
    """
    result = terraform("apply", "-auto-approve", "-input=false", check=False)
    if result.returncode == 0:
        return
    print("\napply failed. Retrying once, in case a component was still starting.", flush=True)
    time.sleep(15)
    terraform("apply", "-auto-approve", "-input=false")


def cmd_up() -> None:
    check_tools("docker", "terraform")
    terraform("init", "-input=false")
    apply_with_retry()
    url = ping_url()
    body = wait_for_pong(url)
    print(f"\n{url} -> {body}")
    print("The stack keeps running. Open the URL in a browser, or run: python run.py down")


def cmd_test() -> None:
    check_tools("terraform")
    url = ping_url()
    try:
        body = fetch(url)
    except OSError as exc:
        die(f"{url} failed: {exc}")
    if body != "pong":
        die(f"{url} returned {body!r}, expected 'pong'")
    print(f"PASS: {url} -> pong")


def cmd_down() -> None:
    check_tools("docker", "terraform")
    terraform("destroy", "-auto-approve", "-input=false")
    print("Removed.")


COMMANDS = {"up": cmd_up, "test": cmd_test, "down": cmd_down}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    try:
        COMMANDS[sys.argv[1]]()
    except KeyboardInterrupt:
        die("interrupted", 130)
