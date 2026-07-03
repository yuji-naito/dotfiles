#!/usr/bin/env python3
"""Determine the current Rails version and the next upgrade target.

Version selection policy (one step at a time):
  1. If a newer minor exists for the current major, bump the minor by exactly 1
     (X.Y -> X.(Y+1)), regardless of how many minors are actually available.
  2. If no newer minor exists, bump the major by 1 and start the minor at 0
     ((X+1).0).
  3. The patch is always the latest released patch of the target minor line.

It also reports the latest patch of the *current* minor line, because Rails
recommends moving to the latest patch of the current version before stepping up.

Usage:
  scripts/select_rails_version.py [--gemfile-lock PATH] [--json]

Reads the resolved Rails version from Gemfile.lock (preferred) or Gemfile, then
queries the RubyGems API for available stable versions. Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request

RUBYGEMS_VERSIONS_URL = "https://rubygems.org/api/v1/versions/rails.json"

# Minimum Ruby version required by each Rails minor line (from the official
# upgrade guide). Used only as a hint; always confirm against the guide.
RUBY_REQUIREMENTS = {
    (8, 1): "3.2.0",
    (8, 0): "3.2.0",
    (7, 2): "3.1.0",
    (7, 1): "2.7.0",
    (7, 0): "2.7.0",
    (6, 1): "2.5.0",
    (6, 0): "2.5.0",
    (5, 2): "2.2.2",
    (5, 1): "2.2.2",
    (5, 0): "2.2.2",
}


def parse_version(text):
    """Return a tuple of ints for a version string like '7.1.3.4'."""
    parts = []
    for chunk in text.strip().split("."):
        m = re.match(r"\d+", chunk)
        if not m:
            break
        parts.append(int(m.group(0)))
    return tuple(parts)


def read_current_version(gemfile_lock, gemfile):
    """Read the resolved Rails version from Gemfile.lock, falling back to Gemfile."""
    if os.path.exists(gemfile_lock):
        with open(gemfile_lock, encoding="utf-8") as f:
            content = f.read()
        # The resolved meta-gem line, e.g. "    rails (7.1.3.4)".
        m = re.search(r"^\s{4}rails \(([\d.]+)\)\s*$", content, re.MULTILINE)
        if m:
            return m.group(1), gemfile_lock
    if os.path.exists(gemfile):
        with open(gemfile, encoding="utf-8") as f:
            content = f.read()
        # e.g. gem "rails", "7.1.3" / gem 'rails', '~> 7.1.0'
        m = re.search(
            r"""gem\s+['"]rails['"]\s*,\s*['"][~>=\s]*([\d.]+)['"]""", content
        )
        if m:
            return m.group(1), gemfile
    return None, None


def fetch_stable_versions():
    """Return a list of (version_tuple, version_string) for stable Rails releases."""
    req = urllib.request.Request(
        RUBYGEMS_VERSIONS_URL, headers={"User-Agent": "rails-upgrade-skill"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    versions = []
    for entry in data:
        if entry.get("prerelease"):
            continue
        number = entry.get("number", "")
        tup = parse_version(number)
        if len(tup) >= 2:
            versions.append((tup, number))
    return versions


def latest_patch(versions, major, minor):
    """Return the highest released version string for the given major.minor, or None."""
    candidates = [
        (tup, num) for tup, num in versions if tup[0] == major and tup[1] == minor
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0])
    return candidates[-1][1]


def compute_target(current_str, versions):
    cur = parse_version(current_str)
    major, minor = cur[0], cur[1]

    current_latest_patch = latest_patch(versions, major, minor)

    # Rule 1: next minor in the same major?
    next_minor_patch = latest_patch(versions, major, minor + 1)
    if next_minor_patch is not None:
        target = next_minor_patch
        target_major, target_minor = major, minor + 1
        step = "minor"
    else:
        # Rule 2: bump major, minor starts at 0.
        target = latest_patch(versions, major + 1, 0)
        target_major, target_minor = major + 1, 0
        step = "major"

    return {
        "current": current_str,
        "current_latest_patch": current_latest_patch,
        "target": target,
        "target_minor_line": f"{target_major}.{target_minor}"
        if target
        else None,
        "step": step,
        "target_ruby_min": RUBY_REQUIREMENTS.get((target_major, target_minor)),
    }


def main():
    ap = argparse.ArgumentParser(description="Select the next Rails upgrade target.")
    ap.add_argument("--gemfile-lock", default="Gemfile.lock")
    ap.add_argument("--gemfile", default="Gemfile")
    ap.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = ap.parse_args()

    current, source = read_current_version(args.gemfile_lock, args.gemfile)
    if not current:
        print(
            "ERROR: could not find the Rails version in Gemfile.lock or Gemfile. "
            "Run this from the Rails project root.",
            file=sys.stderr,
        )
        return 1

    try:
        versions = fetch_stable_versions()
    except Exception as exc:  # network or parse failure
        print(f"ERROR: failed to query RubyGems API: {exc}", file=sys.stderr)
        return 2

    result = compute_target(current, versions)
    result["source"] = source

    if args.json:
        print(json.dumps(result, indent=2))
        return 0

    print(f"Current Rails:        {result['current']}  (from {source})")
    if (
        result["current_latest_patch"]
        and result["current_latest_patch"] != result["current"]
    ):
        print(
            f"Latest current patch: {result['current_latest_patch']}  "
            "(move here first, then to the target)"
        )
    if not result["target"]:
        print("Target:               none found (already on the newest release line)")
        return 0
    print(
        f"Target Rails:         {result['target']}  "
        f"({result['step']} bump -> {result['target_minor_line']} line, latest patch)"
    )
    if result["target_ruby_min"]:
        print(f"Requires Ruby >=      {result['target_ruby_min']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
