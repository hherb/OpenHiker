#!/usr/bin/env python3
"""
Code statistics script for the OpenHiker multi-platform project.

Analyzes source code files across all platforms (iOS, watchOS, macOS, Android, Shared)
and produces statistics on:
- Lines of code vs docstrings/comments vs blank lines per platform
- Documentation line counts
- File length distribution and statistics
"""

import os
import re
import sys
import argparse
from pathlib import Path
from dataclasses import dataclass, field
from collections import defaultdict
from typing import Optional


@dataclass
class FileStats:
    """Statistics for a single source file."""

    path: str
    total_lines: int = 0
    code_lines: int = 0
    comment_lines: int = 0
    docstring_lines: int = 0
    blank_lines: int = 0
    language: str = ""


@dataclass
class PlatformStats:
    """Aggregated statistics for one platform/project."""

    name: str
    files: list = field(default_factory=list)

    @property
    def total_files(self) -> int:
        return len(self.files)

    @property
    def total_lines(self) -> int:
        return sum(f.total_lines for f in self.files)

    @property
    def code_lines(self) -> int:
        return sum(f.code_lines for f in self.files)

    @property
    def comment_lines(self) -> int:
        return sum(f.comment_lines for f in self.files)

    @property
    def docstring_lines(self) -> int:
        return sum(f.docstring_lines for f in self.files)

    @property
    def blank_lines(self) -> int:
        return sum(f.blank_lines for f in self.files)

    @property
    def file_lengths(self) -> list:
        return sorted(f.total_lines for f in self.files)

    def percentile(self, p: float) -> int:
        """Return the p-th percentile of file lengths."""
        lengths = self.file_lengths
        if not lengths:
            return 0
        idx = int(len(lengths) * p / 100)
        idx = min(idx, len(lengths) - 1)
        return lengths[idx]

    @property
    def avg_file_length(self) -> float:
        if not self.files:
            return 0.0
        return self.total_lines / len(self.files)

    @property
    def min_file_length(self) -> int:
        return min((f.total_lines for f in self.files), default=0)

    @property
    def max_file_length(self) -> int:
        return max((f.total_lines for f in self.files), default=0)

    @property
    def median_file_length(self) -> int:
        return self.percentile(50)


# --- Language-specific line classifiers ---


def classify_swift_lines(lines: list[str]) -> FileStats:
    """Classify lines in a Swift file into code, comments, docstrings, blanks."""
    stats = FileStats(path="", language="Swift")
    stats.total_lines = len(lines)
    in_block_comment = False
    in_doc_block = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            stats.blank_lines += 1
            continue

        # Block comment handling
        if in_block_comment or in_doc_block:
            if in_doc_block:
                stats.docstring_lines += 1
            else:
                stats.comment_lines += 1
            if "*/" in stripped:
                in_block_comment = False
                in_doc_block = False
            continue

        # Start of doc comment block: /** ... */
        if stripped.startswith("/**"):
            in_doc_block = True
            stats.docstring_lines += 1
            if "*/" in stripped[3:]:
                in_doc_block = False
            continue

        # Start of regular block comment: /* ... */
        if stripped.startswith("/*"):
            in_block_comment = True
            stats.comment_lines += 1
            if "*/" in stripped[2:]:
                in_block_comment = False
            continue

        # Doc line comment: /// ...
        if stripped.startswith("///"):
            stats.docstring_lines += 1
            continue

        # Regular line comment: // ...
        if stripped.startswith("//"):
            stats.comment_lines += 1
            continue

        stats.code_lines += 1

    return stats


