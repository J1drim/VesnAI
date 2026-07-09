"""Turn context (location block for chat)."""

from __future__ import annotations

from vesnai.ai.turn_context import LocationContext, TurnContext, build_location_block


def test_location_context_from_dict():
    loc = LocationContext.from_dict(
        {
            "lat": 52.23,
            "lon": 21.01,
            "label": "Warsaw, Poland",
            "accuracy_m": 120.0,
            "captured_at": "2026-06-30T12:00:00Z",
        }
    )
    assert loc is not None
    assert loc.label == "Warsaw, Poland"
    assert loc.accuracy_m == 120.0


def test_location_context_from_dict_rejects_invalid():
    assert LocationContext.from_dict({}) is None
    assert LocationContext.from_dict({"lat": "x", "lon": 1}) is None


def test_build_location_block_includes_label_not_raw_coords_by_default():
    block = build_location_block(
        LocationContext(lat=52.2297, lon=21.0122, label="Warsaw")
    )
    assert "Warsaw" in block
    assert "52.22970" in block
    assert "turn context" in block.lower()


def test_turn_context_from_location_dict():
    ctx = TurnContext.from_location_dict(
        {"lat": 1.0, "lon": 2.0, "label": "Somewhere"},
        language="pl",
    )
    assert ctx.location is not None
    assert ctx.language == "pl"


def test_build_system_content_includes_location_block():
    from vesnai.ai.chat import build_system_content

    loc_block = build_location_block(
        LocationContext(lat=52.23, lon=21.01, label="Warsaw, Poland")
    )
    with_loc = build_system_content(
        rag="(none)", memory_block="", language="en", location_block=loc_block
    )
    without_loc = build_system_content(
        rag="(none)", memory_block="", language="en", location_block=""
    )
    assert "Warsaw, Poland" in with_loc
    assert "Tool composition:" in with_loc
    assert "Warsaw, Poland" not in without_loc
