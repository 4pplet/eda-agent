# TODO

The open work, kept short. Order and phases: [ROADMAP.md](ROADMAP.md).
Everything before 2026-11-25 is in
[TODO-history-2026-11-25.md](TODO-history-2026-11-25.md): evidence and
reasoning, not a task list. An item moves here only when it is still open.

Tick an item with the date and where the proof is. Add a defect the day it is
found.

## Now

What is in flight and the next step. Updated before every compact; after one, start here.

- **Direction (Stefan, 2026-11-25):** be in line with upstream and contribute there; findings become fixes
  and pull requests, not reports. A pilot in another repo draws its sheet through upstream's own server
  (0.8.3, installed side by side): [docs/TRIAL-2026-11-25-upstream-as-it-is.md](docs/TRIAL-2026-11-25-upstream-as-it-is.md).
  One Altium, one bridge, one session: no call to either bridge from here while that session works.
- **Sent upstream 2026-11-25:** pull requests 454, 455, 456, 457 (fixes), 459 (the 3D model check), 460
  (the pad-number check) and 461 (the draw says that it saves and takes `reopen=False`). None reviewed yet.
  459 and 460 were rebased the same day: upstream's main had moved.
- **Upstream moved on 2026-11-25** (main `a29d132`, script `2026.11.25.3`, still called 0.8.3): it now keeps
  its own record of unsaved documents by full path (our finding of a library reading as saved), finds a
  document by its own file (issue 398) and shortened its preamble (issue 451). The trial install is still the
  published `9b741b5`. Stefan, 2026-11-25: move, between sheets. A second environment is built beside the
  first (`%LOCALAPPDATA%\PLT\eda-agent\upstream-trial-b`, main `a29d132` as it is, same workspace); the pilot
  switches at its next clean stop and runs two scratch tests there (lookup after a delete; the unsaved record
  after a copy). Saving stays switched on (Stefan, 2026-11-25).
- **Corrected 2026-11-25:** "the draw's save ignores the Saving switch" was wrong. The switch refuses
  `application.save_document` in the dispatcher, already in `9b741b5`; the pilot and I had read only the save
  routine. So the fix needed no script change and went out as 461. Read from source, not run in Altium.
- **The skill** ([skills/altium-bridge/SKILL.md](skills/altium-bridge/SKILL.md)) is rewritten for upstream's
  server from the pilot's report (2026-11-25): a draft that has done one sheet. The pilot tests it on its next
  sheet and reports what it lacked.
- **Next:** the project entry for a missing file (below, needs Altium); check on upstream's new main whether
  a lookup still returns a deleted symbol and whether the unsaved record covers a symbol copy (needs Altium);
  then the drawing check (chamfer and body numbers) and the layer-role check after a create.
- **Our own bridge:** runtime `selected-edits-20261125b` (scripts `2026.11.25.2`) built and used; branch
  `next-build` in both repos holds `2026.11.25.3`, source only. No new work on it until the trial is judged.
- **Undecided with Stefan:** the three private board names in tracked documents and whether the private
  sibling's name is private (section below); how much of the restricted layer is kept after the trial.
- Machine-local state (side checkouts, what is blocked, notes to other repos): `docs/handoffs/LOCAL-TODO.md`.

## Found by the pilot, to fix upstream (added 2026-11-25, after its report)

- [ ] `proj_remove_document` cannot remove a project entry whose file is missing: the script looks only at
      the project's logical documents, which never hold a missing file, and Altium's saves write the entry
      back. Remove what the project FILE lists. The catalog marks the tool `modal`; it raises no dialog.
      Needs Altium to test.
- [ ] From the report, not yet on this list as fixes: the `kinds` filter of `lib_get_footprint_primitives`
      returning an empty list silently; `sch_draw_template` answering `ok: true` while `footprint_issues`
      lists a footprint it could not choose (a warning the caller can miss); a chamfered land given as an
      outline coming out as the full square pad plus a region (assumed, not verified in the editor).
- [ ] The pilot's count of stops for the operator on upstream: 18, of which the check toggles (6), the 3D
      look and one pane click were avoidable. Pull requests 454, 459 and 460 remove some; the drawing check
      (chamfer and body numbers) and the layer-role check after a create are still to fix.
- Qualification rows from the pilot: W30a, W27, W39 passed. W28, W18, W9, W11, W10, W19, W21, W31 were not
  run: the pilot left the restricted bridge first. They stay open with that bridge.

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
- [x] On the same branch (2026-11-25, native half only): two options on the existing `libsymbol` writer, asked
      for by the pilot because its library's symbols have filled bodies and hide the labels of two-pin parts.
      `librect` text `fill/border` (colour integers; empty = not filled, as before) and a fourth `libpin` text
      field (`n` hides the name, `d` the designator); each is read back before the primitive goes on the symbol.
      Options on a built op, not a new op. Row W40.