def classify_kotlin_lines(lines: list[str]) -> FileStats:
    """Classify lines in a Kotlin file into code, comments, docstrings, blanks."""
    stats = FileStats(path="", language="Kotlin")
    stats.total_lines = len(lines)
    in_block_comment = False
    in_doc_block = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            stats.blank_lines += 1
            continue

        if in_block_comment or in_doc_block:
            if in_doc_block:
                stats.docstring_lines += 1
            else:
                stats.comment_lines += 1
            if "*/" in stripped:
                in_block_comment = False
                in_doc_block = False
            continue

        if stripped.startswith("/**"):
            in_doc_block = True
            stats.docstring_lines += 1
            if "*/" in stripped[3:]:
                in_doc_block = False
            continue

        if stripped.startswith("/*"):
            in_block_comment = True
            stats.comment_lines += 1
            if "*/" in stripped[2:]:
                in_block_comment = False
            continue

        # KDoc line comments
        if stripped.startswith("///"):
            stats.docstring_lines += 1
            continue

        if stripped.startswith("//"):
            stats.comment_lines += 1
            continue

        stats.code_lines += 1

    return stats


def classify_python_lines(lines: list[str]) -> FileStats:
    """Classify lines in a Python file into code, comments, docstrings, blanks."""
    stats = FileStats(path="", language="Python")
    stats.total_lines = len(lines)
    in_docstring = False
    docstring_delimiter = None

    for line in lines:
        stripped = line.strip()

        if not stripped:
            stats.blank_lines += 1
            continue

        # Inside a docstring
        if in_docstring:
            stats.docstring_lines += 1
            if docstring_delimiter in stripped:
                in_docstring = False
                docstring_delimiter = None
            continue

        # Start of a docstring
        if stripped.startswith('"""') or stripped.startswith("'''"):
            delimiter = stripped[:3]
            # Single-line docstring
            if stripped.count(delimiter) >= 2 and len(stripped) > 3:
                stats.docstring_lines += 1
                continue
            in_docstring = True
            docstring_delimiter = delimiter
            stats.docstring_lines += 1
            continue

        if stripped.startswith("#"):
            stats.comment_lines += 1
            continue

        stats.code_lines += 1

    return stats


def classify_xml_lines(lines: list[str]) -> FileStats:
    """Classify lines in an XML file into code, comments, blanks."""
    stats = FileStats(path="", language="XML")
    stats.total_lines = len(lines)
    in_comment = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            stats.blank_lines += 1
            continue

        if in_comment:
            stats.comment_lines += 1
            if "-->" in stripped:
                in_comment = False
            continue

        if stripped.startswith("<!--"):
            stats.comment_lines += 1
            if "-->" not in stripped[4:]:
                in_comment = True
            continue

        stats.code_lines += 1

    return stats


def classify_markdown_lines(lines: list[str]) -> FileStats:
    """Classify lines in a Markdown file (all lines count as documentation)."""
    stats = FileStats(path="", language="Markdown")
    stats.total_lines = len(lines)
    for line in lines:
        if line.strip():
            stats.docstring_lines += 1  # docs count as docstring_lines for markdown
        else:
            stats.blank_lines += 1
    return stats


def classify_yaml_lines(lines: list[str]) -> FileStats:
    """Classify lines in a YAML file."""
    stats = FileStats(path="", language="YAML")
    stats.total_lines = len(lines)
    for line in lines:
        stripped = line.strip()
        if not stripped:
            stats.blank_lines += 1
        elif stripped.startswith("#"):
            stats.comment_lines += 1
        else:
            stats.code_lines += 1
    return stats


def classify_generic_lines(lines: list[str], language: str) -> FileStats:
    """Fallback classifier for other file types."""
    stats = FileStats(path="", language=language)
    stats.total_lines = len(lines)
    for line in lines:
        stripped = line.strip()
        if not stripped:
            stats.blank_lines += 1
        elif stripped.startswith("//") or stripped.startswith("#"):
            stats.comment_lines += 1
        else:
            stats.code_lines += 1
    return stats


# --- File extension to classifier mapping ---

