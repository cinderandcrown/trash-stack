#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Prepare App Store Connect for a Trash Stack upload, and check on the build after it.

The TestFlight workflow runs this. It needs only Python and `openssl`, both of which are
on every GitHub runner.

    appstore_connect.py ensure-bundle-id --bundle-id ID --name "Trash Stack"
    appstore_connect.py configure-game-center --bundle-id ID
    appstore_connect.py beta-group --bundle-id ID --name "Trash Stack team"
    appstore_connect.py wait-build --bundle-id ID --version 1.0.0 --build 74.1
    appstore_connect.py distribute-build --bundle-id ID --name "Trash Stack team" \\
        --version 1.0.0 --build 74.1 --tester-email someone@example.com

configure-game-center is idempotent and config-only: enables GAME_CENTER on the App ID
(so cloud-managed profiles include it), then creates missing leaderboards/achievements.
It never submits or releases an App Store version. TestFlight runs it before signing.

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


def iter_collection(client: Client, path: str, query: dict[str, str] | None = None) -> list[dict[str, Any]]:
    """Follow ASC pagination (links.next) and return every resource."""
    items: list[dict[str, Any]] = []
    params = dict(query or {})
    params.setdefault("limit", "200")
    page = client.get(path, params)
    items.extend(page.get("data", []))
    next_url = (page.get("links") or {}).get("next")
    while next_url:
        page = client.get(next_url)
        items.extend(page.get("data", []))
        next_url = (page.get("links") or {}).get("next")
    return items


def find_tester_id(client: Client, email: str) -> str | None:
    needle = email.strip().lower()
    try:
        for tester in iter_collection(client, "/v1/betaTesters", {"filter[email]": email}):
            if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
                return tester["id"]
    except ApiError:
        pass
    # Fall back: scan team testers (Magpie/Neon may already have nawill@mac.com as d1d31281…).
    try:
        for tester in iter_collection(client, "/v1/betaTesters"):
            if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
                return tester["id"]
    except ApiError:
        pass
    try:
        for user in iter_collection(client, "/v1/users", {"filter[username]": email, "limit": "5"}):
            username = (user.get("attributes") or {}).get("username", "").strip().lower()
            if username == needle:
                for tester in iter_collection(client, "/v1/betaTesters"):
                    if (tester.get("attributes") or {}).get("email", "").strip().lower() == needle:
                        return tester["id"]
    except ApiError:
        pass
    return None


def list_group_testers(client: Client, group_id: str) -> list[dict[str, Any]]:
    """Return {id, email, state, inviteType} for every tester on the group."""
    rows: list[dict[str, Any]] = []
    try:
        testers = iter_collection(
            client,
            f"/v1/betaGroups/{group_id}/betaTesters",
            {"fields[betaTesters]": "email,state,inviteType,firstName,lastName"},
        )
    except ApiError:
        return rows
    for tester in testers:
        attrs = tester.get("attributes") or {}
        rows.append(
            {
                "id": tester.get("id", ""),
                "email": attrs.get("email") or "",
                "state": attrs.get("state") or "UNKNOWN",
                "inviteType": attrs.get("inviteType") or "UNKNOWN",
                "firstName": attrs.get("firstName") or "",
                "lastName": attrs.get("lastName") or "",
            }
        )
    return rows


def print_tester_roster(rows: list[dict[str, Any]], label: str) -> None:
    print(f"=== {label} ({len(rows)} tester(s)) ===")
    if not rows:
        print("(none)")
        return
    for row in rows:
        print(
            f"id={row['id']} email={row['email']} state={row['state']} "
            f"inviteType={row['inviteType']}"
        )


def tester_row_for_email(rows: list[dict[str, Any]], email: str) -> dict[str, Any] | None:
    needle = email.strip().lower()
    for row in rows:
        if row.get("email", "").strip().lower() == needle:
            return row
    return None


