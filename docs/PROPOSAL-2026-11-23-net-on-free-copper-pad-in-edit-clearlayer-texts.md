# Proposal: a net on free copper, a pad in an edit batch, texts in clearlayer, free pads read, 2026-11-23

Status: **asked for by Stefan 2026-11-23** ("let's fix all the backlog items", Altium closed), PLT-hw
`tools/eda-agent/TOOLS.md` backlog rows 11 (part), 14, 15, 16 (part), 17, 18 (one word). Built the same evening.
Scripts `2026.11.23.2`, runtime `selected-edits-20261123b` (mail workstation); carries everything in
`2026.11.23.1`. **W1-W8 pending** (section 4). **Superseded the same night by scripts `2026.11.23.3`, runtime
`selected-edits-20261123c`** (section 6: a library part placed on a sheet, backlog 5; W9-W11 pending), which
carries all of `.2`. Runtime `b` was never started in Altium.

## 1. What it adds

| Command | What | Notes |
|---|---|---|
| `pcb.edit_free_checked` `setnet` | the net of a free via (`x1,y1` centre, `x2` size, `y2` hole), a free pad (the same, on `layer`) or a polygon (`x1,y1` first vertex, `w` vertex count) becomes the net in `s2`; `s1` is `via` / `pad` / `poly` | the net must be on the board; a polygon is repoured. **No clearance test** (nothing moves): a wrong net is a short the DRC finds, so a DRC follows every use |
| `addpad` | a free round pad on MultiLayer: `x1,y1` centre, `x2` size, `y2` hole, `w` 1 plated / 0 not, `s2` its net | the graphics writer's pad inside an edit batch: a `delvia` before it turns a via into a pad under ONE tick and one save. Refused within the clearance of other-net copper; an identical pad already there reads `unchanged` |
| `clearlayer` + `s1 = texts` | the layer's free texts go as well; `s2` is the number of texts the plan expects | counted and refused separately from the objects in `w`; texts in components and dimensions stay |
| `pcb.get_free_graphics` + `pads` | free pads (not in a component): layer, net, `x`, `y`, `size`, `size_y`, `hole`, `plated`, raw; at most 500, `pad_total` | a hand-placed pad can be found and named for `delpad` / `setnet` |

How: `setnet` on a via or pad is `Net :=` between the `PCBM_BeginModify` / `PCBM_EndModify` messages (as
`movevia` writes `x` / `y`); on a polygon `BeginModify`, `Net :=`, the repour of `setpoly`, `EndModify`.
`addpad` is the pad block of `pcb.place_graphics_checked` (qualified G1-G8, 2026-11-18) copied into the edit
writer. `FreeLayerTexts` is `FreeTextCount` without the position and string test. The pads read is the
iterator of `FreePadCount`.

**New to this fork:** `Via.Net :=` and `Pad.Net :=` on an EXISTING object (both are assigned at creation in
the copper and graphics writers), `Poly.Net :=` on an existing polygon (assigned at creation in `addpoly`),
`Pad.TopYSize` as a read (written in the graphics writer). No identifier is new.

Client (PLT-hw `tools/eda-agent`): `edit_plan.py` `setnet` (`kind` via / pad / poly), `addpad`, `clearlayer`
with `texts`; `bridge_read.py freegraphics` adds mm to `pads`; `polygons` adds `area_with_arcs_mm2` (computed
in the client from the vertices: the chord polygon plus or minus a circular segment per arc; `area_mm2` stays
the native chord area). `bridge_write.py setup` accepts the scope word `InAnyComponent` (Altium's query
language has it by its documentation; **not proven live**, W6).

## 2. Upstream review

salitronic/eda-agent was reviewed at `7a23938` for `2026.11.23.1` the same day; nothing here uses an API that
build did not already use, so no new scan was made.

## 3. Not in it

