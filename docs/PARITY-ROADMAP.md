# Parity roadmap: importing the upstream surface through the scoped model

Written 2026-09-10 (Stefan + continuation agent), after the nine-tool PCB-read
import demonstrated the pipeline: pick a need, review each upstream function
for purity, replace focused-board targeting with `ResolveSelectedBoard` /
selection scoping, validate shapes client-side, deploy a dated runtime,
qualify natively, flip the pointer. Roughly one tranche per sitting.

**Principle: parity is inventory, not a goal.** The upstream fork holds ~44k
lines of capability; we import along a risk ladder (pure reads → approved
artifact generation → gated writes), and only when a concrete 22p/HDMI task
consumes the tranche. Nothing gets qualified that nothing uses. The
non-negotiable operating limits in [CURRENT-STATE.md](CURRENT-STATE.md) apply
at every phase; the write gates are defined in
[PROJECT-SELECTION-AND-WRITES.md](PROJECT-SELECTION-AND-WRITES.md).

## Phase 0 — reliability substrate (current, partly open)

The base everything compounds on. Items already tracked in TODO.md:
qualify the 2026.09.10.2 PCB-read runtime; resolve the idle-timeout pin
anomaly; the shutdown/lifecycle matrix and crash investigation;
cancellation/deadline semantics; clean-install qualification; CI wiring.
A write path on top of an unreliable lifecycle is not negotiable, so this
phase gates Phase 3+ hard (reads tolerate lifecycle roughness; writes don't).

## Phase 1 — complete the read surface (during 22p layout)

All pure reads, no risk-model change. Consumers exist today.

1. **Remaining PCB reads**: trace lengths per net, component pads,
   full rule properties (all kinds, not just diff-pair), net classes,
   board statistics, selected-objects (operator-cooperative: "check what I
   have selected"). Serves routing-phase validation directly.
2. **Audit suite, purity-reviewed tranche**: signal-vias-without-return,
   components-outside-outline, pads-near-edge, mixed-designator-rotation,
   mirrored-text, via antennas, single-pin nets, missing-datasheets,
   MPN-inconsistencies. Each function individually reviewed for
   select/highlight side effects before exposure. Serves the 22p
   layout-completion checklist and the MPN pass (verification side).
3. **Library reads** — needs its own scoping design first: library paths are
   OUTSIDE the selected project, so they need an explicit operator grant
   (a library analogue of Use-this-project), not a bolted-on path parameter.
   Serves footprint-vs-datasheet checks (R218 Kelvin lands, FH58 pin-1),
   replacing offline olefile parsing.

## Phase 2 — approved artifact generation (computes, not CAD edits)

These write files or mildly mutate document state, so they sit behind an
explicit per-call operator approval — never ambient:

- **Proj_GenerateOutput / OutJob containers**: automates the ODB checkpoint
  export the PCB validation loop leans on; closes the freshness gap.
- **Proj_ExportImage / ExportPDF**: visual board/schematic snapshots for
  review sessions.
- **PCB_RunDRC**: on-demand DRC during layout with violations returned as
  data. Mutates DRC markers, so approval-gated and never during an
  operator edit in progress.

This is where the scoped tool starts beating upstream rather than trailing
it: hashed, dated artifacts tied to a selection token.

## Phase 3 — Gate 2: permission and approval infrastructure

Pure enabling work, no features: operator capability grants, exact-batch
approval (the operator approves a listed set of changes, nothing else),
audit/receipt records, native undo verification, partial-failure recovery.
Blocks all writes; scheduled on non-CAD days per the standing decision.

## Phase 4 — Gate 3: metadata writes (first and lowest-risk write)

Component parameter writes (MPN / LCSC / Value fields). The concrete
consumer is the 111-component blank-parameter pass — but note honestly:
that pass is on the pre-order critical path (week of 2026-09-14) and Gate 3
will not be qualified by then, so this spin's MPN entry stays manual in
Altium, agent-verified afterwards via the parameters read. Gate 3 serves
the respin/HDMI board instead. Qualify on copies, save separately, verify
by read-back plus native export diff.

## Phase 5 — Gates 4-5: schematic writes

Value/footprint assignment changes (the R218/R224-class ECO), then
annotation/variants. Each on copies first with undo/reopen persistence
tests, per the gate document.

## Phase 6 — PCB writes, need-driven and last

The big upstream block, imported selectively:

- **Placement moves** with the collision dry-run read as the mandatory
  companion (propose → check → operator-approved apply).
- **Deterministic bulk operations** that are genuinely good agent tasks:
  stitching-via placement, teardrops, silkscreen autoplace/renumber -
  all behind exact-batch approval.
- **Interactive routing stays human.** Track placement/tuning is not a
  planned import; the agent validates, the operator routes.

## Never-import list (deliberate)

`App_ExecuteMenu` / `Gen_RunProcess` / `App_RunProcess` (generic escape
hatches that bypass every allow-list), delete-by-coordinates, board-shape
and layer-stack edits, panelize (the CM's job), `App_SaveAll` as an agent
action (saving stays an operator act or an explicit gated step). Anything
on this list moving off it requires its own reviewed decision, not a
tranche.

## Standing tranche checklist (what "import" means here)

For every function in every phase: purity/side-effect review → targeting
replaced with selection scoping (fail closed) → client-side shape
validation with honesty fields → lint + source-consistency tests →
failed-set diff vs baseline empty → dated runtime → native qualification
against independent evidence (ODB/native exports) → pointer flip →
runbook + CURRENT-STATE updated. Same discipline at every rung; the ladder
only gets stricter as the rungs go up.
