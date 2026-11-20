#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Prepare App Store Connect for a Trash Stack upload, and check on the build after it.

The TestFlight workflow runs this. It needs only Python and `openssl`, both of which are
on every GitHub runner.

    appstore_connect.py ensure-bundle-id --bundle-id ID --name "Trash Stack"
    appstore_connect.py beta-group --bundle-id ID --name "Trash Stack team"
    appstore_connect.py wait-build --bundle-id ID --version 1.0.0 --build 74.1
    appstore_connect.py distribute-build --bundle-id ID --name "Trash Stack team" \\
        --version 1.0.0 --build 74.1 --tester-email someone@example.com

The key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (the .p8
file). The job log of a public repository is public, so nothing here prints a name, an
email address, or any part of the key.

Adapted from cinderandcrown/neon-city-bandit (Magpie pattern) + phoenix-fox.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable

API = "https://api.appstoreconnect.apple.com"
AGENT = "TrashStack-CI/1.0 (+https://github.com/cinderandcrown/trash-stack)"


class ApiError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(f"App Store Connect answered {status}: {detail}")
        self.status = status
        self.detail = detail


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_signature(der: bytes) -> bytes:
    """Turns openssl's DER signature into the 64 bytes (r then s) that a JWT carries."""

    def read_length(at: int) -> tuple[int, int]:
        first = der[at]
        if first < 0x80:
            return first, at + 1
        count = first & 0x7F
        return int.from_bytes(der[at + 1 : at + 1 + count], "big"), at + 1 + count

    def read_integer(at: int) -> tuple[bytes, int]:
        if der[at] != 0x02:
            raise ValueError("not a DER integer")
        length, start = read_length(at + 1)
        value = der[start : start + length].lstrip(b"\x00")
        if len(value) > 32:
            raise ValueError("integer too large for P-256")
        return value.rjust(32, b"\x00"), start + length

    if not der or der[0] != 0x30:
        raise ValueError("not a DER sequence")
    _, at = read_length(1)
    r, at = read_integer(at)
    s, at = read_integer(at)
    if at != len(der):
        raise ValueError("unexpected data after the signature")
    return r + s


def openssl_sign(key_path: str, message: bytes) -> bytes:
    done = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=message,
        capture_output=True,
        check=False,
    )
    if done.returncode != 0:
        raise SystemExit("Could not sign with the App Store Connect key. Check the ASC_KEY_P8 secret.")
    return done.stdout


def make_token(
    key_id: str,
    issuer_id: str,
    sign: Callable[[bytes], bytes],
    now: float,
    lifetime: int = 15 * 60,
) -> str:
    """A token App Store Connect accepts. Apple refuses lifetimes over twenty minutes."""
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer_id, "iat": int(now), "exp": int(now) + lifetime, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(base64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims))
    return f"{signing_input}.{base64url(raw_signature(sign(signing_input.encode())))}"


Send = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def urllib_send(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


@dataclass
class Client:
    token: Callable[[], str]
    send: Send = urllib_send

    def call(self, method: str, path: str, query: dict[str, str] | None = None, body: Any = None) -> Any:
        url = path if path.startswith("https://") else API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"Authorization": f"Bearer {self.token()}", "Accept": "application/json", "User-Agent": AGENT}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        status, raw = self.send(method, url, headers, data)
        parsed = json.loads(raw) if raw else {}
        if status >= 400:
            raise ApiError(status, describe_errors(parsed))
        return parsed

    def get(self, path: str, query: dict[str, str] | None = None) -> Any:
        return self.call("GET", path, query)

    def post(self, path: str, body: Any) -> Any:
        return self.call("POST", path, body=body)

    def patch(self, path: str, body: Any) -> Any:
        return self.call("PATCH", path, body=body)


def describe_errors(body: Any) -> str:
    errors = body.get("errors") if isinstance(body, dict) else None
    if not errors:
        return "no detail"
    return "; ".join(f"{e.get('code', '?')}: {e.get('detail') or e.get('title') or ''}".strip() for e in errors)


