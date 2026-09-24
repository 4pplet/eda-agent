# Design: event-driven dispatch (replacing the blocking poll loop)

**Status: BUILT, wired as an EXPERIMENT, awaiting its first Altium run.**
§2's prerequisites P1 and P2 both passed (2026-09-23); P3 is still open but is a
"no worse than today" check, not a gate. §3–§7 are implemented on branch
`timer-dispatch-dfm` as script `2026.09.24.2`.

**The wiring is not known to work.** It rests on a forward cross-unit call whose
legality is unverified, and the 2026-09-24 section below retracts an earlier
claim that it was proven. Read that retraction before relying on anything here.

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

## ✅ 2026-09-23: P1 and P2 BOTH PASS — §3 onward is unblocked

**P2, the gate on this entire document, passes.** `ShowStatusFormTimerProbe`
armed a 1 s `TTimer` and returned; the timer kept firing with no script
running. Measured externally by sampling the form's window caption
(`GetWindowText` against another process reads the cached caption without
sending a message, so the measurement cannot hang Altium or perturb what it
measures):

| | |
|---|---|
| Rate | **1.00 ticks/s** — 40 ticks over 40.0 s wall clock, exactly the configured interval |
| Window state | **MINIMIZED** — the same state in which Ctrl+Z fails |
| Drift | The form's own elapsed counter advanced 40 s against 40 s of external wall clock: **no starvation, no drift** |
| Self-stop | Halted exactly at the 120-tick cap and stayed frozen across a further 25 s |

**P1 passed the same session:** Ctrl+Z worked normally with the form shown and
the script returned, so the form is exonerated *and* the VM demonstrably
outlives the call. Both prerequisites in §2 are therefore satisfied.

**What this licenses:** §3–§7 may be built. The timer model works on this host.
**What it does not license:** skipping §8's re-entrancy guard, the
consecutive-failure counter, or the fresh acceptance pass — a passing P2 says
the mechanism exists, not that the migration is correct.

**P3 remains open** and is now the only prerequisite left: close the form while
a probe is ticking, and re-run the shutdown probe. Note §8 has already been
corrected — quit-while-attached crashes *today*, so P3's bar is "no worse than
today", not "clean".

## ⏳ 2026-09-24: the wiring blocker is UNVERIFIED, and this build tests it

**Read the correction at the end of this section before citing anything in it.**
An earlier version of this section declared the blocker disproved. That was
published on a mistake and is retracted.

What is true — the DFM scope rules, each bought with a failed Altium compile:

1. A nested routine cannot read the enclosing routine's params or locals
   (*"Can't access top level variable"*).
2. A DFM control identifier is in scope **only** in the `.pas` paired with the
   `.dfm` (*"Undeclared identifier: tmr_MCP"* from `Dispatcher.pas`).
3. A DFM event handler binds only to a procedure in that same paired `.pas`, and
   **fails silently** otherwise — timer enables, session starts, no tick, no error.
4. Runtime event assignment is unavailable: `X.OnTimer := Proc` gives *"Invalid
   procedure usage"*, `@Proc` gives *"Expression expected but @ found"*.

What is **unverified** — the fifth premise, which nobody has ever tested:

> *"The dispatch handler must call `ProcessSingleRequest`, which is defined after
> `StatusForm.pas`, so it cannot live there."*
> *"`Dispatcher.pas` may call into `StatusForm.pas`, never the reverse."*

**The retraction.** On 2026-09-24 this section claimed that premise was
disproved, citing `StatusForm.pas`→`SelectedProject.pas` and
`Dispatcher.pas`→`Audit.pas` as live forward calls. **Both citations were wrong,
for two independent reasons:**

1. **Wrong project file.** They were read off this repo's `Altium_API.PrjScr`,
   which is IDE-only and sets `ReorderDocumentsOnCompile=1`. The shared runtime
   does not deploy it. PLT-hw's `create_shared_runtime.py:36-41` **generates** a
   different one with an explicit dependency order and
   `ReorderDocumentsOnCompile=0`:
   `… Audit(9), SelectedProject(10), StatusForm.pas(11), StatusForm.dfm(12),
   SelfTest(13), Dispatcher.pas(14)`. In *that* order both cited calls are
   ordinary **backward** calls and prove nothing.
