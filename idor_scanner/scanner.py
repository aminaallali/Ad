#!/usr/bin/env python3
"""
IDOR heuristic scanner for large Rails/JS codebases (GitLab-compatible).

This tool implements a batching, priority-queue driven search to find potential
Insecure Direct Object Reference (IDOR) patterns based on textual heuristics:

- Looks for param-based lookups (params[:id], params[:*_id]) and find/find_by/where
- Checks for absence of authorization indicators (before_action :authenticate_user!, authorize, can?)
- Checks for scope indicators (e.g., @project., project., group.)
- Detects bypass indicators (skip_before_action, bypass_auth_checks)
- Ranks findings with a scoring function; exports JSON/CSV

Usage:
  python3 scanner.py --root /workspace/gitlab \
    --export-json /workspace/idor_findings.json \
    --export-csv /workspace/idor_findings.csv \
    --batch-size 10 --max-files 1000 --threshold 8

The scanner is designed to work incrementally and does not require full repo
checkout to begin scanning; it will analyze whatever files are available under
the provided root.
"""

from __future__ import annotations

import argparse
import csv
import heapq
import json
import os
import re
import sys
from collections import deque, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Deque, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple


# -----------------------------
# Heuristic patterns
# -----------------------------

LOOKUP_REGEXES: Sequence[str] = [
    r"\bparams\[:id\]",
    r"\bparams\s*\[:[a-zA-Z0-9_]+_id\]",
    r"\.find\(",
    r"\bfind_by_[a-zA-Z0-9_]*\(",
    r"\bfind_by\(",
    r"\bfind_by_iid\b",
    r"\bfind_successful_deployment!\b",
    r"\bwhere\(",
]

AUTH_INDICATOR_REGEXES: Sequence[str] = [
    r"before_action\s+:authenticate_user!",
    r"before_action\s+:authorize",
    r"authorize\(",
    r"authorize!",
    r"\bcurrent_user\b",
    r"\bcan\?\(",
    r"\bpolicy\(",
    r"Ability\.allowed\?",
    r"access_denied!",
    r"authorize_read_",
]

BYPASS_INDICATOR_REGEXES: Sequence[str] = [
    r"skip_before_action",
    r"bypass_auth_checks",
    r"if:\s*->\s*\{[^\n]*bypass",
]

SCOPE_HINT_REGEXES: Sequence[str] = [
    r"@project[\._]",
    r"\bproject[\._]",
    r"@group[\._]",
    r"\bgroup[\._]",
    r"@namespace[\._]",
    r"\bnamespace[\._]",
    r"where\s*\(\s*project_id:\s*",
    r"where\s*\(\s*group_id:\s*",
    r"\bscoped\b",
]

JS_ENDPOINT_HINT_REGEXES: Sequence[str] = [
    r"/notes/\\d+",
    r"/projects/[^/]+/\\d+/",
]


# -----------------------------
# Data types
# -----------------------------

@dataclass
class Match:
    pattern: str
    line_number: int
    line_text: str


@dataclass
class Finding:
    file: str
    line: int
    snippet: str
    score: int
    reasons: List[str]
    neighbors: List[str]


# -----------------------------
# Utility functions
# -----------------------------

def compile_patterns(patterns: Sequence[str]) -> List[re.Pattern[str]]:
    return [re.compile(p) for p in patterns]


def iter_file_lines(path: Path) -> Iterator[Tuple[int, str]]:
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as f:
            for idx, line in enumerate(f, start=1):
                yield idx, line.rstrip("\n")
    except Exception:
        return


def find_matches(path: Path, compiled: Sequence[re.Pattern[str]]) -> List[Match]:
    results: List[Match] = []
    for line_no, text in iter_file_lines(path):
        for rx in compiled:
            if rx.search(text):
                results.append(Match(pattern=rx.pattern, line_number=line_no, line_text=text.strip()))
    return results


def any_match_in_file(path: Path, compiled: Sequence[re.Pattern[str]]) -> bool:
    for _ in find_matches(path, compiled):
        return True
    return False


def has_scope_nearby(path: Path, target_line: int, compiled_scope: Sequence[re.Pattern[str]], window: int = 4) -> bool:
    low = max(1, target_line - window)
    high = target_line + window
    for line_no, text in iter_file_lines(path):
        if line_no < low:
            continue
        if line_no > high:
            break
        for rx in compiled_scope:
            if rx.search(text):
                return True
    return False