- [x] Their client half (2026-11-25, PLT-hw branch `next-build`, a separate checkout so the running clients are
      untouched): `body_fill` with the two colours, `pin_labels` on the symbol, `show_name` /
      `show_designator` per pin, validation and tests. A plan without the options gives the same items as before.
- [x] `schlib_check.py` compares fill and label visibility in the saved file when the plan asks for them
      (2026-11-25, same branch). Which flag bit is the name and which the designator comes from the published
      file layout; row W40 confirms it in Altium.
- [x] The client half for the build (2026-11-25, PLT-hw branch `next-build`, 861 tests pass): the generator
      stamps the units before it hashes them and refuses sources without stamps, `status` names a stale or
      unstamped unit, the validators require pad `shape` and region `kind`, the client pin is `2026.11.25.2`.
      A trial runtime built from the two branches into a scratch folder: 25 files, ten units stamped, stamps
      match the files. Not loaded in Altium.
- [x] Built 2026-11-25 (go: Stefan): the pilot paused, Altium closed, both branches merged, runtime
      `selected-edits-20261125b` built side by side.
- [ ] Run in Altium: `status` (version, units), rows W40, W41, W42, the reload checks D1-D5.

## Written for the build after next (branch `next-build` in both repos, scripts `2026.11.25.3`, source only)

Not on `main`: the clients on `main` are pinned to the runtime in use.

- [x] **16 calls of `.Clear` on a string list** in the polygon and shape branches of the free-object writer
      (2026-11-25). Upstream's lint says the call is not declared in Altium's script engine, and those
      branches have never run in Altium, so the first `addpoly`, `setpoly` or shape op would have stopped
      the bridge with a script error. Replaced by a Delete loop, the form upstream uses. Lint: 0 errors,
      0 warnings. Proof is the first run of those ops (rows W5, V5 and the shape rows).
- [x] **Rule priorities** (2026-11-25, ported from upstream `da31d29`): a rule in a setup spec may carry
      `priority` (its place within its kind, 1 = first). Without it nothing changes. Both halves, tests pass.
      **The two Altium calls it uses are measured upstream on a newer Altium only**: row W43 proves them on
      a scratch board first.
- [ ] Merge and build only when no session uses the current runtime.

## Upstream, 2026-11-25

- [x] Our pull request 452 (library pin position) is on upstream's main as `3f9b1eb`, with us as author,
      and was checked live there. The pull request itself was closed, not merged.
- [ ] New upstream commit `2961fa2`: reads and writes a Clearance rule's table by object kind. That is the
      cause of our open defect "Board Outline Clearance reads as 0" (the value is in the object matrix).
      Review it for a port of the read half.

## Direction (Stefan, 2026-11-25): in line with upstream, and contributing there

- [x] Upstream's server installed side by side for a trial (version 0.8.3, commit `9b741b5`; offline health
      check passes; nothing has talked to Altium). `AGENTS.md` has the limits of the trial.
- [x] First session 2026-11-25: connected, reads without any focused window, a symbol copy and delete.
      Usable. Snags recorded in the trial document; three to report upstream.
- [ ] Decided (Stefan, 2026-11-25): continue with upstream and improve as snags are hit. The pilot's session
      continues its sheet through upstream (handoff note left), default settings, the agent does not save.