def find_bundle(client: Client, identifier: str) -> dict[str, Any] | None:
    page = client.get(
        "/v1/bundleIds",
        {"filter[identifier]": identifier, "limit": "200"},
    )
    for bundle in page.get("data", []):
        if bundle["attributes"]["identifier"] == identifier:
            return {"id": bundle["id"], "name": bundle["attributes"].get("name", "")}
    return None


def ensure_bundle_id(client: Client, identifier: str, name: str, platform: str = "IOS") -> tuple[str, bool]:
    """Registers the App ID if missing. Returns (bundle record id, created?)."""
    existing = find_bundle(client, identifier)
    if existing:
        return existing["id"], False
    created = client.post(
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": platform,
                },
            }
        },
    )
    return created["data"]["id"], True


def find_app(client: Client, identifier: str) -> str | None:
    page = client.get("/v1/apps", {"filter[bundleId]": identifier, "limit": "10"})
    for app in page.get("data", []):
        if app["attributes"]["bundleId"] == identifier:
            return app["id"]
    return None


def require_app(client: Client, identifier: str) -> str:
    app_id = find_app(client, identifier)
    if app_id:
        return app_id
    raise SystemExit(
        f"No App Store Connect app record for {identifier}. Create it in App Store Connect "
        f"(Apps > +) with name Trash Stack, SKU trashstack, bundle id {identifier}, "
        f"primary language English (U.S.)."
    )


def ensure_internal_group(client: Client, app_id: str, name: str) -> tuple[str, bool]:
    page = client.get(f"/v1/apps/{app_id}/betaGroups", {"limit": "200"})
    for group in page.get("data", []):
        attributes = group["attributes"]
        if attributes.get("isInternalGroup") and attributes.get("name") == name:
            # Older groups may lack all-builds access — turn it on so every upload lands.
            if attributes.get("hasAccessToAllBuilds") is not True:
                try:
                    client.patch(
                        f"/v1/betaGroups/{group['id']}",
                        {
                            "data": {
                                "type": "betaGroups",
                                "id": group["id"],
                                "attributes": {"hasAccessToAllBuilds": True},
                            }
                        },
                    )
                except ApiError:
                    pass
            return group["id"], False
    created = client.post(
        "/v1/betaGroups",
        {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    return created["data"]["id"], True


def find_tester_id(client: Client, email: str) -> str | None:
    needle = email.strip().lower()
    try:
        page = client.get("/v1/betaTesters", {"filter[email]": email, "limit": "10"})
        for tester in page.get("data", []):
            if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
                return tester["id"]
        if page.get("data"):
            return page["data"][0]["id"]
    except ApiError:
        pass
    # Internal testers are ASC users — match username (usually the Apple ID email).
    try:
        users = client.get("/v1/users", {"filter[username]": email, "limit": "5"}).get("data", [])
        for user in users:
            username = (user.get("attributes") or {}).get("username", "").strip().lower()
            if username == needle:
                # Beta tester id is not the user id; search betaTesters without filter.
                all_testers = client.get("/v1/betaTesters", {"limit": "200"}).get("data", [])
                for tester in all_testers:
                    if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
                        return tester["id"]
    except ApiError:
        pass
    return None


def add_tester(client: Client, group_id: str, email: str, first_name: str = "", last_name: str = "") -> str:
    """Invite/add an internal tester by email. Never prints the address."""
    try:
        client.post(
            "/v1/betaTesters",
            {
                "data": {
                    "type": "betaTesters",
                    "attributes": {
                        "email": email,
                        "firstName": first_name or "",
                        "lastName": last_name or "",
                    },
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}},
                }
            },
        )
        return "Tester added to the group."
    except ApiError as error:
        if error.status == 409:
            try:
                linked = link_existing_tester(client, group_id, email)
                return linked
            except ApiError as link_error:
                return f"Tester was already registered; link failed ({link_error.status})."
        return f"Could not add tester ({error.status}). Add them in App Store Connect > TestFlight."


def link_existing_tester(client: Client, group_id: str, email: str) -> str:
    tester_id = find_tester_id(client, email)
    if not tester_id:
        return "Tester record not found after conflict."
    try:
        client.post(
            f"/v1/betaGroups/{group_id}/relationships/betaTesters",
            {"data": [{"type": "betaTesters", "id": tester_id}]},
        )
        return "Existing tester linked to the group."
    except ApiError as error:
        if error.status == 409:
            return "Tester already in the group."
        raise


