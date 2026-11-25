# Proposal 2026-11-25: the library loop without the operator's hands

**Status: design only. Nothing here is built.** Approved in principle (Stefan,
2026-11-25): copying a symbol, removing a symbol in a narrow form, and opening,
activating and closing a document. Built in the library phase (roadmap phase 3),
after the built writers have run in Altium.

## 1. Why

A pilot that drew one schematic sheet through the bridge logged what cost the
operator time. In one day:

| What happened | Times | Cause |
|---|---|---|
| The operator was asked which documents are open or focused | 5 | not readable (fixed as a read in scripts `2026.11.25.2`) |
| The library was closed and restored from git to retry a rejected symbol | 3 | a created symbol cannot be removed |
| The operator clicked the library to focus it before a library plan | every plan | no op activates a document |
| A symbol was copied by hand from another library | 1 | no copy; drawn symbols are rectangles and pins only |

The writers work. The loop around them needs a person at every turn. These five
ops close it.

## 2. What stays as it is

- The operator selects the project. Every op is bound to that selection.
- Preview, approval hash, one tick, apply, read-back. The same schematic grant;
  no new grant kind.
- Nothing saves, nothing discards, nothing answers a prompt.
- A document outside the selected project is never opened, focused or closed.
  One exception, read only: the source library of a copy (section 3).
- The focused document still selects nothing (`AGENTS.md`: setting focus is not
  following it).

## 3. `libcopy`: copy a symbol into the project's library

Plan:

```
{"op": "libcopy", "library": "<target .SchLib, a project member>",
 "from_library": "<source .SchLib, absolute path>", "from_name": "Res1", "name": "R"}
```

- Create only: a `name` already in the target is refused. No overwrite.
- The source library may be the target itself (a copy under a new name): the pilot's library holds the
  generic symbols, copied in by hand once and committed. Then nothing outside the project is opened.
- The source is a `.SchLib` file. It may be outside the project and is only
  read. An integrated library is not a source in the first version: it has to
  be extracted first, and on a machine without the vendor libraries installed
  there is nothing to extract from. The practical source is a library kept in
  git.
- The source must be saved (not modified); the target follows the rules of
  every library op (active document, section 5 removes the click).

Native method, from upstream's `Lib_CopyComponent`, which records four traps we
keep:

1. A symbol nobody has shown may not be loaded: zero pins read from the source
   means show it, then look it up again.
2. The symbol on screen loses its shown part in a copy: show another symbol (or
   a temporary holder) before `Replicate`.
3. `AddSchComponent` renames the second and later additions in a session: set
   the name again after the add.
4. Without the registration broadcast the copy lives in memory and never
   reaches the file, while every read says it is there.

Upstream focuses the source and the target with `WorkspaceManager:OpenObject`.
Ours does that only for the source, restores the previous view afterwards, and
refuses if the source turns out modified.

Read-back before `ok`: the target resolves the new name, and the copy's pin
count, pin designators and primitive count equal the source's. Offline:
`schlib_check.py` gains a mode that compares a symbol in two saved files.

Refusals: name exists; source symbol not found; source or target unsaved; the
target is not a member of the selected project; the copy has fewer pins than
the source (the copy is removed again and the item reports the two counts).

## 4. `libdelete`: remove a symbol this session created

```
{"op": "libdelete", "library": "<.SchLib>", "name": "R_TEST"}
```

Allowed only when both hold:

- the bridge created or copied the symbol in this bridge session (the native
  side keeps the list: library path and name, cleared when the bridge stops or
  the selection changes), and
- the library has not been saved since (its modified flag has been set without
  a break since the creation; a save clears the list for that library).

So it can never remove a symbol that existed before the session, and "close
without saving" remains the complete rollback. A symbol that is placed on a
sheet in this session is refused.

Native method: upstream's `Lib_DeleteComponent` (`RemoveSchComponent` inside an
edit bracket, library marked modified). Read-back: the name no longer resolves
and the symbol count is one less.

