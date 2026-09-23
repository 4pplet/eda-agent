# Design: event-driven dispatch (replacing the blocking poll loop)

**Status: design for review. No code written.** The prerequisite in §2 must pass
before any of §3 onward is built.

## 1. Why this is now the fix rather than one option

[SHUTDOWN.md](SHUTDOWN.md) deferred a timer-based bridge as an experiment
against the **shutdown crash**. The 2026-09-23 Ctrl+Z bench work makes the same
redesign the only surviving fix for a **second** P0, so the two converge:

| Evidence (TODO P0) | Eliminates |
|---|---|
| Ctrl+Z fails while **idle** (~6 ms pumping) | Message-queue starvation; all yield/poll tuning |
| Fails while the form is **minimized** | Form activation / `Screen.ActiveForm`; all focus fixes |
| **Menu** undo works throughout | The undo command and the action system |
| Presses **replay on detach** | "Swallowed" — they are buffered and flush when the script ends |

Cause class: **the script owning the main thread defers keyboard-to-command
dispatch.** `Application.ProcessMessages` is not a substitute for Altium's own
message loop on that path. Only *not blocking the thread* fixes it — which is
exactly what this redesign does. Two P0s, one piece of work.

## 2. Hard prerequisite — do not write §3 until this passes

SHUTDOWN.md already states it: *"First verify callbacks survive startup
return."* Stage it, cheapest first. **If a stage fails, stop — and per
SHUTDOWN.md, do not restore the polling loop just to make the experiment pass.**

| # | Question | How |
|---|---|---|
| **P1** | Does a form outlive the procedure that showed it? | `ShowStatusFormDiagnostic` (already written, ships this deploy window). Form still there after the script returns = VM survives the call |
| **P2** | Does a **TTimer on that form still fire** after the return? | Add a timer to `StatusForm.dfm` with a log-only `OnTimer`. Watch the log grow with no script running |
| **P3** | Does Stop / form-close / normal Altium quit stay clean with a live timer? | SHUTDOWN.md's existing shutdown probe procedure |

**P1 is free** — it is already in this deploy window for the Ctrl+Z
discrimination, and it answers both questions at once. **P2 is the real gate.**

**If P2 fails**, the timer bridge is dead and the honest position is: keep the
blocking loop, build flush-on-shutdown as a mitigation (subject to its own
caveat in TODO — verify with the 5-press count whether buffering is
message-level or command-level), keep the caption warning, and record that
keyboard dispatch cannot be fixed from inside a DelphiScript bridge.

## 3. Architecture

`StartMCPServer` becomes **arm and return**:

```
StartMCPServer:
    (all existing setup: config, workspace, orphan purge, status form)
    TickState := stArmed
    StatusTimer.Interval := PollIntervalActiveMs
    StatusTimer.Enabled  := True
    -- returns immediately; Altium's own message loop resumes
```

All work moves into `OnTimer`. **Nothing in the handler sleeps, and nothing
calls `Application.ProcessMessages`** — the host is pumping normally now, which
is the entire point. Removing those two calls is what fixes both P0s.

## 4. State migration

Every local the loop carries between iterations becomes module state. This is
the mechanical part, and the part where a missed variable silently changes
behaviour:

| Loop local | Becomes | Note |
|---|---|---|
| `StopPath` | module var | set once at arm |
| `IdleCount` | module var | drives the stats-line cadence |
| `CurrentSleep` | **`CurrentInterval`** | now written to `Timer.Interval`, not `Sleep` |
| `LastActivityMs` | module var | auto-shutdown deadline; `RenewRequested` resets it |
| `ActiveTickCount` | **deleted** | it only existed to ration `ProcessMessages` calls, which no longer exist |
| `HadRequest` | tick-local | recomputed each tick |
| `LoopFailed` | module var | read by the finalise path |
| `I` | **deleted** | the `YieldIterations` inner loop disappears with `Sleep` |

`Running`, `RenewRequested`, `PausedFlag`, `MCPHostClosing`, `MCPStopReason`
and the `Status*` counters are already module-level and are unchanged.

## 5. Adaptive polling without sleeping

The active/idle split survives as **interval changes**, which is strictly better
than sleeping — the thread is free between ticks either way, and now genuinely
so:

- served a request → `Timer.Interval := PollIntervalActiveMs` (10 ms)
- `IdleCount` past `IdleThreshold` → `Timer.Interval := PollIntervalIdleMs` (30 ms)

`YieldIterations` and `YieldEveryNActive` become **dead config**. Keep parsing
them for one release so an existing `mcp_config.json` does not fail to load,
but ignore them and say so in the log.

## 6. Re-entrancy — the trap SHUTDOWN.md already flags

A handler that outruns its interval can re-enter, and a request handler calling
into Altium can pump messages internally even though we no longer call
`ProcessMessages` ourselves. Guard explicitly:

```
OnTimer:
    If InTick Then Exit;        -- drop the tick, do not queue it
    InTick := True;
    Try
        ...one poll's worth of work...
    Finally
        InTick := False;
    End;
```

**Dropping a coincident tick is correct**, not a compromise: the next one is
10–30 ms away and the work is idempotent polling. Queueing them would let a slow
request build a backlog that then stampedes — the very shape of the bug being
fixed.

## 7. Shutdown and finalise

The post-loop block becomes a `FinaliseMCPServer` routine, reached from three
places: the stop file / `application.stop_server`, auto-shutdown, and a tick
exception. Order matters, per SHUTDOWN.md's *"disable the timer before callback
cleanup"*:

```
FinaliseMCPServer:
    StatusTimer.Enabled := False;   -- FIRST: no tick can re-enter cleanup
    Running := False;
    (existing cleanup, log, HideStatusForm)
```

`StatusFormClose` already sets `Running := False`; it must now also disable the
timer, or a closed form leaves a live timer firing against freed controls.
**That is the most likely crash in the whole redesign** and deserves its own
qualification step.

## 8. What would make this worse rather than better

Stated up front so review can weigh it:

- **A live timer at Altium quit may be a *new* crash surface**, where today the
  answer is the blunt but effective "stop the bridge first". P3 exists for this,
  and the existing shutdown probe is the tool.
- **Exceptions change shape.** Today one `Try/Except` wraps the whole loop and a
  failure ends the session. Per-tick handling means a repeating fault could log
  forever instead of stopping. Add a consecutive-failure counter that finalises
  after N.
- **Every native-acceptance result was obtained against the polling loop.** This
  is not a patch; it is a new execution model and needs its own qualification
  pass, not a diff review.

## 9. Sequencing

1. **P1** — free, in the current deploy window (`ShowStatusFormDiagnostic`).
2. **P2** — log-only timer on the form. Small, isolated, no MCP, no CAD.
3. Only then §3–§7, in a dedicated window, with §8's counter included.
4. Full native acceptance as a new execution model.

Until step 3 lands, the operator guidance stands and the caption warning
shipped 2026-09-23 is what stands between a deferred keypress and a silently
reverted board.