def extract_neighbors(path: Path) -> List[str]:
    """Extract naive neighbor file suggestions from include/require/import usage.

    For Ruby concerns: include SomeConcern -> app/controllers/concerns/some_concern.rb
    For require_relative or require 'x/y': map to likely ruby file paths.
    For API files, parse 'helpers' or 'use' lines (best-effort heuristic).
    """
    neighbors: Set[str] = set()
    include_rx = re.compile(r"\binclude\s+([A-Za-z0-9_:]+)")
    require_rx = re.compile(r"\brequire(?:_relative)?\s+["']([^"']+)["']")
    import_rx = re.compile(r"\bfrom\s+["']([^"']+)["']|\bimport\s+["']([^"']+)["']")

    for _, text in iter_file_lines(path):
        for m in include_rx.finditer(text):
            mod = m.group(1)
            snake = re.sub(r"::", "/", mod)
            snake = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", snake).lower()
            candidates = [
                f"app/controllers/concerns/{snake}.rb",
                f"app/models/concerns/{snake}.rb",
                f"lib/{snake}.rb",
            ]
            neighbors.update(candidates)
        for m in require_rx.finditer(text):
            ref = m.group(1)
            if not ref.endswith(".rb"):
                ref += ".rb"
            candidates = [f"{ref}", f"lib/{ref}"]
            neighbors.update(candidates)
        for m in import_rx.finditer(text):
            ref = m.group(1) or m.group(2)
            if ref:
                neighbors.add(ref)
    return sorted(neighbors)


# -----------------------------
# Scoring
# -----------------------------

def compute_score(
    *,
    has_params: bool,
    has_scope_local: bool,
    has_auth_in_file: bool,
    has_bypass_in_file: bool,
    js_endpoint_context: bool,
) -> Tuple[int, List[str]]:
    base_lookup_weight = 5
    params_id_bonus = 6 if has_params else 0
    unscoped_penalty = 8 if not has_scope_local else 0
    no_auth_bonus = 10 if not has_auth_in_file else 0
    bypass_bonus = 12 if has_bypass_in_file else 0
    js_endpoint_bonus = 4 if js_endpoint_context else 0

    reasons: List[str] = []
    reasons.append("lookup")
    if has_params:
        reasons.append("params[:id]")
    if not has_scope_local:
        reasons.append("unscoped_find")
    if not has_auth_in_file:
        reasons.append("no_auth_in_file")
    if has_bypass_in_file:
        reasons.append("bypass_present")
    if js_endpoint_context:
        reasons.append("js_endpoint_hint")

    total = base_lookup_weight + params_id_bonus + unscoped_penalty + no_auth_bonus + bypass_bonus + js_endpoint_bonus
    return total, reasons


# -----------------------------
# Analyzer
# -----------------------------