CLASSIFIERS = {
    ".swift": classify_swift_lines,
    ".kt": classify_kotlin_lines,
    ".kts": classify_kotlin_lines,
    ".py": classify_python_lines,
    ".xml": classify_xml_lines,
    ".md": classify_markdown_lines,
    ".yml": classify_yaml_lines,
    ".yaml": classify_yaml_lines,
}

LANGUAGE_NAMES = {
    ".swift": "Swift",
    ".kt": "Kotlin",
    ".kts": "Gradle KTS",
    ".py": "Python",
    ".xml": "XML",
    ".md": "Markdown",
    ".yml": "YAML",
    ".yaml": "YAML",
    ".toml": "TOML",
    ".properties": "Properties",
    ".json": "JSON",
    ".entitlements": "Entitlements",
    ".plist": "Plist",
}

# Directories to skip entirely
SKIP_DIRS = {
    ".git",
    ".gradle",
    ".idea",
    "build",
    "DerivedData",
    "Pods",
    ".build",
    "__pycache__",
    "node_modules",
    ".claude",
    "xcuserdata",
    "xcshareddata",
    "Assets.xcassets",
    "WatchAssets.xcassets",
    "MacAssets.xcassets",
    "Preview Content",
    "Screenshots",
}

# Extensions to analyze (source code + docs)
SOURCE_EXTENSIONS = {".swift", ".kt", ".kts", ".py"}
DOC_EXTENSIONS = {".md"}
CONFIG_EXTENSIONS = {".xml", ".yml", ".yaml", ".toml", ".properties", ".json"}


def detect_platform(filepath: str, root: str) -> str:
    """Determine which platform a file belongs to based on its path."""
    rel = os.path.relpath(filepath, root)
    parts = Path(rel).parts

    if not parts:
        return "Root"

    first = parts[0]

    if first == "OpenHiker iOS":
        return "iOS"
    elif first == "OpenHiker watchOS":
        return "watchOS"
    elif first == "OpenHiker macOS":
        return "macOS"
    elif first == "OpenHikerAndroid":
        # Distinguish app vs core module
        if len(parts) > 1 and parts[1] == "core":
            return "Android Core"
        elif len(parts) > 1 and parts[1] == "app":
            return "Android App"
        else:
            return "Android (config)"
    elif first == "Shared":
        return "Shared (Apple)"
    elif first == "OpenHikerTests":
        return "Tests"
    elif first == "docs":
        return "Documentation"
    elif first == ".github":
        return "CI/CD"
    elif first == "route-repo-template":
        return "Route Template"
    elif first == "scripts":
        return "Scripts"
    else:
        return "Root"


def analyze_file(filepath: str) -> Optional[FileStats]:
    """Analyze a single file and return its statistics."""
    ext = Path(filepath).suffix.lower()

    if ext not in CLASSIFIERS and ext not in CONFIG_EXTENSIONS:
        return None

    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except (OSError, IOError):
        return None

    if ext in CLASSIFIERS:
        stats = CLASSIFIERS[ext](lines)
    else:
        lang = LANGUAGE_NAMES.get(ext, ext.lstrip(".").upper())
        stats = classify_generic_lines(lines, lang)

    stats.path = filepath
    return stats


def walk_project(root: str) -> dict[str, PlatformStats]:
    """Walk the project tree and collect statistics by platform."""
    platforms: dict[str, PlatformStats] = {}

    for dirpath, dirnames, filenames in os.walk(root):
        # Prune skipped directories
        dirnames[:] = [
            d
            for d in dirnames
            if d not in SKIP_DIRS and not d.startswith(".")
            or d == ".github"
        ]

        for fname in filenames:
            filepath = os.path.join(dirpath, fname)
            ext = Path(fname).suffix.lower()

            # Only analyze known extensions
            all_exts = SOURCE_EXTENSIONS | DOC_EXTENSIONS | CONFIG_EXTENSIONS
            if ext not in all_exts:
                continue

            stats = analyze_file(filepath)
            if stats is None:
                continue

            platform = detect_platform(filepath, root)
            if platform not in platforms:
                platforms[platform] = PlatformStats(name=platform)

            stats.path = os.path.relpath(filepath, root)
            platforms[platform].files.append(stats)

    return platforms


