# Proposal: board setup from a spec (stackup, classes, pairs, rooms, rules), 2026-10-09

Status: **approved and built the same day** (Stefan, 2026-10-09: "let's add support for the bridge
to do the rules and stackup edits"); native qualification pending (section 5). Scripts
`2026.10.09.5`, client PLT-hw `tools/eda-agent`. Third checked board write after
[placement](PROPOSAL-2026-10-07-placement-write-increment.md) and
[copper](PROPOSAL-2026-10-09-copper-write-increment.md); same gates.

## 1. Why this, why now

The HDMI board's rule set is written down (PLT-hw `hdmi-adapter/reviews/hdmi-rules-expected.json`,
14 rules, 2 of 14 on the board) and checked by `bridge.cmd rules --expect`; its stackup
(JLC04161H-7628) and the U501 room are in the fanout record and the plan. Entering them by hand is
half an hour of dialogs per board, and every later board (the 22p re-spin has the same set) repeats
it. With the fanout placed, DRC is the next gate and needs the rules first.

## 2. Where writes are blocked today (keep both)

The native allowlist in `SelectedProject.pas` and the Python `SharedReader.send` policy; one more
command admitted, only in a `--place-edits` runtime.

## 3. Audit of the candidate handlers: do not expose them as-is

Upstream `PCB.pas`: `PCB_CreateDesignRule`, `PCB_SetRuleProperties`, `PCB_CreateNetClass`,
`PCB_CreateDiffPair`, `PCB_CreateRoom`, `PCB_ModifyLayer`. Read 2026-10-09:

| | Finding |
|---|---|
| S1 | Focused board (`GetPCBBoardAnywhere`), not the selected project's |
| S2 | Whole mils everywhere: 0.2104 mm prepreg, 0.127 mm width, 0.15 mm gap all round |
| S3 | `PCB_CreateDesignRule` knows clearance, width, hole size and diff-pair gaps; no via style, matched lengths, routing layers or polygon connect, no min / max / preferred triples for width |
| S4 | No compare-and-set, no batch, no read-back on creation (the layer modifier reads back; the rule creator does not) |
| S5 | `PCB_CreateDesignRule` with an existing name creates a duplicate rule |
| S6 | The upstream note that diff-pair width constraints are not on the rule interface is a claim, not a measurement; the dialog has them |

Confirmed in Altium's own DLLs (Advpcb.dll, Altium.SDK.Interfaces.dll, 2026-10-09): the interface
names `IPCB_RoutingViaStyleRule` (PreferedHoleWidth), `IPCB_RoutingLayersRule` (LayerAllowed),
`IPCB_PolygonConnectStyleRule` (ConnectStyle, ReliefConductorWidth, ReliefEntries, ReliefAirGap),
`IPCB_MatchedNetLengthsConstraint` (Tolerance), `IPCB_ConfinementConstraint`,
`IPCB_DifferentialPair`, the kinds `eRule_MatchedLengths`, `eRule_RoutingLayers`,
`eRule_PolygonConnectStyle`, `eRule_RoutingViaStyle`, and `eDirectConnect`,
`eNetScope_DifferentNetsOnly`, `eClassMemberKind_DifferentialPair`.

## 4. The increment

**Command:** `pcb.setup_board_checked` (native) / `pcb_setup_board_checked` (MCP). The selected
project's PcbDoc only. Items in batch order, each compare-and-set:

| Kind | Writes | State read for compare-and-set and read-back |
|---|---|---|
| `layer` | copper thickness; the dielectric below it (type, height, constant, material); optional rename | name, copper, type, height, constant |
| `netclass` | creates the class, adds the listed nets (never removes) | sorted members |
| `pair` | creates the differential pair from two nets, or re-points it | positive, negative |
| `pairclass` | creates the pair class, adds the listed pairs | sorted members |
| `room` | creates or updates a confinement rule: rectangle, scope | rectangle, scope |
| `rule` | creates or updates in place a rule of kind clearance, width, via, diffpair, matched, layers or polygon: scopes, net scope, enabled, the kind's values | descriptor, scopes, enabled; priority reported |

