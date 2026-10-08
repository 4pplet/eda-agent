# Proposal: a placement-write increment (move components from a checked plan)

**Status: approved by the operator 2026-10-07 and implemented in source the same day (scripts
`2026.10.07.1`, section 8). NOT deployed; the native qualification (section 5) is open, on a
disposable copy, before any live use.** It follows the
pattern of the [metadata-write increment](PROPOSAL-2026-09-28-metadata-write-increment.md), which
is live since 2026-10-05: a narrow new handler instead of an exposed upstream one, the operator's
tick per batch, compare-and-set, read-back, never save.

## 1. Why this, why now

The HDMI board's U501 (TC358870, 0.65 mm BGA) has a checked layout plan: 16 parts beside the
package, on their PLT_lib pads, with positions and rotations that two independent checkers pass
(PLT-hw `hdmi-adapter/reviews/bga-fanout-2026-10-05.plan.json`). Placing them by hand means typing
about 16 x / y / rotation triples into the Properties panel, relative to wherever U501 ends up.

That transcription is where errors come in. The plan itself carried one until 2026-10-07: five
caps and R501 had their pins the other way round from the CAD, which only the new
`bridge.cmd plancheck` (read-only, PLT-hw `plan_compare.py`) caught. A batch generated from the
checked plan removes the transcription. The same `plancheck` then verifies the result before
anything is saved.

Moves are a low-risk write class: no connectivity, no ECO, no copper (placement precedes routing,
and this increment refuses parts with routing attached). `plancheck` and Altium's own DRC verify
the result.

## 2. Where writes are blocked today (keep both)

Unchanged from the metadata increment: the Python `ALLOWED` set in PLT `shared_server.py`, and
`Dispatcher.pas` routing every command to `ProcessSelectedCommand` while
`SELECTED_PROJECT_READ_ONLY`. The increment adds **one command to both**. It does not flip
`SELECTED_PROJECT_READ_ONLY`.

## 3. Audit of the candidate handlers: do not expose them as-is

`PCB_MoveComponent` and `PCB_BatchMoveComponents` (`scripts/altium/PCB.pas`, around lines 1806 and
3594) do the move itself correctly: `PreProcess`, `PCBM_BeginModify`, set `x` / `y` / `Rotation`,
`PCBM_EndModify`, `PostProcess` per component, then mark the document dirty. Read line by line,
they have these problems for our use:

| # | Finding | Why it matters |
|---|---|---|
| M1 | **Board = `GetPCBBoardAnywhere(0)`**: the focused or first open board | Violates *never infer the target from the focused window*. With the 22p and HDMI boards both open, a batch could land on the wrong board |
| M2 | **Coordinates in whole mils** (`StrToIntDef`, `MilsToCoord`) | 0.0254 mm steps. The plan has parts at exactly 0.30 mm from their limits; rounding can cost 0.013 mm of that. Altium's internal unit is 1/10000 mil |
| M3 | **A malformed number becomes 0** (`StrToIntDef(.., 0)`, `StrToFloatDef(.., 0)`) | A typo moves the part to the board origin, or rotates it to 0, and reports success |
| M4 | **Locked parts are moved anyway** | The operator's lock is the one signal that a part is final |
| M5 | **Batch failures are counted, not named**; an unknown designator is skipped silently | The response cannot say which part did not move |
| M6 | **No side check.** The layer is untouched, so a part on the wrong side stays there | Single-sided board: a flip is never what a plan move means. This increment refuses side changes rather than performing them |
| M7 | The batch's header comment says *"Save runs once at the end"*; **the code does not save** | The behaviour (no save) is what we want; the comment is stale |
| M8 | Undo: one `PreProcess` / `PostProcess` pair per component | **Undo is plausible, per part, not qualified** (T9) |
| M9 | Rotation is set on the component, which turns about its origin | Correct for a plan that records the footprint origin (`parts[].at`). Qualify that the pads land where the plan says (T14) |
| M10 | Tracks attached to the part's pads are not dragged by an API move | Irrelevant before routing; the increment refuses parts with routing attached |

**Verdict:** write a narrow PLT handler on the ForBoard pattern that reuses the move sequence and
fixes M1-M6 and M10. Do not patch the upstream handlers in place.