def _collect_src_files(platforms: dict[str, PlatformStats]) -> list[FileStats]:
    """Return all source code files from every platform."""
    result = []
    for ps in platforms.values():
        for f in ps.files:
            if Path(f.path).suffix.lower() in SOURCE_EXTENSIONS:
                result.append(f)
    return result


def _collect_doc_files(platforms: dict[str, PlatformStats]) -> list[FileStats]:
    """Return all documentation files from every platform, sorted by length descending."""
    result = []
    for ps in platforms.values():
        for f in ps.files:
            if Path(f.path).suffix.lower() in DOC_EXTENSIONS:
                result.append(f)
    result.sort(key=lambda f: -f.total_lines)
    return result


def _src_files_for_platform(ps: PlatformStats) -> list[FileStats]:
    """Return source-code-only files for a platform."""
    return [f for f in ps.files if Path(f.path).suffix.lower() in SOURCE_EXTENSIONS]


def _pctl(lengths: list[int], p: float) -> int:
    """Return the p-th percentile from a sorted list of lengths."""
    if not lengths:
        return 0
    idx = min(int(len(lengths) * p / 100), len(lengths) - 1)
    return lengths[idx]


def _pct(part: int, whole: int) -> str:
    """Format a percentage string without padding."""
    if whole == 0:
        return "0.0%"
    return f"{100 * part / whole:.1f}%"


def _lang_stats(platforms: dict[str, PlatformStats]) -> dict[str, dict]:
    """Aggregate line counts by programming language."""
    stats: dict[str, dict] = defaultdict(
        lambda: {"files": 0, "total": 0, "code": 0, "comments": 0, "docs": 0, "blank": 0}
    )
    for ps in platforms.values():
        for f in ps.files:
            if Path(f.path).suffix.lower() not in SOURCE_EXTENSIONS:
                continue
            lang = f.language
            stats[lang]["files"] += 1
            stats[lang]["total"] += f.total_lines
            stats[lang]["code"] += f.code_lines
            stats[lang]["comments"] += f.comment_lines
            stats[lang]["docs"] += f.docstring_lines
            stats[lang]["blank"] += f.blank_lines
    return stats


SIZE_BUCKETS = [
    (0, 50, "1-50 lines"),
    (50, 100, "51-100 lines"),
    (100, 200, "101-200 lines"),
    (200, 300, "201-300 lines"),
    (300, 500, "301-500 lines"),
    (500, 1000, "501-1000 lines"),
    (1000, float("inf"), "1000+ lines"),
]


def _bucket_count(files: list[FileStats], low: float, high: float) -> int:
    """Count files whose total_lines fall in (low, high], with low==0 meaning [1, high]."""
    if low == 0:
        return sum(1 for f in files if f.total_lines <= high)
    return sum(1 for f in files if low < f.total_lines <= high)


# ─── Terminal output ────────────────────────────────────────────────────────────


def format_number(n: int | float, width: int = 8) -> str:
    """Format a number with thousands separator, right-aligned."""
    if isinstance(n, float):
        return f"{n:>{width},.1f}"
    return f"{n:>{width},}"


def format_pct(part: int, whole: int) -> str:
    """Format a percentage for terminal output."""
    if whole == 0:
        return "  0.0%"
    return f"{100 * part / whole:5.1f}%"


def print_divider(char: str = "─", width: int = 120):
    print(char * width)


def print_header(title: str):
    print()
    print(f"  {title}")
    print_divider("═")