class Analyzer:
    def __init__(
        self,
        root: Path,
        batch_size: int = 10,
        threshold: int = 8,
        max_files: int = 1000,
    ) -> None:
        self.root = root
        self.batch_size = batch_size
        self.threshold = threshold
        self.max_files = max_files

        self.lookup_rx = compile_patterns(LOOKUP_REGEXES)
        self.auth_rx = compile_patterns(AUTH_INDICATOR_REGEXES)
        self.bypass_rx = compile_patterns(BYPASS_INDICATOR_REGEXES)
        self.scope_rx = compile_patterns(SCOPE_HINT_REGEXES)
        self.js_hint_rx = compile_patterns(JS_ENDPOINT_HINT_REGEXES)

        self.seen_files: Set[Path] = set()
        self.to_read: Deque[Path] = deque()
        self.pq: List[Tuple[int, Finding]] = []  # store (-score, finding)

    def seed_files(self) -> None:
        seed_dirs = [
            self.root / "app/controllers",
            self.root / "lib/api",
            self.root / "app/services",
            self.root / "app/controllers/concerns",
            self.root / "app/graphql",
        ]
        for d in seed_dirs:
            if not d.exists():
                continue
            for path in d.rglob("*"):
                if path.is_file() and self._is_source_file(path):
                    self.to_read.append(path)
        # explicit routes
        routes = self.root / "config/routes.rb"
        if routes.exists():
            self.to_read.append(routes)

    @staticmethod
    def _is_source_file(path: Path) -> bool:
        exts = {".rb", ".rake", ".js", ".ts", ".vue", ".graphql", ".gql"}
        return path.suffix in exts

    def analyze_file(self, path: Path) -> Tuple[List[Finding], List[str]]:
        findings: List[Finding] = []
        neighbors = extract_neighbors(path)

        # Precompute file-level indicators
        has_auth = any_match_in_file(path, self.auth_rx)
        has_bypass = any_match_in_file(path, self.bypass_rx)
        js_endpoint_hint = any_match_in_file(path, self.js_hint_rx)

        matches = find_matches(path, self.lookup_rx)
        # Fast exit if nothing relevant
        if not matches:
            return findings, neighbors

        for m in matches:
            has_params_here = bool(re.search(r"params\s*\[:id\]|params\s*\[:[a-zA-Z0-9_]+_id\]", m.line_text))
            has_scope_local = has_scope_nearby(path, m.line_number, self.scope_rx, window=4)
            score, reasons = compute_score(
                has_params=has_params_here,
                has_scope_local=has_scope_local,
                has_auth_in_file=has_auth,
                has_bypass_in_file=has_bypass,
                js_endpoint_context=js_endpoint_hint or path.suffix in {".js", ".ts", ".vue"},
            )
            if score >= self.threshold:
                finding = Finding(
                    file=str(path.relative_to(self.root)),
                    line=m.line_number,
                    snippet=m.line_text[:300],
                    score=score,
                    reasons=reasons,
                    neighbors=neighbors,
                )
                findings.append(finding)
        return findings, neighbors

    def expand_neighbors(self, neighbor_paths: Iterable[str]) -> None:
        for rel in neighbor_paths:
            # Normalize relative neighbor references
            rel_path = rel
            if rel.startswith("/"):
                # skip absolute imports
                continue
            candidate = (self.root / rel_path).resolve()
            if candidate.exists() and candidate.is_file() and self._is_source_file(candidate):
                if candidate not in self.seen_files:
                    self.to_read.append(candidate)

    def run(self) -> List[Finding]:
        self.seed_files()
        total_processed = 0
        all_findings: List[Finding] = []

        while self.to_read and total_processed < self.max_files:
            batch: List[Path] = []
            while self.to_read and len(batch) < self.batch_size and total_processed + len(batch) < self.max_files:
                fpath = self.to_read.popleft()
                if fpath in self.seen_files:
                    continue
                self.seen_files.add(fpath)
                batch.append(fpath)

            if not batch:
                break

            for f in batch:
                findings, neighbors = self.analyze_file(f)
                for finding in findings:
                    heapq.heappush(self.pq, (-finding.score, finding))
                # Opportunistic neighbor expansion
                self.expand_neighbors(neighbors)
            total_processed += len(batch)

            # Expand via top PQ items
            top_items = heapq.nsmallest(20, self.pq)
            for neg_score, finding in top_items:
                if -neg_score >= self.threshold:
                    self.expand_neighbors(finding.neighbors)

        # Drain PQ to list
        while self.pq:
            _, finding = heapq.heappop(self.pq)
            all_findings.append(finding)
        # Highest score first
        all_findings.sort(key=lambda f: f.score, reverse=True)
        return all_findings


def export_json(findings: Sequence[Finding], json_path: Path) -> None:
    payload = [asdict(f) for f in findings]
    json_path.parent.mkdir(parents=True, exist_ok=True)
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def export_csv(findings: Sequence[Finding], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "line", "score", "reasons", "snippet"])
        for fin in findings:
            writer.writerow([fin.file, fin.line, fin.score, ",".join(fin.reasons), fin.snippet])


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Heuristic IDOR scanner (GitLab-compatible)")
    parser.add_argument("--root", required=True, help="Root directory of the codebase (sparse checkout allowed)")
    parser.add_argument("--export-json", default=None, help="Path to write JSON results")
    parser.add_argument("--export-csv", default=None, help="Path to write CSV results")
    parser.add_argument("--batch-size", type=int, default=10, help="Files per iteration (default 10)")
    parser.add_argument("--threshold", type=int, default=8, help="Minimum score to record (default 8)")
    parser.add_argument("--max-files", type=int, default=1000, help="Maximum files to analyze (default 1000)")

    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root not found: {root}", file=sys.stderr)
        return 2

    analyzer = Analyzer(root=root, batch_size=args.batch_size, threshold=args.threshold, max_files=args.max_files)
    findings = analyzer.run()

    # Save outputs
    if args.export_json:
        export_json(findings, Path(args.export_json))
    if args.export_csv:
        export_csv(findings, Path(args.export_csv))

    # Print a brief top summary
    top_n = findings[:20]
    print("Top findings:")
    for f in top_n:
        print(f"- {f.score:>2} {f.file}:{f.line} | {';'.join(f.reasons)} | {f.snippet[:120]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