- **Fixes to send upstream** (Stefan, 2026-11-25: fix and open pull requests, not issue reports). Found in
  the trial on Altium 23.3.1 with upstream 0.8.3. Python-only ones first: they can be written and tested
  while the pilot has Altium.
  - [x] The `--toolset` / `--backend` flags restart the server, which drops a stdio connection on Windows:
        upstream pull request 455 (2026-11-25; unit tests, not run end to end with a client).
  - [x] The server exits with code 0 and no message whatever ends its main loop: upstream pull request 456.
  - [x] The symbol-against-pin-table check does not expand a range (`36-53`) or join the wrapped lines of one
        table row, so a module's ground and no-connect pins are reported missing: upstream pull request 454
        (2026-11-25; the datasheet page that was refused now reads 39 of 39 pins).
  - [ ] The template preview answers ok without a picture when the picture library is missing. Not sent: the
        reply already names the cause, and whether it should be a failure is the maintainer's design choice.
        To raise with him, not to patch.
  - [ ] The version check compares the bundled script, not the script project Altium has open. Not sent: the
        reply already warns in plain words when the two locations differ. To raise, not to patch.
  - [x] The IC symbol tool has no pin length, fill or border arguments (a created symbol does not match the
        library it goes into): upstream pull request 457 (not run in Altium).
  - [ ] Needs Altium (after the pilot): a library reads as saved after a symbol copy (their closed issue 251,
        back on Altium 23); after a delete the lookup by name still returns the symbol.
  - [ ] **Check how a 3D model sits on its footprint** (asked by Stefan through the pilot, 2026-11-25). After
        linking a STEP model the agent can read its box and height but not which way round it sits, so the
        operator had to open the 3D view and look. Wanted: a picture of the footprint with its body from top,
        bottom and at an angle, and a check of the model's bottom faces against the pads and the courtyard.
        Upstream has a 3D render module and writes STEP with CadQuery; neither is installed in the trial
        environment. Stefan, 2026-11-25: build it and send a pull request. Feasibility measured the same day
        with FreeCAD (CadQuery is blocked on this workstation by Windows Smart App Control): a module's STEP
        model read in 7 s gives 61 flat faces on its underside, the same count as the footprint's 61 pads, in
        four sizes. So the model's terminals can be matched to the pads, and that tells which way round it
        sits. Plan: read the STEP's box and underside faces; place them with the body's rotation and offset;
        match each face to a pad; try the four rotations and say which fits; draw pads, faces and body outline
        from above. An offline tool taking the pads and the placement as arguments.
        **Built 2026-11-25** on a branch of our fork (`feat/check-3d-model-fit`, tool
        `footprint_check_3d_model`, 11 tests): on the real module it passes the right way round, names
        the move when the model sits at its own origin, and fails a half turn because the body leaves
        the courtyard. Not yet a pull request: upstream's full test run first.
  - [ ] Custom footprint from a drawing (module with a printed body), four findings from one build: the layer
        check runs after the footprint was created and leaves the library marked modified and focus moved;
        the courtyard came from the lands only and missed the body's overhang; lands default to rounded
        corners where the drawing has square ones; the silkscreen has no pin-1 mark.
  - [ ] The footprint-against-drawing check cannot place a body dimension or a chamfer leg, so any module
        drawing with a body outline needs the check switched off.
  - [ ] A linked 3D body lands on Mechanical 1 at the model's own origin, not on the library's 3D layer.
  - [ ] `lib_get_footprint_primitives` with an unknown `kinds` word returns empty lists and no error.
  - [ ] **Tools that save without being asked** (pilot, 2026-11-25; the first read in the source, the second
        seen): the template draw tool says "does not save" and ends by saving, closing and reopening the
        sheet; the sheet-size tool does the same; creating a document also saves the project. Upstream has an
        operator switch that holds saves back, and the save these tools use does not ask it. The fix to send:
        that save honours the switch, the reopen becomes an option, the descriptions say what happens. It
        touches the Altium script, so it is tested in Altium before it is sent. Stefan, 2026-11-25: fix it
        and send a pull request. This is the one finding so far
        that goes against "the operator saves". Decided for the trial (Stefan, 2026-11-25): such a tool may
        be used on a new sheet, files committed first, the save said before the call.
  - [ ] Footprint link: refused with a sheet in front although its description says it brings the library
        forward; several footprints linked to one symbol all read as the current one and no tool sets it; a
        description write on a library symbol through the generic modify reports a match and changes nothing.
  - [ ] Feature asked for (Stefan: "critical that it's correct"): a check that pad N sits where the datasheet's
        pin-layout figure puts pin N. Today nothing ties a pad's number to its position; a footprint numbered
        the wrong way round passes every check. The pilot did it by hand from the figure's labels (53 of 53).
        **Built 2026-11-25**: tool `footprint_compare_pinout` on our fork, branch
        `feat/pad-number-against-pin-layout`, 8 tests, 1415 of upstream's related tests pass. On the real
        figure: 53 of 53 as built; a wrong view, eleven pins numbered the other way and a mirrored
        footprint are each refused. The pull request could not be opened (GitHub answered with a server
        error four times; its status page showed a minor outage): open it when GitHub is back, the text is
        ready.
  - [ ] Feature: compare a built footprint with another footprint (another library, a KiCad file) pad by pad,
        holes and slots with their rotation included.
  - [ ] To raise, not a fix: the server's instructions tell the agent to drive menus and dialogs without
        asking; the long "datasheet first" block in every reply.
- [ ] The trial: one sheet through upstream as it is, compared with the restricted pilot:
      [docs/TRIAL-2026-11-25-upstream-as-it-is.md](docs/TRIAL-2026-11-25-upstream-as-it-is.md). After the
      current pilot; one Altium, one bridge.
