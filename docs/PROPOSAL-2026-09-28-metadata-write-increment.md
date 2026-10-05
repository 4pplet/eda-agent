# Proposal: a first metadata-write increment

**Status: approved by the operator 2026-10-03 and implemented in source (scripts
`2026.10.03.1`); NOT deployed. Native qualification (section 5, plus T14-T17 in
section 7) is open.** Section 7 records how the build differs from this proposal.
Qualify on a day without CAD work, on a disposable copy, per the operator's
standing decision in [CURRENT-STATE](CURRENT-STATE.md).

This is a scoped, concrete slice of **Gate 3** in
[PROJECT-SELECTION-AND-WRITES](PROJECT-SELECTION-AND-WRITES.md). It adds
nothing to that plan's principles. What it adds is an **audit of the native
handler it would build on**, a narrow field list driven by a real need, and a
test list someone can run in one sitting.

---

## 1. Why this, why now

Every BOM entry on PLT's 22p board is typed by hand into the Parameter Table
Editor from a reviewed part list. On 2026-09-28 that meant six `Instruction`
edits and about 25 part numbers, and it produced one real slip: `C219`, a
22 nF 0603 compensation cap, received `C12891`, the 22 uF 1206 part listed two
rows above it. The expectation checks caught it after the fact. A batch
generated from the reviewed list removes the transcription step entirely, and
the same checks then verify it before anything is saved.

Parameter edits are the lowest-risk write class there is: no connectivity, no
copper, no ECO, and `parameters --expect` already verifies the result.

## 2. Where writes are blocked today (keep both)

| Gate | Where | Effect |
|---|---|---|
| Python | PLT `shared_server.py` `ALLOWED` set, re-checked after the wheel rewrites its config | only listed tools are registered |
| Native | `Dispatcher.pas` `ProcessCommand`: when `SELECTED_PROJECT_READ_ONLY`, every command goes to `ProcessSelectedCommand` | the upstream write handlers are unreachable |

The increment adds **one command to both lists**. It must not flip
`SELECTED_PROJECT_READ_ONLY`, which would expose every upstream writer at once.

## 3. Audit of the candidate handler: do not expose it as-is

`set_sch_components_parameters` (`Generic.pas`,
`Gen_SetSchComponentsParameters`, around line 7758) is the obvious base:
batched, one `PreProcess`/`PostProcess` pair, no save. Read line by line, it
has these problems for our use:

| # | Finding | Why it matters |
|---|---|---|
| F1 | **Falls back to the focused document** when `sheet_path` is empty or does not resolve (`SchServer.GetCurrentSchDocument`) | Violates *never infer the target from the focused window*. A typo in the path writes to whatever sheet has focus |
| F2 | **Key `Value` writes `Comp.Comment.Text`**, not the `Value` parameter | On PLT these are distinct fields (`Value` = `0`, `Comment` = `Res1`). Asking to set Value silently overwrites Comment |
| F3 | **Empty values are skipped** (`Val <> ''`), so a field **cannot be cleared** | The 2026-09-28 DNP convention required clearing `LCSC Part #` on R404/R406/R407, the most safety-relevant edit of the day |
| F4 | **Values are not escaped.** `~~` splits ops, `;` splits fields | `DNP 47K - fit if V4 finds TE open-drain; then remove R425` is cut at the `;` and the rest parsed as a malformed field, silently. (`=` inside a value is fine: only the first `=` splits) |
| F5 | **`updated` counts matched components, not written fields.** `SetCompParamText`'s return is ignored, and is `False` for every *existing* parameter, `True` only on create | A success response says nothing about what landed |
| F6 | **Unknown names silently create a new parameter** (`SetCompParamText`, `Generic.pas` around line 6401; name match is case-insensitive) | `Instuction=...` adds a junk parameter instead of failing. Gate 3 says no creation in the first increment |
| F7 | `Footprint` is **silently skipped** yet counted as updated | Same as F5 |
| F8 | Edits go through `SchBeginModify`/`SchEndModify` (`RobotManager` `SCHM_BeginModify`) inside `PreProcess`/`PostProcess(..., 'Edit')` | The standard undo-registration path, so **undo is plausible, not qualified** |
| F9 | Marks the document modified; **does not save** | Correct. Keep |