def report_platform_summary(platforms: dict[str, PlatformStats]):
    """Print the main platform summary table."""
    print_header("PLATFORM / PROJECT SUMMARY")

    source_platforms = {
        name: ps for name, ps in sorted(platforms.items())
        if ps.code_lines > 0 or ps.comment_lines > 0 or ps.docstring_lines > 0
    }

    hdr = (
        f"  {'Platform':<20} {'Files':>6} {'Total':>8} {'Code':>8} "
        f"{'Comments':>8} {'Docstrings':>10} {'Blank':>8} {'Code %':>7}"
    )
    print(hdr)
    print_divider("─")

    grand_files = grand_total = grand_code = grand_comment = grand_doc = grand_blank = 0

    for name, ps in sorted(source_platforms.items()):
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        total = sum(f.total_lines for f in src_files)
        code = sum(f.code_lines for f in src_files)
        comments = sum(f.comment_lines for f in src_files)
        docs = sum(f.docstring_lines for f in src_files)
        blanks = sum(f.blank_lines for f in src_files)

        print(
            f"  {name:<20} {len(src_files):>6} {format_number(total)} {format_number(code)} "
            f"{format_number(comments)} {format_number(docs):>10} {format_number(blanks)} "
            f"{format_pct(code, total):>7}"
        )

        grand_files += len(src_files)
        grand_total += total
        grand_code += code
        grand_comment += comments
        grand_doc += docs
        grand_blank += blanks

    print_divider("─")
    print(
        f"  {'TOTAL':<20} {grand_files:>6} {format_number(grand_total)} {format_number(grand_code)} "
        f"{format_number(grand_comment)} {format_number(grand_doc):>10} {format_number(grand_blank)} "
        f"{format_pct(grand_code, grand_total):>7}"
    )


def report_language_breakdown(platforms: dict[str, PlatformStats]):
    """Print breakdown by programming language."""
    print_header("LANGUAGE BREAKDOWN (source code only)")

    stats = _lang_stats(platforms)

    hdr = (
        f"  {'Language':<15} {'Files':>6} {'Total':>8} {'Code':>8} "
        f"{'Comments':>8} {'Docstrings':>10} {'Blank':>8} {'Code %':>7}"
    )
    print(hdr)
    print_divider("─")

    for lang, s in sorted(stats.items(), key=lambda x: -x[1]["total"]):
        print(
            f"  {lang:<15} {s['files']:>6} {format_number(s['total'])} {format_number(s['code'])} "
            f"{format_number(s['comments'])} {format_number(s['docs']):>10} {format_number(s['blank'])} "
            f"{format_pct(s['code'], s['total']):>7}"
        )


def report_documentation(platforms: dict[str, PlatformStats]):
    """Print documentation statistics."""
    print_header("DOCUMENTATION FILES (.md)")

    doc_files = _collect_doc_files(platforms)
    if not doc_files:
        print("  No documentation files found.")
        return

    total_lines = sum(f.total_lines for f in doc_files)
    content_lines = sum(f.docstring_lines for f in doc_files)
    blank_lines = sum(f.blank_lines for f in doc_files)

    print(f"  Total documentation files: {len(doc_files)}")
    print(f"  Total lines:              {total_lines:,}")
    print(f"  Content lines:            {content_lines:,}")
    print(f"  Blank lines:              {blank_lines:,}")
    print()

    print(f"  {'File':<60} {'Lines':>7}")
    print_divider("─")
    for f in doc_files:
        print(f"  {f.path:<60} {f.total_lines:>7,}")


def report_file_length_stats(platforms: dict[str, PlatformStats]):
    """Print file length distribution per platform."""
    print_header("FILE LENGTH STATISTICS (source code files)")

    hdr = (
        f"  {'Platform':<20} {'Files':>6} {'Min':>6} {'P25':>6} "
        f"{'Median':>6} {'Avg':>8} {'P75':>6} {'P90':>6} {'Max':>6}"
    )
    print(hdr)
    print_divider("─")

    for name, ps in sorted(platforms.items()):
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        lengths = sorted(f.total_lines for f in src_files)
        n = len(lengths)
        avg = sum(lengths) / n
        print(
            f"  {name:<20} {n:>6} {lengths[0]:>6} {_pctl(lengths, 25):>6} "
            f"{_pctl(lengths, 50):>6} {avg:>8.1f} {_pctl(lengths, 75):>6} "
            f"{_pctl(lengths, 90):>6} {lengths[-1]:>6}"
        )


