# Project selection and future controlled component editing

Recorded 2026-09-08. The operator subsequently authorized the project-selector
implementation (not BOM writes). A separate shared read-only candidate `.2` is
implemented/deployed; native qualification remains pending. Existing named `.1`
profiles remain unchanged. Component editing below is a requested roadmap, not
implemented or enabled write access.
Runnable setup and limits: companion PLT-hw
[shared-mode guide](../../PLT-hw/tools/eda-agent/SHARED-PROJECTS.md).
Latest runtime/evidence: [current-state handoff](CURRENT-STATE.md).

## One bridge, operator-selected project

The candidate adds a Project dropdown to the native Altium MCP status panel, showing open
`.PrjPcb` projects with full paths, plus an explicit **Use this project** button.
Free Documents and script projects are not design targets. Start unselected;
changing an editor tab must not change the selected target. Display access mode
and the exact selected path. Automatic classification as copy versus original is
not implemented: shared mode reads the chosen open working project and creates
no snapshot. The operator must identify the revision/copy being used.

Selection is a scoped grant to read a project, not permission to save, edit its
libraries or access other projects. Define approved project/member boundaries;
enumerating an open project's name does not authorize inspecting its contents.
Shared mode permits selecting an original working project for reads; that is not
approval to edit it. Referenced project members can live outside its folder.

Implementation requirements:

- Coordinate the startup guard, native selection state/dispatcher, Python
  wrapper and stop helper. Replacing the dropdown alone is insufficient.
- Bind requests and responses to the canonical project path, bridge session and
  selection generation. A switch invalidates queued old-generation requests and
  caches. Do not silently redirect an old request to a newly selected project.
- Serialize work; disable switching while executing a request and account for
  queued/cancelled requests that may still execute. Revalidate native selection
  before touching objects, including after UI yields that can process closure.
- Audit every exposed handler for implicit focus/active-document dependence.
  Supplying `project_path` in Python is insufficient if a native handler ignores
  it. Adapt and native-test the handler, or keep it unavailable. Do not solve
  incorrect targeting by silently switching tabs or focusing another project.
- Clear selection on target closure, rename, session restart or loss of identity.
  No automatic fallback to the active tab or another project with the same name.
- Keep a single Altium instance/client workflow initially. Multiple open projects
  in one instance are different from multiple X2 processes.
- Native acceptance: two projects open, same-named projects in different folders,
  tab changes, explicit switches, target closure, queued/stale requests, dirty
  documents, restart and stop-first quit. Require exact target evidence in results.

Effort assessment: the UI is a small change; robust end-to-end target binding is
a moderate cross-layer enhancement. The deployed read-only candidate still needs
native qualification before routine use. Altium's lifecycle behavior is the main
uncertainty; no fixed
implementation-time estimate or safety guarantee is claimed.

## Requested editing roadmap

Requested 2026-09-08: allow agents to set/change footprints, values, component
numbers, manufacturer and other component parameters. All entries below remain
future capabilities. Existing upstream write tools do not establish that these
operations are safely targeted or qualified in our shared bridge.

| Capability | Scope and required checks |
|---|---|
| Manufacturer / MFG, MPN, supplier/order codes, datasheet, description | Map the project's actual parameter names to their meanings; distinguish manufacturer part number from supplier SKU and internal part number. Preserve approved selections and provenance. Reject conflicting aliases rather than guessing which field wins. |
| Value / Comment and typed parameters | Preserve units and distinguish displayed Comment from the authoritative value field or parameter expression. Resistance, capacitance, tolerance, rating and similar changes require electrical/part-selection review and consistency with the MPN. |
| Footprint assignment | Assign an existing, explicitly identified library/model footprint. Verify its availability, package dimensions, pin-to-pad mapping, pin 1/orientation and assembly requirements. Preview any schematic-to-PCB ECO separately; do not silently replace placed PCB geometry. |
| Reference designators (R218, U201, etc.) | Treat annotation/renumbering separately from MPN changes. Address components by stable identity plus exact sheet/project, check uniqueness and multi-part components, and verify schematic/PCB links and exported BOM mappings. Never use blind text replacement. |
| Fitted / DNP and variants | Explicitly scope the assembly variant and population changes; verify variant BOM/assembly outputs, including exclusions. Do not infer DNP from a text comment. |
| Other component parameters | Add named, typed fields to the allowlist with validation and ownership rules; reject unknown fields. Shared-library or managed-component updates require separate authority and a declared impact on other designs. |

