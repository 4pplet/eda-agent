# Proposal: copper track delete, text and designator moves, exact reads, connection refresh, 2026-11-18

Status: **asked for by Stefan 2026-11-18** ("let's do all the improvements we can before next PCB work"),
from the HDMI ESD job the same day (PLT-hw `hdmi-adapter/reviews/h3-esd-routing-2026-11-18/`; PLT-hw
`TOOLS.md` limitation rows 2026-11-18). Built 2026-11-18 evening, Altium closed. Scripts `2026.11.18.2`,
runtime `selected-edits-20261118b` (mail workstation); carries everything in `2026.11.18.1`.
**Qualification R1-R8 pending** (section 3): nothing here has run in Altium yet.

## 1. What it changes

| Where | What | Why |
|---|---|---|
| `pcb.move_components_checked` | after the batch, `Board.AnalyzeNet` on every net of the moved parts' pads | bug: the connection lines stayed at the parts' old positions until the PcbDoc was reopened (HDMI U502-U504, 2026-11-18). Upstream's `PCB_BatchMoveComponents` measured the same and fixes it this way |
| `pcb.edit_free_checked` | new op `deltrack`: a free track on a COPPER layer, named by its exact ends, layer, width and net | the DSI segments in front of a new part had to be deleted by hand |
| | new ops `deltext`, `movetext` (new location, optional rotation 90 / 180 / 270 / 360; 0 keeps it) | silk over new parts could not be tidied |
| | new op `movename`: a part's designator text to a location (`ChangeNameAutoposition(eAutoPos_Manual)`, as upstream's placement text move), optional rotation | the same, for designators |
| | 300 items per batch (was 100); a seventh count, free copper tracks, in the compare-and-set string; `Board.AnalyzeNet` on the nets of deleted vias and tracks | a corridor of ten pairs is more than 100 segments; a copper delete must be bound to the preview |
| `pcb.get_component_pads`, `pcb.get_vias`, `pcb.get_component_placements` | `x_raw`, `y_raw` (and `top_x_size_raw`, `top_y_size_raw`; `size_raw`, `hole_size_raw`) beside the whole-mil fields | the mil fields are up to 0.013 mm off; a plan built from them put the arrays 0.005-0.010 mm off the connector rows |

Identifiers, all in use upstream or already in this fork: `Board.AnalyzeNet`, `FindNetByName`,
`Board.RemovePCBObject` after the `PCBM_BoardRegisteration` broadcast, `PCBM_BeginModify` / `PCBM_EndModify`,
`IPCB_Text.XLocation` / `YLocation` / `Rotation`, `IPCB_Component.Name`, `ChangeNameAutoposition`,
`eAutoPos_Manual`. No `RunProcess`.

Client (PLT-hw `tools/eda-agent`): `edit_plan.py` ops `deltrack`, `deltracks` (every free track of the named
nets with both ends inside a box, expanded to `deltrack` items), `deltext`, `movetext`, `movename`;
`bridge_read.py` adds `*_exact_mm` from the raw fields (the `*_mm` fields stay the rounded mil so old
snapshots compare as before); `pair_route.py` (pairs into a pad row, with `lanes`, `extra_tracks`,
`extra_vias` in one copper batch); `bridge_write.py drc` names Altium's "Design Rule Check" dialog when the
pours are out of date.

## 2. Not in it

A copper track modify or reroute (delete and lay new copper instead); arcs; regions; a designator
auto-place; schematic writes (PLT-hw backlog 5 / 5a / 5b); a dialog tool (upstream's UI tools are in the
wheel but not exposed: Stefan's go needed); one plan carrying deletes, copper and repour under one tick
(each write still needs a saved PcbDoc and its own tick); detecting out-of-date pours before the batch DRC
(no identifier known for it).

## 3. Qualification (real 22p, git as rollback, nothing saved unless Stefan saves)

| # | Check | Pass |
|---|---|---|
| R1 | ping `2026.11.18.2` on runtime `20261118b`; `pads` / `vias` / `placements` rows carry the raw fields, `x_exact_mm` of a CON402 pad equals the end of the track on it | versions and values match |
| R2 | `moves` of U405-U407 to CON402 (the real placement) | parts at their targets; the connection lines run from the new positions at once (Stefan looks) |
| R3 | `edit preview` with `deltracks` for the DSI nets in a box right of CON402 | every segment `would_delete`, none outside the box |
| R4 | the same apply without the board tick, then with it | stopped; then all done, read back `remaining 0`, the seventh count down by the number deleted, connection lines appear for the opened nets |
| R5 | refusals: `deltrack` with another net named, with a wrong width, on a non-copper layer; an apply with the old hash after a change | each refused, nothing changed |
| R6 | `movetext` of a silk label (location and rotation), `deltext` of a scratch text placed with `graphics`, `movename` of U405 | done and read back; Altium shows them; U405's designator stays put after a move of the part is NOT required (manual position) |
| R7 | `drc` with stale pours | the client names the dialog; after `repour`, `drc` runs without one |
| R8 | the 22p ESD job with `pair_route.py` (approach right): copper batch, repour, DRC, `pair_route lengths` | DRC clean on clearance / length rules; skew within 0.1 mm |

## 4. Qualification record

- **R1 passed 2026-11-18** (runtime `20261118b`, real 22p): the script loaded without an error, ping
  `2026.11.18.2`; CON402 pads read `x_exact_mm` 145.580 / rows 84.106 ... 94.106 at 0.500 pitch, equal to the
  DSI track ends (the mil-rounded fields read 145.567 and rows off by up to 0.012).
- R2-R8 pending; they run on runtime `20261118c` (scripts `.3`, same PCB code).
