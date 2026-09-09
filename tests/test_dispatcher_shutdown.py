"""Source regression checks, not execution in Altium's native scripting VM.

The manual lifecycle matrix in docs/SHUTDOWN.md is still required. These checks
pin the ordering that previously resumed Sleep immediately after a UI yield.
Run with unittest (no Altium, IPC or third-party packages needed).
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def source(name):
    text = (ROOT / "scripts/altium" / name).read_text(encoding="utf-8-sig")
    return re.sub(r"\{.*?\}|//[^\n]*", "", text, flags=re.S)


def routine(text, name):
    match = re.search(r"(?:Procedure|Function) " + name + r"\b.*?(?=\n(?:Procedure|Function) |\Z)", text, re.S)
    if not match:
        raise AssertionError(f"Missing routine: {name}")
    return match.group(0)


class DispatcherShutdownTests(unittest.TestCase):
    def setUp(self):
        self.dispatcher = source("Dispatcher.pas")
        self.start = routine(self.dispatcher, "StartMCPServer")

    def test_only_polling_message_pump_is_guarded_before_and_after(self):
        self.assertEqual(self.dispatcher.count("Application.ProcessMessages;"), 1)
        body = routine(self.dispatcher, "MCPYield")
        self.assertRegex(body, r"If Not MCPContinuePolling\(StopPath\) Then Exit;\s*Application.ProcessMessages;\s*Result := MCPContinuePolling\(StopPath\);")

    def test_paused_idle_and_active_paths_all_break_on_failed_yield(self):
        self.assertEqual(self.start.count("If Not MCPYield(StopPath) Then Break;"), 3)
        self.assertNotIn("Application.ProcessMessages", self.start)
        self.assertRegex(self.start, r"If Not MCPYield\(StopPath\) Then Break;\s*Sleep\(PollIntervalIdleMs\);")
        self.assertRegex(self.start, r"If Not MCPYield\(StopPath\) Then Break;\s*Sleep\(CurrentSleep Div YieldIterations\);")
        self.assertRegex(self.start, r"If Not MCPYield\(StopPath\) Then Break;\s*ActiveTickCount := 0;\s*End;\s*Sleep\(CurrentSleep\);")

    def test_check_before_dispatch_and_after_handler_before_status(self):
        self.assertRegex(self.start, r"While Running Do\s*Begin\s*If Not MCPContinuePolling\(StopPath\) Then Break;")
        self.assertRegex(self.start, r"HadRequest := ProcessSingleRequest\(0\);\s*If Not MCPContinuePolling\(StopPath\) Then Break;")

    def test_host_loss_latches_and_stops(self):
        body = routine(self.dispatcher, "MCPHostAvailable")
        self.assertIn("If MCPHostClosing Then Exit;", body)
        self.assertRegex(body, r"If Client.IsQuitting Then\s*Begin\s*MCPHostClosing := True;")
        self.assertRegex(body, r"Except\s*MCPHostClosing := True;")
        self.assertRegex(body, r"If MCPHostClosing Then\s*Begin\s*Running := False;\s*Exit;")

    def test_stop_is_latched_before_sentinel_deletion(self):
        body = routine(self.dispatcher, "MCPContinuePolling")
        self.assertRegex(body, r"If FileExists\(StopPath\) Then\s*Begin\s*Running := False;\s*MCPStopReason := 'stop-file';\s*DeleteFile\(StopPath\);\s*Exit;")

    def test_no_ui_pump_or_cad_saves_in_cleanup(self):
        body = routine(self.dispatcher, "CleanupMCPServer")
        self.assertNotIn("Application.", body)
        self.assertNotIn("Save", body)
        self.assertNotIn("CleanupOrphanResponses", body)
        self.assertRegex(self.start, r"If Not LoopFailed Then\s*Begin\s*If MCPHostAvailable\(0\) Then HideStatusForm\(0\);")

    def test_error_not_logged_as_normal_session_end(self):
        self.assertIn("MCPStopReason := 'loop-exception';", self.start)
        self.assertIn("MCPStopReason := 'cleanup-exception';", self.start)
        self.assertRegex(self.start, r"If LoopFailed Then\s*AppendLog\([^\n]*_session_aborted[^\n]*\)\s*Else\s*AppendLog\([^\n]*_session_end")
        self.assertLess(self.start.rindex("CleanupMCPServer(0);"), self.start.index("_session_end"))

    def test_restart_resets_shutdown_latch(self):
        self.assertRegex(self.start, r"If Running Then Exit;\s*MCPHostClosing := False;\s*MCPStopReason := 'stop-requested';\s*LoopFailed := False;")
        self.assertIn("MCPStopReason := 'idle-timeout';", self.start)

    def test_native_detach_and_close_remain_no_save(self):
        for name in ("StatusFormClose", "btn_DetachClick"):
            body = routine(source("StatusForm.pas"), name)
            self.assertIn("Running := False;", body)
            self.assertNotIn("Save", body)
        self.assertRegex(source("Application.pas"), r"'stop_server':\s*Begin\s*SaveAllDirty\(0\);")

    def test_local_script_revision_changed(self):
        self.assertIn("SCRIPT_VERSION = '2026.09.08.2';", source("Main.pas"))


if __name__ == "__main__":
    unittest.main()