Assigning a footprint is distinct from creating/editing its pads, courtyard, 3D
body or library geometry. Symbol replacement, pin/net edits and PCB placement or
routing are also separate later capabilities, not side effects of BOM editing.
Do not claim a successful footprint-name update validates the land pattern or
that a metadata change proves an electrically equivalent part substitution.

Suggested delivery order: qualify shared reads and lifecycle first, then approved
metadata batches on copies, followed by value changes and footprint assignments.
Qualify annotation and variants separately. Default to read-only; any future UI
editing mode must grant an exact project/component/field batch, not unlock all
upstream tools. Switching projects, restarting or changing the reviewed baseline
invalidates approval. A remote request must not grant itself edit authority.

## Proposed GUI permissions panel (2026-09-09)

The operator suggested read/write selection or granular permissions in the GUI.
Configurable grants remain a proposal, not implemented access or authorization
to enable writes. A first side-by-side candidate now includes the existing fixed
read-only policy and unavailable writes/saves/output jobs; no permission toggles
were added. Companion [ownership/status notes](../../PLT-hw/tools/eda-agent/CLIENT-OWNERSHIP.md)
track deployment and the cooperating-client guard. Candidate preparation and its
eight-tool schema and native startup/all eight 22p reads passed on 2026-09-09;
new permissions-label visual verification and lifecycle acceptance remain pending.
Use Read-only as the default preset and expose explicit capabilities rather than
one unrestricted Write toggle:

- Inspect project data; distinguish compile-based checks/report generation from
  inspection that does not compile.
- Propose/dry-run changes without modifying CAD.
- Apply approved manufacturer/MPN/datasheet/description parameter batches.
- Apply approved value/rating changes, footprint assignments, annotation changes
  and population/variant changes as separate capabilities.
- Save only specifically approved affected documents, separately from editing.
- Generate/export reports to an approved output location, separately from CAD saves.
- Shared-library edits, PCB geometry and routing remain separate later capabilities.

The UI should show exact selected project/path, effective grants and a visible
Revoke edits action. Unimplemented/unqualified capabilities must be disabled and
labelled unavailable, not presented as functioning safety controls. Allowing a
capability sets a permission ceiling; it does not approve every proposed change.
Keep exact-batch preview/approval and expected-old-value checks from the workflow
below. Approval must originate with the operator, not a remote self-grant call.

Bind grants and reviewed batches to project identity, bridge session, selection
generation and permission generation; revalidate at execution, not just when a
request is queued. Project switch/closure, restart or permission revocation clears
edit grants and invalidates queued approvals. Deny future/queued writes after
revocation; do not imply it undoes or instantly cancels an in-flight native write.
Report completed/partial/unknown outcomes and require read-back recovery.

Enforce the same policy in the Python tool boundary and native dispatcher.
Hiding tools or disabling a checkbox is not sufficient enforcement. Include
effective permissions/identity in responses and an audit record of grants,
revocations and applied changes. Keep one trusted local bridge/client; this does
not turn Altium's scripting engine or its IPC files into an OS security sandbox.

## Common workflow for future writes

Do not replace read-only mode with unrestricted upstream tools. Start with a
separate, explicitly enabled **metadata-edit** capability for an approved project
and component/field set, initially on a disposable copy or reviewed branch.
Good first candidates are manufacturer, already-approved MPN and datasheet URL
parameters. Changing an MPN still requires part-selection approval; matching text
does not establish electrical equivalence. Decide the authoritative source first:
placed schematic parameters versus managed/library data or a downstream BOM.
Changing a CSV export alone is not a durable schematic/BOM correction.