2. **The code path doesn't run.** Both `StatusForm.pas` calls sit behind
   `If Not SELECTED_PROJECT_READ_ONLY Then Exit;`, so in the checkout profile
   they never execute regardless of ordering.

There is therefore **no verified counter-example, and none confirming the rule
either.** `ReorderDocumentsOnCompile=0` beside a hand-pinned dependency order is
weak evidence the original author believed it.

**A genuine finding survives the retraction:** there are two `Altium_API.PrjScr`
files with different document orders, and the one in the repo is not the one
that compiles. Reasoning about compile order from the checkout is how this went
wrong. `lint.py`'s `PAS_FILES` matches the **deployed** order, so its
cross-file rule was validating the right thing all along; a new test in PLT-hw
(`test_manage_shared_runtime.py::DeployedCompileOrderTests`) now fails if the
two lists drift apart.

**What it cost.** Route 3 was abandoned on an untested premise, then
re-embraced on a bad proof. The one experiment that settles it — a handler *in*
`StatusForm.pas` calling *into* `Dispatcher.pas` — still had not been run.

**This build runs it.** The wiring below is route 3, deployed as an experiment
with a named failure mode rather than as a change believed correct:

| Outcome at script start | Means |
|---|---|
| `Undeclared identifier: MCPTimerTick` | rule is **real**; the DFM route is closed and the fix needs another mechanism |
| starts clean, no `_tick_first` | ordering fine; **rule 3** bit again — the DFM did not bind the handler |
| `_tick_first` present | both fine; the arrangement below is correct |

Note the cycle this sits on: `StatusForm.pas` must hold both the DFM handler
(needing `Dispatcher`, later) and the UI helpers `Dispatcher` calls (earlier).
**If the ordering rule is real, that cycle is unsatisfiable and no arrangement
of these files works** — the fix would have to stop being a DFM timer.

**The wiring under test:**

- `StatusForm.dfm` declares `tmr_MCP` with `OnTimer = tmr_MCPTimer` — rule 2 and
  rule 3 satisfied, same as `tmr_Spinner` and `tmr_Probe`.
- `StatusForm.pas` defines `tmr_MCPTimer`, three lines, calling `MCPTimerTick(0)`;
  plus `ArmMCPTimer` / `DisableMCPTimer` / `SetMCPTimerInterval`, which have to be
  there because they name `tmr_MCP` (rule 2).
- `Dispatcher.pas` keeps `MCPTimerTick` and all dispatch state. Exactly **one**
  call crosses forwards, and it is the three-line shim. That is the bet.
- `MCPYield` is **deleted**, not left unused: it wrapped the file's only
  `Application.ProcessMessages`, and an unused helper for the exact operation
  that causes the P0 is a landmine. A test now asserts zero occurrences.

**Guards added so this class of failure is cheaper next time.** Rule 3 fails
*silently*, which is what made it expensive. `tests/test_pas_project_consistency.py`
now fails if any `StatusForm.dfm` handler names a procedure `StatusForm.pas` does
not define, and `MCPTimerTick` logs `_tick_first` so "armed but never fired" is
distinguishable from "fired and something else broke".

**Residual, not fixed here:** `Library.pas` still calls
`Application.ProcessMessages` three times inside handlers. Those run *during* a
tick and can still defer keyboard dispatch for the duration of a library
command. Out of scope for this change; recorded in TODO.

## 2. Hard prerequisite — do not write §3 until this passes

SHUTDOWN.md already states it: *"First verify callbacks survive startup
return."* Stage it, cheapest first. **If a stage fails, stop — and per
SHUTDOWN.md, do not restore the polling loop just to make the experiment pass.**

