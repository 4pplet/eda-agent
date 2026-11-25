# Agent guide: eda-agent (the 4pplet fork)

Read [AGENTS.md](AGENTS.md) first: it holds the access policy and the lifecycle
rules, and it wins over this file. This file is the short working guide: where
to start, where each kind of truth lives, the commands, and the traps.

**This repository is public.** No client project names, no design data, no
absolute user paths, no memory backups (`tests/test_no_client_design_data.py`
checks the path shape). Write runtime paths with `%LOCALAPPDATA%`.
Handoff notes and their index (`docs/handoffs/*.md`) name other projects: they
are git-ignored and stay on the machine (Stefan, 2026-11-25). Anything else
that names another project or carries its data stays untracked too; in tracked
files say "the sending repo" or "a USB-C connector", not the name.

## Start here

1. [ROADMAP.md](ROADMAP.md): the phases and which one we are in.
2. [TODO.md](TODO.md): the open work, short. History is in
   `TODO-history-<date>.md` and is evidence, not a task list.
3. [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md): what is deployed where.
4. `py -3 -I docs/handoffs/check.py`: notes from other repos (session start,
   after every compact, before closing a task). Rules in
   `docs/handoffs/README.md` (local, not in git; absent on a fresh clone).
5. Before any bridge call: `../PLT-hw/tools/eda-agent/BRIDGE.md`.

## Where each kind of truth lives

| What | Where |
|---|---|
| Access policy, lifecycle rules | [AGENTS.md](AGENTS.md) |
| Phases, order, what "done" means | [ROADMAP.md](ROADMAP.md) |
| Open tasks, defects, decisions waiting on Stefan | [TODO.md](TODO.md) |
| Deployed runtimes per workstation | [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md) |
| Why and how a writer was built, its qualification rows | `docs/PROPOSAL-<date>-*.md` |
| What is built and not yet run in Altium | `../PLT-hw/tools/eda-agent/QUALIFY-TODO.md` |
| Per-increment backlog and the limitations log | `../PLT-hw/tools/eda-agent/TOOLS.md` (moves here in roadmap phase 2) |
| Bridge commands, blind spots | `../PLT-hw/tools/eda-agent/BRIDGE.md` |
| DelphiScript reference | `docs/altium-delphiscript/` |

## The pieces

- `scripts/altium/*.pas`: the native side. Upstream's files plus
  `SelectedProject.pas`, which is ours: selection scoping and every checked
  writer. `Main.pas` holds `SCRIPT_VERSION` and the three build flags
  (`SELECTED_PROJECT_READ_ONLY`, `SELECTED_PARAM_EDITS`, `SELECTED_PLACE_EDITS`),
  all `False` in source; the runtime generator sets them.
- `src/eda_agent/`: upstream's Python server. Our clients do not use it; they
  are in `../PLT-hw/tools/eda-agent` (`shared_server.py`, `project_server.py`,
  `bridge_read.py`, `bridge_write.py`, `sch_plan.py`, `edit_plan.py`).
- A runtime is a generated folder under `%LOCALAPPDATA%\PLT\eda-agent\shared\`,
  hash-checked, never edited in place. Source, wheel, runtime and the VM loaded
  in Altium are four different things.

## Commands

```
python scripts/altium/lint.py                      # Pascal lint, 0 errors required
<venv>\python -m pytest --noconftest tests/test_selected_project.py tests/test_dispatcher_shutdown.py tests/test_delphiscript_lint.py tests/test_pas_project_consistency.py tests/test_lint_*.py
cd ..\PLT-hw\tools\eda-agent && <venv>\python -m pytest -q     # the clients, ~800 tests
python ..\PLT-hw\tools\eda-agent\create_shared_runtime.py --root <new folder> --tool-source . --place-edits
```

`<venv>` is `%LOCALAPPDATA%\PLT\eda-agent\venv\Scripts`. It has pytest but not
pytest-asyncio, so the full upstream suite refuses to start there;
`--noconftest` runs the source-level tests. Do not install into that venv (it
is the runtime's, locked).

## Changing Pascal: the routine

1. Edit; run `lint.py`.
2. Bump `SCRIPT_VERSION` in `Main.pas`, the pin in
   `../PLT-hw/tools/eda-agent/project_server.py`, and the tripwire literal in
   `tests/test_dispatcher_shutdown.py`. All three, same value.
3. A new op needs its client validation, a test that sends it through
   `SharedReader.send`, a proposal section with numbered qualification rows, and
   a row in `QUALIFY-TODO.md`.
4. Build a new side-by-side runtime with Altium closed. Never replace loaded
   scripts.
5. Nothing is "done" until its row has run in Altium. Record pass or fail with
   the date in the proposal and in `QUALIFY-TODO.md`.

## Known traps (each one has bitten)

- **A record property is returned by value.** `Pin.Location.X := v` compiles,
  reports success and does nothing. Read, modify, write back. Lint rule
  `record-property-field-write`.
- **An undeclared identifier or constant is a script error no `Try` catches**,
  and it stops the loop. Prove every new API name against the SDK or upstream
  before use; the lint has lists of known-wrong ones.
- **A count is not a read-back.** "72 of 72 written" was true while every pin
  sat at the origin. Read back the property that was written.
- **A zero is not a pass**: `violations` lists only what the last DRC stored.
- **A modal dialog blocks the bridge** and cannot be dismissed from Python.
- **A timeout is not a cancellation.** Preview again; never retry a write.
- **Check the shared dispatcher before calling a read missing**: several were
  present upstream and only unrouted.
- **PrjScr file order**: `lint.py` `PAS_FILES` is the deployed order.
- Upstream's files are edited as little as possible, so upstream merges stay
  possible; our code goes in `SelectedProject.pas`.
