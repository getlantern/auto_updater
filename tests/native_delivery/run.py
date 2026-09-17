"""Exercise real Sparkle/WinSparkle downloads through a tokenized loopback feed.

Requires cryptography, and either Sparkle's framework or an MSVC developer shell.
Only disposable test bundles are used; the installer handoff is intercepted.
"""

import argparse
import base64
import http.server
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


HERE = Path(__file__).resolve().parent


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, timeout=90)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sparkle", type=Path)
    args = parser.parse_args()
    key = Ed25519PrivateKey.generate()
    public_key = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    with tempfile.TemporaryDirectory(prefix="updater-delivery-") as directory:
        root = Path(directory)
        if sys.platform == "darwin":
            if not args.sparkle:
                parser.error("--sparkle must contain Sparkle.framework")
            host = root / "Delivery.app"
            executable = host / "Contents/MacOS/Delivery"
            executable.parent.mkdir(parents=True)
            frameworks = host / "Contents/Frameworks"
            frameworks.mkdir()
            shutil.copytree(args.sparkle / "Sparkle.framework", frameworks / "Sparkle.framework", symlinks=True)
            metadata = {
                "CFBundleIdentifier": "org.getlantern.delivery-test." + secrets.token_hex(8),
                "CFBundleName": "Delivery", "CFBundleExecutable": "Delivery",
                "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0.0", "SUPublicEDKey": public_key,
                "SUEnableAutomaticChecks": False,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            }
            (host / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            run("xcrun", "swiftc", "-parse-as-library", "-F", args.sparkle,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                HERE / "SparkleDelivery.swift", "-o", executable)
            run("codesign", "--force", "--deep", "--sign", "-", host)
            target = root / "target/Delivery.app"
            shutil.copytree(host, target, symlinks=True)
            metadata.update(CFBundleVersion="2", CFBundleShortVersionString="2.0.0")
            (target / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            run("codesign", "--force", "--deep", "--sign", "-", target)
            artifact = root / "installer.zip"
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", target, artifact)
        elif sys.platform == "win32":
            library = HERE.parents[1] / "packages/auto_updater_windows/windows/WinSparkle-0.9.4"
            executable = root / "Delivery.exe"
            run("cl", "/nologo", "/EHsc", "/std:c++17", f"/I{library / 'include'}",
                HERE / "WinSparkleDelivery.cpp", f"/Fo{root / 'Delivery.obj'}", f"/Fe{executable}",
                "/link", f"/LIBPATH:{library / 'x64/Release'}", "WinSparkle.lib", "user32.lib")
            shutil.copy2(library / "x64/Release/WinSparkle.dll", root)
            artifact = root / "installer.exe"
            artifact.write_bytes(b"Signed delivery fixture; never executed.\n")
        else:
            parser.error("Run on macOS or Windows")

        original = artifact.read_bytes()
        valid_signature = key.sign(original)
        signature = base64.b64encode(valid_signature).decode()
        token = secrets.token_urlsafe(32)
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                if self.path.split("?", 1)[0] == f"/{token}/appcast.xml":
                    body = (f'<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                            f'<channel><title>Test</title><item><title>2.0.0</title>'
                            f'<sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>'
                            f'<enclosure url="{address}/{token}/{artifact.name}" length="{len(original)}" '
                            f'sparkle:version="2" sparkle:edSignature="{signature}" type="application/octet-stream"/>'
                            f'</item></channel></rss>').encode()
                    content_type = "application/xml"
                elif self.path == f"/{token}/{artifact.name}":
                    body = artifact.read_bytes()
                    content_type = "application/octet-stream"
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        address = f"http://127.0.0.1:{server.server_port}"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for mode in ("valid", "invalid"):
                signature = base64.b64encode(valid_signature if mode == "valid" else
                                             bytes([valid_signature[0] ^ 1]) + valid_signature[1:]).decode()
                requests.clear()
                command = [executable, f"{address}/{token}/appcast.xml"]
                if sys.platform == "win32":
                    command.append(public_key)
                run(*command, mode)
                assert any(path.startswith(f"/{token}/appcast.xml") for path in requests), requests
                assert f"/{token}/{artifact.name}" in requests, requests
                print(f"PASS: {mode} signed download through loopback", flush=True)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