## 4. The increment

**Command:** `pcb.move_components_checked` (native) / `pcb_move_components_checked` (MCP). One
board per call: the selected project's PcbDoc, resolved exactly.

| Rule | Detail |
|---|---|
| **Target** | The selected project's PcbDoc only. No focused-board fallback (M1) |
| **Session grant** | Native refusal unless the operator has ticked **"Allow placement edits (this session)"** on the StatusForm. This is a separate box from parameter edits. One tick covers one batch, and the grant clears on session end, Detach and a selection switch. The agent cannot tick it |
| **Coordinates** | Raw Altium coordinates as integers (M2), rotation 0 / 90 / 180 / 270 only. Anything else is refused in preflight (M3) |
| **Compare-and-set** | Each move carries the part's x / y / rotation / layer as read at preview. Preflight the whole batch and refuse **all** of it if any part has moved since |
| **Refusals** | Locked part (M4), a side or layer change (M6), an unknown designator (M5), and a pad with a track or arc attached (M10) |
| **Clean baseline** | Refuse if the PcbDoc is already dirty. One batch per save |
| **Honest result** | Per part: `moved` / `unchanged` / `refused` and the reason, with x / y / rotation **read back** after the write |
| **Never save** | The document is left dirty. The operator's save approves the result; close without saving is the recovery |

**Client (PLT `bridge_write.py`, new subcommand `moves`):**

1. `bridge.cmd plancheck --plan <plan> --emit-moves <batch.json>` writes the batch: for every
   planned part not yet within tolerance, the target origin and rotation in the board frame,
   derived from the anchor's live position. **The anchor (U501) is placed by the operator**; the
   plan follows wherever it goes.
2. `bridge_write.py moves preview <batch.json>` reads each part live and prints
   `ref: (x, y, rot) -> (x, y, rot)`, with distances in mm and an approval hash. It is dry, and
   the default.
3. `bridge_write.py moves apply <batch.json> --hash <h>` refuses if the hash or any part changed
   since preview, sends one native call, and reads back.
4. Then `bridge.cmd plancheck` again: every moved part should report `ok`.

## 5. Qualification: one non-CAD sitting, disposable copy

Pinned runtime version, on a copy of the HDMI project. Record the Altium version and hashes.

| Test | Pass means |
|---|---|
| T1 happy path | 16 planned parts moved in one batch; read-back exact; `plancheck` all ok; netlist unchanged (`ecopreview` and `nets --expect` as before) |
| T2 precision | a target off the mil grid lands within one internal unit |
| T3 malformed | a non-numeric coordinate or a 45 degree rotation: refused in preflight, nothing moved |
| T4 no fallback | another PcbDoc focused: the selected project's board is the one written, or the call is refused; the other board stays clean |
| T5 stale | one part nudged by hand after preview: whole batch refused |
| T6 locked | a locked part in the batch: refused, nothing moved |
| T7 side | a part on the bottom, or a target on the other side: refused |
| T8 unknown | a designator not on the board: refused in preflight |
| T9 **undo** | record what one Ctrl+Z reverts: the batch, one part, or nothing. This decides the recovery story |
| T10 recovery | close without saving and reopen: every part at its pre-batch position |
| T11 grant | grant off: refused natively, including a direct native request that bypasses Python; Detach and selection switch clear it |
| T12 dirty target | the PcbDoc pre-dirtied by hand: refused |
| T13 disconnect | client killed mid-apply: outcome reported unknown; the next preview shows the true state; no automatic retry |
| T14 rotation pivot | a part rotated by 90 / 180 / 270 has its pads where the plan puts them (pad read within 1 mil) |
| T15 routed part | a part with a track on one pad: refused |

**Exit:** all 15 pass on the copy. Only then does the command go into the live PLT runtime.

## 6. Out of scope

Flips and bottom-side placement, creating or deleting components, moving the anchor, tracks,
vias, rooms, rules, classes and the stackup (each a later increment if it earns one), and saving.

## 7. Effort

- **Native handler:** about 150 lines of Pascal on the ForBoard pattern, from the metadata
  handler's grant and compare-and-set code.
- **The rest:** the Python server entry, the client `moves` subcommand, `plancheck --emit-moves`,
  and offline tests.
