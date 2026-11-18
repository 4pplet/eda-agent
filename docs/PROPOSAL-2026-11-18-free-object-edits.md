# Proposal: edits of free objects and a non-copper line read, 2026-11-18

Status: **asked for by Stefan 2026-11-18** ("let's do the MCP changes now, so we can add the features
that's missing instead"), from the 22p break-away work the same morning (PLT-hw `TOOLS.md` limitation
rows 2026-11-18; backlog 2, 4, 6). Built the same day, **native qualification E1-E8 pending**. Scripts
`2026.11.18.1`, runtime `selected-edits-20261118a` (mail workstation); carries everything in `.6`.

## 1. What it adds

| Command | What | Notes |
|---|---|---|
| `pcb.get_free_graphics` (read) | free lines and arcs on non-copper layers: layer, ends / centre, radius, angles, width, raw | the Mechanical 1 outline and V-cut lines were only visible by generating gerbers |
| `pcb.edit_free_checked` (board tick) | `delline` a free line on a non-copper layer; `delvia` / `movevia` a free via (the new place checked against other-net copper with `CopperNearest`); `text` edit a free text in place; `shape` redefine the board shape from vertices that are ends of free lines on a layer | every target named by exact geometry (vias within 5000 raw: the vias read reports whole mils); compare-and-set on the free-object counts, the via count and the board-shape point count; one batch per save; read back; never saves |

Also: graphics and copper refusals name the clearance in mm (`CoordToMMStr`), not raw units.

Client: `bridge_write.py edit preview|apply <plan.json>`; `edit_plan.py` resolves a plan in mm against
live reads (free graphics, texts, vias) to the exact raw targets, and for `shape` walks the OUTER loop of
the layer's lines (T-junctions split, duplicates once, collinear points merged; a layer with arcs or no
closed loop is refused). `bridge_read.py freegraphics`.

Identifiers: `Board.RemovePCBObject` after the `PCBM_BoardRegisteration` broadcast (as `PCB_DeleteObject`
in this fork); `PCBM_BeginModify` / `PCBM_EndModify` around a via move and a text edit (as Library.pas);
`Board.BoardOutline.PointCount` / `Segments[]` with a `TPolySegment` (as `PCB_SetBoardOutline`), then
`Invalidate` / `Rebuild` / `Validate`. No `RunProcess` (the menu's "Define from selected objects" shows a
modal when the selection is not closed; the direct write cannot).

## 2. Not in it

Copper track delete / reroute (backlog 4 proper), regions, mask openings, arcs in the board shape,
Plated flag changes on existing pads.

## 3. Qualification (real 22p, git as rollback, nothing saved unless Stefan saves)

| # | Check | Pass |
|---|---|---|
| E1 | ping `2026.11.18.1` on runtime `20261118a`; `freegraphics` lists the Mechanical 1 lines (rectangle, the redundant top segment, the V-cut) | rows match the board |
| E2 | `edit preview` of a plan with each op: delline (the redundant top segment), movevia (the 0.3 mm via 0.83 mm from the cut, to >= 1 mm), text (a test edit), shape (Mechanical 1) | all would_*; shape 4 vertices |
| E3 | apply without the board tick | stopped, nothing changed |
| E4 | apply with the tick | done, read back, unsaved, tick cleared; Altium shows the line gone, the via moved, the shape = the Mechanical 1 rectangle |
| E5 | a movevia onto other-net copper | refused, clearance named in mm |
| E6 | a delline on a copper layer; a text with no match | refused |
| E7 | apply after the board changed (old hash) | refused (counts / hash) |
| E8 | `gerber_panel_check` and `outjob_check` after Stefan saves and the OutJob runs | V-cut found, ends on the outline; board shape = outline |
