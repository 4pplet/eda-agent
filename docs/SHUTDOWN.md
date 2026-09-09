# Altium bridge shutdown: local fork hardening

## Status (2026-09-08)

Current source/shared candidate is `2026.09.08.2`; its project selector is a
separate change, not a new shutdown fix. Shared session ending at 23:05:07.604 on
2026-09-08 logged `reason=stop-requested`; operator then reported closure and X2
absence was checked. Repeat-cycle and shared stop-file-helper testing remain
pending. Existing named profiles remain on `.1`. See the companion
[shared runtime guide](../../PLT-hw/tools/eda-agent/SHARED-PROJECTS.md) for matching
client/script paths. Do not use new `.2` source helpers with installed `.1` scripts.

Shutdown observations below concern script `2026.09.08.1`, based on commit
`1b60105cbe0c4bd557007b87bc04dda2fd4ef9a1`. Not a released or native-qualified fix.
**Native result: quit while the bridge is running still fails on this candidate.**
Explicit no-save stop followed by normal quit passed once. Stop before quitting;
do not repeat the failing direct-quit test until another reviewed change is ready.
The shutdown-only patch did not change the Python protocol or CAD behavior.
Existing installations do not
update when this checkout changes; do not replace scripts while Altium has them open.

Altium 23.3.1 showed an access violation in `ScriptingSystem.DLL` when quitting
with the bridge running. The debugger highlighted the old `Dispatcher.pas:472`
`Sleep` immediately following `Application.ProcessMessages`; the script had been
left under Free Documents after project closure. No session-end log was present.
This is consistent with host/script teardown during a UI yield, but a native
crash trace would be needed to establish the exact engine failure.

The patch checks stop/host state before and after each polling UI yield (active,
idle and paused), and after request dispatch before updating status. Host quit or
host-query failure latches a stop. Cleanup no longer processes UI events, and
does not touch status controls on a detected host shutdown or loop exception.
The log distinguishes `_session_aborted` from normal `_session_end`, with a reason.
The sentinel still works while paused; response files are retained for the caller.

These checks cannot rescue an interpreter invalidated *inside* a native call,
nor prove safety of every command handler's own UI yields. If quitting while
running still crashes, investigate host lifecycle integration/event-driven
dispatch instead of adding sleeps or swallowing more exceptions.

## Normal shutdown (all projects)

The [standalone shutdown probe](../diagnostics/shutdown-probe/README.md) passed
its explicit Stop baseline, but direct quit left Altium open with Stop disabled.
It avoids CAD/MCP/Client calls and checks the local stop flag before post-yield
logging. Thus removing the host query and changing guard ordering alone did not
establish clean shutdown. See the recorded results below; do not repeat unchanged.

1. Finish outstanding requests and stop the MCP client from issuing more.
2. In the small native **EDA Agent MCP** status window, click **Detach** (or its
   Close button). Those handlers only request the loop to stop; they do not save
   CAD. Alternatively create a file named `stop` in the **verified active profile's**
   IPC workspace. A stop request is not proof the script has returned.
3. Wait for the status form to disappear and a **new** `_session_end` after this
   session's `_session_start` in `workspace/activity.log`. With this patch, normal
   manual reasons are `stop-requested` or `stop-file`; `_session_aborted` is a failure.
   The final log marker is evidence cleanup was reached, not proof of native quit safety.
4. Only then close the script project or quit Altium. Preserve intended CAD edits
   explicitly; the no-save stop is not a backup. Closing Python alone does not stop
   the Altium script immediately, and Pause does not release the scripting engine.

**Different operation:** API `app_detach` / browser dashboard Detach calls
`application.stop_server`, which calls `SaveAllDirty(0)` before stopping.
Do not use that path when saves are not authorized. No fixed stop-time guarantee
applies while a command or modal dialog blocks the scripting engine.

