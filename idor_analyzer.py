#!/usr/bin/env python3
import os
import re
import json
from typing import List, Tuple, Dict, Any

# Configuration
REPO_ROOT = "/workspace/gitlab"
SEED_DIRS = [
    "app/controllers",
    "lib/api",
    "app/services",
    "app/controllers/concerns",
    "app/graphql",
]
FILE_EXTENSIONS = {".rb"}
BATCH_SIZE = 10
PRIORITY_THRESHOLD = 8
MAX_RESULTS = 5000

# Regex patterns
LOOKUP_PATTERNS = [
    re.compile(r"\bparams\[:id\]"),
    re.compile(r"\bparams\[:[a-zA-Z0-9_]+_id\]"),
    re.compile(r"\.find\("),
    re.compile(r"\bfind_by_[a-zA-Z0-9_]*\("),
    re.compile(r"\bfind_by\("),
    re.compile(r"\bfind_by_iid\b"),
    re.compile(r"\bfind_successful_deployment!\b"),
    re.compile(r"\bwhere\("),
]

AUTH_PATTERNS = [
    re.compile(r"before_action\s*:\s*authenticate_user!"),
    re.compile(r"before_action\s*:\s*authorize"),
    re.compile(r"authorize\("),
    re.compile(r"authorize!"),
    re.compile(r"\bcurrent_user\b"),
    re.compile(r"\bcan\?\("),
    re.compile(r"\bpolicy\("),
    re.compile(r"Ability\.allowed\?"),
    re.compile(r"access_denied!"),
    re.compile(r"authorize_read_"),
]

BYPASS_PATTERNS = [
    re.compile(r"skip_before_action"),
    re.compile(r"bypass_auth_checks"),
    re.compile(r"if:\s*->\s*\{[^}]*bypass", re.DOTALL),
]

SCOPE_PATTERNS = [
    re.compile(r"@project"),
    re.compile(r"\bproject\."),
    re.compile(r"@group"),
    re.compile(r"\bgroup\."),
    re.compile(r"\bnamespace\."),
    re.compile(r"\benvironment\."),
    re.compile(r"\bscoped\b"),
    re.compile(r"where\s*\([^)]*(project_id|group_id|namespace_id|environment_id)\s*:"),
]

INCLUDE_PATTERNS = [
    re.compile(r"^\s*(include|extend|prepend)\s+([A-Za-z0-9_:]+)", re.MULTILINE),
    re.compile(r'^\s*require(?:_relative)?\s+["\']([^"\']+)["\']', re.MULTILINE),
]

# Scoring weights
BASE_LOOKUP_WEIGHT = 5
PARAMS_ID_BONUS = 6
UNSCOPED_PENALTY = 8  # actually a bonus to score when unscoped
NO_AUTH_BONUS = 10
BYPASS_BONUS = 12
JS_ENDPOINT_BONUS = 0  # not used in this Ruby-focused pass

WINDOW_LINES = 8


def gather_seed_files(repo_root: str, seed_dirs: List[str]) -> List[str]:
    files: List[str] = []
    for d in seed_dirs:
        abs_dir = os.path.join(repo_root, d)
        if not os.path.isdir(abs_dir):
            continue
        for root, _, filenames in os.walk(abs_dir):
            for fn in filenames:
                _, ext = os.path.splitext(fn)
                if ext in FILE_EXTENSIONS:
                    files.append(os.path.join(root, fn))
    return files


def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        with open(path, "r", encoding="latin-1", errors="ignore") as f:
            return f.read()
    except Exception:
        return ""


def find_matches(patterns: List[re.Pattern], text: str) -> List[re.Match]:
    matches: List[re.Match] = []
    for p in patterns:
        matches.extend(p.finditer(text))
    return matches


def has_any(patterns: List[re.Pattern], text: str) -> bool:
    return any(p.search(text) for p in patterns)


def scopes_nearby(lookup_match: re.Match, lines: List[str]) -> bool:
    # Determine line index of match
    start_pos = lookup_match.start()
    cumulative = 0
    target_index = 0
    for i, line in enumerate(lines):
        cumulative += len(line)
        if cumulative >= start_pos:
            target_index = i
            break
    lo = max(0, target_index - WINDOW_LINES)
    hi = min(len(lines), target_index + WINDOW_LINES + 1)
    window_text = "".join(lines[lo:hi])
    return has_any(SCOPE_PATTERNS, window_text)


