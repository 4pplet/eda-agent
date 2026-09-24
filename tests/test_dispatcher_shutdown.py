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
        self.tick = routine(self.dispatcher, "MCPTimerTick")
        self.finalise = routine(self.dispatcher, "FinaliseMCPServer")

    def test_the_dispatcher_never_pumps_the_host_message_queue(self):
        """The Ctrl+Z P0 in one assertion.

        A script that holds Altium's main thread defers keyboard-to-command
        dispatch, so Ctrl+Z does nothing while the bridge is attached and
        the presses replay as an undo burst on detach. Timer dispatch fixes
        that by never holding the thread: each tick returns and Altium pumps
        its own loop. Calling ProcessMessages from in here would hand the
        thread back mid-tick and reinstate exactly the deferral being fixed,
        so the count is zero rather than "guarded". MCPYield, which used to
        wrap the one call, is deleted for the same reason: an unused helper
        is an invitation.
        """
        self.assertEqual(self.dispatcher.count("Application.ProcessMessages"), 0)
        self.assertNotIn("MCPYield", self.dispatcher)

    def test_a_tick_never_sleeps(self):
        """Pacing is the timer interval now, not a blocked thread.

        Sleep() inside the handler would hold the main thread for its
        duration -- the same failure as ProcessMessages, reached from the
        other side. The interval write is what replaces it.
        """
        self.assertNotIn("Sleep(", self.tick)
        self.assertNotIn("Sleep(", self.start)
        self.assertIn("SetMCPTimerInterval(MCPCurrentInterval);", self.tick)

    def test_check_before_dispatch_and_after_handler_before_status(self):
        """Both stop checks survive the move from loop body to tick body."""
        self.assertRegex(self.tick, r"If Not MCPContinuePolling\(MCPStopPath\) Then\s*Begin\s*FinaliseMCPServer\(0\);\s*Exit;")
        self.assertRegex(self.tick, r"HadRequest := ProcessSingleRequest\(0\);\s*If Not MCPContinuePolling\(MCPStopPath\) Then")

    def test_a_tick_cannot_re_enter_itself(self):
        """A handler that outruns its interval must drop the coincident
        tick, not queue it. Queueing lets a slow request build a backlog
        that then stampedes -- the shape of the bug being fixed."""
        self.assertRegex(self.tick, r"If MCPInTick Then Exit;\s*MCPInTick := True;")
        self.assertRegex(self.tick, r"Finally\s*MCPInTick := False;\s*End;")

    def test_the_first_tick_is_logged(self):
        """A DFM handler that fails to bind is SILENT: the form is up, the
        session logged _session_start, and nothing ever runs. This one log
        line is what separates "armed but never fired" from "firing and
        something else is wrong"; it is the only evidence the operator has.
        """
        self.assertIn("_tick_first", self.tick)

    def test_the_timer_handler_lives_where_the_dfm_can_bind_it(self):
        """tmr_MCP.OnTimer resolves only against StatusForm.pas, and the
        work it needs is in Dispatcher.pas. The shim is the join. If the
        handler ever moves back here it binds to nothing, silently."""
        form = source("StatusForm.pas")
        self.assertRegex(form, r"Procedure tmr_MCPTimer\(Sender : TObject\);\s*Begin\s*MCPTimerTick\(0\);\s*End;")
        self.assertNotIn("Procedure tmr_MCPTimer", self.dispatcher)
        for helper in ("ArmMCPTimer", "DisableMCPTimer", "SetMCPTimerInterval"):
            self.assertIn(f"{helper}", form)
        self.assertIn("tmr_MCP", (ROOT / "scripts/altium/StatusForm.dfm").read_text(encoding="utf-8", errors="replace"))

    def test_arming_the_timer_is_verified_not_assumed(self):
        """Read Enabled back. Without it a form missing tmr_MCP leaves a
        session that logged _session_start, set Running := True, and will
        never serve a request: a bridge that looks up and is dead."""
        arm = routine(source("StatusForm.pas"), "ArmMCPTimer")
        self.assertIn("Result := tmr_MCP.Enabled;", arm)
        self.assertRegex(self.start, r"If Not ArmMCPTimer\(MCPCurrentInterval\) Then\s*Begin\s*MCPLoopFailed := True;\s*MCPStopReason := 'timer-arm-failed';")

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
        self.assertRegex(self.finalise, r"If Not MCPLoopFailed Then\s*Begin\s*If MCPHostAvailable\(0\) Then HideStatusForm\(0\);")

    def test_the_timer_is_disabled_before_anything_else_in_teardown(self):
        """A live timer on a form whose controls are being taken away is
        the most likely crash in this design, so the disable comes first --
        before HideStatusForm, before cleanup, and before any tick can
        re-enter finalise."""
        self.assertRegex(self.finalise, r"Begin\s*DisableMCPTimer\(0\);\s*Running := False;")

    def test_error_not_logged_as_normal_session_end(self):
        self.assertIn("MCPStopReason := 'loop-exception';", self.tick)
        self.assertIn("MCPStopReason := 'cleanup-exception';", self.finalise)
        self.assertRegex(self.finalise, r"If MCPLoopFailed Then\s*AppendLog\([^\n]*_session_aborted[^\n]*\)\s*Else\s*AppendLog\([^\n]*_session_end")
        self.assertLess(self.finalise.rindex("CleanupMCPServer(0);"), self.finalise.index("_session_end"))

    def test_a_repeating_tick_fault_ends_the_session(self):
        """Per-tick Try/Except replaced one Try around the whole loop, so a
        fault no longer ends the session by itself. Without a streak cap a
        repeating fault would log forever at the poll interval."""
        self.assertIn("MCPFaultStreak := 0;", self.tick)
        self.assertRegex(self.tick, r"If MCPFaultStreak >= MCP_MAX_FAULT_STREAK Then")

    def test_restart_resets_shutdown_latch(self):
        self.assertRegex(self.start, r"If Running Then Exit;\s*MCPHostClosing := False;\s*MCPStopReason := 'stop-requested';\s*MCPLoopFailed := False;")
        self.assertIn("MCPStopReason := 'idle-timeout';", self.tick)

    def test_native_detach_and_close_remain_no_save(self):
        for name in ("StatusFormClose", "btn_DetachClick"):
            body = routine(source("StatusForm.pas"), name)
            self.assertIn("Running := False;", body)
            self.assertNotIn("Save", body)
        self.assertRegex(source("Application.pas"), r"'stop_server':\s*Begin\s*SaveAllDirty\(0\);")

    def test_local_script_revision_changed(self):
        """Pinned on purpose, and meant to fail when the .pas files change.

        DelphiScript caches compiled units until the script project is
        reopened or Altium restarts, so SCRIPT_VERSION is the only thing
        that can tell a stale compile from a fresh one -- Python compares
        it against what ping returns and refuses a mismatch. Editing
        Pascal without bumping it produces a bridge that silently runs the
        old code, which reads as "my fix did nothing".

        So this literal is a tripwire: when it fails, bump SCRIPT_VERSION
        in Main.pas AND the pin in the client (PLT-hw
        tools/eda-agent/project_server.py), then update the literal here.
        """
        self.assertIn("SCRIPT_VERSION = '2026.09.24.2';", source("Main.pas"))


if __name__ == "__main__":
    unittest.main()
