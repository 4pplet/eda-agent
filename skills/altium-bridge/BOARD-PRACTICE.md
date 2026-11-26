# Altium and board practice (not run through the eda-agent server)

This is a list of practice, **not a procedure**. No board has been laid out through
upstream's server by us. It was section 9 of [SKILL.md](SKILL.md) until 2026-11-26 and was
moved out so it is not read as steps to follow. When a board has been done through the
server, what was learned replaces this file.

- **Parameters carry the order:** manufacturer part number, supplier number and a
  fitted or not-fitted instruction on every part, checked against an expectation file. A
  bill of materials edited outside the schematic is not a correction.
- **Pin 1 and orientation** are checked on the placed part, not assumed from the symbol.
- **Rules before routing:** stackup, clearances, widths, vias, pairs and classes set from
  a spec file before the first track, and read back, priorities included.
- **A rule check with every rule enabled** before any release, and the report read for
  which rules ran. Repour before a rule check after any move or copper change.
- **Update PCB is the operator's.** Compare first, read the change order, then they
  execute.
- **Output jobs are checked as files:** a layer plotted twice is found in the outputs,
  not in the editor.
- **Order of a layout:** stackup and impedance from the fabricator; placement before
  routing (connectors and mechanics first, then parts with placement rules in their
  datasheets); return paths unbroken; decoupling at the pin it serves; clearance and
  creepage for the voltages present; pairs routed as pairs; thermal pads as the datasheet
  says; test points, fiducials and readable polarity marks; the fabricator's and
  assembler's rules. Every number from the vendor's document, cited.