def snippet_around(lines: List[str], idx: int) -> str:
    lo = max(0, idx - 2)
    hi = min(len(lines), idx + 3)
    return "".join(lines[lo:hi])


def compute_score(lookup_str: str, scoped: bool, has_auth: bool, has_bypass: bool) -> int:
    score = BASE_LOOKUP_WEIGHT
    if re.search(r"params\[:id\]|params\[:[a-zA-Z0-9_]+_id\]", lookup_str):
        score += PARAMS_ID_BONUS
    if not scoped:
        score += UNSCOPED_PENALTY
    if not has_auth:
        score += NO_AUTH_BONUS
    if has_bypass:
        score += BYPASS_BONUS
    return score


def extract_neighbors(text: str) -> List[str]:
    neighbors: List[str] = []
    for p in INCLUDE_PATTERNS:
        for m in p.finditer(text):
            if m.lastindex and m.lastindex >= 2:
                neighbors.append(m.group(2))
            elif m.lastindex and m.lastindex >= 1:
                neighbors.append(m.group(1))
    return neighbors


def analyze_file(path: str) -> Tuple[List[Dict[str, Any]], List[str]]:
    text = read_text(path)
    if not text:
        return [], []

    lines = text.splitlines(keepends=True)
    auth_present = has_any(AUTH_PATTERNS, text)
    bypass_present = has_any(BYPASS_PATTERNS, text)

    findings: List[Dict[str, Any]] = []
    for p in LOOKUP_PATTERNS:
        for m in p.finditer(text):
            # Determine line index
            start_pos = m.start()
            cumulative = 0
            target_index = 0
            for i, line in enumerate(lines):
                cumulative += len(line)
                if cumulative >= start_pos:
                    target_index = i
                    break

            # Window scope
            scoped = scopes_nearby(m, lines)
            snippet = snippet_around(lines, target_index)
            lookup_segment = text[m.start():m.end()]
            score = compute_score(lookup_segment, scoped, auth_present, bypass_present)

            reasons: List[str] = []
            reasons.append("lookup")
            if re.search(r"params\[:id\]|params\[:[a-zA-Z0-9_]+_id\]", snippet):
                reasons.append("params[:*_id]")
            if not scoped:
                reasons.append("unscoped")
            if not auth_present:
                reasons.append("no_auth_in_file")
            if bypass_present:
                reasons.append("bypass_hint")

            findings.append({
                "file": os.path.relpath(path, REPO_ROOT),
                "line": target_index + 1,
                "snippet": snippet.strip(),
                "score": score,
                "reasons": reasons,
            })

    neighbors = extract_neighbors(text)
    return findings, neighbors


def main() -> None:
    seed_files = gather_seed_files(REPO_ROOT, SEED_DIRS)
    results: List[Dict[str, Any]] = []
    neighbor_map: Dict[str, List[str]] = {}

    for idx, path in enumerate(seed_files):
        file_findings, neighbors = analyze_file(path)
        neighbor_map[os.path.relpath(path, REPO_ROOT)] = neighbors
        results.extend(file_findings)
        if len(results) >= MAX_RESULTS:
            break

    # Sort by score desc, then file
    results.sort(key=lambda r: (-r["score"], r["file"], r["line"]))

    # Attach neighbors for top results
    for r in results[:2000]:
        r["neighbors"] = neighbor_map.get(r["file"], [])
        # Suggested fix heuristic
        r["suggested_fix"] = "scope the query (e.g., @project.<assoc>.find_by(id: params[:id])) and authorize after load"

    out_path = "/workspace/idor_results.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    # Print top 20 summary to stdout
    print(f"Analyzed {len(seed_files)} files. Findings: {len(results)}. Top 20:")
    for r in results[:20]:
        print(json.dumps({
            "file": r["file"],
            "line": r["line"],
            "score": r["score"],
            "reasons": r["reasons"],
            "snippet": r["snippet"][:200]
        }, ensure_ascii=False))


if __name__ == "__main__":
    main()