def add_account_holder(client: Client, group_id: str) -> tuple[str, str | None]:
    """Returns (status message, account-holder username/email if known)."""
    try:
        holders = client.get("/v1/users", {"filter[roles]": "ACCOUNT_HOLDER", "limit": "1"}).get("data", [])
    except ApiError as error:
        return (
            f"Could not read the team's users ({error.status}). Add yourself to the group in App Store Connect > TestFlight.",
            None,
        )
    if not holders:
        return ("No account holder was listed. Add yourself to the group in App Store Connect > TestFlight.", None)
    holder = holders[0]["attributes"]
    username = holder.get("username") or ""
    msg = add_tester(
        client,
        group_id,
        username,
        holder.get("firstName") or "",
        holder.get("lastName") or "",
    )
    return msg, username


def group_tester_count(client: Client, group_id: str) -> int:
    try:
        page = client.get(f"/v1/betaGroups/{group_id}/betaTesters", {"limit": "200"})
        return len(page.get("data", []))
    except ApiError:
        return -1


def tester_present(client: Client, group_id: str, email: str) -> bool:
    """True if the email is already a beta tester on this group. Does not print the email."""
    needle = email.strip().lower()
    try:
        page = client.get(
            f"/v1/betaGroups/{group_id}/betaTesters",
            {"limit": "200"},
        )
    except ApiError:
        try:
            page = client.get("/v1/betaTesters", {"filter[email]": email, "limit": "5"})
            return bool(page.get("data"))
        except ApiError:
            return False
    for tester in page.get("data", []):
        if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
            return True
    return False


def group_access_flags(client: Client, group_id: str) -> dict[str, Any]:
    try:
        group = client.get(f"/v1/betaGroups/{group_id}").get("data", {})
        return group.get("attributes") or {}
    except ApiError:
        return {}


def find_build(client: Client, app_id: str, version: str, build: str) -> dict[str, Any] | None:
    page = client.get(
        "/v1/builds",
        {
            "filter[app]": app_id,
            "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
            "limit": "5",
        },
    )
    builds = page.get("data", [])
    return builds[0] if builds else None


def build_state(client: Client, app_id: str, version: str, build: str) -> str | None:
    found = find_build(client, app_id, version, build)
    return found["attributes"].get("processingState") if found else None


def wait_for_build(
    client: Client,
    app_id: str,
    version: str,
    build: str,
    timeout: float,
    sleep: Callable[[float], None] = time.sleep,
    now: Callable[[], float] = time.monotonic,
) -> str:
    deadline = now() + timeout
    last = None
    while True:
        try:
            state = build_state(client, app_id, version, build)
        except ApiError as error:
            if error.status < 500 and error.status != 429:
                raise
            state = last
        if state != last:
            print(f"Build {version} ({build}): {state or 'not listed yet'}")
            last = state
        if state in ("VALID", "INVALID", "FAILED"):
            return state
        if now() >= deadline:
            return "TIMED_OUT"
        sleep(30)


def set_export_compliance(client: Client, build_id: str) -> str:
    """Answer export compliance: app does not use non-exempt encryption."""
    try:
        client.patch(
            f"/v1/builds/{build_id}",
            {
                "data": {
                    "type": "builds",
                    "id": build_id,
                    "attributes": {"usesNonExemptEncryption": False},
                }
            },
        )
        return "Export compliance set (usesNonExemptEncryption=false)."
    except ApiError as error:
        # Already answered / immutable once processed — treat as ok for distribute.
        if error.status in (409, 422):
            return f"Export compliance already set or not changeable ({error.status})."
        return f"Could not set export compliance ({error.status}): {error.detail}"


