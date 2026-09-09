"""Source contracts only: these do not execute Altium's scripting engine."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1] / "scripts/altium"


class NativeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "SelectedProject.pas").read_text(encoding="utf-8-sig")
        self.form = (ROOT / "StatusForm.pas").read_text(encoding="utf-8-sig")
        self.dispatcher = (ROOT / "Dispatcher.pas").read_text(encoding="utf-8-sig")

    def test_selected_mode_intercepts_before_generic_dispatch(self):
        self.assertLess(self.dispatcher.index("ProcessSelectedCommand(Command, Params, RequestId)"),
                        self.dispatcher.index("Case Category Of"))
        self.assertRegex(self.dispatcher, r"(?s)If SELECTED_PROJECT_READ_ONLY Then.*?ProcessSelectedCommand.*?Exit;")

    def test_native_allowlist_and_no_api_selection_setter(self):
        self.assertIn("'READ_ONLY'", self.source)
        self.assertNotIn("'selection.set", self.source)
        self.assertNotIn("DM_FocusedProject", self.source)
        for unsafe in ("SaveAllDirty(", "DM_SetAsCurrentProject", "DM_OpenProject", "ProcessMessages;"):
            self.assertNotIn(unsafe, self.source)

    def test_tokens_checked_before_native_reads(self):
        guard = self.source.index("ExpectedGeneration <> IntToStr(SelectedGeneration)")
        self.assertLess(guard, self.source.index("P.DM_Compile;"))
        self.assertLess(guard, self.source.index("Proj_GetBOM(SafeParams"))
        self.assertIn("ExpectedSession <> SelectedSession", self.source)

    def test_compile_revalidated_and_does_not_repeat_inside_handler(self):
        compile_at = self.source.index("P.DM_Compile;")
        validation_at = self.source.index("CurrentSelectedProject(0) <> P", compile_at)
        ready_at = self.source.index("SelectedCompileReady := True;", compile_at)
        self.assertLess(compile_at, validation_at)
        self.assertLess(validation_at, ready_at)
        self.assertRegex(self.source, r"(?s)Finally\s+SelectedCompileReady := False;.*?SelectedBusy := False;")

    def test_project_closure_invalidates_reference_and_generation(self):
        self.assertIn("Candidate <> SelectedReference", self.source)
        self.assertIn("Inc(SelectedGeneration);", self.source)
        self.assertIn("InvalidateCompileCache(0);", self.source)
        self.assertIn("ClearSelectedProject(0);", self.source)

    def test_ui_has_explicit_apply_and_busy_guard(self):
        dfm = (ROOT / "StatusForm.dfm").read_text(encoding="utf-8-sig")
        self.assertIn("Style = csDropDownList", dfm)
        self.assertIn("Caption = 'Use this project'", dfm)
        self.assertIn("OnClick = UseProjectClick", dfm)
        apply_body = self.form.split("Procedure UseProjectClick", 1)[1].split("Function PadLeft", 1)[0]
        self.assertLess(apply_body.index("If SelectedBusy Or InFlightActive Then Exit;"),
                        apply_body.index("UseSelectedProject(cmb_Project.Text)"))

    def test_native_selector_controls_do_not_inherit_dark_panel_text(self):
        dfm = (ROOT / "StatusForm.dfm").read_text(encoding="utf-8-sig")
        combo = dfm.split("object cmb_Project: TComboBox", 1)[1].split("\n    end", 1)[0]
        button = dfm.split("object btn_UseProject: TButton", 1)[1].split("\n    end", 1)[0]
        self.assertIn("Color = clWindow\n", combo)
        self.assertIn("Font.Color = clWindowText\n", combo)
        self.assertIn("ParentFont = False", combo)
        self.assertIn("Font.Color = clBtnText\n", button)
        self.assertIn("ParentFont = False", button)

    def test_header_uses_scaled_control_bounds_not_fixed_pixels(self):
        self.assertRegex(self.form, r"pnl_Header.Height := lbl_Permissions.Top \+ lbl_Permissions.Height\s*\+ \(lbl_Permissions.Top - lbl_SelectedProject.Top - lbl_SelectedProject.Height\);")
        self.assertNotRegex(self.form, r"pnl_Header.Height := \d+;")
        # Arithmetic example only, not a native DPI/rendering test.
        for scale in (1, 1.25, 1.5, 2):
            last_top, last_height, previous_top, previous_height = [round(v * scale) for v in (166, 36, 110, 50)]
            height = last_top + last_height + (last_top - previous_top - previous_height)
            self.assertGreater(height, last_top + last_height)

    def test_permissions_status_is_not_a_write_control(self):
        dfm = (ROOT / "StatusForm.dfm").read_text(encoding="utf-8-sig")
        self.assertIn("object lbl_Permissions: TLabel", dfm)
        self.assertIn("lbl_Permissions.Visible := SELECTED_PROJECT_READ_ONLY", self.form)
        self.assertIn("Unavailable: edits, saves, output jobs", self.form)
        self.assertIn("Editing permissions are not implemented", self.form)
        self.assertNotIn("OnClick = EnableWrites", dfm)

    def test_selection_confirmation_uses_committed_identity_not_dropdown_draft(self):
        body = self.form.split("Procedure RefreshSelectedLabel", 1)[1].split("Procedure RefreshProjectChoices", 1)[0]
        self.assertIn("CurrentSelectedProject(0)", body)
        self.assertIn("'Selected: ' + ExtractFileName(SelectedPath)", body)
        self.assertIn("lbl_SelectedProject.Hint := SelectedPath", body)
        self.assertIn("StatusForm.Caption := ExtractFileName(SelectedPath)", body)
        self.assertIn("No project selected - EDA (READ ONLY)", body)
        self.assertNotIn("cmb_Project", body)

    def test_dirty_state_blocks_compile_and_is_rechecked_after_compile(self):
        compile_at = self.source.index("P.DM_Compile;")
        before, after = self.source[:compile_at], self.source[compile_at:]
        self.assertIn("ExtractJsonValue(Freshness, 'dirty_doc_count') <> '0'", before)
        self.assertIn("SelectedFreshnessJSON(P)", after)
        self.assertIn("ExtractJsonValue(Freshness, 'dirty_doc_count') <> '0'", after)

    def test_delegated_parameters_are_rebuilt_and_no_forced_save(self):
        self.assertIn("SafeParams := '{\"project_path\":\"'", self.source)
        self.assertIn('with_pin_nets', self.source)
        for handler in ("Proj_GetBOM", "Proj_GetNets", "Proj_GetComponentInfo"):
            self.assertIn(handler + "(SafeParams, RequestId)", self.source)
            self.assertNotIn(handler + "(Params, RequestId)", self.source)

    def test_unit_is_packaged(self):
        self.assertIn("DocumentPath=SelectedProject.pas", (ROOT / "Altium_API.PrjScr").read_text())
        self.assertIn("'SelectedProject.pas'", (ROOT / "build.py").read_text())


if __name__ == "__main__":
    unittest.main()
