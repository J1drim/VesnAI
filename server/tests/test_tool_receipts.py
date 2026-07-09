"""Tool receipt ledger tests."""

from __future__ import annotations

from vesnai.ai.tool_receipts import ToolReceiptLedger, make_receipt


def test_receipt_ledger_records_turn(tmp_path):
    ledger = ToolReceiptLedger(tmp_path)
    ts = "2026-01-01T00:00:00+00:00"
    ledger.append(
        "sess-1",
        make_receipt(
            turn_id="turn-1",
            tool="generate_image",
            arguments={"prompt": "cat"},
            result={"status": "queued", "job_id": "j1"},
            ts=ts,
        ),
    )
    batch = ledger.for_turn("sess-1", "turn-1")
    assert len(batch.receipts) == 1
    assert batch.receipts[0].tool == "generate_image"
    assert batch.receipts[0].status == "queued"
    assert batch.has_succeeded("generate_image")


def test_receipt_failed_status(tmp_path):
    _ledger = ToolReceiptLedger(tmp_path)
    receipt = make_receipt(
        turn_id="t1",
        tool="web_search",
        arguments={"query": "x"},
        result={"error": "offline"},
        ts="2026-01-01T00:00:00+00:00",
    )
    assert receipt.status == "failed"
