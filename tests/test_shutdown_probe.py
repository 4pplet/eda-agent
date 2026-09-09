"""Static safety/ordering checks for the standalone probe; no Altium execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / "diagnostics/shutdown-probe"


class ShutdownProbeTests(unittest.TestCase):
    def setUp(self):
        self.code = re.sub(r"\{.*?\}", "", (ROOT / "ShutdownProbe.pas").read_text(encoding="utf-8"), flags=re.S)
        self.form = (ROOT / "ShutdownProbe.dfm").read_text(encoding="utf-8")

    def test_no_cad_host_or_mcp_calls(self):
        self.assertNotRegex(self.code, r"(?i)\b(Client|SchServer|PCBServer|GetWorkspace|RunProcess|StartMCPServer|ProcessSingleRequest|SaveAllDirty|DeleteFile)\b")

    def test_first_post_yield_operation_is_stop_flag(self):
        self.assertEqual(self.code.count("Application.ProcessMessages;"), 1)
        self.assertRegex(self.code, r"Application.ProcessMessages;\s*If Not ProbeRunning Then\s*Begin\s*ProbeRecord\('after_yield_stopped'\);\s*Break;")
        self.assertLess(self.code.index("after_yield_stopped"), self.code.index("Sleep(100)"))

    def test_stop_and_close_handlers_latch_before_logging(self):
        for name, event in (("ProbeFormCloseQuery", "form_close_query"), ("ProbeFormClose", "form_close"), ("ProbeFormDestroy", "form_destroy"), ("ProbeStopClick", "stop_button")):
            self.assertRegex(self.code, rf"Procedure {name}\([^;]*(?:;[^)]*)?\);\s*Begin\s*ProbeRunning := False;\s*ProbeRecord\('{event}'\);")

    def test_no_post_stop_ui_cleanup(self):
        tail = self.code[self.code.rindex("ProbeRunning := False;"):]
        self.assertRegex(tail, r"^ProbeRunning := False;\s*ProbeRecord\('run_end'\);\s*End;\s*$")
        stop = self.code.split("Procedure ProbeStopClick", 1)[1].split("Procedure RunShutdownProbe", 1)[0]
        self.assertNotIn("ShutdownProbeForm.", stop)

    def test_bounded_ticks_and_failure_record(self):
        self.assertIn("ProbeTickLimit = 1800;", self.code)
        self.assertIn("For Tick := 1 To ProbeTickLimit Do", self.code)
        self.assertRegex(self.code, r"ProbeRecord\('loop_exception'\);\s*ProbeRecord\('run_aborted'\);\s*Exit;")

    def test_logs_closed_after_each_write_and_never_reused(self):
        self.assertEqual(self.code.count("CloseFile(F);"), 2)
        self.assertRegex(self.code, r"(?s)If FileExists\(ProbeLogPath\) Then\s*Begin\s*ProbeLogPath := '';.*?Exit;\s*End;")
        self.assertIn("Append(F);", self.code)
        self.assertIn("ProbeLogFailed := True;", self.code)

    def test_dfm_events_exist_and_geometry_is_numeric(self):
        handlers = re.findall(r"^\s*On\w+ = (\w+)$", self.form, re.M)
        self.assertEqual(set(handlers), {"ProbeFormCloseQuery", "ProbeFormClose", "ProbeFormDestroy", "ProbeStopClick"})
        for name in handlers:
            self.assertIn(f"Procedure {name}(", self.code)
        for value in re.findall(r"^\s*(?:Left|Top|Width|Height|ClientHeight|ClientWidth) = (.+)$", self.form, re.M):
            self.assertRegex(value, r"^-?\d+$")

    def test_project_is_standalone_and_only_one_runnable_entry(self):
        project = (ROOT / "ShutdownProbe.PrjScr").read_text()
        self.assertEqual(re.findall(r"^DocumentPath=(.+)$", project, re.M), ["ShutdownProbe.pas", "ShutdownProbe.dfm"])
        self.assertIn("StartProcName=ShutdownProbe.pas>RunShutdownProbe", project)
        self.assertEqual(re.findall(r"Procedure (\w+);", self.code), ["RunShutdownProbe"])


if __name__ == "__main__":
    unittest.main()
