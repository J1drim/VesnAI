"""OKF (Open Knowledge Format v0.1) library.

An OKF bundle is a directory of Markdown files. Each non-reserved file is a
*concept*: a YAML frontmatter block (delimited by `---`) followed by a Markdown
body. The only required frontmatter field is ``type``. Reserved filenames
``index.md`` and ``log.md`` need not carry a type.

This package provides parsing/serialization (:mod:`vesnai.okf.parse`), the concept
data model (:mod:`vesnai.okf.model`), conformance checking (:mod:`vesnai.okf.conformance`),
and a git-versioned on-disk bundle store (:mod:`vesnai.okf.bundle`).
"""

from vesnai.okf.conformance import ConformanceIssue, Severity, check_bundle, check_concept
from vesnai.okf.model import RESERVED_FILENAMES, Concept, Origin
from vesnai.okf.parse import OKFParseError, dump_concept, parse_concept

__all__ = [
    "Concept",
    "Origin",
    "RESERVED_FILENAMES",
    "OKFParseError",
    "parse_concept",
    "dump_concept",
    "ConformanceIssue",
    "Severity",
    "check_concept",
    "check_bundle",
]