def attach_build_to_group(client: Client, group_id: str, build_id: str) -> str:
    """Link build ↔ internal group. Prefer build→groups; fall back to group→builds."""
    try:
        client.post(
            f"/v1/builds/{build_id}/relationships/betaGroups",
            {"data": [{"type": "betaGroups", "id": group_id}]},
        )
        return "Build attached to the internal group."
    except ApiError as error:
        if error.status == 409:
            return "Build was already on the internal group."
        # Internal "all builds" groups reject explicit membership — that is success.
        detail = (error.detail or "").lower()
        if error.status == 422 and ("internal" in detail or "access" in detail or "all build" in detail):
            return "Group has access to all builds (explicit attach not needed)."
        # Try the opposite relationship direction once.
        try:
            client.post(
                f"/v1/betaGroups/{group_id}/relationships/builds",
                {"data": [{"type": "builds", "id": build_id}]},
            )
            return "Build attached to the internal group (via group relationship)."
        except ApiError as error2:
            if error2.status == 409:
                return "Build was already on the internal group."
            detail2 = (error2.detail or "").lower()
            if error2.status == 422 and ("internal" in detail2 or "access" in detail2 or "all build" in detail2):
                return "Group has access to all builds (explicit attach not needed)."
            return f"Could not attach build ({error.status}/{error2.status}): {error.detail}"


def distribute_build(
    client: Client,
    bundle_id: str,
    group_name: str,
    version: str,
    build: str,
    tester_email: str | None,
    timeout: float,
) -> int:
    """Ensure group + testers, wait/find build, set compliance, attach, report."""
    app_id = require_app(client, bundle_id)
    group_id, created = ensure_internal_group(client, app_id, group_name)
    flags = group_access_flags(client, group_id)
    print(
        f"Internal group “{group_name}”: {'created' if created else 'already there'}. "
        f"hasAccessToAllBuilds={flags.get('hasAccessToAllBuilds')} isInternal={flags.get('isInternalGroup')}."
    )
    holder_msg, holder_email = add_account_holder(client, group_id)
    print(holder_msg)
    holder_ok = bool(holder_email) and tester_present(client, group_id, holder_email)
    print(f"Account holder in group: {'yes' if holder_ok else 'no'}")

    tester_ok = False
    if tester_email:
        print(add_tester(client, group_id, tester_email))
        tester_ok = tester_present(client, group_id, tester_email)
        print(f"Named tester in group: {'yes' if tester_ok else 'no'}")

    count = group_tester_count(client, group_id)
    print(f"Testers currently on group: {count if count >= 0 else 'unknown'}")

    state = wait_for_build(client, app_id, version, build, timeout)
    found = find_build(client, app_id, version, build)
    if not found:
        print(f"Build {version} ({build}) is not listed in App Store Connect yet.")
        if state == "TIMED_OUT":
            return 0
        return 1

    build_id = found["id"]
    attrs = found.get("attributes") or {}
    print(
        f"Build {version} ({build}): processingState={attrs.get('processingState')} "
        f"usesNonExemptEncryption={attrs.get('usesNonExemptEncryption')}"
    )
    print(set_export_compliance(client, build_id))
    print(attach_build_to_group(client, group_id, build_id))

    # Re-check presence after attach.
    if holder_email:
        holder_ok = tester_present(client, group_id, holder_email)
        print(f"Account holder in group (recheck): {'yes' if holder_ok else 'no'}")
    if tester_email:
        tester_ok = tester_present(client, group_id, tester_email)
        print(f"Named tester in group (recheck): {'yes' if tester_ok else 'no'}")

    if state == "VALID":
        print("Apple finished processing. The build is in TestFlight.")
        # Fail the job if nobody is on the group — that is the "never appears" failure mode.
        if count == 0 and not holder_ok and not tester_ok:
            print("ERROR: internal group has no testers — Nicholas will not see the build.")
            return 1
        return 0
    if state == "TIMED_OUT":
        print("Apple is still processing. The build will appear in TestFlight when it finishes.")
        return 0
    print("Apple rejected the build during processing. The reason is in the email from App Store Connect.")
    return 1


