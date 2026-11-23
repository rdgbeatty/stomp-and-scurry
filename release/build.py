#!/usr/bin/env python3
"""Export Windows release assets and sign their update manifest."""
import argparse
import base64
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "launcher" / "app"
EXE = "StompAndScurry.exe"
PACK = "StompAndScurry.pck"
MANIFEST = "release.json"
BOOTSTRAP = "bootstrap-build.json"


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def runtime_number(name, app=APP):
    pattern = rf"^const {name} := (\d+)$"
    return int(re.search(pattern, (app / "pack_release.gd").read_text(), re.M)[1])


def public_key(path):
    return subprocess.check_output(["openssl", "pkey", "-in", str(path), "-pubout"], text=True)


def config_for(args):
    key = public_key(args.key) if args.key else args.public_key.read_text()
    if args.github:
        if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", args.github):
            raise ValueError("Use OWNER/REPO for --github.")
        base = f"https://github.com/{args.github}/releases"
    else:
        base = args.local_feed.rstrip("/")
        url = urlsplit(base)
        if url.scheme != "http" or url.query or url.fragment or url.username is not None:
            raise ValueError("--local-feed must be a plain HTTP address on the local network.")
        if url.hostname != "localhost" and not ipaddress.ip_address(url.hostname or "").is_private:
            raise ValueError("--local-feed must use localhost or a private IP address.")
    return {"base": base, "public_key": key}


def stage_bootstrap(stage, config, app=APP):
    for path in app.iterdir():
        if path.is_file() and path.suffix in {".gd", ".tscn", ".bin", ".godot", ".cfg"}:
            shutil.copyfile(path, stage / path.name)
    project = stage / "project.godot"
    project.write_text(project.read_text().replace("res://launcher.tscn", "res://pack_launcher.tscn"))
    preset = stage / "export_presets.cfg"
    preset.write_text(preset.read_text().replace(
        'include_filter="restart_helper.bin"', 'include_filter="restart_helper.bin,pack-feed.json"'
    ))
    (stage / "pack-feed.json").write_text(json.dumps(config))


def bootstrap_stamp(stage):
    return {path.name: digest(path) for path in sorted(stage.iterdir()) if path.is_file()}


def sign(assets, key, tag, sequence, app=APP):
    validate_release(tag, sequence)
    bootstrap = assets / BOOTSTRAP
    metadata = json.loads(bootstrap.read_text()) if bootstrap.exists() else {
        "runtime_version": runtime_number("RUNTIME_VERSION", app),
        "pack_abi": runtime_number("PACK_ABI", app),
    }
    payload = {
        "schema": 1,
        "tag": tag,
        "sequence": sequence,
        "runtime_version": metadata["runtime_version"],
        "pack_abi": metadata["pack_abi"],
        "runtime_sha256": digest(assets / EXE),
        "pack_sha256": digest(assets / PACK),
    }
    if bootstrap.exists():
        if any(type(payload[field]) is not int or payload[field] < 1 for field in ("runtime_version", "pack_abi")):
            raise ValueError("Invalid runtime version or pack ABI.")
        if metadata["sha256"] != payload["runtime_sha256"]:
            raise ValueError("The executable does not match its build metadata.")
        payload["bootstrap_build_sha256"] = digest(bootstrap)
    encoded = json.dumps(payload, separators=(",", ":")).encode()
    with tempfile.TemporaryDirectory() as temporary:
        message = Path(temporary) / "payload"
        message.write_bytes(encoded)
        signature = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", str(key), str(message)]
        )
    envelope = {"payload": base64.b64encode(encoded).decode(), "signature": base64.b64encode(signature).decode()}
    (assets / MANIFEST).write_text(json.dumps(envelope, separators=(",", ":")) + "\n")
    return payload


