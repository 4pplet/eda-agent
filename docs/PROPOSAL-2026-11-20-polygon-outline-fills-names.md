# Proposal: polygon outlines, free fills / regions read, designator show / hide, fill delete, 2026-11-20

Status: **asked for by Stefan 2026-11-20** ("we can do the MCP changes so you can find the corners";
"let's do all five"), from the 22p holder copper work (N34): the corners of a hand-drawn solder-mask
polygon and of two no-net pours could not be read (PLT-hw `TOOLS.md` limitation row 2026-11-19). Built the
same day. Scripts `2026.11.20.1`, runtime `selected-edits-20261120a` (mail workstation); carries
everything in `2026.11.18.5`. **P1-P3 passed 2026-11-20, P4-P9 pending** (sections 4, 5).
**Scripts `2026.11.20.2`, runtime `selected-edits-20261120b`, the same day** (section 6): `movepoly`, a polygon
moved by an offset, after a hand move of the mask opening went to the wrong place three times; **P10-P12 passed
2026-11-20**, P13 pending.

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

## 5. Qualification record (2026-11-20, real 22p, runtime `selected-edits-20261120a`)

| # | Result |
|---|---|
| P1 | **pass**: Altium started from the runtime with no script error; reads answered on `2026.11.20.1` |
| P2 | **pass**: 8 polygons, every one with all its vertices; the area from the vertices (shoelace, chords for the arcs) equals `area_mm2` on all eight; the three GND pours = x 138.43-208.43, y 57.856-117.856; the two no-net holder pours x 210.312-243.43, full height, poured, 1 piece; the TopSolder polygon 12.192 x 11.049 mm with four arc corners. `copper_pieces` read 0 on the mask polygon after Stefan moved it (not yet repoured) |
| P3 | **pass**: `graphics` 645 rows as on 2026-11-19 plus 13 new on Mechanical 15; `fills` 0; `regions` 26 (one MultiLayer board region, 25 on TopOverlay with up to 5028 points and up to 7 holes: TrueType text), no pour region among them |
| P4-P9 | pending |

## 6. Scripts `2026.11.20.2`: a polygon moved by an offset

Asked by Stefan 2026-11-20 ("let's go through the backlog so you can move it"): the mask opening had to go
X +1.5 mm; by hand it went -15 / +135 mil, then back within 5 mil, then 5 mil the wrong way (PLT-hw
`TOOLS.md` limitation row 2026-11-20, backlog 9).

`pcb.edit_free_checked` op `movepoly`: `layer`, `x1,y1` the polygon's **first outline vertex**, `w` its vertex
count, `x2,y2` the offset, `s1,s2` the last vertex minus the first (raw). The polygon is named by its first
vertex and count, not by its bounding rectangle (a rectangle read after segment writes can be stale until
the document is reopened, as the board shape's was on 2026-11-18). Apply: inside `BeginModify`, every
segment record is read, its vertex (and an arc's centre) moved, and written back whole
(`Seg := Poly.Segments[K]` ... `Poly.Segments[K] := Seg`, as upstream's bevel); then the closing vertex one
past `PointCount` (upstream `ClosePolySegments`: "a replaced outline saved the OLD first vertex there, a
spike"); then `SetState_CopperPourInvalid` / `Rebuild` / `EndModify` / `GraphicallyInvalidate` with the
repour option forced to Always for the call, as our `repour` does. Read back: first vertex = old + offset,
the vertex count, and last-minus-first unchanged. Works on a pour as on a mask polygon; a pour is repoured
by the move, so DRC follows.

Also: the `shape` op (board shape from the outline) now writes the closing vertex too, in `Try`.

Client: `edit_plan.py` `{"op": "movepoly", "layer", "x_mm", "y_mm", "dx_mm", "dy_mm"}` where x / y is any
one vertex of the polygon; resolved against a `polygons` read; an offset above 50 mm is refused.

| # | Check | Pass |
|---|---|---|
| P10 | Altium starts from runtime `20261120b`; `polygons` as P2 | no script error; same rows |
| P11 | `edit preview` of a `movepoly` of the TopSolder polygon to its target; a plan naming a point that is no vertex | would_move; the bad one refused by the client |
| P12 | apply with the board tick | done; `polygons` shows every vertex moved by the offset, arcs included; Altium shows the opening moved and filled; unsaved |
| P13 | after Stefan saves and reopens: `polygons` again | same vertices, `bbox` agrees with them, `copper_pieces` 1 |

Record (2026-11-20, real 22p, runtime `selected-edits-20261120b`):

| # | Result |
|---|---|
| P10 | **pass**: started with no script error; `polygons` as P2 |
| P11 | **pass**: preview of the TopSolder polygon (8 vertices, four arcs) `would_move`; the client's tests cover a point that is no vertex |
| P12 | **pass, twice**: X +1.5 / Y +0.21 mm, then X -1.5 / Y -0.083 mm back onto Stefan's template. Each time every vertex and arc centre moved by the offset, the area stayed 131.48 mm2, `copper_pieces` went to 1 (0 after the hand moves) and `bbox` was right at once, with no reopen. Stefan's screenshot after the first move shows the fill at the new place and no remnant at the old one |
| P13 | pending |