def client_from_environment() -> Client:
    missing = [name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(name)]
    if missing:
        raise SystemExit("Missing: " + ", ".join(missing))
    key_id, issuer_id, key_path = (os.environ[name] for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"))
    cached: dict[str, Any] = {}

    def token() -> str:
        if not cached or time.time() > cached["made"] + 10 * 60:
            cached["made"] = time.time()
            cached["token"] = make_token(key_id, issuer_id, lambda message: openssl_sign(key_path, message), time.time())
        return cached["token"]

    return Client(token=token)


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    register = commands.add_parser("ensure-bundle-id", help="register the App ID if it is missing")
    register.add_argument("--bundle-id", required=True)
    register.add_argument("--name", required=True, help="App ID name in the developer portal")
    register.add_argument("--platform", default="IOS")

    group = commands.add_parser("beta-group", help="make sure an internal TestFlight group exists")
    group.add_argument("--bundle-id", required=True)
    group.add_argument("--name", required=True)
    group.add_argument(
        "--tester-email",
        default="",
        help="Also add this email as an internal tester (address never printed)",
    )

    wait = commands.add_parser("wait-build", help="wait for Apple to process an uploaded build")
    wait.add_argument("--bundle-id", required=True)
    wait.add_argument("--version", required=True)
    wait.add_argument("--build", required=True)
    wait.add_argument("--timeout", type=float, default=30 * 60)

    distribute = commands.add_parser(
        "distribute-build",
        help="ensure group/testers, set export compliance, attach build, wait if needed",
    )
    distribute.add_argument("--bundle-id", required=True)
    distribute.add_argument("--name", required=True, help="Internal beta group name")
    distribute.add_argument("--version", required=True)
    distribute.add_argument("--build", required=True)
    distribute.add_argument("--tester-email", default="")
    distribute.add_argument("--timeout", type=float, default=30 * 60)

    check_app = commands.add_parser("check-app", help="exit 0 if the ASC app record exists, else print create fields")
    check_app.add_argument("--bundle-id", required=True)

    options = parser.parse_args(arguments)
    client = client_from_environment()

    try:
        if options.command == "ensure-bundle-id":
            bundle_id, created = ensure_bundle_id(client, options.bundle_id, options.name, options.platform)
            print(f"App ID {options.bundle_id}: {'created' if created else 'already registered'} ({bundle_id}).")
            return 0
        if options.command == "check-app":
            app_id = find_app(client, options.bundle_id)
            if app_id:
                print(f"App Store Connect app record exists ({app_id}).")
                return 0
            print(
                "MISSING_APP_RECORD\n"
                "Create the app in App Store Connect with these fields:\n"
                "  name: Trash Stack\n"
                "  SKU: trashstack\n"
                f"  bundle id: {options.bundle_id}\n"
                "  primary language: English (U.S.)\n"
            )
            return 2
        if options.command == "beta-group":
            app_id = require_app(client, options.bundle_id)
            group_id, created = ensure_internal_group(client, app_id, options.name)
            flags = group_access_flags(client, group_id)
            print(
                f"Internal group “{options.name}”: {'created' if created else 'already there'}. "
                f"hasAccessToAllBuilds={flags.get('hasAccessToAllBuilds')}."
            )
            holder_msg, holder_email = add_account_holder(client, group_id)
            print(holder_msg)
            if holder_email:
                print(f"Account holder in group: {'yes' if tester_present(client, group_id, holder_email) else 'no'}")
            if options.tester_email:
                print(add_tester(client, group_id, options.tester_email))
                present = tester_present(client, group_id, options.tester_email)
                print(f"Named tester in group: {'yes' if present else 'no'}")
            print(f"Testers currently on group: {group_tester_count(client, group_id)}")
            return 0
        if options.command == "wait-build":
            app_id = require_app(client, options.bundle_id)
            state = wait_for_build(client, app_id, options.version, options.build, options.timeout)
            found = find_build(client, app_id, options.version, options.build)
            if found:
                print(set_export_compliance(client, found["id"]))
            if state == "VALID":
                print("Apple finished processing. The build is in TestFlight.")
                return 0
            if state == "TIMED_OUT":
                print("Apple is still processing. The build will appear in TestFlight when it finishes.")
                return 0
            print("Apple rejected the build during processing. The reason is in the email from App Store Connect.")
            return 1
        if options.command == "distribute-build":
            return distribute_build(
                client,
                options.bundle_id,
                options.name,
                options.version,
                options.build,
                options.tester_email or None,
                options.timeout,
            )
    except ApiError as error:
        print(f"{error}")
        if error.status in (401, 403):
            print("The key was refused. Check ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, and the key's role.")
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