| Rule | Detail |
|---|---|
| **Gate and grant** | `SELECTED_PLACE_EDITS` runtime; apply behind the operator tick, now captioned "Allow board edits"; one tick, one batch, cleared when anything was written |
| **Units** | Every length a raw Altium coordinate as an integer (S2) |
| **Existing objects** | Updated in place by name; a rule of another kind under the name is refused (S5). Nothing is ever deleted |
| **Priority** | Read back and reported, never written (writing `Priority` crashes the engine, `PCB_SetRuleProperties`). The batch writes the specific rule before the default of its kind so the priority Altium gives a new rule is seen on the first run |
| **Compare-and-set** | Preview returns each item's state string; apply carries it back and refuses the batch if any differs (S4) |
| **Clean baseline** | `PCB_DIRTY` refuses an unsaved PcbDoc |
| **Honest result** | Per item `would_create` / `would_update` / `unchanged` / `refused: reason` at preview; `created` / `updated` / `unchanged` / `not_done` (with the reason) at apply, plus the read-back. Stops at the first problem, never rolls back |
| **Never save** | The operator reviews the Rules, Classes and Layer Stack dialogs and saves |

**Known gaps, by design (hand items, named by the client after every apply):** the matched-length
rule's "Within Differential Pair Length" option (no API property confirmed); a routing-layers
rule's allowed layers (`LayerAllowed` is not reachable from DelphiScript, found live 2026-10-09);
the pair rule's width triple (property names unverified; removed before use after the above);
rule priorities. R8 (pair-to-pair clearance) stays held per Stefan 2026-10-07. The client refuses
scope expressions with query functions outside a known list (`InRoom` is not one; `WithinRoom` is).

**Client:** PLT-hw `hdmi-adapter/reviews/board_setup.py` writes the spec
(`board-setup-2026-10-09.json`, mm, board frame: the stackup, class PWR, nine pairs, classes TMDS
and DSI, the room from the plan's rectangle and the live anchor fit, 13 rules);
`bridge_write.py setup preview|apply <spec>` converts to raw items, previews, hashes the previewed
states, applies with them, prints every read-back. Verification afterwards is the existing reads:
`rules --expect`, `stackup`, `netclasses`, `diffpairs`, `rooms`, then DRC.

## 5. Qualification: one native sitting, live board with git as rollback (Stefan's pattern)

| Test | Pass means |
|---|---|
| S1 happy path | the HDMI spec applied: four layers read back as JLC04161H-7628, class PWR with 14 nets, 9 pairs, 2 pair classes, the room at the plan's rectangle, 13 rules with the expected descriptors; `rules --expect` 12 of 14 or better (R8 held, R11's option by hand) |
| S2 priorities | each specific rule (`_BGA`, `_Power`, `_HS`) outranks its default in the Rules dialog, or the report says which do not and the order is fixed by hand once |
| S3 idempotent | the same spec previewed again: layers, classes, pairs read `unchanged`; rules `would_update` with identical descriptors |
| S4 stale | a rule edited by hand (saved) between preview and apply: `refused: changed since preview` |
| S5 dirty | an unsaved edit: `PCB_DIRTY` |
| S6 wrong kind | a spec rule whose name exists as another kind: refused, nothing written |
| S7 grant | untick, Detach, project switch: refused each time |
| S8 recovery | close without saving restores the board |

## 6. Out of scope

Deleting rules, classes or pairs; rule priorities; the matched-length pair option; polygons; DRC
itself; saving.

## 7. Effort

Native about 650 lines (six item kinds, the typed rule writers), server tool and validation,
client subcommand, spec generator, tests: most of a working day. Qualification: one sitting.

## 8. Implementation, 2026-10-09

- **Native** (`SelectedProject.pas`, `SelectedSetupBoardChecked` with `SetupWriteRule`,
  `SetupRuleState`, `SetupLayerState`, `SetupClassMembers`, `SetupPairState`, `SetupRoomState`).
- **Gate:** `SELECTED_PLACE_EDITS`; StatusForm caption "Allow board edits (move parts; plan copper;
  stackup, classes, rooms, rules)".
- **Server:** `pcb_setup_board_checked` with `validate_setup_items` / `validate_setup_result`.
- **Client:** `bridge_write.py setup preview|apply`, `board_setup.py`.
- **Tests:** PLT-hw `test_setup_edits.py` (encoding, results, classification, the HDMI spec loads
  in batch order and passes the client gate), tool surface in `test_place_edits.py`.

## 9. Qualification log

**2026-10-09, live HDMI project (git as rollback: PLT-hw 3ecd11e), runtime `selected-edits-20261009e`
(scripts `.5`), then `-20261009f` (scripts `.6`).**

- **First compile:** the new Pascal compiled at its first load. The preview ran clean on the first
  call: 30 items, every current value read (the stack at Altium's defaults, the stock rules, nothing
  else present), nothing refused.
