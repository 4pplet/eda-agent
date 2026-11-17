# Proposal: native actions (batch DRC, repour, OutJob run), 2026-11-17

Status: **asked for by Stefan 2026-11-17** ("let's try to make the ordering process better and
smoother and try to get as much mcp improvements in before tomorrow"); built the same day, native
qualification pending (section 6). Scripts `2026.11.17.2` (annotate added the same evening, section 5a),
runtime `selected-edits-20261117b` (the first, `selected-edits-20261117` at `.1`, was never started and
is superseded), client PLT-hw `tools/eda-agent`.
Increment 1 of the PLT-hw `TOOLS.md` bridge backlog (2026-10-16). Same selected-project model and
gates as the [setup](PROPOSAL-2026-10-09-setup-write-increment.md) and
[copper](PROPOSAL-2026-10-09-copper-write-increment.md) writes.

## 1. Why this, why now

The 22p rev B + HDMI production order (15 + 5 boards) needs, per board: DRC, a check of the
report, repour after the last copper edit, the "Fab files" OutJob container (Gerber, NC drill,
pick-and-place, BOM, STEP), then `jlc_pack.py`, `jlc_stock.py`, `bom_audit.py`,
`gerber_render.py`. Today every Altium step is Stefan's round trip, and the DRC step is where
the check / fix / re-check loop costs the most. With these three actions the loop runs from the
client, and a new `order_check.py` chains the whole pre-order pass.

## 2. Audit of the existing handlers: do not expose them as-is

| | Handler | Finding |
|---|---|---|
| A1 | `PCB_RunDRC` | runs `PCB:DesignRuleCheck`, which always opens the modal Design Rule Checker and blocks the polling loop until a human answers it (the AD23 resource file `AdvPcb.rcs` gives the process no parameters) |
| A2 | `PCB_RepourPolygons` | runs `PCB:RepourAllPolygons`, **a process that does not exist**: AD23's `AdvPcb.rcs` maps "Repour All" to `PCB:ChangeObject` with `Action=RepourAllPolygons`. Replies `repoured:true` whatever happened |
| A3 | `Proj_RunOutJob` | focused project's first OutJob, not the selected one; no dirty-document check, so outputs can come from unsaved edits; replies success with no evidence that a file was written |
| A4 | all three | focused board / project (`GetPCBBoardAnywhere`, `DM_FocusedProject`), not the selection |

Upstream `salitronic/eda-agent` reviewed 2026-11-17 (PCB.pas / Project.pas at main): it replaced
A1 with `IPCB_Board.RunBatchDesignRuleCheck` (no dialog, report to the workspace, the format passed
as a literal because an unknown identifier halts the loop), A2 with per-polygon
`SetState_CopperPourInvalid` + `Rebuild` in pour order with the repour option forced to "always"
(no yes / no prompt), and found for A3 that a container writes nothing unless the OutJob is the
**active** document, and that a second open OutJob can stop the script inside GenerateReport.
All three lessons are taken.

Confirmed in AD23's `Altium.SDK.Interfaces.dll` by reflection (2026-11-17), never guessed:
`IPCB_Board.RunBatchDesignRuleCheck(String argReportFilename, Int32 argDRCReportFormat,
Boolean argDisplayReportFile, Boolean argPublishToWeb) : Boolean`; `TDRCReportFileFormat`
eDRC_HTML = 0, **eDRC_Text = 1**; `IPCB_Polygon.Rebuild`, `SetState_CopperPourInvalid`,
`GetState_PourIndex`, `GetState_Poured`; `IPCB_SystemOptions.PolygonRepour` with
`TPolygonRepourMode` eNeverRepour 0, eAskRepour 1, **eAlwaysRepour 2**;
`WorkspaceManager:GenerateReport` `Action=Run|ObjectKind=OutputBatch` is the OutJob's F9
(`WorkSpaceManager.rcs`).

## 3. The three commands

All in `SelectedProject.pas`, reachable only in a runtime with `SELECTED_PLACE_EDITS` (the
`selected-project-edits` runtime), only on the selected project, re-checking the selection after
any native call that can pump UI. None of them saves.

| Command | What | Gate |
|---|---|---|
| `pcb.run_drc_checked` | `RunBatchDesignRuleCheck(<workspace>\selected-drc.DRC, 1, False, False)` on the selected PcbDoc; the old report is deleted first, so a report afterwards is this run's. Returns the report path, whether it appeared, the violation count read from the board and up to 500 violations. The text report is what `bridge.cmd drcreport` already parses | none beyond the runtime: writes no design data. `pcb_modified` before / after is reported, since the run marks violations on the board |
| `pcb.repour_checked` | preview lists every polygon (name, net, layer, pour index, poured, child primitive count); apply rebuilds the poured ones in pour-index order with the repour option set to "always" and restored after, and reports the counts after. A shelved polygon stays shelved | apply needs the "Allow board edits" tick and a saved PcbDoc; the tick is cleared after an apply that touched the board |
| `project.run_outjob_checked` | runs one named container of the selected project's own OutJob (exactly one OutJob member, or the one named). Refused while any project document is unsaved (outputs must match the saved files), for a `Printer` container, or when the OutJob is not the active document after opening it. Returns the container's type and base output folder | none beyond the runtime: writes only into the OutJob's output folder |

What was written is decided by the **client**, not the native reply: `bridge_write.py outjob`
lists the files under the container's base folder before and after and reports the new or
changed ones, so a container that wrote nothing is an error, not a success.

## 4. Client

- `shared_server.py`: tools `pcb_run_drc_checked`, `pcb_repour_checked`,
  `proj_run_outjob_checked`, each with its own reply-shape validation.
- `bridge_write.py drc`, `bridge_write.py repour preview|apply`, `bridge_write.py outjob
  <container>`; the repour preview hash binds the apply like the other writers.
- `order_check.py <board>`: DRC → drcreport → repour check → "Fab files" → `jlc_pack.py` →
  `jlc_stock.py` → `bom_audit.py` → `gerber_render.py`, one summary file; stops at the first
  hard failure and says which step.

## 5a. Annotate of `?` designators (added 2026-11-17, scripts `.2`)

`WorkspaceManager:DocumentOptions` `Action=AnnotateQuiet` is captioned "Annotate Schematics
Quietly..." (it may confirm in a dialog) and numbers without the PLT sheet hundreds, so annotate is
native and checked instead. `project.annotate_checked`, parameter-edit runtime flag and the
"Allow parameter edits" tick:
- preview lists every component of the project's schematics (sheet index, `UniqueId`, designator,
  `LibReference`, `IsMultiPartComponent`, `DesignatorLocked`); every sheet must be open;
