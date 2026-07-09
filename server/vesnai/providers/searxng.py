"""SearXNG-backed web search provider (optional, self-hosted meta-search).

SearXNG is AGPL-3.0 and self-hosted, so it stays within the local/privacy model.
Uses its JSON API for search and fetches readable text with httpx.
"""

from __future__ import annotations

import httpx

from vesnai.ai.web_safety import fetch_text
from vesnai.providers.base import SearchResult


class SearxngSearchProvider:
    def __init__(self, base_url: str = "http://127.0.0.1:8888", timeout: float = 10.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def search(
        self, query: str, *, language: str = "en", max_results: int = 10
    ) -> list[SearchResult]:
        params = {"q": query, "format": "json", "language": language}
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(f"{self.base_url}/search", params=params)
            resp.raise_for_status()
            data = resp.json()
        results = []
        for item in data.get("results", [])[:max_results]:
            results.append(
                SearchResult(
                    title=item.get("title", ""),
                    url=item.get("url", ""),
                    snippet=item.get("content", ""),
                    language=language,
                )
            )
        return results

    def fetch(self, url: str) -> str:
        return fetch_text(url, timeout=self.timeout)