- **First apply, two script errors, both mine, both of the uncatchable kind:**
  1. `Undeclared identifier: InRoom` from Altium's query compiler when `Clearance_BGA`'s scope was
     written: the room test is `WithinRoom(...)`, `InRoom` is not a query function. Fixed in the spec
     and guarded in the client (`check_query`: only known query functions leave the client).
  2. `Undeclared identifier: LayerAllowed` when `RoutingLayers_HS` was written: the indexed property
     is not reachable from DelphiScript in the form the width properties use. Scripts `.6` write a
     routing-layers rule's name and scope only; the allowed layers are ticked by hand. The pair
     rule's width triple (the other unverified property set) was removed the same way before it could
     fail.
  Lesson, now in the record: a `Try` protects against exceptions, not against an identifier the
  script engine does not know, which stops the loop with a dialog. Every property written natively
  must have been seen working in this codebase or Altium's own examples; otherwise it is a hand item.
- The bridge loop did not survive the dialogs (status calls queued unanswered); the apply's partial
  result (layers, classes, pairs, room, the Clearance update and some rules) is read by the next
  preview, which is the compare-and-set's whole point.

- **Third script error on the second apply** (`.6`): `Undeclared identifier: eDirectConnect` on the
  last item, PolygonConnect: the enum name is in Altium's DLL but not in DelphiScript's constant
  table. Removed for `.7`; R14's direct connect is a hand item. Stefan force-quit Altium after
  each dialog, so both partial applies were discarded and the third run started from the saved board.
- **Third apply, runtime `-20261009g` (scripts `.7`): 29 of 29 written, 0 partial, every item read
  back.** `rules --expect` afterwards: 11 of 14 matched (Clearance, Clearance_BGA, Width, Width_BGA,
  Width_Power, RoutingVias, RoutingVias_BGA, both MatchedLength rules, RoutingLayers_HS,
  PolygonConnect), R8 absent by decision, the two pair rules mismatched only in the width triple
  (the known hand item). Stackup read back as JLC04161H-7628; class PWR with 14 nets; 9 pairs; 2
  pair classes; room at the plan's rectangle.
- **Priorities, measured:** Altium gives a rule created through the API priority 1 and pushes the
  others of its kind down. So the batch order decides: default first, most specific last. The spec
  wrote Width, Width_BGA, Width_Power in that order and got Width_Power 1 / Width_BGA 2 / Width 3;
  the 0.25 mm rail feeds inside the room would then fall under Width_Power's 0.30 minimum. One hand
  swap on this board; the spec order is corrected for the next.

- **Fourth run, scripts `.8`, on Stefan's saved board:** the three settings that had been hand
  items (pair width triples, routing layers, polygon connect style) were written through the
  `SetState_` methods whose names and signatures were read from `Altium.SDK.Interfaces.dll` by
  reflection (`SetState_MinWidth(IV7_Layer, Int32)`, `SetState_RoutingLayers(IV7_Layer, Boolean)`,
  `SetState_ConnectStyle(Int32)`, 1 = direct). 18 written, 12 read `unchanged` (S3 in effect: the
  class, the pairs and the pair classes), nothing partial. Read back: pair widths 0.19 / 0.21 / 0.20
  and 0.10 / 0.21 / 0.20, PolygonConnect "Direct Connect". The routing-layers descriptor carries no
  layer information; a layer read-back for that kind is a follow-up.
- **Stackup observation:** after Stefan's save the two prepregs read 0.186 mm, not the 0.2104 mm
  written and read back; Altium applies a pressed-thickness model on save. The apply set 0.2104
  again; what the Layer Stack Manager shows decides which figure the impedance calculation uses.

- **Runs five to seven (scripts `.9`, `.10`), driven by the first DRCs:** four rule kinds added
  (hole size, mask expansion, silk-to-mask, mask sliver, all through SDK-named setters) and the
  room recreated on update after DRC showed a room's region is a polygon that only creation builds
  (an updated bounding rectangle read back right while `WithinRoom` kept the old region). Each run
  wrote its items and read them back; the fourth DRC confirmed every rule change took effect.

| Test | Result |
|---|---|
| S1 | **Pass** (runs three to seven); hand items left: R11's pair option, one priority swap |
| S2 | **Measured**: new rules take priority 1 (batch order = priority); one swap needed on this board |
| S3 | **Pass**: every later run read the untouched items `unchanged` and updated the rest in place |
| S4-S8 | Open |
