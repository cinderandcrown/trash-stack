#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Unit tests for appstore_connect.py (no network)."""

from __future__ import annotations

import json
import unittest
from typing import Any
from unittest import mock

import appstore_connect as asc


class FakeSend:
    def __init__(self, responses: dict[tuple[str, str], tuple[int, Any]]):
        self.responses = responses
        self.calls: list[tuple[str, str, Any]] = []

    def __call__(self, method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
        path = url.split("?", 1)[0].replace(asc.API, "")
        self.calls.append((method, path, json.loads(body) if body else None))
        status, payload = self.responses[(method, path)]
        return status, json.dumps(payload).encode()


class TokenTests(unittest.TestCase):
    def test_make_token_shape(self) -> None:
        # Minimal DER SEQUENCE of two 32-byte INTEGER R/S values (openssl-style).
        def der_sig(_message: bytes) -> bytes:
            def integer(value: bytes) -> bytes:
                body = b"\x00" + value  # keep sign bit clear
                return b"\x02" + bytes([len(body)]) + body

            r = integer(b"\x11" * 32)
            s = integer(b"\x22" * 32)
            seq = r + s
            return b"\x30" + bytes([len(seq)]) + seq

        token = asc.make_token("KEY", "ISS", der_sig, now=1_700_000_000)
        parts = token.split(".")
        self.assertEqual(len(parts), 3)


class BundleIdTests(unittest.TestCase):
    def test_ensure_bundle_id_already_there(self) -> None:
        send = FakeSend(
            {
                ("GET", "/v1/bundleIds"): (
                    200,
                    {
                        "data": [
                            {
                                "id": "BID1",
                                "type": "bundleIds",
                                "attributes": {"identifier": "com.cinderandcrown.magpie", "name": "MAGPIE"},
                            }
                        ]
                    },
                )
            }
        )
        client = asc.Client(token=lambda: "t", send=send)
        bid, created = asc.ensure_bundle_id(client, "com.cinderandcrown.magpie", "MAGPIE")
        self.assertEqual(bid, "BID1")
        self.assertFalse(created)

    def test_ensure_bundle_id_creates(self) -> None:
        send = FakeSend(
            {
                ("GET", "/v1/bundleIds"): (200, {"data": []}),
                ("POST", "/v1/bundleIds"): (
                    201,
                    {"data": {"id": "NEWID", "type": "bundleIds", "attributes": {"identifier": "com.cinderandcrown.magpie"}}},
                ),
            }
        )
        client = asc.Client(token=lambda: "t", send=send)
        bid, created = asc.ensure_bundle_id(client, "com.cinderandcrown.magpie", "MAGPIE")
        self.assertEqual(bid, "NEWID")
        self.assertTrue(created)
        post = [c for c in send.calls if c[0] == "POST"][0]
        self.assertEqual(post[2]["data"]["attributes"]["platform"], "IOS")


class AppLookupTests(unittest.TestCase):
    def test_find_app_missing(self) -> None:
        send = FakeSend({("GET", "/v1/apps"): (200, {"data": []})})
        client = asc.Client(token=lambda: "t", send=send)
        self.assertIsNone(asc.find_app(client, "com.cinderandcrown.magpie"))


class WaitBuildTests(unittest.TestCase):
    def test_wait_valid(self) -> None:
        states = iter(
            [
                (200, {"data": []}),
                (200, {"data": [{"attributes": {"processingState": "PROCESSING"}}]}),
                (200, {"data": [{"attributes": {"processingState": "VALID"}}]}),
            ]
        )

        def send(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
            status, payload = next(states)
            return status, json.dumps(payload).encode()

        client = asc.Client(token=lambda: "t", send=send)
        sleeps: list[float] = []
        clock = {"t": 0.0}

        def now() -> float:
            return clock["t"]

        def sleep(seconds: float) -> None:
            sleeps.append(seconds)
            clock["t"] += seconds

        state = asc.wait_for_build(client, "APP", "0.1.0", "1.1", timeout=120, sleep=sleep, now=now)
        self.assertEqual(state, "VALID")
        self.assertTrue(sleeps)


if __name__ == "__main__":
    unittest.main()