def add_tester(client: Client, group_id: str, email: str, first_name: str = "", last_name: str = "") -> str:
    """Add/link an internal tester by email. Prefer linking the existing Magpie/Neon record."""
    existing_id = find_tester_id(client, email)
    if existing_id:
        try:
            client.post(
                f"/v1/betaGroups/{group_id}/relationships/betaTesters",
                {"data": [{"type": "betaTesters", "id": existing_id}]},
            )
            return f"Linked existing tester id={existing_id} to the group."
        except ApiError as error:
            if error.status == 409:
                return f"Tester id={existing_id} already in the group."
            # Fall through to create if link failed for another reason.

    try:
        created = client.post(
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
        new_id = (created.get("data") or {}).get("id", "")
        return f"Tester created and added to the group id={new_id}."
    except ApiError as error:
        if error.status == 409:
            return link_existing_tester(client, group_id, email)
        return f"Could not add tester ({error.status}): {error.detail}"


def link_existing_tester(client: Client, group_id: str, email: str) -> str:
    tester_id = find_tester_id(client, email)
    if not tester_id:
        return "Tester record not found after conflict."
    try:
        client.post(
            f"/v1/betaGroups/{group_id}/relationships/betaTesters",
            {"data": [{"type": "betaTesters", "id": tester_id}]},
        )
        return f"Existing tester linked to the group id={tester_id}."
    except ApiError as error:
        if error.status == 409:
            return f"Tester already in the group id={tester_id}."
        return f"Could not link existing tester ({error.status}): {error.detail}"


def send_tester_invitation(client: Client, app_id: str, tester_id: str) -> str:
    """POST betaTesterInvitations — (re)send the TestFlight invite email for this app."""
    try:
        client.post(
            "/v1/betaTesterInvitations",
            {
                "data": {
                    "type": "betaTesterInvitations",
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}},
                        "betaTester": {"data": {"type": "betaTesters", "id": tester_id}},
                    },
                }
            },
        )
        return f"Invite email sent (betaTesterInvitations) for tester id={tester_id}."
    except ApiError as error:
        if error.status == 409:
            return f"Invite already outstanding/accepted for tester id={tester_id} (409)."
        return f"Could not send invite ({error.status}): {error.detail}"


def ensure_beta_app_information(
    client: Client,
    app_id: str,
    feedback_email: str,
    description: str,
    locale: str = "en-US",
) -> str:
    """Fill TestFlight 'Test Information' so invites are not blocked on missing beta app info."""
    notes: list[str] = []
    try:
        locs = iter_collection(client, f"/v1/apps/{app_id}/betaAppLocalizations")
    except ApiError as error:
        return f"Could not read betaAppLocalizations ({error.status}): {error.detail}"

    target = None
    for loc in locs:
        if (loc.get("attributes") or {}).get("locale") == locale:
            target = loc
            break
    if target is None and locs:
        target = locs[0]

    attrs = {"feedbackEmail": feedback_email, "description": description, "locale": locale}
    if target is None:
        try:
            client.post(
                "/v1/betaAppLocalizations",
                {
                    "data": {
                        "type": "betaAppLocalizations",
                        "attributes": attrs,
                        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                    }
                },
            )
            notes.append(f"Created betaAppLocalization ({locale}) with feedbackEmail + description.")
        except ApiError as error:
            notes.append(f"Could not create betaAppLocalization ({error.status}): {error.detail}")
    else:
        loc_id = target["id"]
        existing = target.get("attributes") or {}
        patch_attrs: dict[str, str] = {}
        if not (existing.get("feedbackEmail") or "").strip():
            patch_attrs["feedbackEmail"] = feedback_email
        elif existing.get("feedbackEmail") != feedback_email:
            patch_attrs["feedbackEmail"] = feedback_email
        if not (existing.get("description") or "").strip():
            patch_attrs["description"] = description
        if patch_attrs:
            try:
                client.patch(
                    f"/v1/betaAppLocalizations/{loc_id}",
                    {"data": {"type": "betaAppLocalizations", "id": loc_id, "attributes": patch_attrs}},
                )
                notes.append(f"Updated betaAppLocalization fields: {', '.join(patch_attrs)}.")
            except ApiError as error:
                notes.append(f"Could not patch betaAppLocalization ({error.status}): {error.detail}")
        else:
            notes.append("betaAppLocalization already has feedbackEmail + description.")

    # betaAppReviewDetail — contact block often required when ASC says Missing Beta App Information.
    try:
        detail_page = client.get(f"/v1/apps/{app_id}/betaAppReviewDetail")
        detail = detail_page.get("data")
    except ApiError as error:
        detail = None
        notes.append(f"betaAppReviewDetail read failed ({error.status}).")

    contact = {
        "contactEmail": feedback_email,
        "contactFirstName": "Nicholas",
        "contactLastName": "Will",
        # ASC rejects placeholder zeros; use a well-formed US number for the review contact block.
        "contactPhone": "+14085550100",
    }
    if detail is None:
        try:
            client.post(
                "/v1/betaAppReviewDetails",
                {
                    "data": {
                        "type": "betaAppReviewDetails",
                        "attributes": contact,
                        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                    }
                },
            )
            notes.append("Created betaAppReviewDetail contact block.")
        except ApiError as error:
            notes.append(f"Could not create betaAppReviewDetail ({error.status}): {error.detail}")
    else:
        detail_id = detail["id"]
        existing = detail.get("attributes") or {}
        patch = {k: v for k, v in contact.items() if not (existing.get(k) or "").strip()}
        if patch:
            try:
                client.patch(
                    f"/v1/betaAppReviewDetails/{detail_id}",
                    {"data": {"type": "betaAppReviewDetails", "id": detail_id, "attributes": patch}},
                )
                notes.append(f"Updated betaAppReviewDetail: {', '.join(patch)}.")
            except ApiError as error:
                notes.append(f"Could not patch betaAppReviewDetail ({error.status}): {error.detail}")
        else:
            notes.append("betaAppReviewDetail contact already set.")

    return " ".join(notes)


