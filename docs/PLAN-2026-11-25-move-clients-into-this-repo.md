# Plan 2026-11-25: move the Python clients into this repository (roadmap phase 2)

**Status: plan only. Nothing has moved.** It starts after phase 1 (the built
writers run in Altium), and never while a session is using the clients.

## 0. Order changed 2026-11-25 (Stefan): upstream first

This fork is 545 commits behind upstream, from a base that never moved. Moving
the clients onto that base would mean moving them twice. The order is now:

1. Phase 1: the built writers run in Altium.
2. **Catch up with upstream**: our layer rebased onto current upstream (a trial
   merge on 2026-11-25 conflicted in 21 files).
3. **Compare before carrying**: for each thing our layer does, check whether
   upstream now does it (its operator settings already refuse edits, deletes
   or closing on request; 33 of its tools take a dry run; it copies and
   deletes library symbols and opens and closes documents). What upstream does
   as well or better, we drop.
4. **Offer upstream** what it lacks and would take, in pieces.
5. **Move what remains** as `clients/eda_bridge`: expected to be the approval
   routine, the runtime generator and the plan resolvers, much less than
   sections 2 to 5 below describe. Those sections are the upper bound.

Open (asked 2026-11-25, not decided): whether the restricted layer is still
needed at all once step 3 is done. A trial of upstream as it is, on committed
files, answers that better than a document.

## 1. Why

The bridge is in two repositories. The Altium scripts are here; the clients
that validate, plan and call them live in a private hardware repository. Every
change costs two commits that must agree on one version string, the tests of
one half cannot see the other half, and nobody else can run the bridge from
this repository at all.

Measured on 2026-11-25: one fix (library pin positions) needed three matching
version literals in two repositories, and one build needed a merge in both
within the same minute because the clients refuse a runtime of another
version.

## 2. What is there today

An offline scan of the private client folder on 2026-11-25 (tracked files):

| | Files | Lines | Free of user paths and project folder names |
|---|---|---|---|
| Python modules | 56 | about 19,000 | 47 |
| Tests | 66 | about 10,000 | 57 |
| Documents | 22 | about 3,800 | 6 |

The scan looks for the shape of a leak (an absolute path into a user's
storage) and for the names of the project folders beside the tools. It does
not find a part number, a net name or a customer's word in a fixture, so
"free" above is a lower bound on the work, not a clearance.

## 3. Three groups

**A. The bridge itself. Moves.** The server and its validators, the runtime
generator and loader, the read and write command lines, the plan resolvers for
schematic, library and board edits, the stop and triage tools, the stamps, the
lease. Their tests. This is what the version pin ties to the scripts.

**B. Generic design tools. Move after A, one at a time.** The offline library
checker, the board and sheet renderers, the plan-against-board comparison, the
rule and stackup readers that work on saved files. They need no bridge and
name no project once their fixtures are generic.

**C. House and project material. Stays private.** Ordering and fabricator
packs, checks that encode one board's rules, the expectation and spec files of
real projects, session notes, deployment logs, the per-machine pointer, the
qualification list while it records real boards. The private repository keeps
them and imports group A as an installed package.

A module that mixes B and C is split: the generic part moves, the project
table stays behind and is passed in as data.

## 4. Where it goes

```
clients/eda_bridge/        group A as a package (import eda_bridge.shared_server ...)
clients/eda_bridge/tools/  group B
clients/tests/             their tests, with generic fixtures only
docs/bridge/               BRIDGE.md and the other guides, rewritten without project names
```

Not under `src/eda_agent/`: that is upstream's server, and keeping ours apart
keeps upstream merges possible. One `pyproject` entry for the package; the
runtime generator copies the client files from the installed package instead
of from a sibling folder.

## 5. The steps

1. **Dev environment first.** A locked environment in this repository that can
   run both suites (today the only environment is the runtime's, it lacks a
   test plugin, and it must not be installed into). Recorded 2026-11-25 as an
   open defect.
2. **Extend the leak guard** before the first file moves: the existing test
   covers `src`, `tests`, `scripts/altium`, `docs`; add `clients`. Add a second
   guard that reads a list of private words from a file **outside** the
   repository (a path in an environment variable) and fails on any of them, so
   the list itself is never committed. Without the variable the guard skips
   and says so.
3. **Move group A in one commit per layer**, bottom up: runtime loader and
   lease; server and validators; generator; command lines; plan resolvers.
   After each: both suites green here, and the private repository switched to
   import that layer from the package, its own copy deleted.
4. **Fixtures.** Every test fixture that carries a real designator set, net
   list or path is replaced by a made-up one of the same shape. A test that
   only passes on real data stays private with its data.
5. **Documents.** The bridge guide, the read and write references and the
   maintenance guide are rewritten for a reader without our projects; the
   dated notes and deployment logs stay private as history.
6. **One version, one place.** `SCRIPT_VERSION` in `Main.pas` becomes the only
   literal; the client reads it from the scripts at build time and the test
   that today pins a second literal checks that there is exactly one.
7. **Group B**, tool by tool, each with its tests.
8. **The private repository** ends with group C, a dependency on this
   package at a pinned commit, and a short guide for its own sessions.

## 6. History

The files move as new files, without their history: the private history
carries project names in messages and in old versions of the files, and
filtering it is more risk than it is worth. The private repository keeps the
full history; each moved file's first commit here names the private commit it
came from by hash only.

## 7. Cutover and fallback

- A cutover day with no session on the bridge and Altium closed.
- The private copy of a layer is deleted only after one real read session and
  one write preview have run from the package.
- Fallback for the first month: the last private commit before the move is
  tagged; a runtime built from it keeps working, because runtimes are
  self-contained folders.

## 8. Risks

| Risk | Guard |
|---|---|
| A project name or design datum reaches the public repository | the two leak guards (step 2) run in the test suite and before every push; fixtures are rewritten, not copied; no history is moved |
| The two halves disagree mid-move | one layer per commit, both suites after each, the pin stays until step 6 |
| A session runs the old clients against a new runtime | already refused by the version check; the cutover is done with no session running |
| Upstream merges get harder | our code stays out of `src/eda_agent/` |

## 9. Decisions (Stefan, 2026-11-25)

1. Package location: `clients/eda_bridge`.
2. Group A (the bridge) is published first. Group B is decided tool by tool,
   later.
3. The qualification list is split: a public list of rows and their results, a
   private log of the board and date each was run on.
4. Apache-2.0 on our files, as the repository. Open: whose name is in the
   copyright line (asked when the move starts).

Step 2 is done ahead of the move (2026-11-25): `tests/test_no_private_words.py`
reads a word list from outside the repository. Its first run found names
already in tracked documents; see TODO.md.

## 10. Done means

A clean clone of this repository, with Altium and nothing else of ours, can
build a runtime, start the bridge and run a read; both suites pass in one
environment; the private repository holds no copy of a file that exists here.
