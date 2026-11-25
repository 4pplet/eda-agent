"""lint.py flags a field write through a by-value record property.

`Pin.Location.X := X` compiles, runs and reports success, and the pin stays at
(0, 0): Location is returned by value, so the assignment changes a temporary.
Found on the first real library write (W27, 2026-11-25), where 72 of 72 items
read "written" and every pin sat at the symbol origin.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts" / "altium"))
import lint  # noqa: E402


def _hits(line: str) -> bool:
    return bool(lint.RULE_RECORD_FIELD_WRITE.pattern.search(lint.strip_comments_and_strings(line)))


def test_direct_field_write_is_flagged():
    assert _hits("    Pin.Location.X := MilsToCoord(X);")
    assert _hits("    Rect.Corner.Y:=Y2;")


def test_read_modify_write_is_not_flagged():
    for line in ("    Loc := Pin.Location;", "    Loc.X := X;", "    Pin.Location := Loc;",
                 "    If Pin.Location.X = X Then Exit;", "    PinX := CoordToMils(Pin.Location.X);",
                 "    { direct `Line.Location.X := value` writes to a copy }"):
        assert not _hits(line), line


def test_rule_is_registered_as_an_error():
    assert lint.RULE_RECORD_FIELD_WRITE in lint.LINE_RULES
    assert lint.RULE_RECORD_FIELD_WRITE.severity == "error"


def test_live_sources_are_clean():
    for name in lint.PAS_FILES:
        path = Path(lint.__file__).resolve().parent / name
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            assert not _hits(line), f"{name}:{number}: {line.strip()}"