Suggested workflow:

1. Read exact sheet/component identities and old values, distinguishing absent,
   empty and inherited parameters. Prepare a dry-run table
   of proposed old-to-new changes, with reasons and approved-part references.
2. Obtain approval for that exact batch. Bind it to project/session/selection and
   a baseline revision, plus expected old values. Reject stale or changed objects.
3. Preserve a recoverable pre-edit baseline, including an explicit policy for
   existing unsaved work. Apply only allowlisted fields using reviewed native
   handlers and correct Altium undo/transaction notifications. Reject unsupported
   managed/read-only objects rather than silently falling back to another source.
   Never edit shared libraries, other project instances or unrelated component
   fields implicitly.
4. Read back every targeted field; detect/report partial application. Do not retry
   unknown-outcome writes automatically. Rollback must be tested; do not promise
   native batch atomicity or rely on Git alone to recover unsaved editor changes.
5. Keep saving separate and explicit, scoped to affected documents rather than
   Save All. After approved saves, regenerate native BOM/net exports as applicable
   and compare against the baseline. Metadata-only edits must not alter connectivity.
   Record exact before/after values and verification in the handoff.

For footprint, annotation and variant work, include the affected schematic/PCB
models, proposed ECO and assembly-output changes in review. Applying an ECO is a
separate approved action; an unexpected connectivity or unrelated geometry change
blocks acceptance. Test undo/recovery and save/reopen persistence on disposable
projects before permitting the capability on an original design. Timeout or
disconnect is an unknown outcome until native read-back establishes what changed.

Footprint assignments, values, fitted/DNP variants, symbol replacements, pin/net
edits and PCB geometry are separate higher-risk capabilities. Qualify them
individually with the necessary electrical, library, assembly and native checks.
Never treat a successful metadata edit as qualification of those operations.

Prerequisites: reliable stop-first operation, versioned deployment/recovery,
trustworthy targeting, cancellation/timeout semantics, native handler tests and
operator-reviewed export evidence. These remain backlog work, not current access.

## Delivery plan and release gates (2026-09-09)

Requested next step is planning, not enabling writes. Qualification applies to a
declared capability set, Altium version and tested object types, not unrestricted
upstream access. Deliver each gate separately, retaining the read-only fallback.

### Gate 0: Reproducible startup and supported shutdown

- Resolve the operator's missing Start entry in the new candidate. On disk,
  `Dispatcher.pas` contains parameterless `StartMCPServer`; the candidate's
  `.PrjScr` includes Dispatcher and sets that startup procedure. Its project file
  is byte-identical to the earlier working shared runtime. This does not prove
  that Altium loaded/discovered it. Subsequently resolved: screenshot showed the
  Projects panel rather than Run Script; operator startup and live candidate
  ping/discovery passed. No startup code change was required.
- Qualify native startup, selected/permissions labels, reads, Detach, explicit
  helper stop and repeated stop-first quit/restart on disposable projects.
- Record exact source/runtime hashes and Altium version with each result.
  Package the matching portable helpers into this fork so a new workstation
  need not depend on PLT-hw for generic operation. Test installation and fallback
  from a clean checkout before publishing a versioned baseline.

Exit: documented launch works, native tests pass and another installation can
reproduce the supported workflow. Direct quit with the loop running remains a
known limitation; stop-first is the supported contract until a separate lifecycle
fix is qualified. Do not relabel that limitation as a fixed shutdown bug.

### Gate 1: Trustworthy reads and stable edit targets

- Finish the native selection matrix: tab changes, drafts, switch, close/reopen,
  duplicate names, dirty selected/unrelated documents and session restart.
- Expose exact sheet and stable component identity, field ownership/type,
  missing versus empty versus inherited values, compile result, enumeration
  mode and skipped-object/completeness diagnostics. Reject uncertain targets.