**Verdict:** write a new narrow PLT handler that reuses the parsing and the
`SetCompParamText` approach but fixes F1-F7. Do not patch the upstream
handler in place: other callers may depend on its behaviour, and Gate 3 says
*do not expose an existing setter merely by name*.

## 4. The increment

**Command:** `project.set_component_params_checked` (native) /
`proj_set_component_params_checked` (MCP). One sheet per call.

| Rule | Detail |
|---|---|
| **Target** | `sheet_path` required, must be a member of the *selected* project, resolved exactly. No focused-document fallback (F1) |
| **Session grant** | Native refusal unless the operator has ticked **"Allow parameter edits (this session)"** on the StatusForm. Cleared on session end, Detach and selection switch. The agent cannot tick it, which is what stops an agent approving its own writes |
| **Field allowlist** | `LCSC Part #` and `Instruction`. Nothing else. `Value` and `Comment` belong to **Gate 4** (typed values, ownership), and F2 makes `Value` doubly unsafe with this code |
| **Existing parameters only** | Refuse if the named parameter does not exist on that component (F6). No creation, no deletion |
| **Clearing allowed** | Setting `""` is a normal write (F3). It is not deletion |
| **Compare-and-set** | Each field carries its expected old value. Preflight the whole batch and refuse **all** of it if any old value differs (a manual edit since preview) |
| **Encoding** | The client percent-encodes every value; native decodes `%XX`. Round-trips `;`, `=`, `~~`, `%`, quotes, micro and Ohm signs (F4) |
| **Clean baseline** | Refuse if the target sheet is already dirty. One batch per save (Gate 3's first-version rule) |
| **Honest result** | Per field: `written` / `unchanged` / `refused` plus reason, with the value **read back from the object after the write** (F5, F7) |
| **Never save** | The document is left dirty. The operator's Save All approves the result; close-without-save is the recovery |

**Client (`bridge_write.py`, separate from `bridge_read.py`):**

1. `preview --batch <file.json>` reads current values live, prints
   `ref / field / old -> new` and computes a batch hash. **Default, and dry.**
2. `apply --batch <file.json> --hash <h>` refuses if the hash or any old value
   changed since preview, then sends one native call per sheet.
3. It immediately re-reads every touched field and, if given, runs
   `parameters --expect <file>`.

Batch file shape, in the same style as the expectation files:

```json
{"sheet": "C:\\...\\4_22p-adapter_IO.SchDoc",
 "edits": [
  {"designator": "R404", "field": "Instruction",
   "old": "DNP 0R",
   "new": "DNP 0R - board B only. Never with R428 (shorts VDDIO)"},
  {"designator": "R433", "field": "Instruction",
   "old": "DNP 47K",
   "new": "DNP 47K - fit if DK V4 finds TE open-drain; then remove R425"}
 ]}
```

## 5. Qualification: one non-CAD sitting, disposable copy

Pinned runtime version, stop-first lifecycle as currently qualified, on a
`design-copy` of the 22p project. Record the Altium version and hashes.

| Test | Pass means |
|---|---|
| T1 happy path | 6 `Instruction` edits in one batch; read-back exact; `nets --diff` against a pre-batch snapshot shows zero changes |
| T2 clear | `LCSC Part #` set to `""` on one part; read-back blank; the parameter still exists |
| T3 round-trip | a value containing `;` `=` `~~` `%` `"` and micro/Ohm signs comes back byte-identical |
| T4 no fallback | missing and misspelt `sheet_path`, with a *different* sheet focused: refused, **dirty count unchanged** |
| T5 stale | hand-edit one field after preview: whole batch refused, nothing written |
| T6 allowlist | `Value`, `Comment`, `Footprint`, `Instuction`: refused in preflight, **no parameter created** |
| T7 unknown ref | designator not on that sheet: refused in preflight |
| T8 **undo** | after T1, record exactly what one Ctrl+Z and Edit > Undo revert: the batch, one field, or nothing. **This decides the recovery story** |
| T9 recovery | close without saving and reopen: every field equals its pre-batch value |
| T10 persistence | save, close, reopen: values persist; the BOM export shows them; `nets --diff` zero |
| T11 grant | grant off: refused natively, **including a direct native request that bypasses Python**. Detach and selection switch clear the grant |
| T12 dirty target | pre-dirty the sheet by hand: refused |
| T13 disconnect | kill the client mid-apply: outcome reported *unknown*; the next preview shows the true native state; no automatic retry |

**Exit:** all 13 pass on the copy. Only then add the command to the live PLT
runtime, still restricted to `LCSC Part #` and `Instruction`.

## 6. Out of scope for this increment

`Value`, `Comment`, footprints, parameter creation or deletion, variants,
annotation, any PCB-side write, saving, and the full Gate 2 permissions panel
(this uses one session checkbox, not per-capability grants).

## 7. Implementation, 2026-10-03

Approved by the operator 2026-10-03. Source only; no runtime provisioned, nothing deployed.

**Where it is**

| Part | Location |
|---|---|
| Native gate | `Main.pas` `SELECTED_PARAM_EDITS = False` (source default) |
| Native command | `SelectedProject.pas` `SelectedSetParamsChecked`, reached from `ProcessSelectedCommand` only when the gate is True |
| Grant | `SelectedProject.pas` `ParamEditGrant` / `ToggleParamEditGrant`; `StatusForm` `chk_AllowParams` (hidden unless the gate is True) |
| Runtime | PLT-hw `create_shared_runtime.py --param-edits`: mode `selected-project-param-edits`, ping profile `eda-selected-paramedit-v1` |
| MCP tool | PLT-hw `shared_server.py` `proj_set_component_params_checked`, registered only in that mode |
| Client | PLT-hw `bridge_write.py` (`preview`, `apply --hash`) |
| Batches | PLT-hw `sheet_spec.py batch` |
| Offline tests | PLT-hw `test_param_edits.py`, `test_bridge_write.py`, `test_shared_runtime.py`, `test_sheet_spec.py` |

**Differences from sections 4-5**

- **Preview is native.** `mode: preview` reads the targeted parameters from the same schematic
  objects an apply writes and returns `would_write` / `unchanged` / `refused: reason` per edit; it
  needs no grant and writes nothing. The client's approval hash covers project, sheet and, per
  edit, the previewed value and the new value; the selection token is left out so the grant tick
  (which bumps the generation) does not void a preview. Compare-and-set at apply is the guarantee.
- **One tick, one batch.** An apply that touches the sheet clears the grant natively, so the
  operator approves each batch, not a session (review finding C4). Grant changes bump the
  selection generation, so a token taken before a tick or untick is refused afterwards. A project
  switch, Detach and session end clear the grant; the tick is refused while a request is in
  flight; the status form logs a grant that ended without a click.
- **Identity is bound, not only values.** Preview returns each component's `UniqueId`; the
  approval hash covers it and apply refuses (`refused: component identity changed since
  preview`) if a re-annotation moved the designator to another part (review finding C3).
- **Separate runtime identity.** The param-edit runtime's ping names `eda-selected-paramedit-v1`
  and its selection carries `param_edits: off | granted`; the read-only client refuses such a
  bridge and the write client refuses the read-only one. With the gate False, ping and selection
  JSON are unchanged from `2026.10.02.1`.
- **Review.** An adversarial review of the build on 2026-10-03 found C1-C6 and P1-P3; all are
  addressed as listed above and in the tests.
- **Encoding is ASCII-only.** Values are percent-encoded printable ASCII; micro and Ohm signs are
  refused on both sides until a Unicode round trip is qualified. T3 is narrowed accordingly.
- **Multi-part and duplicate designators are refused.** The designator is counted across every
  schematic of the selected project, so every schematic must be open (`SHEET_NOT_OPEN`
  otherwise). A multi-part device split over sheets (the HDMI board's U501) is set by hand.
- **Apply marks the sheet dirty after a write** (`MarkDocDirtyByPath`): upstream 69374c2 measured
  that an API parameter write leaves the document clean, so Save has nothing to flush.
- **Outcome classes, decided by code.** Native refusals all return before `PreProcess`. PLT-hw
  `shared_server._param_edit` prefixes every failure with `NO_WRITE:` (client validation, the
  selection or grant check before sending, a native pre-write error code, any preview failure) or
  `OUTCOME_UNKNOWN:` (a timeout, disconnect, `CHANGED_DURING_WRITE`, any other native code, a
  result that fails validation, a selection that moved before delivery), and the client reads
  only that leading prefix. Free-text matching was rejected after review finding C1: a triage
  annotation can quote an old refusal from the log. Never re-run apply on OUTCOME_UNKNOWN.
- **Dirty mark on touch.** The sheet is marked dirty as soon as a value is assigned, whatever
  the read-back says, and `PostProcess` / `GraphicallyInvalidate` are each guarded (C2). The
  parameter is found first and written after its iterators are destroyed, as `SetCompParamText`
  does (P1).
- **Values that cannot round-trip block at preview** (C5): apply sends the previewed value back
  as `old`, so a current value outside printable ASCII is reported for a hand edit.

**Added native tests**

| Test | Pass means |
|---|---|
| T14 multi-part | a designator with two symbols (same or different sheets): refused in preview and apply, nothing written |
| T15 read-only unchanged | a read-only runtime built from `2026.10.03.1`: ping and selection JSON have the `2026.10.02.1` shape (no `param_edits`), the command returns `READ_ONLY`, no checkbox shows, the read surface passes its usual smoke test |
| T16 grant lifecycle | tick, untick, project switch and Detach each change or clear the grant as the window shows; a token from before a tick is refused; the tick does nothing while a request is in flight; after an apply that wrote, the grant is off, the log says so and a second apply is refused until the next tick |
| T17 identity | preview, then swap two designators by hand and save, then apply with the old hash: refused, nothing written |

**Qualification procedure (non-CAD day)**

1. Stop the bridge, close Altium. Make a disposable copy of a project (the 22p is the reference).
2. `python create_shared_runtime.py --root %LOCALAPPDATA%\PLT\eda-agent\shared\selected-paramedit-<date> --tool-source <eda-agent checkout> --param-edits`
3. Start Altium, open the copy and the new runtime's `scripts\Altium_API.PrjScr`, run
   `Dispatcher.pas > StartMCPServer`, select the copy, open all its schematics.
4. Run T1-T17 with `bridge_write.py --shared-root <that runtime>` and record each result, the
   Altium version and the runtime hashes in a dated note.
5. Only then decide whether the runtime may point at a working project.

## 8. First live use and widening, 2026-10-05

**Stefan's decisions, 2026-10-05:** qualify on the live HDMI project instead of a disposable copy,
with every design file committed and pushed first as the rollback point (PLT-hw e1a9041); and,
once that worked, widen the write from `LCSC Part #` / `Instruction` to any existing parameter.

**Live results on scripts `2026.10.03.1` (runtime `selected-paramedit-20261005`):**
- Refused in preview, nothing written, the sheet stayed clean: `Value` and `Instuction` (client
  allowlist), an unknown designator, a designator on another sheet, the two-part CON401 (T14).
- Apply without the tick: refused, nothing written (client side; the native bypass half of T11
  was not exercised).
- Four batches applied, one tick each: sheet 4 (15 written), sheet 2 (19), sheet 5 (21),
  sheet 1 (1). Each read back exact, the grant ended with each batch, only the target sheet was
  dirty, and after Stefan saved, the netlist was identical to the pre-write baseline and exactly
  the batch's fields had changed (PLT-hw `hdmi-adapter` commits 48285f0, 842daab, 7e30c29, cff020f).
- Not exercised live: T3 round-trip of special characters, T5 stale hand edit, T8 undo (Stefan
  saved without the Ctrl+Z step), T9 close without saving, T12 pre-dirtied sheet, T13
  disconnect, T16 tick lifecycle detail, T17 identity swap. They remain open.

**Widening, scripts `2026.10.05.1`:** any EXISTING parameter by exact name (printable ASCII,
1-64 characters). Never written: `Designator`, `Footprint` and the component properties that the
parameter table shows but that are not parameters (`Component Kind`, `Library Reference`,
`Library Name`, `Pin Info`, `Signal Integrity`, `Simulation`, `Ibis Model`, `PCB3D`). The
finder now matches the name exactly (was case-insensitive), so a misspelt field finds nothing
and is refused; nothing is ever created. Every other rule of section 7 is unchanged.

**Workflow (Stefan):** read every parameter, write a change log, Stefan approves it, then apply
it (PLT-hw `tools/eda-agent/bom_plan.py` writes the log and the batches from the same plan).
