"""Handoff check: run at session start, after every compact, and before closing a task.

    py -3 -I docs/handoffs/check.py            # local state of this repo and the sibling checkouts
    py -3 -I docs/handoffs/check.py --fetch    # git fetch each sibling first (other machine's commits)

Inbound (notes other repos left for us):
  NEW           untracked in docs/handoffs/ -> read it, index it in README.md, put its asks on TODO, commit it
  NOT INDEXED   committed but not linked from README.md
  NEW (outbox)  in a sibling's docs/handoffs/outbound/eda-agent/ (its working tree or its
                upstream branch) but not in our docs/handoffs/ -> copy it in, set its Status:, index, commit
Outbound (our notes, *_from_eda_agent_*):
  WAITING       not committed in the receiver's repo (neither locally nor on its upstream branch)
  PICKED UP     committed there
  plus the receiver's `Status:` line, NOT INDEXED if our README doesn't list it, and
  NOT IN OUTBOX if a waiting note isn't committed in our docs/handoffs/outbound/<repo>/ (notes must cross machines:
  the receiver may run elsewhere, Stefan 2026-11-23).

Stdlib only. Reads git state; changes nothing except `git fetch` with --fetch.
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent          # docs/handoffs
REPO = HERE.parent.parent
SELF = "eda-agent"
SELF_TAG = "_from_eda_agent_"
OUTBOX = HERE / "outbound"


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


def status_line(text):
    for line in text.splitlines()[:15]:
        m = re.match(r"^Status:\s*(.+)$", line)
        if m:
            return m.group(1).strip()
    return None


def upstream_files(repo, path):
    """Files under `path` on the repo's upstream branch (empty if none)."""
    code, out = git(repo, "ls-tree", "-r", "--name-only", "@{u}", "--", path)
    return set(out.split()) if code == 0 else set()


def main():
    fetch = "--fetch" in sys.argv
    readme = (HERE / "README.md").read_text(encoding="utf-8")
    siblings = [o for o in sorted(REPO.parent.iterdir())
                if o != REPO and (o / ".git").exists() and (o / "docs" / "handoffs").is_dir()]
    if fetch:
        for o in siblings:
            git(o, "fetch", "--quiet")
    problems = 0

    print("Inbound (docs/handoffs/ in this repo, and the siblings' outboxes for us)")
    n0 = problems
    _, untracked = git(REPO, "ls-files", "--others", "--exclude-standard", "--", "docs/handoffs")
    untracked = {pathlib.Path(p).name for p in untracked.split()}
    ours = {f.name for f in HERE.glob("*.md")}
    for f in sorted(HERE.glob("*.md")):
        if f.name == "README.md":
            continue
        if f.name in untracked:
            print(f"  NEW           {f.name}")
            problems += 1
        elif f.name not in readme:
            print(f"  NOT INDEXED   {f.name}")
            problems += 1
    for o in siblings:
        rel = f"docs/handoffs/outbound/{SELF}"
        names = {pathlib.Path(p).name for p in upstream_files(o, rel)}
        names |= {f.name for f in (o / rel).glob("*.md")} if (o / rel).is_dir() else set()
        for n in sorted(names - ours):
            print(f"  NEW (outbox)  {o.name}: {n}")
            problems += 1
    if problems == n0:
        print("  nothing new")

    print("\nOutbound (our notes; receiver's copy and our outbox)")
    found = False
    for o in siblings:
        hd = o / "docs" / "handoffs"
        sent = {f.name for f in hd.glob(f"*{SELF_TAG}*.md")}
        box = OUTBOX / o.name
        boxed = {f.name for f in box.glob("*.md")} if box.is_dir() else set()
        _, tracked_box = git(REPO, "ls-files", "--", str(box.relative_to(REPO)))
        tracked_box = {pathlib.Path(p).name for p in tracked_box.split()}
        up = {pathlib.Path(p).name for p in upstream_files(o, "docs/handoffs")}
        for name in sorted(sent | boxed):
            found = True
            local = hd / name
            code, _ = git(o, "ls-files", "--error-unmatch", "--", f"docs/handoffs/{name}")
            picked = code == 0 or name in up
            text = ""
            if code == 0 or (not picked and local.exists()):
                text = local.read_text(encoding="utf-8", errors="replace")
            elif name in up:
                text = git(o, "show", f"@{{u}}:docs/handoffs/{name}")[1]
            st = status_line(text) if text else None
            flags = ""
            if name not in readme:
                flags += "  NOT INDEXED in our README"
            if name not in tracked_box and not picked:  # the outbox only matters until pickup
                flags += "  NOT IN OUTBOX"
            state = "PICKED UP" if picked else "WAITING  "
            print(f"  {state}  {o.name}: {name}" + (f"  [Status: {st}]" if st else "") + flags)
            if not picked or flags:
                problems += 1
    if not found:
        print("  no notes of ours in sibling checkouts or the outbox")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
