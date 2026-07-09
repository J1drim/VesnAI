"""Build a knowledge graph from OKF cross-links.

Nodes are concepts; edges are links between them. Broken links (targets not in
the bundle) are tolerated and simply omitted from edges. Supports filtering by
tag, type and origin for the client's graph view.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from vesnai.okf.conformance import resolve_link
from vesnai.okf.model import Concept, Origin


@dataclass
class GraphNode:
    id: str
    title: str
    type: str | None
    origin: str
    tags: list[str] = field(default_factory=list)


@dataclass
class GraphEdge:
    source: str
    target: str


@dataclass
class Graph:
    nodes: list[GraphNode] = field(default_factory=list)
    edges: list[GraphEdge] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "nodes": [n.__dict__ for n in self.nodes],
            "edges": [e.__dict__ for e in self.edges],
        }


def build_graph(
    concepts: dict[str, Concept],
    *,
    tag: str | None = None,
    tags: list[str] | None = None,
    type: str | None = None,
    origin: Origin | None = None,
) -> Graph:
    tag_set = set(tags or [])
    if tag is not None:
        tag_set.add(tag)

    def keep(c: Concept) -> bool:
        if tag_set and not tag_set.intersection(c.tags):
            return False
        if type is not None and c.type != type:
            return False
        if origin is not None and c.origin is not origin:
            return False
        return True

    selected = {rel: c for rel, c in concepts.items() if keep(c)}
    known = set(selected.keys())

    nodes = [
        GraphNode(
            id=rel,
            title=c.title or rel,
            type=c.type,
            origin=c.origin.value,
            tags=c.tags,
        )
        for rel, c in selected.items()
    ]

    edges: list[GraphEdge] = []
    seen: set[tuple[str, str]] = set()
    for rel, c in selected.items():
        candidates = [(h, True) for h in c.explicit_links()] + [
            (h, False) for h in c.body_links()
        ]
        for href, explicit in candidates:
            if "://" in href:
                continue
            target = resolve_link(rel, href, explicit=explicit)
            if target in known and target != rel and (rel, target) not in seen:
                seen.add((rel, target))
                edges.append(GraphEdge(source=rel, target=target))
    return Graph(nodes=nodes, edges=edges)
