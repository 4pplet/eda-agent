---
name: altium-bridge
description: Work on a live Altium Designer project through the checked bridge (selected-project reads and preview / tick / apply writes). Apply when asked to read, check, draw or edit an Altium schematic, board or library through the bridge, to verify a design against a plan, or to prepare a board for ordering. Not for upstream's autonomous design tools.
---

# Working in Altium through the checked bridge

**DRAFT 2026-11-25. Not yet used to do a job.** Written from the bridge's own guides before
the first end-to-end pilot reported back. Lines marked `PILOT:` wait for that report. The
acceptance test of this skill is one schematic sheet drawn by a session that has only this
file. Until that has happened, where this file and the bridge guide disagree, the guide wins.

This is the restricted bridge: an operator-selected project, reads that refuse rather than
guess, and writes that go preview, approval, apply, read-back and never save. It is not the
broad tool set of the upstream server, and a tool being reachable is not permission to use it.

## 1. Before anything

1. Read the bridge guide next to the clients (`BRIDGE.md`): the runtime in use, every command,
   and the table of what the bridge cannot see. Read the repo's own rules for the design.
2. One Altium, one bridge, one client. Run the status command first, every session. If another
   session holds the bridge, wait; do not start a second client.
3. The operator selects the project in the bridge window. Never infer it from the focused
   tab. Every call is bound to that selection; a changed selection means start again.
4. Know which runtime is running and stay on it for the whole job. Results recorded against
   two builds are not one result.
5. The design files are committed and pushed before a write session. Git is the rollback.

```
bridge.cmd status
bridge.cmd freshness
```

## 2. What is whose

| The agent | The operator |
|---|---|
| reads, checks, plans, previews | selects the project |
| applies a batch after its approval | ticks the grant in the bridge window, once per batch |
| reads back and reports | saves, or closes without saving to discard |
| | Update PCB (the change-order dialog), any dialog button |
| | closing Altium; starting the bridge |

Never save, never force a recompile, never press a dialog button, never retry a write whose
outcome is unknown. Stop the bridge without saving before Altium is closed.

## 3. Reading

- A read is live editor state unless it says otherwise. A compiled read (parts, nets,
  parameters, ERC) refuses while a document of the project is unsaved: ask for a save.
- Every result says which document it came from and whether that document is modified. Use
  a read as evidence only with the document saved.
- Units differ by read: some are whole mils with mm beside them, some are raw (10000 per mil).
  Use the mm fields. Near a limit, use a read that is exact, or the fabrication output.
- **A zero is not a pass.** Stored violations are only what the last rule check stored; an
  empty list on a board never checked looks clean.
- **A count is not a read-back.** "72 of 72 written" was true while every pin of five new
  symbols sat at the origin. Read back the property that was written, or check the saved file.
- Know the blind spots before concluding anything (the table in the bridge guide): rule
  values held in a matrix, poured copper versus a pour's outline, pad shape, mask, cutouts.
- The strongest check is an expectation file written before the work: nets, parameters and
  rules compared with what was intended, so a filled field that is wrong fails.

## 4. Writing: the one routine

Every writer follows it. Learn it once.

1. **Plan** in a file (JSON), committed with the work. One logical step per plan.
2. **Preview.** It changes nothing and prints what would change, what is refused and why, and
   an approval hash over the project and the exact batch.
3. Show the preview to the operator. He ticks the grant for that kind of edit.
4. **Apply** with the hash. One tick covers one batch.
5. The apply compares every old value with the preview's, writes, reads back, and reports per
   item. It never saves.
6. **Check** with a read (and the offline checkers), then the operator saves or discards.
7. An outcome reported as unknown, or a timeout: preview again and compare. Never re-send.

```
bridge_write.py --shared-root <runtime> --expect-project <PrjPcb> <kind> preview <plan.json>
bridge_write.py --shared-root <runtime> --expect-project <PrjPcb> <kind> apply <plan.json> --hash <H>
```

Kinds: parameters, part moves, copper (vias and tracks), board setup (stackup, classes, pairs,
rooms, rules), graphics, free-object edits, schematic and library edits, annotate, and the
native actions (rule check, repour, an output job container). The bridge guide lists each
kind's plan fields, what it refuses and whether it has been run in Altium yet. **An op that
has not been run in Altium is used on a copy, or on files that are committed, first.**

`PILOT:` the exact sequence for a schematic sheet, with the commands as run: library symbols,
footprints, new sheet, parts, wiring, No ERC markers, parameters, verify.
`PILOT:` what must be active, saved or ticked at each step, and every stop for the operator.
`PILOT:` units and orientation numbers per plan kind; which point of a pin a wire attaches to.

