"""Per-turn context passed from the client (location, etc.)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class LocationContext:
    lat: float
    lon: float
    label: str | None = None
    accuracy_m: float | None = None
    captured_at: str | None = None

    @classmethod
    def from_dict(cls, raw: dict | None) -> LocationContext | None:
        if not raw:
            return None
        try:
            lat = float(raw["lat"])
            lon = float(raw["lon"])
        except (KeyError, TypeError, ValueError):
            return None
        accuracy = raw.get("accuracy_m")
        return cls(
            lat=lat,
            lon=lon,
            label=raw.get("label") or None,
            accuracy_m=float(accuracy) if accuracy is not None else None,
            captured_at=raw.get("captured_at") or None,
        )

    def to_dict(self) -> dict:
        payload: dict = {"lat": self.lat, "lon": self.lon}
        if self.label:
            payload["label"] = self.label
        if self.accuracy_m is not None:
            payload["accuracy_m"] = self.accuracy_m
        if self.captured_at:
            payload["captured_at"] = self.captured_at
        return payload


@dataclass
class TurnContext:
    location: LocationContext | None = None
    language: str | None = None

    @classmethod
    def from_location_dict(cls, raw: dict | None, *, language: str | None = None) -> TurnContext:
        return cls(location=LocationContext.from_dict(raw), language=language)


def build_location_block(location: LocationContext | None) -> str:
    if location is None:
        return ""
    label = (location.label or "").strip()
    acc = location.accuracy_m
    acc_note = f" (±{int(acc)}m)" if acc is not None else ""
    lines = [
        "\n\nUser shared approximate location (turn context — not stored in chat history):",
    ]
    if label:
        lines.append(f"- Place: {label}")
    lines.append(f"- Coordinates: {location.lat:.5f}, {location.lon:.5f}{acc_note}")
    if location.captured_at:
        lines.append(f"- Captured: {location.captured_at}")
    lines.append(
        "Use for local/nearby/current requests. Do not cite raw coordinates unless asked."
    )
    return "\n".join(lines)
