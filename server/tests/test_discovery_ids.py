"""mDNS service-info construction and ID/slug helpers."""

from __future__ import annotations

from vesnai.discovery import SERVICE_TYPE, build_service_info
from vesnai.ids import slugify, uuid7


def test_build_service_info():
    info = build_service_info("VesnAI", "127.0.0.1", 8443, https=True)
    assert info.type == SERVICE_TYPE
    assert info.port == 8443
    assert info.properties[b"scheme"] == b"https"


def test_uuid7_is_time_ordered():
    a = uuid7(1000)
    b = uuid7(2000)
    assert a < b
    assert len(a) == 36 and a[14] == "7"  # version nibble


def test_slugify():
    assert slugify("Hello, World!") == "hello-world"
    assert slugify("   ") == "note"
    assert len(slugify("x" * 200)) <= 60
