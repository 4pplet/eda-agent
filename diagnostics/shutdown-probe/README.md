# Standalone Altium shutdown probe v1

Diagnostic, not a fix or an alternative MCP bridge. It uses no CAD API, `Client`,
workspace API, MCP IPC, save command or automatic quit. It writes only its own
timestamped diagnostic logs and shows a small modeless form.

## What this isolates

The current bridge failed at `Client.IsQuitting` after yielding UI processing.
Its guard queries the host before honoring the local stop flag, and cleanup
queries the host again. This probe instead checks the local flag first and never
queries the host. Close-query, close, destroy and Stop-button handlers set that
flag before logging their event. After the loop, it only logs `run_end` and returns:
there is deliberately no form hide/free, host query, sleep or extra message pump.

The experiment asks whether those events occur during Altium quit and whether
execution can return from `Application.ProcessMessages` and end using only local
state/file logging. Any native call, including logging, can still fail if the
script environment has already been invalidated. The location and last log event
are evidence, not a native stack trace.

## Installed diagnostic on Stefan's workstation

Keep Altium closed while preparing the diagnostic. The configured copy is:

```text
C:\Users\stefan-local\AppData\Local\PLT\eda-agent\diagnostics\shutdown-probe-v1\ShutdownProbe.PrjScr
```

Logs are in its adjacent `logs` folder, named `probe-<date>-<time>-<milliseconds>.log`.
Source templates here are tracked separately from that disposable runtime.
The template refuses to run until `@LOG_DIRECTORY@` in the Pascal constant is
replaced in a deployment copy with a dedicated absolute writable directory
(escape apostrophes as doubled apostrophes). Preserve this source template.
Copy only the three `ShutdownProbe` files; do not include any production bridge
units. Existing MCP profiles, pointers and configuration are unchanged.

## Test A: explicit Stop baseline (do this first)

1. Open Altium. Close any automatically restored CAD, libraries and bridge script
   projects, including Free Documents. Only this diagnostic project should remain.
   Do not start `AgentStartCopy`, `StartMCPServer` or a Python MCP client. The probe
   does not inspect/enforce this setup because that would introduce host API calls.
2. Open the exact `.PrjScr` path above, not the unconfigured source template.
3. **File > Run Script > ShutdownProbe.pas > RunShutdownProbe > Run**.
4. When the small diagnostic window appears, click **Stop probe**. Its window may
   stay visible; the loop intentionally does not hide/free the form afterward.
5. Ask the agent to inspect the newest log. Require `stop_button`, then
   `after_yield_stopped`, then `run_end` with no error. Do not infer success just
   because the window closed or Altium says it is responsive.
6. After confirmation, close the diagnostic project/Altium normally. Record result.

## Test B: normal quit while probe runs (only after A passes)

1. Start a fresh Altium session with only this diagnostic project, and run again.
2. After the agent confirms a new log with paired yield events, quit Altium using
   its main window / normal Quit command. **Do not click Stop probe or the small
   probe window's Close button first.** Do not close the script project separately.
3. If a native error appears, capture the highlighted source line and error text.
   Do not automatically resume the faulting script or send a crash report. Recovery
   and any forced termination remain operator decisions; no valuable unsaved work
   should be open during these tests.
4. Inspect the new log even if Altium appears to quit successfully.

## Interpretation and limits

- Close events followed by `after_yield_stopped` and `run_end`: supports a local
  stop path without post-yield host calls in this minimal probe. It does not yet
  qualify the full bridge or prove that one simple ordering change fixes it.
- Last event `before_yield`: no logged return; the fault may occur inside the
  yield, on return, or in the next logging call. Do not assume which without the
  debugger line and native evidence.
- Close event then error before `run_end`: returning from teardown can still be
  unsafe even without `Client.IsQuitting`.
- `loop_exception` / `run_aborted`: exception handling was reached, but test failed.
- `tick_limit`: roughly three-minute self-stop, **not** evidence that quit/Stop
  worked. A blocked modal/native call can defeat the timeout; it is not a watchdog.
- Missing/incomplete log is inconclusive. Logging errors stop the loop without
  additional modal UI. Each event closes its file, but logging can affect timing.
- The probe adds `OnCloseQuery`/`OnDestroy` instrumentation absent from the bridge,
  uses a simpler form, and omits request handlers/timers. Keep those differences
  explicit when interpreting a pass; this is not a timer-dispatch experiment.

Native status: **Stop baseline passed; direct quit did not complete** (Altium
23.3.1, 2026-09-08). Do not repeat test B unchanged. See the
[recorded results](../../docs/SHUTDOWN.md#standalone-probe-results-2026-09-08).
Eight static tests passed;
the fork's DelphiScript trap linter reported zero findings. The configured runtime
was compared against source (only its log-directory constant differs); hashes are
recorded in its `deployment.json`. Existing bridge profiles were not changed.

```text
python -m unittest discover -s tests -p test_shutdown_probe.py -v
```

Related evidence: [shutdown investigation](../../docs/SHUTDOWN.md).
