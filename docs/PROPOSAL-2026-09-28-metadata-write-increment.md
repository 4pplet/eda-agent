# Proposal: a first metadata-write increment

**Status: proposal, 2026-09-28. Nothing here is implemented or enabled.**
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