- [ ] Then decide how much of the restricted layer is rebased, offered upstream or retired.

## Plans

- [docs/PLAN-2026-11-25-move-clients-into-this-repo.md](docs/PLAN-2026-11-25-move-clients-into-this-repo.md):
  roadmap phase 2, plan only, with four decisions for Stefan.

## Private names already in this public repository (found 2026-11-25)

The new guard `tests/test_no_private_words.py` (word list outside the repository; it skips where there is no
list) fails on this machine. Counts only, the names are not repeated here:

- [ ] Three board or project names in 10 tracked documents (the old TODO history, CURRENT-STATE, six
      proposals, the shutdown guide, the README). They have been public since those files were pushed.
- [ ] The private sibling repository's name in 29 tracked files (every path of the form `../<repo>/tools/...`).
- Stefan decides: rewrite the files (the names stay in git history unless the history is rewritten too, which
  breaks every clone and the upstream pull-request branch), and whether the sibling's name counts as private.
  Until decided the guard stays red here on purpose.

## Defects and questions found in the pilot

- [x] W27 (pin positions) and W39 (bracketed footprint name) passed in Altium on `2026.11.25.1` (2026-11-25;
      PLT-hw `QUALIFY-TODO.md`).
- [x] **A tick that no apply used had no end.** A tick made in the morning was still standing hours later.
      Decided (Stefan, 2026-11-25): a ten-minute limit, and the preview prints the tick's age. The limit is on
      `next-build` for both grants (source only, row W41); the status form names it.
- [x] The tick's age in the preview (2026-11-25, both `next-build` branches): the ping carries `grant_age_s`
      outside the selection object, and every preview prints "granted (ticked N ago; ...)". Row W41.
- [ ] **Limitations logged by the pilot (2026-11-25), for phase 3 (the library loop).** New write ops, so
      none is built during the phase 1 freeze; the two that cost the operator most are first.
      Design for copy, delete, open, activate and close, with rows L1-L12:
      [docs/PROPOSAL-2026-11-25-library-loop-copy-delete-documents.md](docs/PROPOSAL-2026-11-25-library-loop-copy-delete-documents.md).
  - [ ] Copy a symbol from another library or from a placed part into the project library (create-only, same
        tick). Upstream has `Lib_CopyComponent`; read it before writing ours. Also covers "no lines or arcs in
        a drawn symbol", since a copied symbol keeps its drawing. Approved (Stefan, 2026-11-25, directly).
  - [ ] Remove a library symbol, limited to one this bridge session created and the library has not been saved
        with. Upstream has `Lib_DeleteComponent`. Today a rejected symbol costs a close and a restore from git.
        Approved in this narrow form "for now" (Stefan, 2026-11-25). Built in the library phase, not before.
  - [x] Which documents are open and which is focused could not be read, so the operator was asked five times
        in one day. Read only, so not held by the freeze: the freshness read now names the project's open
        documents and the focused one when it is a project member (both `next-build` branches, row W42).
  - [ ] Open a project member document; make a named open document the active one (the earlier ask); close
        a document only when it is not modified. Three new ops that act on the editor, not on design data.
        The second touches the rule "never follow focused tabs" (it sets focus, it does not follow it); the
        third must refuse a modified document. Approved for the library phase (Stefan, 2026-11-25); the
        rule text in `AGENTS.md` has the line that setting focus is not following it.
  - [ ] `libsymbol` creates single-unit symbols only: a unit number per pin and one body per unit would
        cover multi-part symbols. Read in the source, not hit on a run; no sheet needs it today. Related:
        pin edits refuse a pin number found on more than one unit.
  - [ ] Lines, polylines and arcs in `libsymbol` (after the copy op; may not be needed then).
  - [ ] `libfootprint` refuses a repeated pad number, which an exposed pad split in several pads needs.
  - [ ] `docparam` cannot create a parameter that does not exist on a new sheet (`Title`).
  - [ ] Footprint names in `footprint` / `liblink` are not checked against the footprint library.
  - [ ] `part` places from a `.SchLib` file only, not from an installed integrated library.
  - [x] An offline tool that imports a sibling failed under `python -I`: fixed in PLT-hw `schlib_check.py`.
  - For the skill, not the bridge: Altium's Make Schematic Library adds its output to the project, and a
    later project save writes it into the project file; remove it before saving.
  - Also for the skill: the bridge command needs PowerShell, not Git Bash; a pin type other than
    `passive` draws Altium's direction arrows; every library run costs a save and a reopen to check.

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