def describe_build_blockers(client: Client, build_id: str, attrs: dict[str, Any]) -> str:
    bits = [
        f"processingState={attrs.get('processingState')}",
        f"usesNonExemptEncryption={attrs.get('usesNonExemptEncryption')}",
    ]
    try:
        detail = client.get(f"/v1/builds/{build_id}/buildBetaDetail").get("data") or {}
        dattrs = detail.get("attributes") or {}
        bits.append(f"internalBuildState={dattrs.get('internalBuildState')}")
        bits.append(f"externalBuildState={dattrs.get('externalBuildState')}")
        bits.append(f"autoNotifyEnabled={dattrs.get('autoNotifyEnabled')}")
    except ApiError as error:
        bits.append(f"buildBetaDetail=error:{error.status}")
    return " ".join(bits)


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
    return len(list_group_testers(client, group_id))


def tester_present(client: Client, group_id: str, email: str) -> bool:
    return tester_row_for_email(list_group_testers(client, group_id), email) is not None


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
    feedback_email: str = "info@cinderandcrown.com",
) -> int:
    """Ensure group + testers, beta info, invite, compliance, attach, report."""
    app_id = require_app(client, bundle_id)
    print(f"ASC app resource id={app_id} (Trash Stack / Apple ID 6834995780).")

    group_id, created = ensure_internal_group(client, app_id, group_name)
    flags = group_access_flags(client, group_id)
    print(
        f"Internal group “{group_name}”: {'created' if created else 'already there'}. "
        f"hasAccessToAllBuilds={flags.get('hasAccessToAllBuilds')} isInternal={flags.get('isInternalGroup')}."
    )

    before = list_group_testers(client, group_id)
    print_tester_roster(before, "BEFORE")
    before_row = tester_row_for_email(before, tester_email) if tester_email else None
    if tester_email:
        if before_row:
            print(
                f"PRIMARY BEFORE: email={before_row['email']} state={before_row['state']} "
                f"inviteType={before_row['inviteType']} id={before_row['id']}"
            )
        else:
            print(f"PRIMARY BEFORE: email={tester_email} NOT on group")

    print(
        ensure_beta_app_information(
            client,
            app_id,
            feedback_email=feedback_email,
            description="Trash Stack — neon dumpster puzzle. Match materials, slam the press, recycle junk on the night shift.",
        )
    )

    # Prefer the Apple ID that actually owns TestFlight installs (nawill@mac.com).
    if tester_email:
        print(add_tester(client, group_id, tester_email, first_name="Nicholas", last_name="Will"))
    holder_msg, holder_email = add_account_holder(client, group_id)
    print(f"Account holder path: {holder_msg}")
    if holder_email:
        print(f"ASC account-holder username={holder_email}")

    after_add = list_group_testers(client, group_id)
    print_tester_roster(after_add, "AFTER ADD")
    primary = tester_row_for_email(after_add, tester_email) if tester_email else None
    invite_msg = "Invite skipped (no primary tester on group)."
    if primary:
        print(
            f"PRIMARY AFTER ADD: email={primary['email']} state={primary['state']} "
            f"inviteType={primary['inviteType']} id={primary['id']}"
        )
        if primary["state"] not in ("ACCEPTED", "INSTALLED"):
            invite_msg = send_tester_invitation(client, app_id, primary["id"])
        else:
            invite_msg = f"Invite not resent — state already {primary['state']}."
        print(invite_msg)
    elif tester_email:
        print(f"PRIMARY AFTER ADD: email={tester_email} still NOT on group")
        print(invite_msg)

    state = wait_for_build(client, app_id, version, build, timeout)
    found = find_build(client, app_id, version, build)
    if not found:
        print(f"Build {version} ({build}) is not listed in App Store Connect yet.")
        if state == "TIMED_OUT":
            return 0
        return 1

    build_id = found["id"]
    attrs = found.get("attributes") or {}
    print(f"Build {version} ({build}): {describe_build_blockers(client, build_id, attrs)}")
    print(set_export_compliance(client, build_id))
    print(attach_build_to_group(client, group_id, build_id))

    final = list_group_testers(client, group_id)
    print_tester_roster(final, "FINAL")
    final_row = tester_row_for_email(final, tester_email) if tester_email else None
    if final_row:
        print(
            f"PRIMARY FINAL: email={final_row['email']} state={final_row['state']} "
            f"inviteType={final_row['inviteType']} id={final_row['id']}"
        )
        # Resend once more if still not accepted after beta info + attach.
        if final_row["state"] not in ("ACCEPTED", "INSTALLED"):
            print(send_tester_invitation(client, app_id, final_row["id"]))
    elif tester_email:
        print(f"PRIMARY FINAL: email={tester_email} NOT on group — Nicholas will not see Trash Stack.")
        return 1

    if state == "VALID":
        print("Apple finished processing. The build is in TestFlight.")
        return 0
    if state == "TIMED_OUT":
        print("Apple is still processing. The build will appear in TestFlight when it finishes.")
        return 0
    print("Apple rejected the build during processing. The reason is in the email from App Store Connect.")
    return 1