- **Operator's time:** a deploy window and one qualification sitting of about an hour in Altium.

## 8. Implementation, 2026-10-07

Scripts `2026.10.07.1` (eda-agent `scripts/altium`), client PLT-hw `tools/eda-agent`.

- **Native** (`SelectedProject.pas`, `SelectedMoveComponentsChecked`): the selected project's
  PcbDoc through `ResolveSelectedBoard`, never `GetPCBBoardAnywhere` (M1).
  - Raw coordinates as integers; a strict integer parser refuses anything else (M2, M3).
  - Rotation 0 / 90 / 180 / 270 only.
  - Refusals, each named (M5): not on the board, locked (`Moveable = False`, M4), not on
    TopLayer (M6), copper track / arc / via overlapping the part's bounding rectangle (M10),
    moved since the preview.
  - Apply: every part re-read; rotation set before x / y, so the origin lands where asked
    whatever the pivot; read back. Then mark dirty, never save; one tick, one batch.
  - At most 100 moves; `PCB_DIRTY` refuses a board with unsaved edits.
- **Gate:** `Main.pas` `SELECTED_PLACE_EDITS`, set only by
  `create_shared_runtime.py --place-edits`. That runtime also has `SELECTED_PARAM_EDITS`: mode
  `selected-project-edits`, ping profile `eda-selected-edits-v1`, `place_edits` in the selection
  identity.
- **Operator grant:** a second StatusForm tick, "Allow placement edits". Ticking either grant
  moves the selection generation, so the two can never be active at once.
- **Server:** `pcb_move_components_checked` with the same NO_WRITE / OUTCOME_UNKNOWN
  classification as the parameter tool; `PCB_DIRTY` and the board-resolution codes count as
  pre-write.
- **Client:** `bridge_write.py moves preview|apply BATCH [--hash]`. The batch comes from
  `bridge.cmd plancheck --plan P --emit-moves BATCH`, which leaves out missing parts, parts on
  the wrong side and parts whose pin nets differ from the plan.
- **Tests:** PLT-hw `test_place_edits.py` and `test_plan_compare.py`, offline. What Altium does
  with the move is what section 5 qualifies.
- **2026-10-08 (scripts `2026.10.08.1`):** the routed-part refusal tests the component's own
  extent (`PlaceEditExtent`: pads, tracks, arcs, regions, fills), not `BoundingRectangle`, which
  spans the designator / comment text; eight parts had been refused because their labels reached a
  mounting-hole ring (Stefan: not on designator text).
- **Differences from section 4:** the routing check is the bounding-rectangle overlap
  (conservative, before routing), not a per-pad connection test. The StatusForm's
  parameter-grant caption no longer says "LCSC Part #, Instruction" (stale since the widening).

## 9. Qualification runbook (for the sitting)

Runtime: `create_shared_runtime.py --place-edits` into a new directory. Point `bridge.cmd` at it
with `EDA_AGENT_SHARED_ROOT`, and `bridge_write.py` with `--shared-root`. Commit the design files
first. The target is a copy of the HDMI project, or, if the operator chooses as on 2026-10-05,
the live project with git as the rollback.

| Test | Do | Expect |
|---|---|---|
| T1 | Place U501 by hand. `bridge.cmd plancheck --plan <plan> --emit-moves m.json`; `bridge_write.py moves preview m.json`; tick; `moves apply m.json --hash H` | all 16 moved, read-back exact; `plancheck` 16/16 ok; `ecopreview` and `nets --expect` as before |
| T2 | A batch entry with x = 1234567 (off the mil grid) | read-back 1234567 |
| T3 | Hand-edit a batch to x 1.5, then to rotation 45 | refused by the client and, sent raw, by the native side; nothing moved |
| T4 | Open another PcbDoc and focus it; preview and apply | the selected project's board is the one read and written; the other stays clean |
| T5 | Preview, nudge one part by hand, save, apply with the old hash | hash refusal; or with a fresh hash and a nudge after it, `moved since preview`; nothing moved |
| T6 | Lock one part (Properties > Locked); preview | `refused: the part is locked` |
| T7 | Put one part on the bottom; preview | `refused: the part is not on the top layer` |
| T8 | A designator not on the board | `refused: designator not on the board` |
| T9 | After T1, one Ctrl+Z, then Edit > Undo | record what each reverts: the batch, one part, or nothing |
| T10 | After T1, close the PcbDoc without saving, reopen | every part at its pre-batch position |
| T11 | Untick; apply. Then tick, Detach, apply. Then tick, switch project, apply | refused each time, also on a direct native request |
| T12 | Edit the board by hand (unsaved); apply | `PCB_DIRTY`, nothing moved |
| T13 | Kill the client during an apply | `OUTCOME UNKNOWN`; the next preview shows the true state; no retry |
| T14 | After T1, `bridge.cmd pads` on parts at 90 / 180 / 270 | pads where the plan puts them, within 1 mil (`plancheck` ok) |
| T15 | A short track on one pad of a part; preview | `refused: copper routing overlaps the part` |

