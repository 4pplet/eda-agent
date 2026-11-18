# Proposal: three upstream lessons (micro sign, timed-out requests, annular ring), 2026-11-17

Status: **asked for by Stefan 2026-11-17** ("let's do it tonight", after the upstream review in PLT-hw
`tools/eda-agent/UPSTREAM-REVIEW-2026-11-17.md`); built the same night, **native qualification U1-U7
pending**. Scripts `2026.11.17.5`, runtime `selected-edits-20261117e`; **qualify on `selected-edits-20261117f`** (scripts `.6`, which adds the read-only `pcb.get_texts`, U7). It also
carries everything in `.4` (graphic objects, G1-G8 passed 2026-11-18). **U1-U5 and U7 passed 2026-11-18** (section 4); U6 not run.

## 1. What changed

| # | Upstream | Here | Where |
|---|---|---|---|
| 1 | `f552f69` | `EscapeJsonString` writes all four hex digits of each UTF-16 code unit (`CodeUnitHex4` replaces `ByteToHex4`, which wrote `00` + the low byte: an Ohm sign U+03A9 read back as U+00A9) | `Utils.pas` |
| 2 | (`f552f69`'s lesson) | parameter edits carry the **micro sign** U+00B5 as `%B5`; `ParamEditDecode` accepts code 181 besides 32-126. It is below 256, so `Chr` makes it exactly. **Ohm signs (U+03A9, U+2126) stay refused** (`Chr` above 255 is unreliable in DelphiScript; upstream needed UTF-8 request files behind a BOM, which our ASCII-only, percent-encoded batches do not need for µ). The client hints: Greek mu U+03BC -> use U+00B5 or `u`; Ohm -> `R` / `ohm` | `SelectedProject.pas`; PLT-hw `shared_server.encode_param_value` (`PARAM_EXTRA_CHARS`), `bridge_write.encodable`, `bom_plan.PRINTABLE` |
| 3 | `f8afb3f` (part) | a request that times out before Altium reads it is **withdrawn** (its own `request_<id>.json` deleted), so it cannot run later; one Altium already took is reported as possibly still landing. Done in the hashed shared client by wrapping the pinned wheel's (0.5.0) `_poll_response`, not by changing the venv's wheel (which all runtimes share). A timed-out write stays OUTCOME_UNKNOWN: the window between the dispatcher's read and its delete is not closed | PLT-hw `shared_server.withdraw_timed_out_requests` |
| 4 | `c5c46f9` | the copper writer's vias and the graphics writer's pads never pass through a no-ring state: when the new size is not above the fresh object's default hole, the hole is set first. The client already refused hole >= size | `SelectedProject.pas` |

## 2. Not in it

Ohm signs in parameter writes; UTF-8 request files; changes to the wheel in the venv.

## 3. Qualification (real 22p, git as rollback, nothing saved)

| # | Check | Pass |
|---|---|---|
| U1 | ping `.6` on runtime `20261117f`; then G1 (drc and one OutJob refusal) on the same runtime | version and profile match |
| U2 | `bridge_read parameters`: L202 Value reads `3.3 µH` with the micro sign (and any value holding an Ohm sign, if the project has one, reads as Ω, not ©) | characters exact |
| U3 | param preview L202 Value `3.3 µH` -> `4.7 µH` | would_write, current read back exactly, nothing blocking |
| U4 | apply with the tick; read back; then apply `4.7 µH` -> `3.3 µH` | written exactly both ways, sheet unsaved, tick cleared each time |
| U5 | a graphics pad smaller than the default pad hole (e.g. 0.6 mm, hole 0.3 mm, NPTH) during G4 | placed with size and hole as asked |
| U6 | withdrawal: with a modal open in Altium (e.g. Preferences), one read times out; close the modal | error says "withdrawn"; no request file left; nothing ran late (workspace log) |
| U7 | (scripts `.6`, runtime `20261117f`, same night) `bridge_read texts` on the 22p: the free texts listed with layer and position; designators and comments counted, not listed | rows match what Altium shows; a hidden text is not listed |

## 4. Qualification record (2026-11-18, real 22p, runtime `selected-edits-20261117f`, scripts `.6`)

| # | Result |
|---|---|
| U1 | **pass**: ping `.6`, profile and selection; DRC and the OutJob refusal as G1 in the graphics proposal |
| U2 | **pass**: L201 / L202 Value read `4.7 µH` / `3.3 µH` with U+00B5 exactly; footprint names with U+00D7 exact. No Ohm sign in the project, so the U+03A9 read could not be exercised |
| U3 | **pass**: preview L202 `3.3 µH` -> `4.7 µH` would_write, nothing blocking |
| U4 | **pass**: applied with the parameter tick, read back `4.7 µH` exactly, unsaved, tick cleared. The back-apply is refused by design (one batch per save), so Stefan closed the sheet without saving; preview then read `3.3 µH` again with the identical approval hash (UniqueId kept) |
| U5 | **pass**: 0.6 mm pad with a 0.3 mm hole placed exactly (graphics G4/G5) |
| U6 | not run (needs a modal held open for a read to time out); offline tests only |
| U7 | **pass**: `texts` on the 22p: 23 free texts (all TopOverlay), 545 component texts counted, 0 hidden; `text_check` flagged the missing "V-CUT" (expected before today's CAD); after G4 it listed 24 with "G-TEST" |

Findings for the board: no "V-CUT" text yet; the silk still says "REV A2".