| # | Question | How |
|---|---|---|
| **P1** | Does a form outlive the procedure that showed it? | `ShowStatusFormDiagnostic` (already written, ships this deploy window). Form still there after the script returns = VM survives the call |
| **P2** | Does a **TTimer on that form still fire** after the return? | `ShowStatusFormTimerProbe` (written 2026-09-23, ships this deploy window). Arms `tmr_Probe` at 1 s and returns; the tick count and elapsed seconds show in the form **caption**, readable in the taskbar while minimized |
| **P3** | Does Stop / form-close / normal Altium quit stay clean with a live timer? | SHUTDOWN.md's existing shutdown probe procedure — but close the form while the P2 probe is still ticking first; that is §7's failure mode for free |

**P1 is free** — it is already in this deploy window for the Ctrl+Z
discrimination, and it answers both questions at once. **P2 is the real gate**,
and it is now also free: the probe rides the same Altium stop/start cycle, so
neither prerequisite costs a window of its own.

Reporting elapsed seconds beside the count is deliberate — it makes P2 a rate
measurement, so "fires but starved" comes back as its own answer rather than
being scored as a pass.

**If P2 fails**, the timer bridge is dead. The fallback is thinner than this
document originally claimed, so state it accurately:

Flush-on-shutdown **is not available**. It was specified as
`PeekMessage`/`PM_REMOVE`, and `Project.pas:2145` already records that
DelphiScript blocks `external` DLL imports — user32 is unreachable, so the
flush cannot be written here at all. That also retires the 5-press count, which
existed only to decide whether to build it (TODO P0 carries the full reasoning,
including why the test would not have discriminated anyway).

What actually remains if P2 fails: keep the blocking loop, keep the caption
warning, and probe **`Application.OnMessage` via a DFM-loaded
`TApplicationEvents`** — untested, and the one candidate that needs no external
import, since Ctrl state can be tracked from the messages themselves. If that
fails too, the honest conclusion is that keyboard dispatch cannot be fixed from
inside a DelphiScript bridge, and the operator warning is the permanent answer.

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

**Done ahead of the redesign, 2026-09-23.** `StatusFormClose` now disables
`tmr_Probe` and `tmr_Spinner` before the form goes away, so the prescribed
ordering is established while the only timers are a spinner and a probe and the
blast radius is nil. `tmr_Spinner` was already exposed to this — closing the
form mid-request left it enabled — so this is a latent fix, not just
groundwork. Closing the form during the P2 probe exercises the path for real.

## 8. What would make this worse rather than better

Stated up front so review can weigh it:

- ~~**A live timer at Altium quit may be a *new* crash surface**~~ — **corrected
  2026-09-23: it is an EXISTING surface.** Quitting Altium with the bridge
  attached crashes *today*, on the polling loop, reproduced on `2026.09.23.1`:
  `ScriptingSystem.DLL` access violation reading `0x78`, stopped on
  `If Client.IsQuitting Then` in `MCPHostAvailable` — the guard dereferences the
  already-freed `Client` it exists to test, and its `Try/Except` cannot catch an
  AV raised inside a native call. So **P3's bar is "no worse than today", not
  "clean"**, and a timer that is disabled before teardown may well be *better*
  than a loop that keeps calling into a dying host. Do not let this item block
  the redesign on a standard the current design also fails. The operator rule is
  unchanged: stop the bridge before quitting Altium.
- **Exceptions change shape.** Today one `Try/Except` wraps the whole loop and a
  failure ends the session. Per-tick handling means a repeating fault could log
  forever instead of stopping. Add a consecutive-failure counter that finalises
  after N.
- **Every native-acceptance result was obtained against the polling loop.** This
  is not a patch; it is a new execution model and needs its own qualification
  pass, not a diff review.

## 9. Sequencing

1. **P1** — free, in the current deploy window (`ShowStatusFormDiagnostic`).
2. **P2** — also free, same window (`ShowStatusFormTimerProbe`, written
   2026-09-23). Small, isolated, no MCP, no CAD, self-bounding at 120 ticks.
3. Only then §3–§7, in a dedicated window, with §8's counter included.
4. Full native acceptance as a new execution model.

Until step 3 lands, the operator guidance stands and the caption warning
shipped 2026-09-23 is what stands between a deferred keypress and a silently
reverted board.