Polygon delete (child regions after `RemovePCBObject` unproven), 3D bodies (rotation unproven), a second
batch on an unsaved board, a net on a free fill, parameter add / bottom-side placement / rule delete (backlog
3), track cut and a via move that drags its tracks (backlog 4), schematic part add (backlog 5). Each needs
identifiers or behaviour proven on a disposable copy in a live session first.

## 4. Qualification (real board, git as rollback, nothing saved unless Stefan saves)

| # | Check | Pass |
|---|---|---|
| W1 | Altium starts from runtime `20261123b` with no script error; `freegraphics` lists the six mounting pads of the 22p under `pads` (GND, 5.0 / 3.5, plated) | 6 rows, `pad_total` 6 |
| W2 | `polygons`: `area_with_arcs_mm2` of the bottom mask opening | about 1854.07 (chord area 1851.5) |
| W3 | `setnet` preview and apply on one scratch no-net via placed for the test, to GND; then `delvia` | would_set (was ""), done, read back `net GND`; the via reads GND in `vias` |
| W4 | `addpad` + `delvia` in one batch (a scratch via turned into a pad), then `setnet` of that pad to another net and back | one tick; pad in `freegraphics`; net read back |
| W5 | `setnet` of a scratch polygon (`addpoly` on a copper layer, no net) to GND | would_set, done, repoured, `polygons` shows the net |
| W6 | `setup` with a scratch polygon-connect rule scoped `IsPad And Not InAnyComponent` | created with no script error; the rule lists in `rules`; then the real `PolygonConnect_FreePads` (direct) on both boards |
| W7 | `clearlayer` with `texts` on a scratch mechanical layer holding two lines and one text; a wrong `texts` count first | refused by the client; then removed 2, texts removed 1, remaining 0 |
| W8 | `setnet` to a net that is not on the board; `addpad` on top of other-net copper | refused natively |

## 5. Qualification record

Pending.

## 6. Scripts 2026.11.23.3: a library part on a sheet (`proj.edit_schematic_checked` op `part`)

Stefan 2026-11-23: "I'll test creating schematics using the MCP soon". Until now the checked writer edited
sheet-level objects only (labels, power ports, wires, text, notes, boxes, lines, parameters) and never placed
a part. The fork already carries upstream's placement, `Gen_PlaceSchComponentFromLibrary` (Generic.pas), which
upstream records as the working API after `PlaceSchComponent` proved broken: `SchServer.LoadComponentFromLibrary
(reference, path)`, `AddSchObject`, `MoveToXY`, `SetState_Orientation`, `Designator.Text`, registration. The
generic tool is not reachable in a selected-project runtime; `part` runs the same calls behind the writer's
gates.

| Item | `part|sheet|x1|y1|0|0|n|s1|s2|s3` |
|---|---|
| `x1,y1` | the part's reference point, raw (10000 per mil) |
| `n` | orientation 0-3 (0, 90, 180, 270 degrees) |
| `s1` / `s2` / `s3` | library reference / absolute `.SchLib` path / designator (`U408`, or `U?` for annotate) |

Preflight (nothing written on any refusal): the sheet is saved; the reference is found in the library file by
`ResolveLibRef` (upstream: read off disk through `CreateLibCompInfoReader`, because a load that fails inside
Altium raises a modal dialog no handler catches); no part sits at that location; the designator is not on the
sheet. The client also refuses a designator that is anywhere in the project and a library path that is not an
existing absolute `.SchLib`. Read back: one part at the location carrying the designator.

**New to this fork's checked path, proven upstream only:** `SchServer.LoadComponentFromLibrary`,
`Comp.MoveToXY`, `Comp.SetState_Orientation`, `SchServer.CreateLibCompInfoReader` and its reader
(`ReadAllComponentInfo`, `NumComponentInfos`, `ComponentInfos[I].CompName`). They are the only calls on this
path, so W9 decides them. Upstream's caveat: a multi-part symbol can load with a lower part count than the
library's (Generic.pas, `PartCount`); `part` places part 1 of a symbol and is meant for single-part symbols.