def verify_manifest(directory, key):
    envelope = json.loads((directory / MANIFEST).read_text())
    payload = base64.b64decode(envelope["payload"], validate=True)
    signature = base64.b64decode(envelope["signature"], validate=True)
    with tempfile.TemporaryDirectory() as temporary:
        message = Path(temporary) / "payload"
        signature_file = Path(temporary) / "signature"
        message.write_bytes(payload)
        signature_file.write_bytes(signature)
        subprocess.run([
            "openssl", "dgst", "-sha256", "-verify", str(key), "-signature",
            str(signature_file), str(message),
        ], check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads(payload)
    validate_release(manifest["tag"], manifest["sequence"])
    files = [("runtime_sha256", EXE), ("bootstrap_build_sha256", BOOTSTRAP)]
    if (directory / PACK).exists():
        files.append(("pack_sha256", PACK))
    for field, name in files:
        if digest(directory / name) != manifest[field]:
            raise ValueError(f"The signed release has invalid {name}.")
    return manifest


def godot(args, project, *operation):
    process = subprocess.run(
        [args.godot, "--headless", "--path", str(project), *operation],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if process.stdout:
        print(process.stdout, end="")
    if process.returncode != 0 or re.search(r"(?im)^\s*(?:script error|error):", process.stdout):
        raise ValueError("Godot reported a build error.")


def validate_release(tag, sequence):
    if not re.fullmatch(r"v[0-9]{1,8}\.[0-9]{1,8}\.[0-9]{1,8}", tag):
        raise ValueError("Use a release tag such as v0.1.0.")
    if type(sequence) is not int or not 1 <= sequence <= 2147483647:
        raise ValueError("--sequence must be a positive integer. Increase it for each release.")


def build(args):
    validate_release(args.tag, args.sequence)
    if args.output.exists():
        raise ValueError(f"Choose an empty output location. {args.output} already exists.")
    config = config_for(args)
    source = args.source.resolve()
    app = source / "launcher" / "app"
    version = runtime_number("RUNTIME_VERSION", app)
    abi = runtime_number("PACK_ABI", app)
    reuse_exe = args.reuse_exe
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".stomp-release-", dir=args.output.parent) as temporary:
        stage = Path(temporary).resolve() / "bootstrap"
        assets = stage.parent / "assets"
        stage.mkdir()
        assets.mkdir()
        stage_bootstrap(stage, config, app)
        stamp = bootstrap_stamp(stage)
        if args.previous:
            trusted = stage.parent / "public-key.pem"
            trusted.write_text(config["public_key"])
            manifest = verify_manifest(args.previous, trusted)
            if args.sequence <= manifest["sequence"]:
                raise ValueError("Use a sequence higher than the latest signed release.")
            if version < manifest["runtime_version"] or abi < manifest["pack_abi"]:
                raise ValueError("Do not decrease RUNTIME_VERSION or PACK_ABI.")
            if version == manifest["runtime_version"]:
                reuse_exe = args.previous
        if reuse_exe:
            previous = json.loads((reuse_exe / BOOTSTRAP).read_text())
            exe = reuse_exe / EXE
            if previous.get("inputs") != stamp or previous.get("sha256") != digest(exe):
                raise ValueError("The bootstrap inputs or executable changed. Rebuild it and bump RUNTIME_VERSION.")
            shutil.copyfile(exe, assets / EXE)
        else:
            godot(args, stage, "--editor", "--import")
            godot(args, stage, "--export-release", "Windows Desktop", str(assets / EXE))
        godot(args, source, "--editor", "--import")
        godot(args, source, "--export-pack", "Windows Desktop", str(assets / PACK))
        if args.verify_windows:
            command = [str(assets / EXE), "--headless", "--quit-after", "15"]
            subprocess.run(command, check=True, timeout=30)
            marker = stage.parent / "pack.ready"
            subprocess.run([
                *command, "--main-pack", str(assets / PACK), "--", "--game-pack",
                digest(assets / PACK), str(marker), "solo", "-", "-",
            ], check=True, timeout=30)
            if not marker.exists() or marker.read_text() != "ready":
                raise ValueError("The Windows executable did not start the external game pack.")
        (assets / BOOTSTRAP).write_text(json.dumps({
            "inputs": stamp, "sha256": digest(assets / EXE), "runtime_version": version, "pack_abi": abi,
        }))
        if args.key:
            sign(assets, args.key, args.tag, args.sequence, app)
        for name in ("LICENSE", "GODOT-NOTICES.txt"):
            shutil.copyfile(source / name, assets / name)
        assets.replace(args.output)
    print(f"Prepared {args.tag} in {args.output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.3 editor executable with Windows export templates installed")
    parser.add_argument("--source", type=Path, default=ROOT, help="source tree to export")
    keys = parser.add_mutually_exclusive_group(required=True)
    keys.add_argument("--key", type=Path, help="RSA private key stored outside the source repository")
    keys.add_argument("--public-key", type=Path, help="build artifacts for signing in a separate job")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--sequence", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    previous = parser.add_mutually_exclusive_group()
    previous.add_argument("--reuse-exe", type=Path, help="previous local output directory")
    previous.add_argument("--previous", type=Path, help="verified previous public release used to check versioning and reuse the executable")
    parser.add_argument("--verify-windows", action="store_true", help="start both exports on a Windows build machine")
    feed = parser.add_mutually_exclusive_group(required=True)
    feed.add_argument("--github", metavar="OWNER/REPO")
    feed.add_argument("--local-feed", metavar="URL")
    args = parser.parse_args()
    args.output = args.output.resolve()
    if args.key:
        args.key = args.key.resolve()
        if args.key in (ROOT, args.source.resolve()) or ROOT in args.key.parents or args.source.resolve() in args.key.parents:
            parser.error("Keep the signing key outside the repository.")
    try:
        build(args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