This changes the rule "library ops are create-only" to "create-only, and undo of
this session's own creations".

## 5. Documents: `docopen`, `docactivate`, `docclose`

```
{"op": "docopen",     "document": "<member path>"}
{"op": "docactivate", "document": "<member path>"}
{"op": "docclose",    "document": "<member path>"}
```

- Members of the selected project only, by exact path.
- `docopen`: opens the document in its editor. Already open is `unchanged`.
- `docactivate`: the document must be open; it becomes the active one. Removes
  the click before each library plan; a library plan may then start with it.
- `docclose`: refused when the document is modified, when it is the board or a
  sheet with a modified sibling the compile needs, and when it is the last view
  of a document a running command uses. Never a prompt: if Altium would ask,
  the op has already refused.

They change no design data, so they need no approval hash over old values, but
they do go through preview (what would happen, what is refused) and they do
need the tick: an agent that rearranges the operator's editor unasked is not
acceptable. One tick may cover a library batch that starts with `docactivate`.

Native calls, all in upstream's `Application.pas`: `Client.OpenDocument`,
`Client.ShowDocument`, `Client.CloseDocument` on the document object. Upstream
notes that `WorkspaceManager:CloseObject` acts on the focused object, not the
named one, so it is not used.

Read-back: the freshness read (`open_docs`, `active_doc`, scripts
`2026.11.25.2`).

## 6. Not in this proposal

- Lines, polylines and arcs in `libsymbol` (a copied symbol keeps its drawing;
  decide after `libcopy` has been used).
- Multi-part symbols in `libsymbol`.
- Copy from a placed part or from an integrated library.
- Any close that discards, any save.

## 7. Order of building

1. `docactivate` and `docopen` (smallest, used by everything after).
2. `libcopy`.
3. `libdelete`.
4. `docclose`.

Each with client validation, a test through `SharedReader.send`, and its rows
below run on a copy of a library before a real one.

## 8. Qualification rows

| # | Test |
|---|---|
| L1 | `docopen` on a closed member library: it opens; `open_docs` lists it; nothing is modified |
| L2 | `docactivate` on an open library with a sheet focused: `active_doc` is the library; a `libsymbol` batch in the same plan then applies without a click |
| L3 | `docopen` / `docactivate` on a path outside the project, and on a member that does not exist on disk: refused in preview |
| L4 | `libcopy` of a two-pin symbol with lines and arcs from a library in git: the copy shows in the editor as the source does; save; `schlib_check.py` two-file mode: equal |
| L5 | `libcopy` of a multi-part symbol with one part on screen in the source: every part of the copy has its pins (upstream's trap 2) |
| L6 | `libcopy` twice in one batch: both names are the planned ones, not auto names (trap 3); save, close, reopen: both are in the file (trap 4) |
| L7 | `libcopy` refusals: name exists; source symbol missing; source modified; target not a member |
| L8 | `libdelete` of a symbol created in this session, library unsaved: gone from the editor; the other symbols unchanged; close without saving leaves the file as it was |
| L9 | `libdelete` refusals: a symbol that existed before the session; a session symbol after the library was saved; a session symbol placed on a sheet |
| L10 | `docclose` on an unmodified library: closed; `open_docs` no longer lists it; a restore from git then works without a prompt |
| L11 | `docclose` on a modified document: refused, no prompt appears, the document is still open and still modified |
| L12 | Every op without the tick: stopped |

## 9. Open questions

- Does `Replicate` keep the footprint links and parameters of the source
  symbol? Upstream reports parameters survive; the links are to be measured in
  L4.
- Does opening the source library of a copy add it to the project? If it does,
  the op removes nothing itself; it refuses and says so, since a later project
  save would write the membership into the project file.
- How the native side learns that a library was saved (for the `libdelete`
  list): by the modified flag going false between two calls; to be proven.
