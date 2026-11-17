# Proposal: graphic objects from a checked plan (free pads, fills, text, lines), 2026-11-17

Status: **asked for by Stefan 2026-11-17** ("let's continue with the MCP tool work"), increment 2 of the
PLT-hw `TOOLS.md` bridge backlog; built the same evening, **native qualification G1-G8 pending**.
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
