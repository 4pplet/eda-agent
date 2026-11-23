# Proposal: polygons from an outline, more free-object deletes, poured copper read, 2026-11-23

Status: **asked for by Stefan 2026-11-23** ("can we work our way through the backlog?" / "let's do it"), PLT-hw
`tools/eda-agent/TOOLS.md` backlog rows 8, 9, 10 and 12. Built the same day. Scripts `2026.11.23.1`, runtime
`selected-edits-20261123a` (mail workstation); carries everything in `2026.11.20.2`. **V1-V10 pending** (section 4);
of `2026.11.20.x`, P4-P9 and P13 are still pending and run on this runtime too.

## 1. What it adds

| Command | What | Notes |
|---|---|---|
| `pcb.edit_free_checked` `addpoly` | a new polygon on `layer` from an outline in `s1`; `s2` its net on copper | solid, pour over same net, repoured. Refused when a polygon with the same first vertex and count is already on the layer |
| `setpoly` | the polygon named by its first vertex `x1,y1` and vertex count `w` takes the outline in `s1` | the reshape of backlog 9; repoured |
| outline format | tokens separated by spaces: `x,y` a line vertex; `x,y,cx,cy,a1,a2` an arc from this vertex to the next, counter-clockwise, angles in millidegrees; 3-64 vertices, raw units | integers only: a decimal separator never crosses into Pascal (the workstation's locale uses a comma) |
| `delarc` | a free arc on a non-copper layer: `x1,y1` centre, `x2` radius, `y2` start angle in millidegrees (matched within 0.002 degrees) | |
| `delpad` | a free pad on `layer`: `x1,y1` centre, `x2` size, `y2` hole | the undo of a pad placed by the graphics writer |
| `clearlayer` | EVERY free line, arc, fill and region on a non-copper layer; `w` is the number the plan expects and the batch is refused when the layer holds another number | texts stay; objects in components, polygons and dimensions stay. One object is found and removed at a time, never while an iterator is open |
| `pcb.get_polygons` + `copper_index` | the poured copper of ONE polygon: each child region's outline and its holes, raw, at most 6000 points, `copper_truncated` | a via or pad the pour cleared is a hole in a piece; one it connects to is not. Answers "does this pour reach this via" |
| graphics text | a text placed on a layer whose name starts with `Bottom` is mirrored (`MirrorFlag`) | upstream `5cfd20f` |

How: `PolyWriteOutline` sets `PointCount`, writes each segment as a whole record (`Seg := TPolySegment`, as our
qualified shape op; an arc with `Kind := ePolySegmentArc`, `cx`, `cy`, `Radius`, `Angle1`, `Angle2`, as
upstream's circular board shape), then the closing vertex one past `PointCount` (upstream `ClosePolySegments`).
`addpoly` follows the fork's `PCB_PlacePolygonRect` (factory, layer, `ePolySolid`, outline, net,
`ePolygonPourOver_SameNet`, `AddPCBObject`, registration). Repour as the repour action (`PolygonRepour := 2` for
the call, `SetState_CopperPourInvalid`, `Rebuild`). Copper read: `Polygon.GroupIterator_Create` filtered to
regions (already used by the repour action's child count), `Region.MainContour` 1-based as the free-regions
read of `2026.11.20.1` measured it, `Region.HoleCount` / `Region.Holes[H]` as upstream's `RegionCopperSqMils`.

**New to this fork, proven only upstream:** `ePolySegmentArc`, `Seg.Radius`, `Region.Holes[H]`. Each sits on a
path of its own (an outline with arcs; a copper read of a pour with holes), so V4 and V8 are the checks that
decide them. An "Undeclared identifier" there stops that call with Altium's script error dialog.

Client (PLT-hw `tools/eda-agent`): `edit_plan.py` `addpoly` / `setpoly` with `rect_mm` (+ `corner_mm`) or
`vertices_mm` (turned counter-clockwise), `delarc`, `delpad`, `clearlayer` with `expect`;
`bridge_read.py polygons --copper-index N`. New offline tool `step_faces.py` (a STEP model's solids, planes
and cylinders from the file's text; no Altium).

## 2. Upstream review (salitronic/eda-agent `7a23938`, unchanged since 2026-11-20)

| Upstream | What | Taken |
|---|---|---|
| `ClosePolySegments` (PCBGeneric.pas) | the closing vertex at index `PointCount` must be rewritten, or a replaced outline keeps the old first vertex (a spike) | yes, in `PolyWriteOutline` (and since `.2` in `movepoly` and `shape`) |
| circular board shape | arc segments written as `ePolySegmentArc` with `cx`, `cy`, `Radius`, `Angle1`, `Angle2` on a `TPolySegment` | yes, the field set |
| `PCB_BevelPolygonCorners` | `BeginModify`, `PointCount`, segments, `SetState_CopperPourInvalid`, `Rebuild`, `EndModify`, `GraphicallyInvalidate` | yes, the order (`setpoly`) |
| `RegionCopperSqMils` | `Region.HoleCount`, `Region.Holes[H]` as contours | yes |
| `5cfd20f` | a text placed on a bottom layer is mirrored | yes |
| `PCB_Place3DBody` | a STEP model as a free 3D body; **no rotation**: "IPCB_ComponentBody exposes no Rotation ... assigning it raised Undeclared identifier, which DelphiScript cannot catch, and it took the polling loop down" | **not taken**: the display case needs a rotation (its long axis is the model's z), and the only route is `Model.SetState(RotX, RotY, RotZ, Dz)`, unproven here. Stefan places the body by hand; a mock model in board orientation is the alternative |
| polygon delete | none upstream by `RemovePCBObject` | not built: what happens to a pour's child regions is unproven. `setpoly` covers a change of shape |

## 3. Not in it

Polygon delete, a net on free copper (backlog 11), a via move that drags its tracks, a cut of a track, 3D
bodies, deleting texts with `clearlayer`.

## 4. Qualification (real 22p, git as rollback, nothing saved unless Stefan saves)

| # | Check | Pass |
|---|---|---|
| V1 | Altium starts from runtime `20261123a` with no script error; `polygons` and `freegraphics` as on 2026-11-20 | same rows |
| V2 | `polygons --copper-index` of a no-net holder pour (one piece) and of the top GND pour (35 pieces, many holes) | pieces = `copper_pieces`; holes where vias and pads are cleared; `copper_truncated` on the large one |
| V3 | `edit preview`: `addpoly` of a small rectangle on `TopSolder` on the holder (lines only) | would_add |
| V4 | apply V3; then `setpoly` of it to a rectangle with rounded corners | done; `polygons` shows the vertices, the arcs with their centres; Altium shows the shape filled |
| V5 | `addpoly` on a copper layer with a net that is not on the board; `setpoly` naming a point that is no vertex | refused natively / by the client |
| V6 | `delarc` of one Mechanical 15 template arc; `delpad` of a pad placed by `graphics` in the same session | deleted, read back |
| V7 | `clearlayer` preview with the wrong `expect`; with the right one on a scratch layer holding a few test lines | refused by the client; would_clear, then removed N, remaining 0 |
| V8 | a `graphics` text on `BottomOverlay` | mirrored in Altium and in `texts` |
| V9 | apply without the tick; apply after the board changed | stopped; refused |
| V10 | the real use: the top mask opening reshaped to the agreed outline, the Sapien drawing and the template cleared before the pack | `polygons` and `freegraphics` agree; `order_check` reference-layer step passes |

## 5. Qualification record

Pending.
