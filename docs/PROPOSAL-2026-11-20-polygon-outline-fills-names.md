# Proposal: polygon outlines, free fills / regions read, designator show / hide, fill delete, 2026-11-20

Status: **asked for by Stefan 2026-11-20** ("we can do the MCP changes so you can find the corners";
"let's do all five"), from the 22p holder copper work (N34): the corners of a hand-drawn solder-mask
polygon and of two no-net pours could not be read (PLT-hw `TOOLS.md` limitation row 2026-11-19). Built the
same day. Scripts `2026.11.20.1`, runtime `selected-edits-20261120a` (mail workstation); carries
everything in `2026.11.18.5`. **P1-P9 pending** (section 4).

## 1. What it adds

| Command | What | Notes |
|---|---|---|
| `pcb.get_polygons` (read) | per polygon also `vertices` (raw; `line` or `arc` with centre and angles, at most 300), `bbox` (raw, left / bottom / right / top), `poured`, `copper_pieces` (child regions, -1 when not readable); the reply carries `units` / `coord_per_mil` | pours on copper and polygons on mask or other layers alike. The segment fields are the ones the board-outline read already uses (`Segments[I].Kind / vx / vy / cx / cy / Angle1 / Angle2`) |
| `pcb.get_free_graphics` (read) | also `fills` (corners, rotation, net) and `regions` (outline points at most 200 of `point_count`, `hole_count`, net) that are free (not in a component, polygon or dimension), on **every** layer, copper included; `fill_total` / `region_total`, at most 500 rows each | the `graphics` rows (lines and arcs on non-copper layers) are unchanged. A pour's own regions are `InPolygon` and stay out |
| `pcb.edit_free_checked` (board tick) | `showname` / `hidename`: a part's designator text shown or hidden (`Comp.NameOn`); `delfill`: delete a free fill named by its exact corners on its layer, copper or not | same gates as the other ops: compare-and-set on the counts, one batch per save, read back, never saves |
| text moves (`movetext`, `movename`) | the move goes through `MoveByXY` inside the modify pair, then `GraphicallyInvalidate`; the direct `XLocation` / `YLocation` write stays as the fallback when the text is not where it was sent | fixes the selection box staying at the old place until the document was reopened (22p, 2026-11-19) |

Not new: fills on the solder-mask layers. `pcb.place_graphics_checked` already takes a fill on any single
layer (`TopSolder`, `BottomSolder`); a no-net copper fill is not refused over no-net vias (`CopperNearest`
treats an equal net name, including none, as a connection). P7 exercises it.

Client (PLT-hw `tools/eda-agent`): `bridge_read.py polygons` adds mm to the vertices and the box;
`freegraphics` adds mm to fills and regions; `edit_plan.py` takes `showname` / `hidename` (`designator` or
`designators`) and `delfill` (corners in mm, resolved against the fills read);
`reference_layer_check.py` counts fills and regions on a reference layer too.

## 2. Upstream review (salitronic/eda-agent `7a23938`, 2026-11-20; 21 commits since the 2026-11-17 review)

| Upstream | What | Taken |
|---|---|---|
| `PCB_GetPolygons` | `Polygon.Poured`, poured pieces through `Polygon.GroupIterator_Create` filtered to regions | yes: `poured`, `copper_pieces` (the count only; the copper area needs their `RegionCopperSqMils`, not taken) |
| text move in the bulk object writer | "XLocation / YLocation writes left all 27 texts where they were. Moved ... by MoveByXY inside BeginModify", then `GraphicallyInvalidate` in `Try` | yes: `EditMoveText` |
| `PCB_SetTextVisibility` | `Comp.NameOn` read and written per component, `Board.GraphicallyInvalidate` after | yes: the property; ours is per named designator inside the checked batch |
| `Region.HoleCount` | read in `Try`, -1 when it raises | yes |
| `5cfd20f`, `d828d1f` (2026-11-19) | a text placed on a bottom layer is mirrored; `UseTTFonts` written from the text's kind | not taken: our graphics writer's texts have gone on top-side and mechanical layers only. Worth taking before the first bottom-silk text |
| `91aab8a` | Polygon Connect relief angle written as the enum value | not ours: we do not write rules of that kind |

## 3. Not in it

Polygon writes (create or reshape a pour or a mask polygon), the poured copper's own outline (which via a
pour reaches), delete of free arcs, regions or pads, a cut of a track at a point, a via move that drags its
tracks, pour shelving.

## 4. Qualification (real 22p, git as rollback, nothing saved unless Stefan saves)

| # | Check | Pass |
|---|---|---|
| P1 | Altium starts from runtime `20261120a` with no script error; ping `2026.11.20.1` | version matches |
| P2 | `polygons`: the eight polygons of 2026-11-19 with vertices; the GND pours' outline = the main board rectangle (x 138.43-208.43); the two no-net holder pours and the TopSolder polygon located | vertex count = `vertex_count`; areas from the vertices = `area_mm2` |
| P3 | `freegraphics`: `graphics` rows as before (645 with the flex drawing on Mechanical 4 / 11); `fills` and `regions` listed with totals | the read validates; no pour region in `regions` |
| P4 | `edit preview`: `hidename` of the five N29 parts if visible (or a show / hide pair on one part); `showname` of a shown part | would_hide / would_show / unchanged |
| P5 | apply P4 with the board tick | done, read back shown / hidden, unsaved; Altium shows it |
| P6 | `movename` or `movetext` of one text by 1 mm and back | the selection box follows the text without a reopen |
| P7 | `graphics`: a small fill on `TopSolder` and a no-net fill on `TopLayer` over a no-net via on the holder | placed, read back; both appear in `freegraphics` `fills` |
| P8 | `edit`: `delfill` of the two P7 fills; a `delfill` with corners that match nothing | deleted, `remaining 0`; the bad one refused |
| P9 | apply without the tick; apply after the board changed | stopped; refused |

## 5. Qualification record

Pending.
