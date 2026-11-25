# Trial 2026-11-25: one sheet through upstream as it is

**Status: installed, not started.** Decided by Stefan, 2026-11-25. Limits of the
trial: [AGENTS.md](../AGENTS.md), "Upstream trial".

## The question

Is this fork's restricted layer (selected project, preview and approval hash,
one tick per batch, never saves) still needed, now that upstream has operator
settings that refuse edits, deletes and closing, a dry run on many tools, and
most of what our pilot had to ask for? The answer decides how much of our layer
is rebased, offered upstream, or retired. The aim behind it: be in line with
upstream and contribute there, not carry a parallel bridge.

## What is installed (this workstation)

Under `%LOCALAPPDATA%\PLT\eda-agent\upstream-trial\`, beside the restricted
runtimes and touching none of them:

| | |
|---|---|
| Upstream commit | `9b741b5` (version 0.8.3) |
| `venv\` | upstream's server, installed from the upstream checkout |
| `scripts\Altium_API.PrjScr` | upstream's script project, unmodified |
| `workspace\` | its own request folder (`EDA_AGENT_WORKSPACE`) |

Upstream's scripts find their workspace through one fixed file,
`C:\ProgramData\eda-agent\workspace-path.txt`, which the install wrote. Our
runtimes do not read that file (the generator gives each its own pointer). The
script project is **not** registered in Altium's Global Projects: for the trial
it is opened as a project and started by hand, as ours is.

Offline check (`eda-agent health`): 4 passed, 2 warnings (not registered in
Global Projects, on purpose; no EasyEDA extension), 0 failures. Nothing has
talked to Altium.

## How to run it

1. No session on the restricted bridge. Altium closed and reopened.
2. The trial project is a **copy**, or its files are committed and pushed.
3. Open the script project above; run `Dispatcher.pas > StartMCPServer`.
4. In upstream's settings: Deleting refused, Closing refused, UI automation
   off, Edits allowed. Saving stays with the operator.
5. The trial session starts upstream's server with
   `EDA_AGENT_WORKSPACE` set to the workspace above
   (`<venv>\Scripts\python.exe -m eda_agent`), full tool set.
6. First call: its `doctor` preflight (version match, a read round trip).

## What is done in it

The same job as the restricted pilot, so the two can be compared: the library
symbols of one sheet (including a copy of a generic symbol and a filled body),
the sheet, its parts, wiring, parameters, then the compiled netlist against
the plan.

## What is recorded

| | Restricted bridge (pilot) | Upstream |
|---|---|---|
| Times the operator had to act (ticks, focus, questions, saves) | | |
| Things reported done that were not | | |
| Anything saved, closed, deleted or changed that was not asked for | | |
| Which project and document each write went to, and how that was decided | | |
| Script errors, dialogs, hangs | | |
| What could not be done at all | | |
| Time for the sheet | | |

Plus, per write tool used: whether it has a dry run, and whether an apply can
detect that the design changed since the dry run.

## What each outcome means

- Upstream holds up: adopt it; keep a short operating guide (commit first,
  review the diff, the operator saves); offer upstream what it lacks, starting
  with "never save" and binding to a chosen project; retire the rest of our
  layer.
- Upstream does something not acceptable on a real board: that names the part
  of our layer to keep, rebase and offer upstream.

## Removing it

Delete the `upstream-trial` folder and `C:\ProgramData\eda-agent\`. Nothing
else was changed.
