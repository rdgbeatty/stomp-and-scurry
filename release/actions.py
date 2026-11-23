#!/usr/bin/env python3
"""Fetch prior release assets and sign artifacts from the Windows build job."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

from build import BOOTSTRAP, EXE, MANIFEST, PACK, public_key, sign, validate_release, verify_manifest

TRUSTED_KEY = Path(__file__).with_name("public-key.pem")


def fetch_previous(repo, directory):
    result = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases/latest", "--jq", ".tag_name"],
        capture_output=True, text=True,
    )
    if result.returncode:
        if "HTTP 404" in result.stderr:
            print("No published stable release. Building the first executable.")
            return
        raise ValueError(result.stderr.strip() or "Could not look up the latest release.")
    tag = result.stdout.strip()
    validate_release(tag, 1)
    directory.mkdir()
    command = ["gh", "release", "download", tag, "--repo", repo, "--dir", str(directory)]
    for name in (EXE, BOOTSTRAP, MANIFEST):
        command.extend(["--pattern", name])
    subprocess.run(command, check=True)


def sign_build(directory, tag, sequence):
    validate_release(tag, sequence)
    private = os.environ.pop("STOMP_RELEASE_PRIVATE_KEY", "")
    if not private.strip():
        raise ValueError("Set the STOMP_RELEASE_PRIVATE_KEY repository secret first.")
    for name in (EXE, BOOTSTRAP, PACK, "LICENSE", "GODOT-NOTICES.txt"):
        if not (directory / name).is_file():
            raise ValueError(f"Missing build artifact {name}.")
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "private.pem"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", newline="\n") as stream:
            stream.write(private.strip() + "\n")
        del private
        expected = TRUSTED_KEY.read_text().strip()
        if public_key(path).strip() != expected:
            raise ValueError("The signing secret does not match the public key committed in release/public-key.pem.")
        sign(directory, path, tag, sequence)
    verify_manifest(directory, TRUSTED_KEY)
    print(f"Signed and verified {tag}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    previous = commands.add_parser("previous")
    previous.add_argument("--repo", required=True)
    previous.add_argument("directory", type=Path)
    sign_parser = commands.add_parser("sign")
    sign_parser.add_argument("--tag", required=True)
    sign_parser.add_argument("--sequence", required=True, type=int)
    sign_parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "previous":
            if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", args.repo):
                raise ValueError("Use OWNER/REPO for --repo.")
            fetch_previous(args.repo, args.directory)
        else:
            sign_build(args.directory, args.tag, args.sequence)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
