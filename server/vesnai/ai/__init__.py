"""AI services: vector index, enrichment, RAG chat, web-search agent, self-tuning.

All heavyweight/non-deterministic capabilities are accessed through the provider
protocols in :mod:`vesnai.providers`, so every service here is testable with the
deterministic fakes and runs fully offline by default.
"""
