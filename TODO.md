# Fork integration TODO

Updated 2026-09-09. Base `1b60105cbe0c4bd557007b87bc04dda2fd4ef9a1`,
package 0.5.0. Named profiles remain `2026.09.08.1`; shared source/runtime is
`2026.09.08.2` plus recorded UI patches. The `.1` shutdown observations below
are historical evidence, not a claim that `.2` fixes direct quit.
Focused Altium/PLT integration backlog, not a full upstream audit.
Distinguish reproduced Python behavior, source-level risks and native acceptance.
These items do not authorize CAD writes or enabling additional tools.
Current deployment/test evidence and agent memory: [handoff](docs/CURRENT-STATE.md).

Execution order: [read/write delivery gates](docs/PROJECT-SELECTION-AND-WRITES.md#delivery-plan-and-release-gates-2026-09-09).
First target is qualified metadata editing (Gates 0-3), then values/footprints and
annotation/variants separately. Missing Start report resolved: the screenshot was
the Projects panel, not Run Script; operator started the candidate and live
ping/discovery passed. The expected-22p full-read test stopped before content
reads when selection changed to cyber80. Complete candidate read/visual/stop
acceptance; do not enable writes or overwrite loaded scripts. Subsequent 22p
generation-4 checks passed all eight tools; see the current-state handoff.

## P0: Native shutdown qualification

2026-09-09 update: operator confirms the short close/reopen and
Detach/quit/restart checks completed. Exact cycles/logs not supplied; remaining
matrix items below are not closed by that confirmation. See current-state handoff.

Progress: 22p live reads on `2026.09.08.1`, no-save stop acknowledgement and one
operator-confirmed normal quit after stopping passed. **Quit while running FAILED
on that same patched revision**, with `ScriptingSystem.DLL` access violation at
read address `0x78` and no end/abort log. Details are in the shutdown log below.

- [ ] Complete [the shutdown matrix](docs/SHUTDOWN.md) on disposable CAD:
  new-version ping/read, explicit no-save stop, native Detach/Close, repeated
  restart cycles, paused/active/idle stop and timeout. Test quit while running
  only after a separately reviewed lifecycle change; do not repeat the known failure.
  Require fresh session-end evidence and no native crash. Source checks are
  not native Pascal execution. Do not call the candidate a proven quit fix.
- [x] Capture patched failure location: operator screenshot shows deployed
  `Dispatcher.pas:325`, `If Client.IsQuitting Then`, with Dispatcher left under
  Free Documents. This is the new host-state check, not the old Sleep line.
- [ ] Investigate the reproduced direct-quit failure: obtain native stack/object
  lifetime evidence, check debugger exception behavior and supported earlier
  shutdown/lifecycle/event-driven dispatch.
  Do not assume the interpreter's exact failure point from its address, or add
  arbitrary sleep delays. Current post-yield guards are insufficient.
- [x] Prepare a separate no-CAD/no-MCP [shutdown probe](diagnostics/shutdown-probe/README.md)
  with local-stop-first ordering and form-close/yield event logs. No production
  bridge code changed by this experiment.
- [x] Run probe A (Stop button baseline), inspect its log, then probe B (normal
  Altium quit with only the diagnostic running). A recorded clean loop completion;
  B left Altium open, source under Free Documents and Run > Stop disabled. Last
  log event was `before_yield`; operator force-closed. No AV dialog was captured
  for B. See [probe evidence](docs/SHUTDOWN.md#standalone-probe-results-2026-09-08).
- [ ] Deferred while qualifying stop-first use: prepare a separate timer-only lifetime probe: startup returns, no polling
  loop/manual UI pump, no CAD/MCP. Verify callback survival first, then explicit
  Stop and normal quit. Timer support alone does not establish safe lifetime.

## P1: Trustworthy read responses

- [x] Validate BOM/net response schemas at the normal tool boundary, not only
  in the smoke test: required lists/row fields, count/list consistency and
  truncation/completeness. Treat unexpectedly empty known-populated designs as
  failed extraction; support genuinely empty projects explicitly.
  **Isolated fake reproduction:** the PLT wrapper accepts empty BOM/net lists
  and even `{"count":172}` without a component list. Native Altium was not used.
  The wrapper lives in companion PLT-hw `tools/eda-agent/project_server.py`;
  coordinate changes to its installed client snapshots.
  **Implemented/deployed client-only update:** reject malformed rows/counts,
  truncation/limit hits and unexpected emptiness. Genuine empty designs need an
  explicit local profile expectation; installed PLT profiles have none. Blank
  metadata/unconnected net strings remain visible. 48 combined offline tests and
  both nine-tool startup checks pass. Updated 22p live reads passed at 21:55-21:56
  with 172 components/559 pin entries and valid schemas. This does not
  fix native enumeration omissions or the separate offline extractor.
- [x] Return compile outcome and physical-versus-logical enumeration mode.
  **Candidate 2026.09.09.1 NATIVELY QUALIFIED 2026-09-09** (runtime
  `selected-readonly-extraction-20260909`, session 20260909125934012, live
  22p reads): extraction block physical/4 docs/zero skips/limit_hit false/
  compile_action delegated on both BOM and nets, strict validation enforcing
  (extraction_checked true), counts 172/559 in parity with the previous
  runtime. Implemented in f285621 + PLT-hw 9f11328. BOM/net responses carry an extraction block
  (enumeration mode, doc_count, skipped-nil counters, limit_hit,
  compile_action); the Python wrapper rejects nonzero skips, truncation,
  logical-multisheet fallback and unrecorded compiles; INCOMPLETE_DOCUMENTS
  now names the identityless document (closes the draft-diagnosability note
  at source). Lint 12/0; all source tests pass including the two previously
  failing wheel force-include checks (SelectedProject.pas added). Remaining:
  create a new dated shared runtime at the next stopped-Altium window
  (create_shared_runtime), native startup + 22p reads verifying the block,
  and a draft test confirming the named-document error. compile_action
  records call completion, not Altium's compile verdict - ECO/ECC stays
  authoritative.
- [x] Fix offline BOM extraction returning a successful empty result
  (fixed 2026-09-09, commit 93f5f4a). Root cause was input handling, not the
  SchDoc reader: a nonexistent path, a non-.SchDoc/.PrjPcb input or a missing
  .PrjPcbStructure returned [] with exit 0, and the offline review turned the
  same cases into a silent clean pass. bom_from_file/review_project_file now
  refuse those (allow_empty/--allow-empty states a genuinely empty design
  explicitly); eight regression tests. Verified against the real project:
  refusals exit 2, 66 lines / 172 parts on the .PrjPcb. Native exports remain
  authoritative for sign-off; the reader itself matched the live BOM count.
- [x] Automate same-snapshot designator and connected-pin/net comparison with
  native exports: companion PLT-hw `tools/eda-agent/compare_native_export.py`
  (commit c00957e) diffs bridge BOM/net dumps against native Protel v1/v2
  exports, reporting missing, mismatched and additional entries separately.
  First snapshot-verified run against the 2026-09-08 Protel2 bundle export:
  172/172 designators, 550/550 shared pins identical, 9 additional single-pin
  bridge entries, 0 mismatches. Content agreement only, not connectivity or
  electrical acceptance. **ODB++ leg landed 2026-09-09**: companion
  `odb_parity.py` (PLT-hw 1173560) parses the ODB++ step and checks
  alias-tolerant net partitions (splits/merges reported separately); first run
  reproduced audit A2 (172/172, 550/550, zero splits/merges, nine single-pin
  nets correctly no-net on the PCB). CI wiring remains open.
- [ ] Add a bulk parameter read (proposed 2026-09-09): `proj_get_bom` strips
  parameters, so a full-project parameter table costs one
  `proj_get_component_info` call per component. Companion `dump_parameters.py`
  (PLT-hw 6db9c8b) is the client-side stand-in and works today (172 components,
  ~1 min); a native `proj_get_parameters` bulk handler would replace it. New
  read tool: needs the usual schema/policy surface review and a deployment
  window (never replace loaded scripts).

## P1: Deployment and evidence consistency

- [x] Add guarded shared-runtime check/side-by-side preparation/manual rollback
  instructions via companion `tools/eda-agent/manage_shared_runtime.py`.
  Checks manifests/gate/IPC pointers, requires stopped clients/Altium, creates
  only a new sibling, preserves the old runtime, and returns exact manual launch
  paths. No auto-activation/config changes or in-place overwrites. Nine synthetic
  management tests pass (82 total Python tests); real installed 22-file check passes.
- [ ] Qualify a real side-by-side candidate activation and manual rollback cycle.
  Candidate `selected-readonly-permissions-20260909` was prepared on 2026-09-09
  with Altium/clients stopped: 23-file integrity/pointers and installed eight-tool
  schema pass; previous 22-file runtime preserved. Native startup and all eight
  22p reads now pass; visual/lifecycle and manual rollback qualification remain.
  Add separately reviewed legacy named-profile/package and cross-version support;
  the new helper deliberately handles only its matching shared-version family.
  Never run a generic installer over generated profiles.
- [ ] Align packaged scripts with patched source/named profiles. The installed
  wheel still contains older shutdown code; preserve it before rebuilding.
  Distinguish source, installed package, deployed scripts and loaded script.
- [ ] Verify deployment hashes at startup and expose exact CAD snapshot identity
  in read evidence. Shared startup already enforces all 22 script/client hashes;
  that item is complete for shared mode, not a CAD snapshot guarantee. Legacy
  startup enforcement and exact source/copy revision evidence remain open.
  Detect saved-copy/source drift; do not silently refresh CAD or compare revisions.
- [x] Publish the scoped source fixes, tests and companion runbooks checkpoint.
  Fork `d5b62a0` and PLT-hw `3b7cc66` pushed to origin/main; remote hashes and clean
  worktrees verified. See the current-state handoff for immutable links.
  Keep venvs, copied CAD, IPC logs and workstation runtime artifacts out of Git.

- [x] Draft-state diagnosability - NATIVELY VERIFIED 2026-09-09: with an
  unsaved sheet, the refusal reads "Cannot establish selected-project
  document identity (unsaved/identityless: Sheet1.SchDoc); save or discard
  the named document"; after a deliberate discard, compiled reads recovered
  immediately with healthy extraction blocks, no restart or re-selection. Original note kept for context (noted 2026-09-09, behavior itself
  accepted):
  with an unsaved new sheet in the selected project, ALL project reads refuse
  with `INCOMPLETE_DOCUMENTS - Cannot establish selected-project document
  identity` - correct fail-closed handling, natively verified. But unlike
  DIRTY_PROJECT (where freshness still serves and names dirty_docs), nothing
  names the identityless member. Let proj_get_compile_freshness (or a small
  diagnostics read) list draft/identityless documents - names only, content
  reads keep refusing. Decision: keep fail-closed; new files are supported
  once saved.

## P2: Cancellation, deadlines and usability

- [ ] Define cancellation semantics and a consistent end-to-end deadline.
  **Isolated reproduction:** cancellation releases the PLT reader lock while
  its executor worker continues. The single-worker executor prevents concurrent
  execution through that queue, but later work may wait behind the cancelled
  request. Do not claim cancellation stops native execution. Test queued,
  published, active and timed-out requests; avoid unsafe automatic retries,
  especially before future write access.
- [ ] Reconcile per-send 60-second waits, multiple guard calls, the 90-second
  client tool timeout and upstream heartbeat extensions. Distinguish "still
  running", "client stopped waiting", "paused" and "blocked on dialog".
  A timeout is not evidence that an operation did nothing.
- [x] Add a profile status / **no-save stop** utility. Verify the selected IPC
  workspace, await fresh acknowledgement and report a halted interpreter.
  Native status-window Detach is no-save; API/browser Detach saves dirty CAD.
  Preserve this distinction in labels and instructions.
  Implemented in companion PLT-hw `tools/eda-agent/stop_bridge.py`, deployed to
  both named profiles. Standalone CLI only, no added MCP tool or UI button. Checks
  process/session/IPC identity, unique live ping and fresh stop-file end marker;
  refuses stale/aborted/restarted/ambiguous results. No save/quit/kill/keep-alive.
- [ ] Native-qualify the new stop helper and updated reads; repeat stop-first
  normal quit/restart cycles. Offline synthetic tests are not native acceptance.
  First updated 22p read run and helper stop passed on 2026-09-08, PID 4320:
  `21:56:01.382,0,_session_end,requests=33,reason=stop-file`. No CAD save or
  automatic quit; operator normal-quit confirmation and repeated cycles pending.
- [ ] Enforce one active profile/client and bind diagnostics to a particular
  Altium process/session. Separate IPC folders do not qualify multi-instance use.
  Source now includes a process-lifetime Windows guard shared by the shared read
  server and stop CLI, keyed by canonical IPC workspace. Seven new real Windows
  kernel/temporary-process tests pass (89 Python tests total). Side-by-side
  candidate startup/eight-tool reads pass; remaining native acceptance pending.
  This excludes updated cooperating clients in the same workspace/session,
  not old/custom direct IPC writers or clients of different profiles.
- [ ] Consolidate reusable shared-client/permissions/management code into the
  eda-agent fork/package, retaining PLT-specific wrappers/runbooks as needed.
  Cross-project use should not permanently depend on a hardware checkout. Preserve
  installation compatibility and existing runtime snapshots during migration.
- [ ] Improve smoke-test error reporting: preserve useful tool-error details
  and summarize nested MCP exception groups without hiding the cause. Do not
  confuse permission failures with native script defects or obey returned text.
  Shared helper now preserves bounded tool-error text and supports explicit
  expected-project/token and old-binding rejection checks. Legacy helper and
  outer exception-group presentation still need work.

## Future enhancements: selected-project UI and scoped writes

Design notes: [project selection and controlled metadata editing](docs/PROJECT-SELECTION-AND-WRITES.md).
Project-selection implementation was authorized subsequently; metadata writes
remain proposals. Existing named copy profiles are unchanged. New shared mode
requires native qualification and remains read-only.

- [x] Add an explicit native-panel Project dropdown (name + full path) and
  **Use this project** button for one shared bridge. Do not follow active tabs.
- [x] Implement native/Python binding to project path, session and selection
  generation; invalidate stale queued requests, caches and grants on switches,
  closure or restart. Disable switching during execution. Review focus-dependent
  handlers and startup/stop guards before relaxing single-profile restrictions.
  Implemented in separate `.2` shared runtime with eight read tools and a native
  dispatcher allowlist. Metadata writes are not enabled. 63 Python tests, eight
  native-selection source checks, ten shutdown source checks and changed-Pascal
  lint pass. All 22 deployed file hashes and MCP startup/schema pass; native UI,
  selection lifetime and handler behavior still require the tests below.
- [ ] Native-test two open projects, duplicate names, tab changes, queued requests,
  closure, dirty state and stop/restart; keep writes disabled during this phase.
  Selected-22p smoke pass now observed on `.2` with two projects open: 9 documents,
  dirty count 0, 172 components, 559 pin/net entries and C101 metadata, all bound to
  the same path/session/generation. This is not native export parity or a switch
  test by itself. Subsequent explicit switch to cyber80 advanced generation 2 to
  3; all eight tools passed (8 documents, dirty count 0, 260 components, 616 pin/net
  entries, D201 metadata). Live wrapper rejected old path/token, new path/old token
  and old path/new token before native document dispatch. Queue races and native
  guard in isolation remain untested. Session/binding evidence is in the companion
  shared-mode guide.
- [x] Implement/deploy selected-project confirmation sizing and text fix:
  operator clicked Use
  and backend selection succeeded, but reported no visible indication. Screenshots
  confirm clipping consistent with scaled child controls and an unscaled 166-pixel
  header. Height now derives from scaled control bounds. The committed project
  basename/read-only state appear in the label and window title; hover shows the
  exact path. Draft dropdown changes do not update committed identity.
  Patch `selector-layout-checks-20260908-v1` deployed after verified session end
  and Altium closure, with four-file backup and manifest/provenance update.
  73 Python tests, 12 selection source checks, ten shutdown source checks, changed
  Pascal lint, 22 runtime hashes and eight-tool initialization pass.
- [ ] Native-test the new layout/title after restart, current display scaling,
  hover full-path identity, selection changes and unapplied dropdown drafts.
  On 2026-09-09 the operator confirmed selected-project text is visible, and all
  eight reads passed after restart on the 22p copy (9 documents, dirty count 0,
  172 components, 559 pin/net entries, C101). The prior session's token was
  explicitly rejected with the current selection unchanged. Hover/title details,
  unapplied drafts and closure/reopen still need separate observation.
- [x] Deploy selector contrast fix after session end and confirmed Altium closure.
  Operator reported white-on-white dropdown text in `.2`:
  the native combo inherited the dark form's light font. Source now explicitly
  uses window background/text colors and button text color without parent font
  inheritance; all nine selection source tests pass. Shared runtime updated with
  a three-file backup and revised form hash/provenance; 22-file integrity and
  eight-tool initialization pass without contacting Altium. Script stays `.2`.
- [ ] Finish contrast qualification: collapsed/open/highlighted dropdown and Use
  button are readable in operator screenshots; disabled state remains unverified.
- [ ] Prototype a separate allowlisted metadata-edit capability: approved MPN,
  manufacturer and datasheet fields for explicit components on a copy/branch.
  Require a dry-run diff, exact-batch approval, expected-old-value checks,
  recoverable baseline, read-back verification and separately authorized saves.
- [ ] Design/qualify the proposed GUI permissions panel: read-only default,
  per-capability grants and Revoke edits, disabled unimplemented capabilities,
  and separate edit/save/export scopes. Operator grants are a ceiling, not blanket
  batch approval. Bind permission generation to session/project/selection, clear
  edit grants on switch/closure/restart, reject stale queued approvals and report
  in-flight unknown outcomes honestly. Enforce in Python and native dispatcher.
  First candidate UI increment shows the effective fixed read-only policy and
  unavailable editing/saving/output jobs, with DPI-aware bounds. No configurable
  grant controls or writes added; side-by-side preparation/schema passed, native
  visual/start/read/stop acceptance pending.
  Thirteen selection source checks and changed-Pascal lint pass.
- [ ] Qualify partial-failure recovery and native undo behavior; reject stale
  approvals and never retry uncertain writes automatically. Re-export and compare
  BOM/net evidence; metadata-only changes must not change connectivity.
- [ ] Define parameter ownership and aliases for MFG/manufacturer, MPN, supplier
  SKU, internal part number, datasheet and description. Distinguish missing,
  empty and inherited values; reject conflicting aliases or unsupported managed
  objects. A BOM CSV edit alone is not a schematic correction.
- [ ] Add separately approved value/Comment and typed-parameter edits. Preserve
  units/expressions and verify electrical ratings, approved MPN consistency and
  native export/save-reopen results; do not treat these as cosmetic metadata.
- [ ] Add assignment/change of existing library footprints with explicit model
  identity, package and pin-pad/pin-1 checks, library availability and assembly
  review. Preview schematic-to-PCB ECO separately; require approval before
  changing the placed PCB footprint. Footprint geometry editing is a later scope.
- [ ] Add reference-designator annotation/renumbering (distinct from part numbers)
  using stable component identities, uniqueness/multi-part checks and verified
  schematic/PCB/BOM mappings. No blind bulk text replacement.
- [ ] Add separately scoped fitted/DNP/variant edits with variant BOM and assembly
  output checks. Shared-library/managed-source updates need separate impact review.
- [ ] Keep default read-only and use exact-batch, session/project-bound approvals
  for each editing capability. Qualify native undo, partial failure, timeout and
  disconnect recovery, and save/reopen persistence on disposable projects first.
- [ ] Keep footprint geometry, symbols, nets and PCB placement/routing as separate
  later capabilities, not part of a broad write-mode toggle.

## Acceptance discipline

- [ ] Run relevant upstream tests in an isolated test environment. Initial
  coverage: 10 shutdown source checks and 30 PLT helper tests; pytest was not
  installed during patch work. Native observations belong in the shutdown log.
- [ ] Qualify HDMI and each new profile independently; a 22p read pass does not
  transfer to another board or a new script revision.
- [ ] Keep CAD-write tools disabled until an explicitly authorized edit workflow
  has backups, scoped changes, diffs, native checks and operator review.