def report_longest_files(platforms: dict[str, PlatformStats], top_n: int = 20):
    """Print the longest source files across all platforms."""
    print_header(f"TOP {top_n} LONGEST SOURCE FILES")

    all_src = _collect_src_files(platforms)
    all_src.sort(key=lambda f: -f.total_lines)

    hdr = f"  {'File':<65} {'Lines':>6} {'Code':>6} {'Doc':>6} {'Cmt':>5} {'Blk':>5}"
    print(hdr)
    print_divider("─")

    for f in all_src[:top_n]:
        print(
            f"  {f.path:<65} {f.total_lines:>6} {f.code_lines:>6} "
            f"{f.docstring_lines:>6} {f.comment_lines:>5} {f.blank_lines:>5}"
        )


def report_doc_coverage(platforms: dict[str, PlatformStats]):
    """Print documentation coverage ratio per platform."""
    print_header("DOCUMENTATION COVERAGE (docstring lines / code lines)")

    hdr = f"  {'Platform':<20} {'Code Lines':>10} {'Docstring Lines':>15} {'Ratio':>8}"
    print(hdr)
    print_divider("─")

    for name, ps in sorted(platforms.items()):
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        code = sum(f.code_lines for f in src_files)
        docs = sum(f.docstring_lines for f in src_files)
        ratio = f"{docs / code:.2f}" if code > 0 else "N/A"
        print(f"  {name:<20} {code:>10,} {docs:>15,} {ratio:>8}")


def report_file_size_distribution(platforms: dict[str, PlatformStats]):
    """Print histogram-style file size distribution."""
    print_header("FILE SIZE DISTRIBUTION (source code files)")

    all_src = _collect_src_files(platforms)
    if not all_src:
        print("  No source files found.")
        return

    total = len(all_src)
    print(f"  {'Range':<18} {'Count':>7} {'%':>7}  Bar")
    print_divider("─")

    for low, high, label in SIZE_BUCKETS:
        count = _bucket_count(all_src, low, high)
        pct = 100 * count / total if total else 0
        bar = "\u2588" * int(pct / 2)
        print(f"  {label:<18} {count:>7} {pct:>6.1f}%  {bar}")


# ─── Markdown output ────────────────────────────────────────────────────────────


