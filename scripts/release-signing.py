#!/usr/bin/env python3
"""Prepare a project-specific release certificate or load it on the Release runner."""
import argparse
import base64
import fcntl
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import tempfile

REPO = "kirktools/hotkey"
ARCHIVE_SECRET = "HOTKEY_RELEASE_P12_BASE64"
PASSWORD_SECRET = "HOTKEY_RELEASE_P12_PASSWORD"
SECURITY = "/usr/bin/security"
OPENSSL = "/usr/bin/openssl"
OPENSSL_CONFIG = """[req]
prompt=no
distinguished_name=subject
x509_extensions=signing
[subject]
CN=Hotkey Release Signing
[signing]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
"""


def run(*args, input_data=None):
    result = subprocess.run(args, input=input_data, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} 执行失败（退出码 {result.returncode}）。")
    return result.stdout.decode()


def prepare(upload):
    common = Path(run("git", "rev-parse", "--git-common-dir").strip()).resolve()
    root = common.parent / ".local/signing"
    root.mkdir(parents=True, exist_ok=True)
    state = root / "release"
    with (root / "release.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not state.exists():
            with tempfile.TemporaryDirectory(dir=root) as temporary:
                work = Path(temporary)
                archive = work / "release"
                archive.mkdir()
                config, key, cert = (work / name for name in ("openssl.cnf", "key.pem", "cert.pem"))
                config.write_text(OPENSSL_CONFIG)
                password_file = archive / "password"
                password_file.write_text(secrets.token_urlsafe(40))
                run(OPENSSL, "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650",
                    "-config", str(config), "-keyout", str(key), "-out", str(cert))
                run(OPENSSL, "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                    "-out", str(archive / "certificate.p12"), "-passout", "file:" + str(password_file))
                archive.rename(state)
        password_file = state / "password"
        archive = state / "certificate.p12"
        if not password_file.is_file() or not archive.is_file():
            raise RuntimeError("发布证书资料不完整。请恢复备份，避免更换应用身份。")
        run(OPENSSL, "pkcs12", "-in", str(archive), "-noout", "-passin", "file:" + str(password_file))
        if upload:
            run("gh", "secret", "set", ARCHIVE_SECRET, "--repo", REPO,
                input_data=base64.b64encode(archive.read_bytes()))
            run("gh", "secret", "set", PASSWORD_SECRET, "--repo", REPO,
                input_data=password_file.read_bytes())
    print("Hotkey 发布签名已配置到 GitHub Actions。" if upload else "固定发布证书已在本机准备好。")


def load_ci():
    encoded, password = os.environ.get(ARCHIVE_SECRET), os.environ.get(PASSWORD_SECRET)
    if not encoded or not password:
        raise RuntimeError("缺少 Hotkey 固定签名 Secrets。请先运行 make signing-ci。")
    folder = Path(os.environ["RUNNER_TEMP"]) / "hotkey-release-signing"
    folder.mkdir()
    keychain = str(folder / "release.keychain-db")
    keychain_password = secrets.token_urlsafe(40)
    with tempfile.TemporaryDirectory(dir=folder) as temporary:
        archive = Path(temporary) / "certificate.p12"
        archive.write_bytes(base64.b64decode(encoded, validate=True))
        run(SECURITY, "create-keychain", "-p", keychain_password, keychain)
        run(SECURITY, "unlock-keychain", "-p", keychain_password, keychain)
        run(SECURITY, "set-keychain-settings", "-lut", "21600", keychain)
        run(SECURITY, "import", str(archive), "-k", keychain, "-P", password, "-T", "/usr/bin/codesign")
        run(SECURITY, "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", keychain_password, keychain)
    identities = set(re.findall(r"\b[0-9A-F]{40}\b", run(SECURITY, "find-identity", "-p", "codesigning", keychain)))
    if len(identities) != 1:
        raise RuntimeError("发布钥匙串必须恰好包含一个代码签名身份。")
    current = shlex.split(run(SECURITY, "list-keychains", "-d", "user"))
    run(SECURITY, "list-keychains", "-d", "user", "-s", keychain, *(item for item in current if item != keychain))
    with Path(os.environ["GITHUB_ENV"]).open("a") as target:
        target.write(f"RELEASE_SIGNING_IDENTITY={identities.pop()}\nRELEASE_SIGNING_KEYCHAIN={keychain}\n")


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "upload", "runner"])
    mode = parser.parse_args().mode
    try:
        if mode == "runner":
            load_ci()
        else:
            prepare(upload=mode == "upload")
    except RuntimeError as error:
        raise SystemExit(str(error))
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        raise SystemExit("发布签名准备失败，请检查固定证书、环境与权限。")
