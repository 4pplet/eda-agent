# Trial 2026-11-25: one sheet through upstream as it is

**Status: first session run 2026-11-25 (reads, one copy and one delete of a library symbol). The sheet itself is not drawn yet.** Decided by Stefan, 2026-11-25. Limits of the
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

## First session, 2026-11-25 (upstream `9b741b5`, Altium 23.3.1, a project whose files were committed and pushed)

Connection:

- Upstream refuses a server started by a script in an AI session's shell; the tools are reached only through
  the session's own connection. A deliberate guard, and a good one.
- The `--toolset` flag restarts the server once, which drops a stdio connection on Windows: the client waited
  out its whole limit twice. The documented way, the environment variable, works. To report upstream.
- The server exits with code 0 and no message when its main loop ends, so a crash at start would look the
  same. To report upstream.
- The script loop in Altium stops after sitting idle and is started again by hand, as ours is.

Reads (no window had to be focused):

- Open projects, every document of every open project with loaded and modified flags, the active document,
  the documents of one project by its path, the symbols of a library by its path. Three projects were open;
  each read named the project or file it was asked for.
- Its ping reports per-unit stamps and whether saving is allowed (it was).
- Every reply that touches a part carries a long block of instructions for the agent ("datasheet first").
  It is text inside a tool result; it costs context on every call and is treated here as data.

Writes (library only, by explicit path, nothing saved):

| Step | Reply | Checked |
|---|---|---|
| Focus the library by path | done, and it says the focused document moved | active document read back |
| Copy a two-pin symbol to a new name in the same library | success, "verified", 2 pins, "in memory only" | the copy read back with its pins, parameters, hidden pin labels and footprint link; no file changed on disk |
| Delete the copy | success, "in memory only" | **two reads disagree**: the library's list no longer has the name (47 symbols, as before), but a read of the symbol by name still returns it in full |

Findings:

1. **A read that disagrees with another read.** After the delete, the list says gone and the lookup by name
   says present. Which is true needs a look in Altium's library panel. Until explained, a lookup by name is
   not a read-back for a delete.
2. **The modified flag stayed false** on the library through a copy and a delete. Here the net change is
   nothing, so this proves little; upstream's own notes say a copy may leave the library reading as saved.
   To test: copy only, then read the flag.
3. A copy keeps footprint links and parameters (an open question in our own proposal: answered yes).
4. Nothing was saved, closed or changed without being asked. Saving is available to the agent
   (`app_save_all`, `app_save_document`) and was not used.
5. Not yet looked at: the operator's permission settings (edits, deleting, closing), a dry run, what a write
   does when another project's document is in front, and the sheet itself.

Second step, same day (the library had been closed by the operator without saving):

- A copy addressed to the closed library by path **opened it and moved focus to it**, and said so in the reply.
- **Copy only, then the modified flag: still false.** The library holds a symbol that is not on disk and reads
  as saved. On this Altium (23.3.1) upstream's own guard for that case does not hold. Consequence: neither an
  agent nor a status read can tell that there is unsaved work in a library. To report upstream.
- The operator's permission settings (edits, deleting, closing, UI automation) are on the Config tab of
  upstream's status window in Altium and are stored in the workspace; only the operator changes them. No tool
  reads or sets them.

## Removing it

Delete the `upstream-trial` folder and `C:\ProgramData\eda-agent\`. Nothing
else was changed.
