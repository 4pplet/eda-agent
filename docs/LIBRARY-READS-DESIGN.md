# Library reads: the operator-grant design (Phase 1 item 3)

Drafted 2026-09-10. Status: DESIGN ONLY — nothing here is implemented or
authorizes exposure of any library command. Implementation follows the
standard tranche checklist after this design is agreed.

## Problem

Library documents (PcbLib/SchLib) live OUTSIDE the selected project, so the
selection model ("Use this project" grants reads on that project's own
members) cannot authorize them. But footprint-vs-datasheet verification is
a recurring, high-value read (the R218 Kelvin lands, the FH58SA pin-1
location, the WS2812 2020 pad numbering — all real cases from 2026-09-10),
today served by offline olefile binary parsing with known parser-bug risk.
Upstream has native readers (Lib_GetFootprints, Lib_GetFootprintPads,
Lib_GetLibraryGeometry) but they resolve libraries by FOCUS and can open
documents — both forbidden by our targeting rules.

## Principles (unchanged from the project-selection model)

1. **A grant is an operator act in the native UI**, never a client
   parameter. The client can request nothing into scope.
2. **Fail closed on liveness**: the granted library must already be OPEN in
   Altium (operator's act); the bridge never opens documents or changes
   focus. Same shape as `PCB_NOT_OPEN`.
3. **Grants are session-scoped and generation-stamped** like the selection:
   cleared at session end, bumped on every change, echoed in every result,
   stale tokens refused, never redirected.
4. **Reads only**, shape-validated client-side, and qualified against an
   independent reader before trust.

## Design

### Grant surface (native)

Extend the selector StatusForm with a second list, "Granted libraries":

- **Grant**: an operator button opens the native file dialog; the operator
  picks a `.PcbLib`/`.SchLib`. The path is appended to the session grant
  list and `LibGrantGeneration` increments. No wildcard grants, no
  directories — one file per grant.
- **Revoke**: select an entry, click Revoke; generation increments.
- The list renders in the form (same contrast rules as the project list —
  the white-on-white lesson applies) so the operator always sees exactly
  what is readable.

New discovery command `library.get_grants` returns
`{grants: [{lib_path}], session, lib_grant_generation}`; scoped library
commands require `lib_path` + `lib_grant_token` (`session:generation`) and
refuse on any mismatch (`LIB_GRANT_CHANGED`) or ungranted path
(`NOT_GRANTED`).

### Command tranche 1 (PcbLib only)

- `library.get_footprints(lib_path)` — footprint names + pad counts.
- `library.get_footprint_pads(lib_path, footprint)` — per-pad name, x/y,
  sizes, rotation, layer, hole. The direct replacement for the olefile
  workflow's pad geometry (including its hard-won rules: rotation is
  stored, width/height are pre-rotation).

SchLib symbol reads are tranche 2 after the PcbLib model is qualified.

### Native adaptation required (same class as ResolveSelectedBoard)

Upstream `FocusSchLib`/`GetTargetLibComponent` focus and can open library
documents. The shared cores must instead:

1. Verify `lib_path` is in the grant list (exact, case-insensitive path).
2. `Client.GetDocumentByPath(lib_path)` — refuse `LIB_NOT_OPEN` if absent.
3. Resolve the library object by PATH through the already-loaded editor
   server, never via focus; the PCBServer/SchServer
   touch-only-when-proven-loaded hazard rule applies (an open .PcbLib
   proves the PCB library editor server is registered).
4. Enumerate read-only; no SetState, no current-component changes, no
   part-stepping (upstream's SelectLibComponentPart MUTATES the library's
   current part — excluded).

### Honesty fields

Every result carries `lib_path`, `lib_modified` (unsaved library edits —
the pcb_modified analogue) and the grant token echo.

### Qualification

Against the independent olefile parser on the same saved library file:
pad-for-pad equality on a footprint with known geometry (FH58SA and the
TPS22975 WSON — the footprint the olefile workflow once got wrong is
exactly the right test article). Two independent readers agreeing is the
strongest evidence this project can produce offline.

## Non-goals

No library writes (Gates 4-5 territory), no library discovery/scanning of
disk, no cross-library search, no auto-open, no focus interaction. Vault /
managed libraries out of scope.
