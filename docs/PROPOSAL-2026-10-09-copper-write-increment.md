# Proposal: copper placement from a checked plan (vias and tracks), 2026-10-09

Status: **approved and built the same day** (Stefan, 2026-10-09: "let's add the tool support");
native qualification pending (section 5). Scripts `2026.10.09.1`, client PLT-hw `tools/eda-agent`.
Follows [PROPOSAL-2026-10-07-placement-write-increment.md](PROPOSAL-2026-10-07-placement-write-increment.md)
and keeps its gates.

## 1. Why this, why now

The HDMI board's TC358870 (0.65 mm BGA) fanout is a checked plan (PLT-hw
`hdmi-adapter/reviews/bga-fanout-2026-10-05.plan.json`, `layout-plan/1`): 66 vias and 150 traces
with net, position, size and layer, verified by two independent checkers (`layout_plan.Plan.check`,
`plan_verify.py`) and compared with the live board by `bridge.cmd plancheck`. Placing that by hand
is one to two hours of exact work that the plan already holds, and the same pattern recurs for the
rail groups, the stitching vias and every later board. Stefan asked whether the bridge could place
vias with their nets; it could not.

## 2. Where writes are blocked today (keep both)

As for the placement write: `ProcessSelectedCommand`'s allowlist in `SelectedProject.pas`, and
the Python `SharedReader.send` policy. Both now admit one more command, only in a runtime
generated with `--place-edits`.

## 3. Audit of the candidate handlers: do not expose them as-is

Upstream `PCB.pas` has `PCB_PlaceVia`, `PCB_PlaceTrack`, `PCB_PlaceTracks` (and `PCB_GetVias`,
`PCB_GetTracks`, `PCB_DeleteObject`). Read 2026-10-09:

| | Finding |
|---|---|
| C1 | `GetPCBBoardAnywhere(0)`: the focused board, not the selected project's (M1 again) |
| C2 | Coordinates, sizes and widths in **whole mils**: a 0.30 mm via becomes 0.305 mm, its 0.15 mm hole 0.152, and the 0.65 mm ball grid lands 0.01 mm off |
| C3 | `StrToIntDef(..., 0)`: a malformed number becomes a via at the origin (M3 again) |
| C4 | A net that does not exist is silently skipped: the via is placed **without a net** |
| C5 | No clearance test against the copper already on the board; no duplicate test, so a re-run doubles every object |
| C6 | No compare-and-set, no read-back, no dirty-board refusal; `PCB_PlaceTracks` batches with `|` and `,` as both delimiters |
| C7 | `MarkDocDirtyByPath` yes, but nothing reports what was placed |

## 4. The increment

**Command:** `pcb.place_copper_checked` (native) / `pcb_place_copper_checked` (MCP). One board per
call: the selected project's PcbDoc, resolved exactly (`ResolveSelectedBoard`).

| Rule | Detail |
|---|---|
| **Gate and grant** | `SELECTED_PLACE_EDITS` runtime only; apply needs the same operator tick as the component moves, "Allow placement edits": one tick, one batch, cleared when anything was placed |
| **Objects** | Free through vias (`net, x, y, size, hole, clearance`) and track segments (`net, layer, x1, y1, x2, y2, width, clearance`), every number a raw Altium coordinate as an integer (C2, C3); at most 300 vias and 500 tracks; layer by the board's own layer name, resolved and required to be copper |
| **Net** | Must exist on the board, or the object is refused (C4) |
| **Clearance** | Each object carries the clearance it must keep (the plan's rule where it lies: 0.10 mm in the BGA room, 0.15 outside). The native side measures the true gap (segment-to-segment, segment-to-circle for round pads and vias, segment-to-rectangle for other pads) to every pad, via, track and arc of another net on the relevant layers, after a bounding-box prefilter. Inside the gap: refused, naming the nearest object (C5) |
| **Idempotent** | An identical free object (same net, geometry, size, layer) already on the board reads `unchanged`, so a second run of the same batch places nothing (C5) |
| **Compare-and-set** | Preview reports the board's free via and track counts; apply carries them back and the batch is refused if either changed (C6) |
| **Clean baseline** | `PCB_DIRTY` refuses a PcbDoc with unsaved edits; one batch per save |
| **Honest result** | Per object `would_place` / `unchanged` / `refused: reason` at preview; `placed` / `unchanged` / `not_placed` / `placed_readback_differs` at apply, with the geometry read back from the created object (C6, C7). Stops at the first surprise, reports what was placed, never rolls back |
| **Never save** | The document is left dirty; the operator reviews and saves, or closes without saving |

**Not checked natively, by design:** the batch's objects against each other (the plan checkers do
that with the plan's own geometry), polygons and regions (none on this board yet; a pour is a
later increment), and design rules (Altium DRC after the save).

**Client (PLT `bridge_write.py copper`, `bridge.cmd plancheck --emit-copper / --copper`):**

1. `bridge.cmd plancheck --plan <plan> --emit-copper <batch.json>` fits the plan to the live
   anchor (as for moves), maps each plan net to its live net through the pads they share, maps
   plan layers `L1..Ln` to the board's copper layers in stack order (the stackup read), splits
   polyline traces into segments, converts to raw coordinates and attaches the plan's clearance
   per object. Objects whose plan net maps to two live nets are left out and listed.
2. `bridge_write.py copper preview <batch.json>` prints every refusal, the free counts and an
   approval hash that binds the board, the free counts and each object's previewed status.
3. `bridge_write.py copper apply <batch.json> --hash <h>` sends one native call with the
   previewed counts, then previews again and expects every object to read `unchanged`.