# --- Game Center (config only — no submission / release) ---

LEADERBOARDS = [
    {
        "referenceName": "Endless High Score",
        "vendorId": "trashstack_endless",
        "defaultFormatter": "INTEGER",
        "submissionType": "BEST_SCORE",
        "scoreSortType": "DESC",
        "scoreRangeStart": "0",
        "scoreRangeEnd": "999999999",
        "locale": "en-US",
        "name": "Endless Night Shift",
        "formatter": "INTEGER",
    },
    {
        "referenceName": "Daily Dumpster",
        "vendorId": "trashstack_daily",
        "defaultFormatter": "INTEGER",
        "submissionType": "BEST_SCORE",
        "scoreSortType": "DESC",
        "scoreRangeStart": "0",
        "scoreRangeEnd": "999999999",
        "locale": "en-US",
        "name": "Daily Dumpster",
        "formatter": "INTEGER",
    },
    {
        "referenceName": "Weekly Tournament",
        "vendorId": "trashstack_weekly",
        "defaultFormatter": "INTEGER",
        "submissionType": "BEST_SCORE",
        "scoreSortType": "DESC",
        "scoreRangeStart": "0",
        "scoreRangeEnd": "999999999",
        "locale": "en-US",
        "name": "Weekly Tournament",
        "formatter": "INTEGER",
        "recurrenceRule": "FREQ=WEEKLY;INTERVAL=1",
    },
]

# Keep in sync with GameCore.AchievementID.allConfigured
ACHIEVEMENTS = [
    ("ts_first_recycle", "First Recycle", 5),
    ("ts_chain_5", "Chain Reaction", 10),
    ("ts_press_slam", "Press Operator", 5),
    ("ts_daily_clear", "Daily Dump Cleared", 5),
    ("ts_streak_7", "Week on the Job", 15),
    ("ts_snatch", "Sticky Fingers", 5),
    ("ts_tt_first_win", "First Trash Talk Win", 10),
    ("ts_tt_streak_3", "Trash Talk Streak ×3", 15),
    ("ts_tt_streak_5", "Trash Talk Streak ×5", 25),
    ("ts_four_clear", "Quad Clear", 10),
    ("ts_junk_10", "Junk Courier", 10),
    ("ts_junk_50", "Junk Tycoon", 20),
    ("ts_weekly_top10", "Weekly Top 10", 15),
    ("ts_weekly_champ", "Weekly Champion", 50),
    ("ts_score_10k", "Night Shift 10K", 10),
    ("ts_score_50k", "Night Shift 50K", 25),
    ("ts_beat_friend", "Beat a Friend", 10),
    ("ts_tt_rematch_win", "Rematch Revenge", 10),
    ("ts_near_miss", "Lip of the Bin", 5),
    ("cc_bandit_of_both_worlds", "Bandit of Both Worlds", 50),
]