If the debugger is halted, use **Run > Stop / Ctrl+F3** as documented by
[Altium](https://www.altium.com/documentation/altium-designer/scripting/writing-scripts).
A native access violation may not be recoverable this way. Do not resume the
faulting loop, auto-submit a crash report, or force-kill Altium without operator
approval and consideration of unsaved work. A stop sentinel cannot execute in a
halted interpreter.

## Deployment and required native regression matrix

Stop Altium first. Preserve existing runtime scripts/client hashes and backups;
retain project-specific IPC paths, startup guards and markers. Deploy the changed
Dispatcher and Main together, reload from disk, and check ping reports
`2026.09.08.1`. A client that pins the old script version must be updated with it.
Rebuilding/installing a wheel is separate from editing this checkout; do not run
a generic script installer over project-specific scripts.

On disposable CAD only, with one Altium instance and one client, record results:

- [x] Native script compilation/start and ping at the new revision (22p, 2026-09-08).
- [x] Read smoke test, then stop sentinel while idle; fresh normal end marker (22p).
- [x] First normal Altium quit after explicit stop (22p; operator confirmed).
- [ ] Native Detach and native Close, each in a new session; no implicit CAD save.
- [ ] Stop while paused and during active reads; no post-stop request/status work.
- [ ] Repeat start/read/stop/close at least three times; no stuck Dispatcher document.
- [ ] Idle timeout exits normally and another session starts successfully.
- [ ] Close script project / quit Altium while idle, paused and active (separate tests).
  **FAILED:** normal quit with the bridge left running after the read client exited.
- [ ] Repeat normal stop-then-quit, and restart Altium after each quit test.
- [ ] Verify copied CAD hashes/dirty-state behavior and surviving response delivery.

The remaining native cases are pending. Offline source-order tests do not simulate
`ScriptingSystem.DLL` or validate the host quit flag's timing.

### Native observation: 2026-09-08, 22p profile

- Altium PID 19968, `_session_start` at 21:13:22.082, script `2026.09.08.1`.
- Live ping version/profile checks and all nine bounded read tools passed at
  approximately 21:16. Active/focused project paths were inside the intended
  disposable 22p profile; Free Documents was empty. Reported dirty count was zero.
- BOM returned 172 components; nets returned 559 entries, neither truncated.
  This rerun checked tool responses/counts, not a new full native-export comparison.
- First sandboxed smoke attempt returned a generic tool error; rerunning with
  approved access to the external IPC environment succeeded. The first error's
  underlying detail was not preserved, so its exact cause is not established.
- With the direct client exited, an explicit no-save `workspace/stop` was consumed.
  Log: `2026-09-08 21:17:01.177,0,_session_end,requests=32,reason=stop-file`.
  X2 remained responsive. No save/CAD-edit commands or automatic quit were issued.
- The operator confirmed Altium quit normally after this explicit stop. The
  tested PID 19968 was no longer present at the next check; a different X2
  process (PID 22916) was running. This is one successful stop-then-quit cycle.
- This first observation establishes only one stop-then-quit cycle. The following
  direct-quit test failed; repeat-cycle coverage also remains incomplete.

### Failed direct-quit test on the patched script

- Same date, Altium PID 22916; new session started at 21:19:02.680 with
  `2026.09.08.1`. Live ping independently confirmed that loaded version and the
  intended `plt-22p` profile. Only the copied design/script projects were listed,
  Free Documents was empty, and the copied project reported zero dirty documents.
- Read client exited after identity/freshness checks at 21:19:38.627. No bridge
  stop was requested. The operator then attempted normal Altium quit.
- Operator reported: `Access violation at address 000000014B1968C4 in module
  'ScriptingSystem.DLL'. Read of address 0000000000000078 at 000000014B1968C4.`
- Log still ended at the last read; neither `_session_end` nor `_session_aborted`
  appeared for this session. X2 remained present and reported responsive; that
  process flag does not mean the script or shutdown is healthy.
- Follow-up screenshot `Screenshot 2026-09-08 212116.png` identifies deployed
  `Dispatcher.pas:325` in `MCPHostAvailable`: `If Client.IsQuitting Then`.
  This matches the on-disk source. The project tree again contains only
  Dispatcher under Free Documents. The highlighted location is now the host
  shutdown query itself, not the old Sleep line. The existing Try/Except did
  not yield a logged clean exit in this observation; debugger exception trapping
  versus an unrecoverable native failure still needs investigation.
- This disproves the candidate as a complete direct-quit fix. It is consistent
  with querying host state after script/project teardown has begun, but the
  exact native object lifetime and call stack remain unknown. Investigate an
  earlier shutdown boundary or supported lifecycle/event-driven dispatch; merely
  removing this check does not establish that subsequent operations are safe.
  No automatic dialog dismissal, resume or kill was attempted.
- The screenshot also shows missing `22p-adapter.OutJob`. The profile manifest
  explicitly excluded that output-job file while retaining the project reference;
  this is a known snapshot warning, not evidence identifying the AV's cause.

Offline regression command from the fork:

```text
python -m unittest discover -s tests -p test_dispatcher_shutdown.py -v
```

### Standalone probe results: 2026-09-08

- Probe v1 explicit Stop: `probe-20260908-213304-331.log` recorded
  `46,stop_button`, `47,after_yield_stopped`, `48,run_end`, followed by
  `49,form_close_query` and `50,form_close`. This establishes the Stop baseline;
  it does not by itself prove that the surrounding Altium process quit normally.
- Direct quit: new Altium PID 5492 (started 21:33:34), log
  `probe-20260908-213355-827.log`. Last recorded event was `3395,before_yield`,
  unchanged on subsequent inspection; last-write time was 21:37:21. There was no
  close/destroy/stop event, `tick_limit`, `run_end`, or exception/abort marker.
  The next source operation after the pre-yield stop check is
  `Application.ProcessMessages`. No return was logged; this does not locate an
  exact native fault or prove which operation blocked/terminated execution.
- Operator screenshot `Screenshot 2026-09-08 213734.png`: project closed,
  `ShutdownProbe.pas` left under Free Documents, no visible error dialog.
  `Screenshot 2026-09-08 213937.png`: Run menu present but Stop disabled;
  Ctrl+F3 had no effect. A responsive X2 process was not a successful shutdown.
- Operator force-closed Altium and confirmed closure. Subsequent process check
  found no X2. Runtime logs remain under the shared installation's
  `diagnostics/shutdown-probe-v1/logs`; source and deployed bridge were unchanged.
- Classification: **incomplete shutdown**, not a reproduced access-violation
  dialog in this experiment. It occurs without MCP, CAD APIs or `Client` calls.
  Do not assume the same native cause as the full bridge AV without a stack trace.

Deferred experiment (not implemented; stop-first remains the workflow): a
standalone modeless form with a
`TTimer`, short log-only callbacks, and a startup procedure that returns without
`Application.ProcessMessages`, `Sleep`, or a polling loop. First verify callbacks
survive startup return; only then test Stop/close and normal Altium quit. No CAD,
MCP or production-profile deployment. Disable the timer before callback cleanup
and guard against re-entry. If callbacks cannot survive startup return, do not
restore the same polling loop just to make this experiment pass.

Altium documents [timer components and form events](https://www.altium.com/documentation/altium-designer/scripting/delphiscript/forms-components)
and an [UpdateTime example](https://www.altium.com/documentation/altium-designer/scripting/examples-reference).
Those references do not qualify modeless callback lifetime or shutdown safety on
23.3.1. A timer-based bridge remains a hypothesis, not a fix. Keep using explicit
no-save stop before project closure/quit while investigating.
