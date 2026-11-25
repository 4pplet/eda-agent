# Design: a development runtime (fixes without a new folder and an Altium restart)

Written 2026-11-25. A design note, nothing built. Roadmap phase 2.

## The cost today

Every fix, Pascal or Python, is: stop the bridge, close Altium, generate a new
`selected-edits-<date><letter>` folder, start Altium, open the new script
project, start the server, select the project again. On 2026-11-18 a one-line
client fix cost three Altium restarts in one evening. Twenty-five runtime
folders have accumulated on one workstation in five weeks.

## What forces each step

| Step | Forced by | Really needed? |
|---|---|---|
| New folder for a **client** fix | the client files are inside the hashed runtime, and the script project is in the same folder | No. The client is ordinary Python in its own process; nothing in Altium reads it |
| New folder for a **Pascal** fix | our rule "do not replace loaded scripts", plus the hash manifest | Partly. Scripts must not change while loaded. They may change once the script project is closed |
| Altium restart | habit, and the same rule | No, by upstream's measurement (below) |

## What upstream measured about reloading

From `salitronic/eda-agent` at `9c0a14f` (their code and comments; **not yet
measured by us on AD 23.3.1**):

- Altium keeps compiled script units between runs. Running `StartMCPServer`
  again does **not** recompile an edited unit.
- Restarting Altium does **not** reliably recompile either: Altium reopens the
  script project together with its compiled units.
- What does: **close the script project** in the Projects panel (right-click,
  Close Project), reopen it, run `StartMCPServer`.
- A unit that fails to compile can keep serving its previous image while the
  version constant in `Main.pas` reads new. So one version string cannot say
  whether the code on disk is the code running. Upstream ends every unit with
  a `UnitStamp_<unit>` function; the deploy step writes a hash of the unit into
  it, a command reports all stamps, and the client compares them with the
  files.
- A running Altium can be told to start the script from outside:
  `X2.exe -RScriptingSystem:RunScript(ProjectName=<PrjScr>|ProcName=Dispatcher.pas>StartMCPServer)`.
  The second process hands over to the running instance and exits.

Two consequences for what we do today. A new folder per build has been
protecting us from the stale-compile trap without our knowing why: a new path
has no compiled units. And our `SCRIPT_VERSION` check would not notice a unit
that failed to compile in an existing folder.

## Proposed

1. **Client outside the hash for a development runtime.** The runtime keeps
   its scripts hashed; the client is run from the checkout. A client fix then
   needs no Altium action at all. Qualified runtimes keep their hashed client
   copy, so what was qualified stays what runs.
2. **One development runtime folder, regenerated in place**, allowed only
   while its script project is closed in Altium and no bridge answers. The
   loop for a Pascal fix: Detach, Close Project, regenerate, open the script
   project, Start. Altium stays open; the design documents stay open.
3. **Per-unit stamps**, ported from upstream, so `status` names any unit whose
   running compile differs from the file. Without this, step 2 is not safe to
   trust.
4. **Start from the command line** with the `-R` hand-off, so "Start" is a
   command and not a walk through the Run Script dialog. Starting a script in
   the operator's Altium stays the operator's call: the command is run by him
   or on his word.
5. **Qualification still happens on a dated, hashed, side-by-side runtime**
   built from the commit that the development loop arrived at. The
   development runtime is never the one a result is recorded against.

## To prove first, on a scratch project (cheap, one sitting)

| # | Check | Pass |
|---|---|---|
| D1 | edit a string in a handler, Close Project, reopen, Start | the new string is served, Altium not restarted |
| D2 | the same edit, Start again WITHOUT Close Project | the old string is served (confirms the trap exists on AD 23.3.1) |
| D3 | break one unit on purpose (a syntax error), Close Project, reopen, Start | what Altium does: refuses to start, or serves the old image. Decides how much the stamps matter |
| D4 | the `-R` hand-off with the script project open | the server starts in the running Altium; no second instance stays |
| D5 | the `-R` hand-off while a modal dialog is open | recorded; upstream found the script goes to a second Altium |

## What this changes in AGENTS.md (Stefan's text)

"Do not replace loaded scripts. Stop the bridge and close Altium before
deploying a new side-by-side runtime" stays true for qualified runtimes. The
development runtime needs one added sentence: its scripts may be replaced
while its script project is closed in Altium.

## Not proposed

Reloading while the script project is open; replacing files under a running
loop; using the development runtime for writes on a working board.