def list_bundle_capabilities(client: Client, bundle_record_id: str) -> set[str]:
    # Relationship endpoint rejects `limit` (PARAMETER_ERROR.ILLEGAL).
    page = client.get(
        f"/v1/bundleIds/{bundle_record_id}/bundleIdCapabilities",
        {"fields[bundleIdCapabilities]": "capabilityType"},
    )
    out: set[str] = set()
    for row in page.get("data", []):
        cap = (row.get("attributes") or {}).get("capabilityType")
        if cap:
            out.add(cap)
    return out


def ensure_bundle_game_center_capability(client: Client, bundle_identifier: str) -> bool:
    """Enable GAME_CENTER on the App ID so provisioning profiles include the entitlement.

    Idempotent. Returns True when the capability is present after this call.
    Automatic App Store export (`-allowProvisioningUpdates`) regenerates the
    profile with Game Center once the App ID has the capability.
    """
    bundle = find_bundle(client, bundle_identifier)
    if not bundle:
        raise SystemExit(f"No App ID for {bundle_identifier}. Run ensure-bundle-id first.")
    caps = list_bundle_capabilities(client, bundle["id"])
    if "GAME_CENTER" in caps:
        print(f"App ID {bundle_identifier}: GAME_CENTER capability already enabled.")
        return True
    try:
        client.post(
            "/v1/bundleIdCapabilities",
            {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": "GAME_CENTER"},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                    },
                }
            },
        )
        print(f"App ID {bundle_identifier}: enabled GAME_CENTER capability.")
    except ApiError as error:
        # Concurrent enable or already-on → treat as success after re-check.
        if error.status not in (409, 422):
            raise
        print(f"App ID {bundle_identifier}: GAME_CENTER enable raced ({error.status}); re-checking.")
    caps = list_bundle_capabilities(client, bundle["id"])
    if "GAME_CENTER" not in caps:
        raise SystemExit(f"App ID {bundle_identifier}: GAME_CENTER capability still missing after enable.")
    print(f"App ID {bundle_identifier}: GAME_CENTER confirmed on App ID (profiles will pick it up on export).")
    return True


def ensure_game_center_detail(client: Client, app_id: str) -> str:
    """Enable Game Center for the app; return gameCenterDetail id. Idempotent."""
    try:
        existing = client.get(
            f"/v1/apps/{app_id}/gameCenterDetail",
            {"fields[gameCenterDetails]": "challengeEnabled"},
        )
        data = existing.get("data")
        if isinstance(data, dict) and data.get("id"):
            print(f"Game Center detail already present ({data['id']}).")
            return data["id"]
    except ApiError as error:
        # 404 / empty relationship → create; other errors bubble.
        if error.status != 404:
            raise
    try:
        created = client.post(
            "/v1/gameCenterDetails",
            {
                "data": {
                    "type": "gameCenterDetails",
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}},
                    },
                }
            },
        )
        detail_id = created["data"]["id"]
        print(f"Enabled Game Center detail ({detail_id}).")
        return detail_id
    except ApiError as error:
        if error.status in (409, 422):
            # Already enabled — re-fetch.
            existing = client.get(
                f"/v1/apps/{app_id}/gameCenterDetail",
                {"fields[gameCenterDetails]": "challengeEnabled"},
            )
            data = existing.get("data")
            if isinstance(data, dict) and data.get("id"):
                print(f"Game Center detail already present ({data['id']}).")
                return data["id"]
        raise


