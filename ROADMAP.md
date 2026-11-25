# Roadmap

Written 2026-11-25. Tasks are in [TODO.md](TODO.md); this page holds the order
and what each phase must deliver. It replaces `docs/PARITY-ROADMAP.md` and the
"Bridge backlog" table in PLT-hw `tools/eda-agent/TOOLS.md` as the place where
order is decided (both stay as history and detail).

## What "feature complete" means

A design goes from an empty project to fabrication outputs through the bridge:
library parts, schematic sheets, board setup, placement, copper, finishing,
checks, outputs. In the checked mode three things stay with the operator: the
tick per batch, saving, and the Execute click in Altium's Update PCB dialog.
The full-access mode (phase 2b) has none of those and is for scratch designs.

## Where we are

Phase 0 is built (scripts `2026.11.25.1`, runtime `selected-edits-20261125a`),
waiting for the re-run in Altium. Phase 1 is next.

## Phases

| # | Phase | Delivers | Done when |
|---|---|---|---|
| 0 | **Fix** | pin position in new library symbols (and the same bug in upstream's `Lib_AddPin`), a read-back of the position, a lint rule for the pattern, brackets in footprint names | the sending repo's library plan re-runs and the pins are where the plan says |
| 1 | **Qualify, feature freeze** | every row of PLT-hw `QUALIFY-TODO.md` run in Altium, refusal paths first (apply without the tick, apply after the board changed); R2 re-run; the open S, U6 and D rows | one runtime whose provenance says qualified; the runtime pointer names it |
| 2 | **Consolidate** | clients, runtime generator and their tests move into this repo as a package; a per-machine runtime pointer; client files outside the hashed set, so a validator fix needs no Altium restart; a development runtime whose script project points at this checkout, so a Pascal fix is Detach, close and reopen the script project, Start (to prove once: that Altium recompiles on reopen without a restart); a session claim (one agent holds the bridge, shown in the bridge window, released on exit or expiry) and, for the holder only, a command that selects another project among those open in Altium: the selection generation advances and every tick is cleared, as when the operator switches; AGENTS.md and CURRENT-STATE rewritten to say what is true today; the backlog and limitations log here | a third repo uses the bridge without a PLT-hw checkout |
| 2a | **Seeing and querying** | a render or screenshot of a sheet, a board area or a library part (upstream's render tooling, to be read first), returned as an image; one generic read that runs an Altium filter query and returns the matches, paged (`Gen_QueryObjects` behind selection scoping); view helpers that change nothing on disk: cross-probe, highlight a net, zoom to a coordinate | a qualification row is checked from an image and a query, without a screenshot from Stefan |
| 2b | **Full-access mode = current upstream, side by side** | upstream's own server and scripts installed beside our runtimes, unmodified: save, Update PCB, generic object writes, simulation, render, everything it has. Guards on our side only: its own folder and client, and it is pointed only at a project that is clean and committed in git or is a copy. Used to go all out on scratch designs, to try an op before it gets a checked writer, and to judge upstream's own read-only switch and document scoping against ours | a scratch project built end to end with it; a written comparison of its safety model with ours |
| 3 | **Schematic and library loop** | reads: a sheet's parts, sheet symbols and buses; what a library holds (search, pin lists, pad geometry). Writes: activate a named library, symbol lines / arcs / text, multi-part symbols, symbol parameters, footprint arcs / text / 3D model, harnesses, junctions, directives. Schematic-to-PCB compare and the launch of Update PCB; Update From Libraries, so a corrected symbol or footprint reaches the placed parts; full ERC message text; part import (EasyEDA / KiCad) through the checked library writer | a sheet and its library parts built from a plan and verified by a read |
| 4 | **Board finishing** | via move with its tracks, 3D body with rotation, stitching vias, teardrops, tenting, length tuning, align / distribute / replicate, footprint placement, variants (read, matrix, active variant; fitted / DNP outputs), test points per net class, dimensions, keep-outs, cutouts and slots; reads of pad shape, mask and paste, and full rule matrices. To check for script access first: rule import / export as a `.RUL` file, impedance profiles in the layer stack, xSignals, pin and part swapping | an order check passes with no hand steps beyond the three operator gates |
| 5 | **Simulation** | upstream's SPICE tools behind our scoping: readiness read, attach a primitive or a vendor model, place probes, run an analysis and read the result | one real block (a regulator or a filter) simulated from a plan |
| 6 | **Workflow** | one plan for remove + place + repour, a second batch on an unsaved board, cancellation and deadlines defined end to end, undo qualified | a multi-step job takes one tick and one save |

## Upstream

`salitronic/eda-agent` is active: 541 commits past our base (2026-09-01) by
2026-11-23. It now has timer dispatch, a read-only switch, and document
scoping by full path in progress, which were three of our reasons to fork. Its
Pascal files have been largely rewritten since (a trial merge conflicts in 21
files), so upstream is not merged; it is used in three ways:

1. **Fixes go up.** Small fixes as pull requests (the maintainer cherry-picks
   them; `SCRIPT_VERSION` is left alone). First: the pin position in
   `Lib_AddPin` with its lint rule, pull request 452 (2026-11-25).
2. **Fixes come down by hand.** Before each build, review upstream's commits
   since the last review (PLT-hw `UPSTREAM-REVIEW-*.md`) for the APIs our code
   uses, and port what applies. Last review: 2026-11-25 (to upstream `9c0a14f`).
3. **Rebase after phase 1.** Our layer (`SelectedProject.pas`, the pure-read
   splits, the gates in the dispatcher and status form) moved onto current
   upstream as a small patch set, and the checked-write pattern proposed
   upstream as an issue. Everything is re-qualified on the new base, which is
   why it waits for phase 1.

## Decisions that are Stefan's

- Phase 2b: the guard list. Opening pull requests upstream (public, under Stefan's account).
- Phase 2: an agent switching the selected project changes "the operator chooses" in AGENTS.md.
- Phase 6: a second batch on an unsaved board changes a safety gate.
- AGENTS.md says read-only; the writers have run on working boards since
  2026-10. The text should say what is authorized today (phase 2).

## Not planned

Draftsman, PDN Analyzer, the legacy signal-integrity tool, Altium 365, and the
Situs autorouter (a process call; full-access mode only if ever).

## Staying out, in the checked mode

Generic `create_object` / `modify_objects` / `delete_objects` / `run_process` /
`execute_menu`, library deletes and renames, a silent ECO, any save. They have
no preview and no read-back. They belong to the full-access mode only.

## The rule that holds the order

No new op while a built one is untested. On 2026-11-23 nine builds were stacked
with Altium closed; the first real use of the eighth failed, and the count-based
read-back said it had passed.