## 5. Checks, in the order to run them

1. The apply's own per-item result: every item written, none partial.
2. A read of what was written (positions, texts, nets), compared with the plan.
3. For a library: the saved file against the plan, pin by pin (`schlib_check.py`).
4. For a sheet: the compiled netlist against the plan (the verify step), then ERC.
5. For a board: stored violations after a full rule check, the saved rule-check report for
   which rules actually ran, then the order check on the output files.
6. A look: `sheet_render.py`, `board_render.py` (a window, one net, before and after a batch).
   A picture of the reads, not of the design; it finds a wrong place, it proves nothing.

`PILOT:` which of these earned their place, and their real order.

## 6. When something goes wrong

- A refusal is the bridge working. Read the reason, fix the plan or the state, preview again.
- A script error dialog in Altium: note the identifier it names, tell the operator, stop that
  step. The bridge is blocked until the dialog is answered, and answering it is his.
- A timeout names no cause: run the triage tool before guessing.
- The bridge stops after its idle time. Ask for a restart; queued requests are withdrawn.
- A result that reads "written" while the editor shows otherwise is a bug in the bridge:
  report it to the bridge's repo with the plan, the runtime and what was seen. Do not work
  around it by writing the file yourself. Design files change only through Altium.

`PILOT:` the failures actually met and how each was recovered.

## 7. Altium practice

House practice on these boards, each learned the hard way. Marked (general) where it is common
practice rather than ours.

- **Libraries first.** A part exists as a symbol and a footprint in the project's library
  before it is placed. A footprint from a part vendor or a library site is checked against the
  datasheet land pattern, pad by pad (size, pitch, pin 1, exposed pad), and a corrected copy
  gets its own name. Several fetched footprints were wrong; one belonged to another part.
- **Pin 1 and orientation** are checked on the placed part, not assumed from the symbol.
- **Parameters carry the order:** manufacturer part number, supplier number and a fitted or
  not-fitted instruction on every part, checked against an expectation file. A bill of
  materials edited outside the schematic is not a correction.
- **Rules before routing** (general): stackup, clearances, widths, vias, pairs and classes are
  set from a spec file before the first track, and read back. A rule's priority decides which
  rule applies; read the priorities after any rule change.
- **A rule check with every rule enabled** before any release, and the report read for which
  rules ran. A rule that was not run reports no violations.
- **Repour before a rule check** after any move or copper change.
- **Update PCB is the operator's**: it can remove things. Compare first, read the change
  order, then he executes.
- **Output jobs** are checked as files: a layer plotted twice, or the outline added to every
  plot, is found in the job settings and in the outputs, not in the editor.
- **Save points.** Compiled reads and release evidence are taken at a save the operator made
  on purpose, with the files committed.

## 8. Board design practice (general, with the house numbers kept out)

A checklist of what to settle and in what order, not a substitute for the fabricator's rules,
the parts' datasheets or a review. Source every specific number from the vendor's document and
cite it; none are given here on purpose.

1. **Stackup and impedance first.** Layer count, the fabricator's real stack, and the widths
   and gaps for each controlled impedance, from the fabricator's calculator.
2. **Return paths.** Every fast signal over an unbroken reference plane; a layer change gets a
   return via beside it; no routing across a split.
3. **Power.** Decoupling at the pin it serves, the small value closest; loop area of a
   switching regulator kept small and laid out as its datasheet shows; copper sized for the
   current and the temperature rise.
4. **Placement before routing.** Connectors and mechanical parts fixed first, then the parts
   with placement rules in their datasheets, then the rest by signal flow.
5. **Clearance and creepage** for the voltages present, from the applicable standard, and
   between copper and the board edge, cutouts and mounting holes.
6. **Differential pairs** routed as pairs: coupled length, intra-pair skew, spacing to other
   pairs, and the same reference plane for both legs.
7. **Thermal.** Exposed pads connected as the datasheet says, with the via count and size it
   gives; heat spread into copper, not into a neighbour.
8. **Test and assembly.** A test point on every net needed at bring-up; fiducials; polarity
   and pin 1 marks readable after assembly; designators off pads and vias.
9. **The fabricator's and assembler's rules**: minimum track, gap, drill, annular ring, mask
   sliver, silk width, panel and edge rules. Their checker's verdict is not the design's.
10. **Before ordering:** rule check clean with every rule on, the netlist against the
    schematic, outputs opened and looked at, the bill of materials against stock, and what is
    still unverified written down.

## 9. Reporting

Say what was verified and how (a read, a saved file, the editor, the operator's eyes), and what
was not. Name the runtime and the saved revision. A successful response is not a correct
design, and a clean check is a statement about that check.
