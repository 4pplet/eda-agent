# TODO

The open work, kept short. Order and phases: [ROADMAP.md](ROADMAP.md).
Everything before 2026-11-25 is in
[TODO-history-2026-11-25.md](TODO-history-2026-11-25.md): evidence and
reasoning, not a task list. An item moves here only when it is still open.

Tick an item with the date and where the proof is. Add a defect the day it is
found.

## Now

What is in flight and the next step. Updated before every compact; after one, start here.

- **In flight (2026-11-25):** a pilot in another repo is drawing a schematic sheet through the bridge on runtime
  `selected-edits-20261125a` (scripts `2026.11.25.1`). While it runs: no bridge calls from here, no version
  bump on `main`, no edits to the client files it runs. New files are safe.
- **Waiting for:** its pass / fail per qualification row and its report for the skill.
- **Ready, not built:** branch `next-build`, scripts `2026.11.25.2` (pad shape, region kind, per-unit stamps).
- **Next:** tick the rows; fill the skill's `PILOT:` lines; wire the new fields and the stamps into the
  generator, validators and `status`; build `2026.11.25.2`; the reload checks D1-D5; then phase 1.
- Machine-local state (side checkouts, what is blocked, notes to other repos): `docs/handoffs/LOCAL-TODO.md`.

## Done 2026-11-25 (phase 0)

- [x] `libsymbol` pins at the origin: read-modify-write in `SchEditLibPin`, and
      the pin's position read back before it goes on the symbol (2026-11-25,
      scripts `2026.11.25.1`, source only).
- [x] The same bug in upstream's `Lib_AddPin` (`Library.pas`).
- [x] Lint rule `record-property-field-write`, with a test.
- [x] Brackets in footprint names (`0402[1005]`): client check in PLT-hw
      `shared_server.py`, with a test.
- [x] Runtime `selected-edits-20261125a` built 2026-11-25 with Altium closed (24 files,
      integrity check and tool list pass; nothing run in Altium).
- [x] Runtime started 2026-11-25; the pilot session's reads and the L1 apply ran on it.
- [x] W27 pin positions on `2026.11.25.1`: the library saved 2026-11-25 09:49 matches the plan, 5 of 5 symbols,
      60 pins, by position, length, side and name (PLT-hw `schlib_check.py` on the saved file, and its drawing
      looked at). Still owed from the pilot session: the look in Altium's editor, and W39 (bracketed footprint link).
- [x] Reply note left in the sending repo (2026-11-25).
- [x] Committed: this repo `e9c2af2`, PLT-hw `75556c7` (2026-11-25, not pushed).
- [x] The `Lib_AddPin` fix and lint rule sent upstream: salitronic/eda-agent pull request 452.
- [x] Upstream reviewed to 2026-11-23 (PLT-hw `tools/eda-agent/UPSTREAM-REVIEW-2026-11-25.md`): one port
      candidate, rule priorities kept and settable in `setup` (upstream `da31d29`), after phase 1.
- [x] Read how upstream reloads scripts: closing and reopening the script project recompiles, an Altium
      restart alone may not (2026-11-25, [design note](docs/DESIGN-development-runtime.md)).
- [ ] Prove D1-D5 of that note on a scratch project (one sitting, before phase 2 builds on it).

## Next (phase 1: qualify, no new ops)

The list is PLT-hw `tools/eda-agent/QUALIFY-TODO.md`. In this order:

- [ ] Refusal paths never run live: V5, V9, P9, W8, W30, W31.
- [ ] Part A leftovers on the board: W13, W7, W3 / W17, W4 / W16.
- [ ] Part B: W5, W12, W14, W15, W9-W11, W18-W26, W33-W37.
- [ ] Part C: W27 (failed 2026-11-25 on `2026.11.23.10`, see above), W28, W29.
- [ ] R2 (failed 2026-11-18): find out what failed, fix or record.
- [ ] Older open rows: setup S4-S8, U6, dialog press D1-D3, placement T2-T13 / T15.
- [ ] Mark the runtime qualified in `provenance.json`; move the pointer.

## Next build: read-only additions (after phase 1; no new write op)

Found 2026-11-25 while drawing boards from reads (PLT-hw `board_render.py`). The drawing is ready for each;
the reads do not carry them yet. Each is a field on an existing read, with its validator and one live check.