4. `bridge.cmd plancheck --copper` reads the board's vias and tracks and reports which of the
   plan's are there (`vias_found / missing`, `tracks_found / missing`, unplanned copper in the
   plan's window); then Altium DRC.

## 5. Qualification: one native sitting, disposable copy (or the live board with git as rollback)

Pinned runtime, record the Altium version and hashes.

| Test | Pass means |
|---|---|
| C1 happy path | the U501 plan's vias and tracks placed in one batch (or two, under the limits); every object read back exact; a second preview reads all `unchanged`; `plancheck --copper` complete; DRC clean for clearance inside the room |
| C2 precision | a via at a coordinate off the mil grid reads back at that raw coordinate |
| C3 malformed | a float, a hole >= size, a zero-length track, an unknown layer: refused by the client and, sent raw, natively; nothing placed |
| C4 net | a net name not on the board: `refused: net not on the board`, nothing placed |
| C5 clearance | a track through a foreign-net ball: `refused: pad ... within clearance`; a track ending on its own net's pad: `would_place` |
| C6 idempotent | the same batch applied twice: the second apply places nothing (`unchanged`) and the free counts do not change |
| C7 stale | a via added by hand (saved) between preview and apply: `PREFLIGHT_REFUSED ... free copper changed` |
| C8 dirty | an unsaved hand edit: `PCB_DIRTY` |
| C9 grant | untick, Detach, project switch: refused each time, also on a direct native request |
| C10 undo and recovery | what one Ctrl+Z reverts; close without saving restores the board |
| C11 disconnect | client killed during apply: `OUTCOME UNKNOWN`; the next preview shows the true state |
| C12 nets | after the save, `ecopreview` and `nets --expect`: no netlist change; the Nets panel shows each via and track on its net |

## 6. Out of scope

Polygons and regions, arcs, blind or buried vias, deleting or moving copper, rules, classes,
the stackup, and saving. Each a later increment if it earns one.

## 7. Effort

Native handler about 550 lines (geometry helpers included), server tool and validation, client
subcommand, plan emitter and copper comparison, 30 offline tests: one day. Operator's time: a
deploy window and one qualification sitting of about an hour.

## 8. Implementation, 2026-10-09

- **Native** (`SelectedProject.pas`, `SelectedPlaceCopperChecked` with `CopperNearest`,
  `CopperViaExists`, `CopperTrackExists`, `CopperCountFree` and the segment geometry): as in
  section 4. The grant and generation handling is the move command's.
- **Gate:** the existing `SELECTED_PLACE_EDITS`; the StatusForm caption now says "place plan copper".
- **Server:** `pcb_place_copper_checked` in `shared_server.py` with `validate_copper_edits` /
  `validate_copper_edit_result` and the NO_WRITE / OUTCOME_UNKNOWN classification of the move tool.
- **Client:** `bridge_write.py copper preview|apply`; `plan_compare.emit_copper` /
  `compare_copper`; `bridge_read.py plancheck --emit-copper / --copper`.
- **Tests:** PLT-hw `test_copper_edits.py`, `test_plan_compare.py` (emit and compare on the HDMI
  plan turned 90 degrees), `test_place_edits.py` (tool surface); eda-agent source contracts and
  `lint.py` clean.

## 9. Qualification log

**2026-10-09, live HDMI project (Stefan's choice, git as rollback: PLT-hw 8078953 before, 68971b1
between the two applies), runtimes `selected-edits-20261009` to `-20261009d`.**

- **First compile:** the new Pascal compiled at its first load (scripts 2026.10.09.1); profile
  `eda-selected-edits-v1`, the grant state carried in the selection identity.
- **Three defects found by the first previews, each fixed and reloaded the same hour:**
  1. `2026.10.09.1`: seven refusals on spots the offline geometry found clear. `.2` added the
     nearest prim's rectangle to the refusal: a pad's `BoundingRectangle` includes its solder-mask
     expansion (0.85 x 0.80 mm read as 1.05 x 1.00), and DelphiScript kept integer arithmetic for
     the typed-Double parameters, overflowing on products of raw coordinates.
  2. `.3`: pads measured from centre and size (turned with the pad), every distance forced to
     floating point. Two refusals left, both 0.148 against 0.15: a segment leaving the BGA room had
     the outside rule for its whole length, and the fit to the balls is in whole mils. Fixed in the
     emitter (the strictest rule along the object, less the read resolution), not natively.
  3. `.3` apply: 66 vias placed and read back exact, then stopped after the first track because
     Altium stored its ends in the other order (`placed_readback_differs`); 214 not placed, the
     result honest. `.4` accepts either end order. Stefan saved the 66 vias + 1 track; the second
     apply found all 67 `unchanged` (the idempotence test on a real board) and placed the 214.
- **A wrong selection caught:** one preview ran against the 22p project (every net "not on the
  board", free copper 525 / 2300); nothing is written by a preview, and `--expect-project` now
  guards every run.

| Test | Result |
|---|---|
| C1 | **Pass.** The U501 plan's 66 vias and 215 segments on the board; a second preview reads all 281 `unchanged`; `plancheck --copper` complete (see the PLT-hw record); DRC pending the rules |
| C2 | **Pass** by the batch itself: every coordinate is an off-mil-grid raw value and read back exact |
| C6 | **Pass** (unplanned): the second apply read the first apply's 67 objects as `unchanged`, free counts 72 / 117 |
| C4 | **Pass** (unplanned): the 22p board refused every object with `net not on the board` |
| C3, C5, C7-C12 | Open |

Timing: a preview of 281 objects takes about three minutes on this board (one board iteration per
object); an apply about three more plus the verifying preview. Acceptable for a fanout; a candidate
list built once per call would cut it if a later board needs it.
