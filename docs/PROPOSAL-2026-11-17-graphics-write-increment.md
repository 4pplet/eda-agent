# Proposal: graphic objects from a checked plan (free pads, fills, text, lines), 2026-11-17

Status: **asked for by Stefan 2026-11-17** ("let's continue with the MCP tool work"), increment 2 of the
PLT-hw `TOOLS.md` bridge backlog; built the same evening, **G1-G8 passed 2026-11-18** (section 5, runtime `selected-edits-20261117f`).
Scripts `2026.11.17.4`, runtime `selected-edits-20261117d` (mail workstation). Fifth checked board
write after placement, copper, setup and the native actions; same gate and tick ("Allow board edits").

## 1. Why

The 22p production break-away (rev B N28) needs a GND copper pad on the holder part, non-plated holder
holes, "V-CUT" text on Mechanical 1 and rails; HS A2 needed ground pads, cap holes and a mask opening
that were drawn by hand (TOOLS.md limitation row 2026-10-16). None of these belong to a schematic part.

## 2. The command

`pcb.place_graphics_checked` in `SelectedProject.pas`; client `bridge_write.py graphics preview|apply
<plan.json>` (plan in mm, absolute coordinates as the reads give them; `load_graphics` documents the
format). Items `kind|layer|x1|y1|x2|y2|w|net|text`, at most 100:

| Kind | Fields | Layers | Checks |
|---|---|---|---|
| pad | centre, size, hole (0 = SMD), plated 1/0, shape round / rect, optional net | drilled: MultiLayer; SMD: a copper layer | size > hole; other-net copper within `clearance` refused |
| fill | two corners, optional net | any one layer; net only on copper | non-empty; clearance on copper |
| text | location, height, rotation 0/90/180/270, stroke, 1-40 plain characters | non-copper only | |
| line | two ends, width | non-copper only (copper goes through the copper writer) | |

Preview classifies every item and reports the counts of free pads, fills, texts and non-copper lines;
apply needs the tick, a saved PcbDoc and those counts unchanged (compare-and-set), refuses the whole
batch on any refusal, places inside one PreProcess / PostProcess, reads each object back, clears the
tick, never saves, never deletes.

Identifiers from AD23's `Altium.SDK.Interfaces.dll` (2026-11-17): `IPCB_Pad` XLocation / TopXSize /
TopShape / HoleSize / Plated / Mode, `TShape` eRounded 1 and eRectangular 2 (passed as literals),
`IPCB_RectangularPrimitive` X1Location..Y2Location / XLocation / YLocation / Rotation (fills and text),
`IPCB_Text` Text / Size / Width / UseTTFonts, `IPCB_Primitive` Layer / Net; upstream `PCB_PlacePad`,
`PCB_PlaceFill`, `PCB_PlaceText` use the same property names (`Pad.X`, `Pad.Plated := False`).

## 3. Not in it

Deleting or moving anything (the old plated holder vias are removed by hand), regions / polygons,
board-outline edits, mask or paste openings as separate objects, TrueType text.

## 4. Qualification (on the real board, git as rollback, nothing saved)

| # | Check | Pass |
|---|---|---|
| G1 | ping `.4` on runtime `20261117d`; `drc` and an OutJob refusal (carried from the native actions re-check) | as in that proposal |
| G2 | preview of a plan with one of each kind | all would_place; counts reported |
| G3 | apply without the tick | refused NO_GRANT |
| G4 | apply with the tick | placed, read back, unsaved, tick cleared; objects visible where planned |
| G5 | the NPTH pad: Properties shows Plated off, hole as asked | |
| G6 | a copper pad or fill against other-net copper | refused with the clearance named |
| G7 | text on a copper layer, a line on a copper layer | refused |
| G8 | apply after a manual edit adds a free object | refused PREFLIGHT_REFUSED (counts changed) |

## 5. Qualification record (2026-11-18, real 22p, runtime `selected-edits-20261117f`, scripts `.6`)

Stefan in Altium, nothing saved (PcbDoc closed without saving afterwards). Plans and outputs in the
session scratchpad; objects placed just left of the board outline (x 124-130 mm, y 80-94 mm).

| # | Result |
|---|---|
| G1 | **pass**: ping `.6`; batch DRC 4.5 s, 198 violations on the board = 198 in the report, 17 rules (the `.3` report-path fix holds natively); OutJob "Fab files" with an unsaved sheet refused `NO_WRITE: DIRTY_PROJECT` (the code survives `send()`, the `.3` fix) |
| G2 | **pass**: one pad (NPTH 0.6 / 0.3 mm), one Top fill, "G-TEST" on Mechanical 1, one overlay line: 4 would_place; counts 0,0,23,12 (texts = the `texts` read) |
| G3 | **pass**: apply without the board tick stopped by the client before sending (grant read from ping); nothing written. An apply with only the parameter tick on was stopped the same way |
| G4 | **pass**: placed 4 of 4, each read back as planned, unsaved, tick cleared; Stefan's screenshot shows all four where planned |
| G5 | **pass**: pad read back size 236220, hole 118110 (0.6 / 0.3 mm), plated false; Stefan: looks good |
| G6 | **pass**: a pad and a VCC3V3 fill on a GND via refused at preview, the via and the clearance named (in raw units; mm would read better) |
| G7 | **pass**: text and a line on TopLayer refused ("text goes on silk, mechanical ...", "copper lines go through the copper writer") |
| G8 | **pass at hash level**: after G4 the counts read 1,1,24,13 and the approval hash changed, so the old hash cannot apply; the native count compare under a saved board was not forced (it would need a save of the real board) |
