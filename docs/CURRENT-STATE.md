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
- Re-run: 89 companion Python tests, 13 native-selection source checks,
  10 shutdown source checks and 8 standalone-probe source checks pass.
  Full Pascal lint in canonical source order: 12 files, zero errors/warnings.
  Source tests do not execute Altium's VM. Counts/schema are not export parity,
  electrical acceptance or full extraction completeness.

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
The ten-minute timeout tracks bridge traffic, including keepalive pings, not
general Altium activity. Never replace loaded scripts or auto-dismiss/save/kill
Altium to complete tests. No write permissions were enabled by this publication.