- Compare component identities and connected pin/net mappings with native
  exports from the same saved snapshot, documenting legitimate representation
  differences. Counts alone are insufficient. Keep the defective offline
  extractor out of the write-verification path unless separately repaired.

Exit: the bridge can identify exactly what will be edited and reliably read it
back. Unsupported managed, hierarchical or multi-part cases are rejected until
qualified; existing success responses must not conceal partial extraction.

### Gate 2: Permissions, approval and operation lifecycle

- Add operator-controlled per-capability GUI grants, default read-only, with
  Revoke edits. Keep unimplemented capabilities disabled. Enforce independently
  in Python and the native dispatcher; no arbitrary upstream dispatch escape.
- Separate propose/preview, exact-batch approval, apply, status/read-back and
  save. Bind an immutable batch to project/member/component identities, session,
  selection and permission generations, expected old values and baseline.
  Approval is single-use for that batch; an agent cannot approve its own changes.
- Define queued, dispatched, running, applied, verified, failed, partial and
  unknown outcomes. Timeout/disconnect does not mean cancellation. Do not release
  serialization or retry an uncertain write merely because its caller stopped
  waiting. Use operation IDs and recovery records, checking native state before
  any resubmission; do not claim exactly-once execution after a process crash.
- Recheck grants and baseline immediately before mutation. Revoke/switch/closure
  invalidates queued approval, but cannot undo an in-flight operation.

Exit: negative tests cover stale identity/approval, manual edits after preview,
unauthorized fields, second clients, cancellation and disconnect, including
direct native requests that bypass Python. No CAD-write capability enabled for
ordinary projects yet.

### Gate 3: First qualified writes: component metadata

Start narrowly: update existing, placed schematic string parameters for
manufacturer, already-approved MPN and datasheet on explicit components. No
parameter creation/deletion, inherited/managed overrides, value changes,
annotation, library edits or PCB changes in this first increment.

- Define project field aliases/ownership and reject conflicts. MPN approval
  remains an engineering decision, not inferred from matching text.
- Preflight the entire batch and require a clean, recoverable baseline for all
  target documents in the first version. Refuse dirty targets; never save or
  discard existing unsaved work automatically.
- Audit/adapt native handlers for exact targeting, undo notifications and hidden
  save/focus side effects. Do not expose an existing setter merely by name.
- Apply only the approved batch, read back every field, report partial failure
  honestly and qualify undo/recovery through injected failures. Cross-document
  atomicity is not assumed.
- Save affected documents only after separate approval; test save/reopen
  persistence, exact parameter/BOM differences and unchanged connectivity.

Exit: single-component and bounded multi-component batches pass happy-path,
stale-baseline, partial-failure, timeout/disconnect, undo and save/reopen tests on
disposable designs. This is the first release we can call **qualified scoped
read/write for metadata**, not general CAD editing.

### Gate 4: Values and existing-footprint assignments

Deliver and qualify these separately. Values need typed units, Comment/expression
ownership, ratings and approved-part consistency. Footprints need exact library/
model identity, availability and pin-pad/pin-1/package checks. A schematic model
assignment does not approve replacing the placed PCB footprint: ECO preview and
application need separate approval and before/after checks. Test native undo,
save/reopen, BOM and connectivity/PCB effects for each capability.

### Gate 5: Annotation, population variants and production release

Qualify annotation and variant/population changes individually, including stable
identity, multi-part uniqueness, schematic/PCB links and assembly outputs.
Shared-library, symbol, pin/net and PCB geometry/routing edits stay outside this
plan's initial release. Publish the capability matrix, test evidence, known
limitations, recovery procedure and clean-install instructions. Expand supported
Altium versions/object types only with new evidence.

First practical target: Gates 0-3. Follow with the requested value/footprint
features, then annotation/variants. Native behavior, undo and failure recovery
are the main uncertainties; a GUI toggle alone is not the integration work.
