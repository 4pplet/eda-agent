# Current integration state / agent handoff

Updated 2026-09-09. This is the current-state entry point; dated session logs are
historical evidence, not pending-work truth. See [TODO](../TODO.md) and the
[read/write delivery gates](PROJECT-SELECTION-AND-WRITES.md#delivery-plan-and-release-gates-2026-09-09).

Published checkpoint: [eda-agent d5b62a0](https://github.com/4pplet/eda-agent/commit/d5b62a03b20d1c2c6dfa416b4990d7c74fe11ad9)
and [PLT-hw 3b7cc66](https://github.com/4pplet/PLT-hw/commit/3b7cc66f4bd55cffe53a26141abdc85a52e65160).
Both were pushed to `origin/main`; their remote hashes and clean worktrees were
verified before this documentation-only receipt. These are matching source/helper
baselines; no installed package/runtime redeployment accompanied publication.

## What is running

- Fork: `4pplet/eda-agent`, based on `1b60105cbe0c4bd557007b87bc04dda2fd4ef9a1`.
  This publication checkpoint contains the local integration changes; use its
  actual Git revision, not the old base alone, to reproduce them.
- Altium 23.3.1; shared scripts `2026.09.08.2`; eight bounded read tools.
  Runtime: `C:\Users\stefan-local\AppData\Local\PLT\eda-agent\shared\selected-readonly-permissions-20260909`.
  Manifest SHA-256:
  `e3dd10e76af730af55700e8e8c9f563c0a24d63ddcf2d382a5c243abff39bd88` (23 files).
- The older `shared/selected-readonly-v1` runtime and named `.1` profiles remain
  untouched fallbacks. The installed Python wheel is older than the fork source.
  Committing source does not update the wheel or loaded/deployed scripts.
- Generic Python wrappers/provisioning currently live in companion
  [PLT-hw tooling](https://github.com/4pplet/PLT-hw/tree/main/tools/eda-agent).
  Moving them into this package is pending. Until then both checkouts are needed.
  Use the [shared runbook](https://github.com/4pplet/PLT-hw/blob/main/tools/eda-agent/SHARED-PROJECTS.md),
  not the historical named-profile patch recipe or a generic reinstall.

Important: the raw source defaults `SELECTED_PROJECT_READ_ONLY = False` for
upstream compatibility. The reviewed shared generator enables it and installs
matching restricted clients. Running arbitrary source scripts/upstream tools is
**not** equivalent to our read-only runtime. No shared persistent client config
has been enabled; checks use a single short-lived STDIO diagnostic client.

## Latest observed evidence

- Operator confirmed the short project close/reopen and Detach/quit/restart
  checks completed on 2026-09-09. This is operator-reported evidence; exact cycle
  count/session logs were not supplied. It does not close dirty-state, duplicate
  names, native guard bypass, helper-stop or in-flight tests, or fix direct quit
  with the bridge running.

- Missing Start report resolved: user was viewing the Projects panel, not
  File > Run Script. `Dispatcher.pas > StartMCPServer` works; no startup fix needed.
- Candidate live session `20260909084536379-17129109`, Altium PID 3612:
  ping/project discovery passed; 22p generation 2 changed to cyber80 generation 3.
  A test bound to 22p correctly stopped at preflight before content dispatch.
- User selected the 22p disposable copy again, generation 4. All eight tool
  checks passed: 9 documents, dirty count 0, 172 BOM components, 559 pin/net rows,
  C101 metadata. Every scoped response retained the selected path/session/token.
  No CAD edit/save command sent; BOM/net reads use allowed non-forced compilation.
  This is a copy under `projects/plt-22p/design-copy`, not necessarily latest CAD.
- 2026-09-09 continuation (different agent): the same-snapshot export
  comparison is automated in companion PLT-hw `compare_native_export.py`
  (c00957e, ten synthetic tests, suite green in the installed venv). Real run
  with hash-verified snapshot identity (design-copy files == PLT-hw `05d18ab`):
  bridge generation-4 BOM/net dumps versus the 09-08 Protel2 bundle export gave
  172/172 designators, 550/550 shared pins with identical nets, 0 mismatches
  and 9 additional-only single-pin entries (spare pads, TVS NCs, floating U205
  EN, freed PC15, and D302-3 - extra evidence for the open D302 numbering
  dispute). The 15:48 sheet-scoped v1 export carries only 542 of the 550;
  prefer the full-project Protel2 export as comparison input.
- Re-run: 89 companion Python tests, 13 native-selection source checks,
  10 shutdown source checks and 8 standalone-probe source checks pass.
  Full Pascal lint in canonical source order: 12 files, zero errors/warnings.
  Source tests do not execute Altium's VM. Counts/schema are not export parity,
  electrical acceptance or full extraction completeness.

- Native dirty-state read test PASSED (2026-09-09, session
  20260909103901779-23934625, working 22p project, generation 2): with two
  operator-confirmed unsaved documents (22p-adapter.PcbDoc,
  3_22p-adapter_mcu.SchDoc), `proj_get_compile_freshness` reported
  dirty_doc_count=2 and named both files, `proj_list_documents` still served,
  and `proj_get_bom` was refused with `DIRTY_PROJECT - Save intended edits
  manually before compiled reads`. First native confirmation of the dirty-target
  guard: inspection reads work, compiled reads refuse. The full row is now closed
  (2026-09-09, session 20260909113532577): an operator save that did NOT
  reach disk was correctly still refused (file mtimes proved the bridge
  right); after a real Save All, dirty_doc_count returned 0 and BOM/net
  reads succeeded (172/559, byte-identical schematic content to the
  pre-edit baseline). Dirty state also survives a bridge restart - it is
  live Altium state, not bridge cache - and unsaved documents of the other
  open, unselected project (cyber80) never appeared in any response:
  dirty reporting is selection-scoped. Drafts (new unsaved documents in the
  selected project) remain an open matrix row.

- Usability batch (2026-09-09 afternoon, companion PLT-hw, client-side only,
  no deployment needed): shared idle timeout is config-pinned to 60 minutes
  (operator decision; EDA_AGENT_AUTO_SHUTDOWN_MS overrides; seeded for new
  runtimes, re-pinned after every wheel connect, current runtime updated) -
  the 10-minute default forced two mid-CAD restarts. New `bridge_read.py`
  CLI: one-command status/bom/nets/parameters(+blank-report)/documents/
  freshness bound to the live selection, runtime root from the reviewed
  ACTIVE-RUNTIME.txt pointer, DIRTY_PROJECT errors enriched with dirty
  document names; both paths live-verified (2026-09-09 15:11 session: status and the
  full 172-component parameters+blank-report in seconds on the 60-min
  clock). New `check_install.py` drift doctor: 13/13 on the
  current installation. Stop-first at wind-down matters more with the longer
  timeout, not less.
- Batch candidate 2026.09.09.2 QUALIFIED and active (2026-09-09): runtime
  `shared/selected-readonly-batch-20260909`, prepared with the guarded
  cross-version manage_shared_runtime prepare (update-receipt records the
  09.09.1 baseline). Ninth tool proj_get_component_info_batch: full
  172-designator pull matched all, byte-equivalent to the single-call loop,
  not_found honest for unknown designators; eight existing reads regression-
  passed with extraction validation active. Rollback: the 09.09.1 extraction
  runtime, itself falling back to the 09.08.2 permissions runtime.
- Extraction candidate 2026.09.09.1 QUALIFIED and active (2026-09-09):
  new runtime `shared/selected-readonly-extraction-20260909` (23 files
  hashed, integrity check passed offline, eight-tool schema intact) is now
  the operating shared runtime; `selected-readonly-permissions-20260909`
  remains untouched as rollback. Live qualification on the working 22p
  project: version agreement, all reads, extraction block
  physical/zero-skips/delegated with strict client validation enforcing,
  draft refusal naming the offending document, and immediate recovery after
  a deliberate discard. The cross-version guard in manage_shared_runtime
  correctly refused to inspect the old-family runtime (documented
  limitation); create_shared_runtime provisioned the new family directly.

- Foreign-tab invariance, post-crash recovery and drafts recovery PASSED
  (2026-09-09, session 20260909120705744, post-crash relaunch): with a tab of
  a NON-selected project focused, selection stayed 22p generation 2 and all
  eight reads served only selected-project data with the correct binding on
  every response; the tool surface exposes no active-tab query at all. Same
  probe confirmed clean recovery after the 11:50 crash and after the
  identityless draft ceased to exist (dirty 0, BOM 172, nets 559). Drafts row
  closed: fail-closed INCOMPLETE_DOCUMENTS while a draft exists (see TODO
  diagnosability note), clean reads once it is gone; the deliberate
  discard-without-crash variant can be repeated cheaply any session.
  Remaining live matrix work: repeat helper-stop, close/reopen selection
  clearing, duplicate names, dirty-unrelated-document case.

- New shutdown-family crash data point (2026-09-09): X2.EXE 23.3.1.30
  crashed at 11:50:51 with exception 0xc0000374 (heap corruption, faulting
  module ntdll.dll, WER report 541a7215-1b4d-43ec-add6-e7eb165d7dc6) - 1.2 s
  AFTER the bridge loop ended cleanly by idle-timeout at 11:50:49.794
  (_session_end, requests=51). Not the known quit-while-running case: the loop
  had exited first. Either a spontaneous crash right after loop teardown or an
  operator close racing it. Strengthens "do not depend on inactivity timeout
  to quit"; relevant to the P0 lifetime investigation. An unsaved draft sheet
  (part of the drafts matrix test) was open at crash time; saved documents
  (11:37 Save All) were unaffected. Two unrelated LiveKernelEvent reports
  (10:33, 11:21) the same morning are system-level, not X2.

- Wind-down evidence 2026-09-09 evening (positive, plus one anomaly):
  deliberate stop at 16:05:47 (`_session_end reason=stop-requested`; fresh
  session 9 s later served reads) — first live helper-stop data point toward
  the "repeat helper-stop" matrix row. After the 16:16:36 idle-timeout exit,
  Altium was closed with NO crash in the event log (contrast 11:50:51 —
  the idle-timeout-then-crash signature did not repeat). Anomaly: that final
  session timed out after exactly 600.0 s despite the 60-minute pin
  (mcp_config.json held 3600000, mtime 15:11:47), while the 15:11 session
  had survived 53 min idle — the pin held once and not the other time.
  Logged with hypotheses in TODO.md (config re-read race vs restart-time
  read); investigate on a non-CAD day alongside the deferred crash work.

## Continuation ownership (2026-09-09)

The agent that built this integration has stopped (out of credits) and will not
continue. The plan and evidence here remain the handoff. Stefan's decision:
resume gate work later, **on a day without CAD work** — Gate 0 lifecycle tests
involve repeated Altium quit/restart cycles and the known direct-quit crash,
and must never share a session with real design edits. Read-only use continues
under the operating contract in the shared runbook meanwhile.

- 2026-09-09 (continuation agent): offline BOM/review silent-empty defect
  fixed at source (93f5f4a) and the installed wheel rebuilt from that commit
  during a no-Altium window: old wheel preserved as
  wheels/eda_agent-0.5.0-py3-none-any.whl.pre-fix-20260909.bak
  (SHA-256 84fb7109...), current build (b7bd379, guard scoped to
  the .PrjPcb branch after a full failed-set baseline diff came back clean)
  SHA-256 1c15b063... installed, pip check clean, installed CLI verified on
  the real project, shared client eight-tool list-only schema check passes. pytest was added to the runtime venv as dev
  tooling (runtime lock unchanged per pip check). Targeted suites around the
  changed files: identical 15 pre-existing failures on clean tree, +7 new
  passing regressions; full-suite baseline comparison recorded separately.

## Remaining work, in order

This is qualification order, not a strictly sequential implementation queue.
Packaging, documentation and permissions design may proceed alongside native
read/lifecycle testing. Reliable target/baseline reads, approval enforcement,
failure recovery and separate-save safeguards must pass before enabling writes.

1. Finish candidate visual/selection lifecycle tests (draft, tabs, close/reopen,
   duplicate names, dirty documents), native guard tests and repeated no-save
   Detach/helper-stop/quit/restart. Side-by-side manual rollback still needs testing.
2. Expose extraction omissions/compile results and automate exact same-snapshot
   native export comparison. Do not rely on the broken offline BOM extractor.
3. Consolidate packaging and qualify clean installation; improve concise
   diagnostic errors and define cancellation/deadline/unknown-outcome recovery.
4. Implement operator-only capability grants and exact-batch approval with
   native/Python enforcement, baseline checks and audit/recovery records.
5. Qualify existing manufacturer/approved-MPN/datasheet parameter updates on
   copies first. Save separately; test undo, failures and save/reopen persistence.
6. Values and footprint assignments next; annotation/variants separately. PCB
   ECO application, library/geometry and connectivity edits are separate scopes.

## Non-negotiable operating limits

Default to scoped reads. Selection is not CAD-write authority. Keep one Altium
instance/client, exact absolute project and fresh token; never follow focused tabs.
No forced recompile, Save All or automatic retries after uncertain writes.
The named kernel client guard coordinates updated cooperating clients only.

**Detach before closing the script project or quitting Altium.** Direct quit with
the loop running remains a known failure, not a fixed issue. Pause is not Detach.
The idle timeout tracks bridge traffic, including keepalive pings, not general
Altium activity; it is pinned to 60 minutes via mcp_config.json, but the
2026-09-09 16:16 anomaly (a 600 s timeout despite the pin — see TODO.md) means
the pin cannot yet be relied on: treat the effective timeout as possibly ten
minutes until the anomaly is resolved. Never replace loaded scripts or auto-dismiss/save/kill
Altium to complete tests. No write permissions were enabled by this publication.
