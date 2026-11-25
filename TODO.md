# TODO

The open work, kept short. Order and phases: [ROADMAP.md](ROADMAP.md).
Everything before 2026-11-25 is in
[TODO-history-2026-11-25.md](TODO-history-2026-11-25.md): evidence and
reasoning, not a task list. An item moves here only when it is still open.

Tick an item with the date and where the proof is. Add a defect the day it is
found.

## Now (phase 0)

- [x] `libsymbol` pins at the origin: read-modify-write in `SchEditLibPin`, and
      the pin's position read back before it goes on the symbol (2026-11-25,
      scripts `2026.11.25.1`, source only).
- [x] The same bug in upstream's `Lib_AddPin` (`Library.pas`).
- [x] Lint rule `record-property-field-write`, with a test.
- [x] Brackets in footprint names (`0402[1005]`): client check in PLT-hw
      `shared_server.py`, with a test.
- [x] Runtime `selected-edits-20261125a` built 2026-11-25 with Altium closed (24 files,
      integrity check and tool list pass; nothing run in Altium).
- [ ] **Stefan: start Altium from the new runtime's script project.**
- [ ] Re-run W27 on it: pins at the planned positions after save, close, reopen.
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