Not in it: a new sheet, ports, sheet symbols and entries, buses, No ERC markers, junctions (Altium adds them
on a wire T), moving or deleting a part, choosing a sub-part, footprint override. A placed part's pins are in
the NEXT read only, so wiring (`pinnet` / `pinpower`) is a second plan after the operator has saved.

| # | Check | Pass |
|---|---|---|
| W9 | on a scratch sheet of a disposable project copy: `sch preview` then `apply` of one `part` from `lib/PLT_lib.SchLib` (a resistor, `R?`) | no script error; the part shows on the sheet at the place, rotated as asked; `sch read` lists its pins |
| W10 | a second plan: `pinnet` / `pinpower` on the new part's pins; save; `sch verify` | the compiled netlist has the pins on the nets |
| W11 | refusals: an unknown `lib_ref`; a designator already used; a part already at the location | refused with the reason, nothing written, no dialog |

## 7. Scripts 2026.11.23.4: polygon delete, rule delete, part flip, 3D body; audit fixes

Stefan 2026-11-23, on the list of what was still not built: "we can build this?" / "this is a good time for it".
Runtime `selected-edits-20261123d`, carries `.3`. **Runtimes `b` and `c` were never started; `d` is the one to
start. W1-W16 pending.** `lint.py` reports 0 errors on this build.

| `pcb.edit_free_checked` op | What | From |
|---|---|---|
| `delpoly` | the polygon with first vertex `x1,y1` and `w` vertices removed (`RemovePCBObject` after the registration message) | new: **what becomes of the pour's child regions is not known.** W12 on a scratch polygon decides it; until then not on a real pour |
| `delrule` | the design rule named `s1` removed; refused unless exactly one rule carries the name | upstream `PCB_DeleteDesignRule` |
| `flip` | the part `s1` to the other outer layer (`Comp.Layer :=` between the modify messages) | upstream `PCB_FlipComponent`. Tracks on the part's pads stay where they are: for unrouted parts |
| `body3d` | the STEP model at path `s1` (forward slashes, turned into backslashes natively) as a free 3D body: origin at `x1,y1`, `layer` TopLayer / BottomLayer, `x2` standoff. No rotation | upstream `PCB_Place3DBody`, in its order of calls (factory, `ModelFactory_FromFilename`, `SetState_FromModel`, `Model :=`, add and register, THEN layer, `MoveByXY`, `StandoffHeight`): upstream measured an access violation in ADVPCB.DLL with any other order. **First on a disposable board copy** |

Audit fixes: `addpad` skips the clearance test when the same batch deletes a via at the same centre that is at
least as large (a no-net via becomes a GND pad in one batch); `PolyVertices` no longer passes `''` as an
argument (lint `empty-string-literal-arg`, four times; the code had passed V3 / V4 live).