- [ ] **Pad shape** in `pcb.get_component_pads` and in the free pads of `pcb.get_free_graphics`: `shape`
      (round / oval / rect / roundrect / octagon), `corner_radius_pct`, and the size per side where top and
      bottom differ. Today a pad is its top size only, so every pad draws as a rectangle and a pad-to-track gap
      near a limit cannot be computed (the 2026-10-14 limitation, BRIDGE.md section 4). Upstream reads pad
      geometry in its library tools; check its property names before ours.
- [ ] **Board cutouts**: a region's kind in the free-region read (`cutout` true for a board cutout, and the
      keep-out and mask kinds), and the holes of the board outline. Upstream's object read returns
      `Region.Kind = eRegionKind_BoardCutout`; check that the free-region read includes cutout regions at all.
- [ ] Holes of a free region (today only their count), and the arc centres already present in polygon
      outlines drawn as arcs in the client.

- [x] On branch `next-build` (scripts `2026.11.25.2`, not built, 2026-11-25): pad `shape` in the pads read, a
      region's `kind` in the free-graphics read, and a per-unit stamp in ten script units reported by the ping as
      `unit_stamps` (PLT-hw `script_stamps.py` is the client half).
- [ ] To build it: merge the branch, bump the client pin in PLT-hw, let `create_shared_runtime.py` stamp the
      units before it hashes them, let `status` name a stale unit, accept the new fields in the validators.
      Only when no session is using the current runtime.

## Tasks kept out of this file

This repository is public, so a task that names another repo is in `docs/handoffs/LOCAL-TODO.md`
(git-ignored, on the machine). One line each here:

- [x] ~~Audit of an agent guide for Altium work in another repo~~ (2026-11-25: there is no such guide; the
      guide meant is the skill below, which now carries the Altium and board-design practice).
- [x] Skill draft written 2026-11-25: [skills/altium-bridge/SKILL.md](skills/altium-bridge/SKILL.md), with
      `PILOT:` gaps. Not installed, not yet used for a job.
- [ ] A skill for working in Altium through the bridge: finished here after a pilot in another repo reports
      what worked, generic, kept with the clients; that repo tests it on its next sheet (2026-11-25).

## Open defects

| Found | Defect | State |
|---|---|---|
| 2026-11-24 | `allpads` stops on a USB-C connector with "Invalid pad row" (client check of `pcb.get_component_pads`) | the row is now in the message; needs one live read to see the field |
| 2026-11-23 | `rules` reads Board Outline Clearance as 0 (the value is in an object matrix) | workaround `pcb_rules_offline.py`; fix in phase 4 reads |
| 2026-11-18 | connection lines stale after `moves apply` | `ViewManager_FullUpdate` added in `2026.11.18.5`, not confirmed |
| 2026-11-18 | `movevia` leaves the tracks behind | phase 4 |
| 2026-11-18 | bounding rectangle stale after a board-shape write until reopen | open |
| 2026-11-18 | Altium shows an `EFOpenError` modal on a caught exception (script debugger) and blocks the bridge | 40 ms wait added; not seen since |
| 2026-11-18 | `tracelengths` differs from the sum of the tracks by up to 0.06 mm | unexplained |
| 2026-11-25 | no op makes a named library the active document | phase 3 |
| 2026-09-24 | `Library.pas` calls `Application.ProcessMessages` inside handlers (can defer keys during a library command) | open |
| 2026-09 | cancellation and deadlines undefined end to end | phase 6 |
| 2026-11-25 | the upstream test suite does not start in the runtime venv (no pytest-asyncio); no dev environment is defined | phase 2 |

## Docs that say something untrue today

- [ ] AGENTS.md "Current access policy": read-only, writes not authorized.
      Stefan's text to change.
- [ ] docs/CURRENT-STATE.md "In progress": one paragraph for fifteen builds;
      rewrite as a table at the end of phase 1.
- [ ] PLT-hw `BRIDGE.md` and `ACTIVE-RUNTIME.txt` name a 2026-10-02 runtime on
      the other workstation.

## Waiting on Stefan

See "Decisions that are Stefan's" in [ROADMAP.md](ROADMAP.md).