- the client (`annotate_plan.py`) proposes names by sheet hundreds (sheet number from the file
  name's leading digits, else the sheet's most common hundred; one past the highest in use);
- apply writes `Designator.Text` per item by compare-and-set: sheet saved, component found once on
  its sheet by `UniqueId`, current text equal to old and ending in `?`, not multi-part, not locked,
  new unused in the project; any problem refuses the whole batch. One PreProcess / PostProcess per
  sheet, read back, grant cleared, never saved. Update PCB stays Stefan's.

## 5. Deliberately left out
- STEP on its own: it is in the "Fab files" container.
- Saving, Update PCB, and anything that deletes: unchanged, kept manual.

## 6. Qualification (on a disposable copy, before use on a working project)

| # | Check | Pass |
|---|---|---|
| Q1 | runtime check + ping | `selected-edits` runtime, scripts `2026.11.17.1` |
| Q2 | DRC on the copy | no dialog; report appears in the workspace; `drcreport` parses it; count equals the board's |
| Q3 | DRC twice | second run's report replaces the first, loop alive |
| Q4 | repour preview, apply without tick | preview lists every polygon; apply refused `NO_GRANT` |
| Q5 | repour apply with tick | no prompt; rebuilt in pour order; board marked modified, not saved; tick cleared |
| Q6 | OutJob with a dirty document | refused `DIRTY_PROJECT` |
| Q7 | OutJob "Fab files" | Gerber, drill, pick-and-place, BOM, STEP appear in the dated folder; the client lists them; `jlc_pack.py` packs them |
| Q8 | OutJob unknown container / Printer container | refused, nothing run |
| Q9 | the loop after all of the above | ping answers; reads still work |
| Q10 | annotate preview with one `R?` placed by hand | proposal `R<sheet>NN` one past the highest; nothing written |
| Q11 | annotate apply without the parameter tick, then with it | refused `NO_GRANT`; then written, read back, sheet dirty, not saved, tick cleared |
| Q12 | annotate apply after renaming the part by hand | refused `PREFLIGHT_REFUSED`, nothing written |