def _md_table(headers: list[str], rows: list[list[str]], alignments: Optional[list[str]] = None) -> str:
    """Build a markdown table string.

    alignments: list of 'l', 'r', or 'c' per column. Defaults to left for first, right for rest.
    """
    if alignments is None:
        alignments = ["l"] + ["r"] * (len(headers) - 1)

    sep_map = {"l": ":---", "r": "---:", "c": ":---:"}
    sep_row = [sep_map.get(a, "---") for a in alignments]

    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(sep_row) + " |")
    for row in rows:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def generate_markdown(platforms: dict[str, PlatformStats], top_n: int = 20) -> str:
    """Generate the full report as a markdown string."""
    from datetime import date

    sections = []
    sections.append(f"# OpenHiker Code Statistics")
    sections.append(f"*Generated: {date.today().isoformat()}*\n")

    # ── Platform summary ──
    sections.append("## Platform / Project Summary\n")

    headers = ["Platform", "Files", "Total", "Code", "Comments", "Docstrings", "Blank", "Code %"]
    rows = []
    grand_files = grand_total = grand_code = grand_comment = grand_doc = grand_blank = 0

    for name, ps in sorted(platforms.items()):
        if not (ps.code_lines > 0 or ps.comment_lines > 0 or ps.docstring_lines > 0):
            continue
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        total = sum(f.total_lines for f in src_files)
        code = sum(f.code_lines for f in src_files)
        comments = sum(f.comment_lines for f in src_files)
        docs = sum(f.docstring_lines for f in src_files)
        blanks = sum(f.blank_lines for f in src_files)

        rows.append([
            name, str(len(src_files)), f"{total:,}", f"{code:,}",
            f"{comments:,}", f"{docs:,}", f"{blanks:,}", _pct(code, total),
        ])
        grand_files += len(src_files)
        grand_total += total
        grand_code += code
        grand_comment += comments
        grand_doc += docs
        grand_blank += blanks

    rows.append([
        "**TOTAL**", f"**{grand_files}**", f"**{grand_total:,}**", f"**{grand_code:,}**",
        f"**{grand_comment:,}**", f"**{grand_doc:,}**", f"**{grand_blank:,}**",
        f"**{_pct(grand_code, grand_total)}**",
    ])
    sections.append(_md_table(headers, rows, ["l"] + ["r"] * 7))

    # ── Language breakdown ──
    sections.append("\n## Language Breakdown\n")

    stats = _lang_stats(platforms)
    headers = ["Language", "Files", "Total", "Code", "Comments", "Docstrings", "Blank", "Code %"]
    rows = []
    for lang, s in sorted(stats.items(), key=lambda x: -x[1]["total"]):
        rows.append([
            lang, str(s["files"]), f"{s['total']:,}", f"{s['code']:,}",
            f"{s['comments']:,}", f"{s['docs']:,}", f"{s['blank']:,}",
            _pct(s["code"], s["total"]),
        ])
    sections.append(_md_table(headers, rows, ["l"] + ["r"] * 7))

    # ── Doc coverage ──
    sections.append("\n## Documentation Coverage\n")
    sections.append("Ratio of docstring/doc-comment lines to code lines per platform.\n")

    headers = ["Platform", "Code Lines", "Docstring Lines", "Ratio"]
    rows = []
    for name, ps in sorted(platforms.items()):
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        code = sum(f.code_lines for f in src_files)
        docs = sum(f.docstring_lines for f in src_files)
        ratio = f"{docs / code:.2f}" if code > 0 else "N/A"
        rows.append([name, f"{code:,}", f"{docs:,}", ratio])
    sections.append(_md_table(headers, rows, ["l", "r", "r", "r"]))

    # ── Documentation files ──
    sections.append("\n## Documentation Files (.md)\n")

    doc_files = _collect_doc_files(platforms)
    if doc_files:
        total_lines = sum(f.total_lines for f in doc_files)
        content_lines = sum(f.docstring_lines for f in doc_files)
        blank_lines = sum(f.blank_lines for f in doc_files)

        sections.append(f"- **Total files:** {len(doc_files)}")
        sections.append(f"- **Total lines:** {total_lines:,}")
        sections.append(f"- **Content lines:** {content_lines:,}")
        sections.append(f"- **Blank lines:** {blank_lines:,}\n")

        headers = ["File", "Lines"]
        rows = [[f"`{f.path}`", f"{f.total_lines:,}"] for f in doc_files]
        sections.append(_md_table(headers, rows, ["l", "r"]))
    else:
        sections.append("No documentation files found.")

    # ── File length statistics ──
    sections.append("\n## File Length Statistics\n")
    sections.append("Percentile distribution of source file lengths (in lines) per platform.\n")

    headers = ["Platform", "Files", "Min", "P25", "Median", "Avg", "P75", "P90", "Max"]
    rows = []
    for name, ps in sorted(platforms.items()):
        src_files = _src_files_for_platform(ps)
        if not src_files:
            continue
        lengths = sorted(f.total_lines for f in src_files)
        n = len(lengths)
        avg = sum(lengths) / n
        rows.append([
            name, str(n), str(lengths[0]), str(_pctl(lengths, 25)),
            str(_pctl(lengths, 50)), f"{avg:.1f}", str(_pctl(lengths, 75)),
            str(_pctl(lengths, 90)), str(lengths[-1]),
        ])
    sections.append(_md_table(headers, rows, ["l"] + ["r"] * 8))

    # ── File size distribution ──
    sections.append("\n## File Size Distribution\n")

    all_src = _collect_src_files(platforms)
    if all_src:
        total = len(all_src)
        headers = ["Range", "Count", "%", ""]
        rows = []
        for low, high, label in SIZE_BUCKETS:
            count = _bucket_count(all_src, low, high)
            pct = 100 * count / total if total else 0
            bar = "\u2588" * int(pct / 2)
            rows.append([label, str(count), f"{pct:.1f}%", bar])
        sections.append(_md_table(headers, rows, ["l", "r", "r", "l"]))
    else:
        sections.append("No source files found.")

    # ── Longest files ──
    sections.append(f"\n## Top {top_n} Longest Source Files\n")

    all_src_sorted = sorted(_collect_src_files(platforms), key=lambda f: -f.total_lines)
    headers = ["File", "Lines", "Code", "Doc", "Comments", "Blank"]
    rows = []
    for f in all_src_sorted[:top_n]:
        rows.append([
            f"`{f.path}`", str(f.total_lines), str(f.code_lines),
            str(f.docstring_lines), str(f.comment_lines), str(f.blank_lines),
        ])
    sections.append(_md_table(headers, rows, ["l"] + ["r"] * 5))

    sections.append("")  # trailing newline
    return "\n\n".join(sections)