## 10. Qualification log

**2026-10-07, runtime `selected-edits-20261007` (scripts `2026.10.07.1`), live HDMI project.**
- **Setup:** Stefan chose the live project with git as the rollback, as for parameter edits. The
  design files were committed first (PLT-hw b2d05a7).
- **First compile:** the new Pascal compiled at its first load, with no script error.
- **Ping:** profile `eda-selected-edits-v1`. The selection identity carries both grant states.

| Test | Result |
|---|---|
| T1 | **Pass.** `plancheck --emit-moves` wrote 16 moves; the preview refused none. One tick, then apply with hash `5b1088ad...6738`: 16 moved, 0 partial, every part read back at its target, verify preview clean, grant ended. `plancheck` on the unsaved board: 16 / 16 in place, largest pad offset 0.016 mm (the read's 1-mil resolution), 0 clearance violations, nothing floating. After Stefan's save, `ecopreview` showed only the 16 pending ESD pad changes: the moves changed no nets (PLT-hw a80ef7d) |
| T14 | **Pass.** Parts at 90, 180 and 270 degrees have their pads where the plan puts them: rotation turns about the footprint origin, and setting x / y after the rotation lands the origin exactly |
| T2-T13, T15 | Open |

**Second live batch, 2026-10-07 afternoon (same runtime):** the plan re-fitted on footprint outlines
(PLT-hw c410605). Saved board committed first (a80ef7d). Preview: 16 to move (0.15-0.60 mm, no
rotation change), nothing refused. One tick, apply with hash `b92dd32f...ff11`: 16 moved, 0 partial,
read back at target, grant ended. `plancheck`: 16 / 16, largest pad offset 0.015 mm, 0 violations of
48 864 checks including the new outline check, nothing floating; two gaps under one mil short of
their rule are listed as read resolution (plan 0.100 / 0.162, read 0.091 / 0.149).

**Third live batch, 2026-10-07 (same runtime):** the six rail groups, 22 parts brought onto the board
from the parking area (190-264 mm each, rotations changed). Rollback PLT-hw f274060. Preview refused
nothing; Stefan had pre-approved the batch and ticked. Applied: 22 moved, 0 partial, read back at
target, grant ended. `plancheck`: 38 / 38 planned parts in place (largest pad offset 0.016 mm),
nothing floating; its outline fallback (pads + 0.25 mm) flagged unplanned neighbours (U301's caps),
not the moved parts.

**Fourth live batch, 2026-10-07:** after Stefan's own adjustments (saved, PLT-hw 7a37341), a 3-part
batch (C509 0.05 mm, TP503 1.3 mm, C506 3.4 mm) on his standing approval and tick: applied, read
back, grant ended; plancheck 38 / 38, nothing floating. The tool moved parts a person had moved by
hand without trouble: the compare-and-set read his positions as the old ones.

**Fifth and sixth live batches, 2026-10-08 (the board arrangement, USB-C west):** batch A, 92 parts
on `selected-edits-20261007`; eight parts refused because their designator text reached a
mounting-hole ring. Scripts `2026.10.08.1` (`PlaceEditExtent`) deployed as `selected-edits-20261008`,
compiled at first load, ping `2026.10.08.1`; batch B, 10 parts, including seven of those eight.
TP208 stays refused on the new script and rightly: its own pad is on the ring (by hand). Both
batches read back at target, grant ended each time.