def list_leaderboard_vendor_ids(client: Client, detail_id: str) -> set[str]:
    page = client.get(
        f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboards",
        {"limit": "200", "fields[gameCenterLeaderboards]": "referenceName,vendorIdentifier"},
    )
    out: set[str] = set()
    for row in page.get("data", []):
        vid = (row.get("attributes") or {}).get("vendorIdentifier")
        if vid:
            out.add(vid)
    return out


def ensure_leaderboards(client: Client, detail_id: str) -> None:
    have = list_leaderboard_vendor_ids(client, detail_id)
    for spec in LEADERBOARDS:
        if spec["vendorId"] in have:
            print(f"Leaderboard {spec['vendorId']}: already there.")
            continue
        attributes = {
            "defaultFormatter": spec["defaultFormatter"],
            "referenceName": spec["referenceName"],
            "submissionType": spec["submissionType"],
            "scoreSortType": spec["scoreSortType"],
            "scoreRangeStart": spec["scoreRangeStart"],
            "scoreRangeEnd": spec["scoreRangeEnd"],
            "vendorIdentifier": spec["vendorId"],
        }
        # Recurring weekly when supported by the API version.
        if spec.get("recurrenceRule"):
            attributes["recurrenceStartDate"] = "2026-01-05T00:00:00.000Z"
            attributes["recurrenceDuration"] = "P7D"
            attributes["recurrenceRule"] = spec["recurrenceRule"]
        body = {
            "data": {
                "type": "gameCenterLeaderboards",
                "attributes": attributes,
                "relationships": {
                    "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail_id}},
                },
            }
        }
        try:
            created = client.post("/v1/gameCenterLeaderboards", body)
            lb_id = created["data"]["id"]
            print(f"Leaderboard {spec['vendorId']}: created ({lb_id}).")
            try:
                client.post(
                    "/v1/gameCenterLeaderboardLocalizations",
                    {
                        "data": {
                            "type": "gameCenterLeaderboardLocalizations",
                            "attributes": {
                                "locale": spec["locale"],
                                "name": spec["name"],
                                "formatterOverride": spec["formatter"],
                            },
                            "relationships": {
                                "gameCenterLeaderboard": {
                                    "data": {"type": "gameCenterLeaderboards", "id": lb_id}
                                }
                            },
                        }
                    },
                )
            except ApiError as loc_error:
                if loc_error.status not in (409, 422):
                    raise
                print(f"Leaderboard {spec['vendorId']}: localization already present.")
        except ApiError as error:
            # Recurrence fields may be rejected on older API shapes — retry without them.
            if any(k in attributes for k in ("recurrenceStartDate", "recurrenceDuration", "recurrenceRule")) and error.status in (
                400,
                409,
                422,
            ):
                for key in ("recurrenceStartDate", "recurrenceDuration", "recurrenceRule"):
                    attributes.pop(key, None)
                body["data"]["attributes"] = attributes
                try:
                    created = client.post("/v1/gameCenterLeaderboards", body)
                    print(f"Leaderboard {spec['vendorId']}: created without recurrence ({created['data']['id']}).")
                except ApiError as retry_error:
                    if retry_error.status in (409, 422):
                        print(f"Leaderboard {spec['vendorId']}: already there (conflict).")
                    else:
                        raise
            elif error.status in (409, 422):
                print(f"Leaderboard {spec['vendorId']}: already there (conflict).")
            else:
                raise


def list_achievement_refs(client: Client, detail_id: str) -> set[str]:
    page = client.get(
        f"/v1/gameCenterDetails/{detail_id}/gameCenterAchievements",
        {"limit": "200", "fields[gameCenterAchievements]": "referenceName,vendorIdentifier"},
    )
    out: set[str] = set()
    for row in page.get("data", []):
        vid = (row.get("attributes") or {}).get("vendorIdentifier")
        if vid:
            out.add(vid)
    return out