Not built: a track cut and fills / texts / lines inside an edit batch (they need the copper writer's track
creation inside the edit writer), bottom-side moves in `moves`, a second batch on an unsaved board (a safety
gate: Stefan's decision), parameter add in the PCB parameter writer.

| # | Check | Pass |
|---|---|---|
| W12 | disposable copy: `addpoly` a small no-net polygon on a copper layer, then `delpoly` it | would_delete, done, remaining 0; `polygons` and the layer's regions show nothing left behind; DRC clean |
| W13 | `setup` a scratch rule, then `delrule` it | would_delete, done; gone from `rules` |
| W14 | disposable copy: `flip` an unrouted two-pad part and back | on the bottom, then on the top; pads on the right layer |
| W15 | disposable copy: `body3d` with `display-on-board.step` at the board origin | no crash; the body shows in 3D where the holder is |
| W16 | `delvia` + `addpad` of a no-net via to a GND pad in one batch | would_place (replaces a via of this batch), done |

## 8. Scripts 2026.11.23.5: `setnet` with a clearance test

Runtime `selected-edits-20261123e`, carries `.4`. **Runtimes `b`, `c` and `d` were never started; `e` is the
one to start. W1-W17 pending.** `lint.py`: 0 errors.

`setnet` on a via or a pad is now refused when other-net copper (pads, vias, tracks, arcs) lies within the
plan's clearance of its spot under the NEW net: that would be a short. The test is `CopperNearestExcept`, a
copy of `CopperNearest` that leaves one primitive out (the object itself still carries its old net and would
be found on its own spot); the qualified `CopperNearest` that the copper, graphics and via writers use is not
touched. A polygon has no such test: it repours around what is there, and the DRC is its check. This replaces
"no clearance test" in section 1.

| # | Check | Pass |
|---|---|---|
| W17 | `setnet` of a scratch no-net via that sits on a track of another net, to GND; then of a free one | refused naming the track and the gap; the free one would_set, done |

## 9. Scripts 2026.11.23.6: the schematic writer: a new sheet, ports, No ERC, a part deleted / moved / rotated

Stefan 2026-11-23: "let's build the missing pieces and add to todo what we need to test". Runtime
`selected-edits-20261123f`, carries `.5`. **Runtimes `b` to `e` were never started; `f` is the one to start.
W1-W21 pending**; the test list in order is PLT-hw `tools/eda-agent/QUALIFY-TODO.md`. `lint.py`: 0 errors.

| `proj.edit_schematic_checked` | What | From |
|---|---|---|
| `newsheet|0|...|s1 = name` | a new, empty `<name>.SchDoc` beside the project file, saved and added to the project. **The one op that writes a file at once**; the client lets it stand alone in its plan. Run before the per-sheet writes, outside any sheet's edit transaction | upstream `Gen_AddSheet`: `Client.OpenNewDocument('SCH', path, name, False)`, `SetFileName`, `DoFileSave`, `DM_AddSourceDocument` (their note: the WorkspaceManager process without a file name raised a modal dialog) |
| `add` kind `port` | a port at `x1,y1`: `s3` its name, `s2` its style (none, left, right, left_right), `n` its IO type (0 unspecified, 1 output, 2 input, 3 bidirectional) | upstream `Gen_PlacePort` |
| `add` kind `noerc` | a No ERC marker at `x1,y1` | upstream `Gen_PlaceNoERC` |
| `del` kind `port` / `noerc` | through the writer's existing delete (found by location) | |
| `delpart` / `movepart` / `rotpart`, `s1` = designator | the part removed (`RemoveSchObject` + the announcement the writer's `del` uses); moved to `x2,y2` (`MoveToXY` between the modify calls); orientation `n` 0-3 (`SetState_Orientation`). Refused when the designator is on the sheet more than once (a multi-part symbol). Wires do not follow a moved part | `MoveToXY` and `SetState_Orientation` as in `part` (section 6) |

Client: `sch_plan.py` ops `newsheet`, `delpart`, `movepart`, `rotpart`, `port`, `noerc`. Offline
`schlib_parts.py <lib.SchLib> [filter]` lists a library's part names (the `lib_ref` of `part`) from the
file's `FileHeader`, without Altium.

**New on this path, proven upstream only:** `Client.OpenNewDocument`, `IServerDocument.SetFileName` /
`DoFileSave`, `ISch_Port` (`Name`, `Style`, `IOType`, `ePort...`), `eNoERC`, `RemoveSchObject` on a component.

Not in it: sheet symbols and entries, buses and bus entries, harnesses, sub-parts of multi-part symbols,
footprint choice on a placed part, symbol and footprint library editing, Update PCB.

| # | Check (disposable project copy) | Pass |
|---|---|---|
| W18 | `newsheet` | the SchDoc is on disk beside the project and in the project panel; no dialog; `sch read` lists it |
| W19 | `port` in each style and IO type, `noerc`; then `del` of one port and of the marker | shown as asked; deleted; no script error |
| W20 | `movepart`, `rotpart`, `delpart` on the part placed in W9 | at the target; rotated; gone |
| W21 | a small real flow on the new sheet: two parts, wires, labels, a port, power ports; save; compile | `nets` shows the pins on the nets |