def main():
    parser = argparse.ArgumentParser(
        description="Code statistics for the OpenHiker project"
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=os.getcwd(),
        help="Project root directory (default: current directory)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="Number of longest files to show (default: 20)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON instead of formatted text",
    )
    parser.add_argument(
        "--markdown", "-md",
        type=str,
        nargs="?",
        const="code_stats.md",
        default=None,
        metavar="FILE",
        help="Output as markdown. Optionally specify output file (default: code_stats.md). "
             "Use '-' to write to stdout instead of a file.",
    )
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f"Error: {root} is not a directory", file=sys.stderr)
        sys.exit(1)

    platforms = walk_project(root)

    if not platforms:
        print("  No source files found.")
        sys.exit(0)

    if args.markdown is not None:
        md = generate_markdown(platforms, top_n=args.top)
        if args.markdown == "-":
            print(md)
        else:
            outpath = os.path.abspath(args.markdown)
            with open(outpath, "w", encoding="utf-8") as f:
                f.write(md)
            print(f"Markdown report written to {outpath}")
    elif args.json:
        import json

        output = {}
        for name, ps in sorted(platforms.items()):
            output[name] = {
                "files": ps.total_files,
                "total_lines": ps.total_lines,
                "code_lines": ps.code_lines,
                "comment_lines": ps.comment_lines,
                "docstring_lines": ps.docstring_lines,
                "blank_lines": ps.blank_lines,
                "avg_file_length": round(ps.avg_file_length, 1),
                "file_list": [
                    {
                        "path": f.path,
                        "language": f.language,
                        "total": f.total_lines,
                        "code": f.code_lines,
                        "comments": f.comment_lines,
                        "docstrings": f.docstring_lines,
                        "blank": f.blank_lines,
                    }
                    for f in ps.files
                ],
            }
        print(json.dumps(output, indent=2))
    else:
        print()
        print(f"  OpenHiker Code Statistics")
        print(f"  Root: {root}")
        print_divider("═")

        report_platform_summary(platforms)
        report_language_breakdown(platforms)
        report_doc_coverage(platforms)
        report_documentation(platforms)
        report_file_length_stats(platforms)
        report_file_size_distribution(platforms)
        report_longest_files(platforms, top_n=args.top)

    print()


if __name__ == "__main__":
    main()