def ensure_achievements(client: Client, detail_id: str) -> None:
    have = list_achievement_refs(client, detail_id)
    for vendor, name, points in ACHIEVEMENTS:
        if vendor in have:
            print(f"Achievement {vendor}: already there.")
            continue
        try:
            created = client.post(
                "/v1/gameCenterAchievements",
                {
                    "data": {
                        "type": "gameCenterAchievements",
                        "attributes": {
                            "referenceName": name,
                            "vendorIdentifier": vendor,
                            "points": points,
                            "showBeforeEarned": True,
                            "repeatable": False,
                        },
                        "relationships": {
                            "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail_id}},
                        },
                    }
                },
            )
            ach_id = created["data"]["id"]
            print(f"Achievement {vendor}: created ({ach_id}).")
            try:
                client.post(
                    "/v1/gameCenterAchievementLocalizations",
                    {
                        "data": {
                            "type": "gameCenterAchievementLocalizations",
                            "attributes": {
                                "locale": "en-US",
                                "name": name,
                                "beforeEarnedDescription": f"Earn: {name}",
                                "afterEarnedDescription": f"Unlocked: {name}",
                            },
                            "relationships": {
                                "gameCenterAchievement": {
                                    "data": {"type": "gameCenterAchievements", "id": ach_id}
                                }
                            },
                        }
                    },
                )
            except ApiError as loc_error:
                if loc_error.status not in (409, 422):
                    raise
                print(f"Achievement {vendor}: localization already present.")
        except ApiError as error:
            if error.status in (409, 422):
                print(f"Achievement {vendor}: already there (conflict).")
            else:
                raise


def ensure_game_center_group(client: Client, group_name: str = "Cinder Crown Bandit Universe") -> str | None:
    """Create or find a Game Center group for cross-game achievements (Trash Stack + NCB)."""
    page = client.get("/v1/gameCenterGroups", {"limit": "200"})
    for row in page.get("data", []):
        if (row.get("attributes") or {}).get("referenceName") == group_name:
            print(f"Game Center group already present ({row['id']}).")
            return row["id"]
    try:
        created = client.post(
            "/v1/gameCenterGroups",
            {
                "data": {
                    "type": "gameCenterGroups",
                    "attributes": {"referenceName": group_name},
                }
            },
        )
        gid = created["data"]["id"]
        print(f"Game Center group created ({gid}).")
        return gid
    except ApiError as error:
        print(f"Game Center group skipped: {error}")
        return None


def configure_game_center(client: Client, bundle_id: str) -> int:
    """Idempotent Game Center setup for TestFlight (config only — no release).

    1. Enable GAME_CENTER on the App ID (so cloud-managed profiles include it).
    2. Enable gameCenterDetail + create missing leaderboards / achievements.
    """
    ensure_bundle_game_center_capability(client, bundle_id)
    app_id = find_app(client, bundle_id)
    if not app_id:
        print(
            f"No ASC app record for {bundle_id} yet — App ID GAME_CENTER is on; "
            "leaderboards/achievements will be created on the next run after the app exists."
        )
        print("No App Store version was submitted or released.")
        return 0
    detail_id = ensure_game_center_detail(client, app_id)
    ensure_leaderboards(client, detail_id)
    ensure_achievements(client, detail_id)
    ensure_game_center_group(client)
    print(
        "Game Center config done (App ID capability + detail + leaderboards + achievements). "
        "No App Store version was submitted or released."
    )
    return 0


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
    distribute.add_argument("--feedback-email", default="info@cinderandcrown.com")
    distribute.add_argument("--timeout", type=float, default=30 * 60)

    list_testers = commands.add_parser("list-testers", help="list email/state/inviteType on an internal group")
    list_testers.add_argument("--bundle-id", required=True)
    list_testers.add_argument("--name", required=True)

    check_app = commands.add_parser("check-app", help="exit 0 if the ASC app record exists, else print create fields")
    check_app.add_argument("--bundle-id", required=True)

    gc = commands.add_parser(
        "configure-game-center",
        help="enable Game Center, create leaderboards + achievements (config only, no release)",
    )
    gc.add_argument("--bundle-id", required=True)

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
        if options.command == "list-testers":
            app_id = require_app(client, options.bundle_id)
            group_id, _ = ensure_internal_group(client, app_id, options.name)
            print_tester_roster(list_group_testers(client, group_id), options.name)
            return 0
        if options.command == "distribute-build":
            return distribute_build(
                client,
                options.bundle_id,
                options.name,
                options.version,
                options.build,
                options.tester_email or None,
                options.timeout,
                feedback_email=options.feedback_email,
            )
        if options.command == "configure-game-center":
            return configure_game_center(client, options.bundle_id)
    except ApiError as error:
        print(f"{error}")
        if error.status in (401, 403):
            print("The key was refused. Check ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, and the key's role.")
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
