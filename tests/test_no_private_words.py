# SPDX-License-Identifier: Apache-2.0
"""Private words must not reach this public repository.

`test_no_client_design_data.py` matches the SHAPE of a leak (an absolute path
into a user's storage) and names no client, because a list of forbidden strings
in the repository is itself the leak. This guard is the other half: it reads
the words from a file OUTSIDE the repository, so the list is never committed.

    EDA_AGENT_PRIVATE_WORDS = <path to a text file, one word or phrase per line, # comments>

Without the variable it looks for `%LOCALAPPDATA%/PLT/eda-agent/private-words.txt`.
With neither it skips and says so: a skip is not a pass.

It checks the files git tracks, plus untracked files git does not ignore (what
the next `git add -A` would take). Git-ignored files are out of scope on
purpose: handoff notes name other projects and stay on the machine.

It also applies the path-shape check to the folders the first guard does not
walk (`clients`, `skills`), ahead of the clients moving here (docs/PLAN-2026-11-25).
"""
import os
import re
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
TEXT = {".py", ".pas", ".dfm", ".md", ".json", ".js", ".ts", ".toml", ".txt", ".cmd", ".yml", ".yaml", ".cfg", ".ini"}
EXTRA_SHAPE_ROOTS = ("clients", "skills")
USER_PATH = re.compile(r"[A-Za-z]:\\{1,2}(?:Dropbox|Users|OneDrive)\\{1,2}[A-Za-z0-9_. -]+", re.IGNORECASE)
SYNTHETIC = ("users\\test", "users\\\\test", "users\\user", "users\\\\user", "users\\username", "users\\\\username")


def words_file():
    named = os.environ.get("EDA_AGENT_PRIVATE_WORDS")
    if named:
        return Path(named)
    local = os.environ.get("LOCALAPPDATA")
    if local:
        default = Path(local) / "PLT" / "eda-agent" / "private-words.txt"
        if default.is_file():
            return default
    return None


def load_words(path):
    words = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            words.append(line)
    return words


def committed_files():
    """Tracked files, and untracked ones that are not ignored."""
    out = subprocess.run(["git", "-C", str(REPO), "ls-files", "--cached", "--others", "--exclude-standard"],
                         capture_output=True, text=True, check=True).stdout
    for rel in out.splitlines():
        path = REPO / rel
        if path.suffix.lower() in TEXT and path.is_file() and not rel.startswith("reference/"):
            yield rel, path


def find_words(text, words):
    """Whole-word, case-insensitive hits. A word bounded by letters or digits on either side does not count,
    so a short name does not match inside a longer identifier."""
    hits = []
    for word in words:
        if re.search(r"(?<![A-Za-z0-9])" + re.escape(word) + r"(?![A-Za-z0-9])", text, re.IGNORECASE):
            hits.append(word)
    return hits


def test_the_matcher_finds_whole_words_only():
    assert find_words("the Board-X1 project", ["board-x1"]) == ["board-x1"]
    assert find_words("see BOARD-X1.", ["board-x1"]) == ["board-x1"]
    assert find_words("keyboard-x10 layout", ["board-x1"]) == []
    assert find_words("nothing here", ["board-x1"]) == []


def test_no_private_word_in_a_file_that_gets_committed():
    source = words_file()
    if source is None or not source.is_file():
        pytest.skip("no private word list on this machine (EDA_AGENT_PRIVATE_WORDS): NOT checked")
    words = load_words(source)
    if not words:
        pytest.skip("the private word list is empty: NOT checked")
    found = []
    scanned = 0
    for rel, path in committed_files():
        scanned += 1
        hits = find_words(path.read_text(encoding="utf-8", errors="replace"), words)
        if hits:
            # count only: the words themselves must not end up in a CI log either
            found.append(f"{rel}: {len(hits)} private word(s)")
    assert scanned > 50, "the guard scanned almost nothing: it would pass for the wrong reason"
    assert not found, ("private words in files git would commit (the list is in "
                       f"{source.name}, outside the repository):\n  " + "\n  ".join(found))


def test_no_user_path_in_the_folders_the_first_guard_does_not_walk():
    found = []
    for rel, path in committed_files():
        if rel.split("/")[0] not in EXTRA_SHAPE_ROOTS:
            continue
        for hit in USER_PATH.findall(path.read_text(encoding="utf-8", errors="replace")):
            if not any(marker in hit.lower() for marker in SYNTHETIC):
                found.append(f"{rel}: {hit}")
    assert not found, "absolute paths into private storage:\n  " + "\n  ".join(found)
