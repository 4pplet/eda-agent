# Checked schematic edits: labels, power ports, wires, text, notes, boxes, sheet parameters

2026-11-18, PLT fork. Scripts `2026.11.18.4`, runtime `selected-edits-20261118e` (`.3` / runtimes `c`, `d` were the
first build: the script loaded on AD 23.3.1, ping `.3`, but the client refused its own command, fixed in `d`; `.4`
adds `compparam`). Stefan asked for it
the same day ("let's also do the schematic work ... useful functionality, not just this specific
thing"), after the 22p ESD pin table had to change and the bridge could not rename 24 net labels.
PLT-hw backlog 5a (labels on pins) and most of 5b (schematic tidy).

## 1. What it adds

One native command, `project.edit_schematic_checked` (`SelectedEditSchematicChecked` in
`SelectedProject.pas`), behind `SELECTED_PARAM_EDITS` and the parameter tick, which the status form now
calls "Allow schematic edits".

- **preview** (read, no tick): the sheet list; with `sheet` = an index, that sheet's net labels, power
  ports, ports (read only), wires with every vertex, free text, text frames, rectangles, lines, the
  electrical end of every pin (Location + PinLength along Orientation) and the sheet-level parameters.
  Raw coordinates. `templates=1` adds each sheet's template file name (opt-in, see section 2).
- **apply**: at most 200 items `op|sheet|x1|y1|x2|y2|n|s1|s2|s3`, texts percent-encoded, `%0A` = CR LF.
  - `add` a label, power port, wire, text, box, line or note;
  - `settext` on a label, power port, text or note (old text must match);
  - `move` a label, power port or text;
  - `del` any of the seven kinds by exact geometry (and text);
  - `docparam`: the value of one sheet-level parameter (old value must match);
  - `compparam` (`.4`): one parameter on every part of a designator on the sheet, so a multi-part symbol is
    covered sheet by sheet; changes it (old value must match on every part) or, with n = 1, adds it hidden
    (`SetCompParamText`'s creation path: factory, Name, Text, `Comp.AddSchObject`, `SchRegisterObject`). The
    older parameter writer is untouched.

It never creates, moves or deletes parts, pins, ports or sheet symbols.

Checks before the first write, whole batch refused otherwise: every sheet of the project open, the
touched sheets saved, the old object found exactly once at its exact place with the stated text, an add
not duplicating an object, a sheet parameter not read-only. One PreProcess / PostProcess pair per sheet,
every item read back, the sheets marked modified, never saved, the tick cleared.

The client side (PLT-hw `tools/eda-agent`): `sch_plan.py` resolves a plan written by intent (`pinnet`,
`pinpower`, `renamenet`, raw graphics ops, `docparam`) against the read; `bridge_write.py sch
read|preview|apply|verify`; `verify` compares the plan's pins with the compiled netlist after the save.

## 2. Where the code comes from, and what is unproven

Object creation follows the fork's own `Generic.pas` (upstream code that already loads in this
runtime): the wire's two `InsertVertex` calls, `RegisterSchObjectInContainer` + `SchRegisterObject`,
the sheet's majority net-label style (`InferNetLabelStyle`), typed locals for `Corner`.

Upstream fixes read before the build (salitronic/eda-agent, 2026-11-06 to 11-17) and applied:
- `160650b` a removal is announced with `SchRegisterObject` after `RemoveSchObject`, or the compiled
  model keeps the object until the sheet is reopened;
- `d23c50d` a Text write lands on a read-only parameter anyway: refused here (`ValueIsReadOnly`);
- `71da1a4` the line break in a text frame is CR LF.

Unproven on this Altium version, so kept out of the default path:
- `GetState_TemplateFileName` (upstream `a98d70e`, measured on AD 25.8.1): read only with `templates=1`;
- `ISch_Parameter.ValueIsReadOnly`: reached only by `docparam`;
- setting a template (`Sch:ChangeCurrentTemplate`, Silent) is NOT built: it acts on the active sheet
  through a process, and a dialog on another version would block the loop. Try on a disposable copy.

## 3. Qualification (real 22p, git as rollback: PLT-hw 47d5467 holds the CAD)

| # | Check | Pass |
|---|---|---|
| Q1 | runtime loads, ping `2026.11.18.4` | no script error |
| Q2 | `sch read` on the 22p (six sheets) | counts per sheet plausible; U405's ten pin ends lie on its wires / labels |
| Q3 | `sch preview` of the 24-pin relabel plan | each pin shows `old -> new`; a pin whose wire reaches another part is refused, not renamed |
| Q4 | apply without the tick, then with it | stopped; then 24 written, read back |
| Q5 | Stefan saves; `sch verify` | 24 of 24 pins on the planned net in the compiled netlist |
| Q6 | on a scratch corner of one sheet: `box`, `note` (two lines), `text`, `line`, then `settext`, `move`, `del` of each | drawn as planned; deletes leave nothing; undo in Altium takes each batch back |
| Q7 | `pinnet` + `pinpower` on a bare scratch part's pins (or after deleting one stub) | stub + label / port; `verify` passes after the save |
| Q8 | refusals: unsaved sheet, wrong old text, duplicate add, a second apply with the same hash | nothing written each time |
| Q9 | `docparam` on one title-block field; `sch read --templates` | value changes and reads back; the template read returns names without stopping the script |
| Q10 | `compparam`: change one field of U301 (multi-part) and add a new field to one resistor; save; `parameters` read | every part carries the value; the new field exists, hidden |

## 4. Qualification record

- 2026-11-18: the `.3` script loaded on AD 23.3.1 without an error (ping `2026.11.18.3`, runtime `c`).
- **Q1-Q5 passed 2026-11-18 on runtime `e`, real 22p**: ping `.4`; `sch read` of the four sheets (621 pins); the
  relabel preview refused all 24 pins first (each label's wire also reaches the NC twin pin), then with `shared`
  resolved to 12 label edits; apply without a tick was stopped, with it 12 of 12 written and read back; after
  Stefan's save `sch verify` read 24 of 24 pins on the planned nets and Update PCB carried them to the board.
  The sheet labels PB7 / PB6 as SDA / SCL: the plan took an `expect` for the compiled name.
- Q6-Q10 pending. Scripts `.5` / runtime `f` (same schematic code): see the copper-delete proposal, section 4.
