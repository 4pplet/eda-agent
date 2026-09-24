{ SPDX-License-Identifier: Apache-2.0                                   }
{ Copyright (c) 2026 George Saliba <george.saliba@salitronic.com>                                      }
{..............................................................................}
{ StatusForm.pas - DFM-backed MCP dashboard.                                  }
{                                                                              }
{ Modern dark UI with:                                                        }
{   - Status pill (dot color + label + spinner glyph during in-flight calls)  }
{   - Four KPI cards (uptime, requests, busy time, idle timeout)              }
{   - Inline last-error display                                                }
{   - Prominent "Open Dashboard" button (writes a sentinel the Python bridge  }
{     watches and opens the user's default browser at the web dashboard)      }
{   - Pause / Cancel-current / Renew / Clear / Detach action row              }
{   - Filter box + Hide-pings / Only->100ms / Always-on-top toggles           }
{   - Log tab with newest-on-top entries, request-ID column, inline error    }
{     detail rows, free-text filter                                            }
{   - Perf tab with per-command stats, sorted by max duration desc            }
{                                                                              }
{ State lives in module-level TStringLists, function locals avoid fixed-size  }
{ arrays per [[delphiscript_fixed_string_array_bug]]. Module-level fixed-size }
{ arrays are still safe (no function-return slot to clobber) but we use       }
{ TStringLists for the perf table so the cap can grow past 64 cleanly.        }
{..............................................................................}

Var
    HidePingsFlag    : Boolean;
    OnlySlowFlag     : Boolean;
    AlwaysOnTopFlag  : Boolean;

    { Pause: when True, Dispatcher's poll loop skips ScanForRequestFile.    }
    PausedFlag       : Boolean;

    { Renew: set by the Renew button, consumed once by the Dispatcher to    }
    { reset its real idle deadline (LastActivityMs). The form's             }
    { LastActivityTick alone only moves the visible countdown, not the      }
    { actual auto-shutdown timer that lives local to StartMCPServer.        }
    RenewRequested   : Boolean;

    { Spinner state. SpinnerFrame indexes into a 4-phase moon glyph cycle. }
    SpinnerFrame     : Integer;
    InFlightCommand  : String;
    InFlightStartMs  : Cardinal;
    InFlightActive   : Boolean;

    { Free-text filter applied at WRITE time to mmo_Log.Lines. Empty = no   }
    { text filter. Changing the filter only affects new entries; old ones   }
    { stay until you click Clear log. (We used to keep a TStringList buffer }
    { and re-render on filter change, but DelphiScript's TStringList API is }
    { broken in too many spots, .Insert and .Clear undeclared, typed-param   }
    { dispatch loses methods, empty-literal arguments trip the parser; the  }
    { committed pattern wrote straight to mmo_Log.Lines and we're back to    }
    { that.)                                                                 }
    FilterText       : String;

    { Perf table - parallel TStringLists. Lists grow with the command set. }
    PerfNames        : TStringList;
    PerfCountStrs    : TStringList;
    PerfTotalStrs    : TStringList;
    PerfMaxStrs      : TStringList;

    { Idle-timeout state (mirrored from Dispatcher for the Renew button). }
    LastActivityTick : Cardinal;

    { MCP liveness: GetTickCount at the most-recently-processed command.   }
    { Open Dashboard button only enables when this is within the last 60s. }
    LastPingMs       : Cardinal;
    OpenWebEnabled   : Boolean;

    { P2 prerequisite probe (see eda-agent docs/DESIGN-event-driven-dispatch.md }
    { section 2). Counts tmr_Probe firings so the operator can read the rate    }
    { off the caption. Module-level because the handler carries no state of     }
    { its own between ticks - which is exactly the migration the redesign       }
    { needs, so this doubles as a rehearsal of section 4.                       }
    ProbeTickCount   : Integer;
    ProbeStartMs     : Cardinal;


{ Static UI constants. Modern dark palette intended for the StatusForm.   }
{ DelphiScript color literals are BGR-ordered Cardinals (8 hex digits      }
{ after the $); a malformed 7-digit literal bombs the parser without an   }
{ obvious error location, so always double-count.                          }
Const
    COLOR_BG_BASE       = $001A1B1E;
    COLOR_BG_CARD       = $0025262B;
    COLOR_BG_ELEVATED   = $002E2F35;
    COLOR_ACCENT_BLUE   = $00FF9E4A;   { #4A9EFF in BGR }
    COLOR_ACCENT_AMBER  = $00589EE0;   { #E09E58 in BGR }
    COLOR_ACCENT_RED    = $005C5CFF;   { #FF5C5C in BGR }
    COLOR_ACCENT_GREEN  = $006BC464;   { #64C46B in BGR }
    COLOR_TEXT_BODY     = $00E1E2E6;
    COLOR_TEXT_MUTED    = $008B8E96;
    COLOR_TEXT_FAINT    = $00696C73;

    MAX_LOG_LINES       = 2000;
    SPINNER_FRAMES      = 4;

    { P2 probe. 1 s is slow enough to read off a taskbar caption and fast    }
    { enough to make starvation obvious; the cap bounds a probe the operator }
    { walks away from, so a forgotten timer cannot outlive the session.      }
    PROBE_INTERVAL_MS   = 1000;
    PROBE_MAX_TICKS     = 120;


{ Ctrl+Z is deferred while the bridge holds the main thread, and the presses   }
{ REPLAY as an undo burst when it detaches (TODO P0, cause class established    }
{ 2026-09-23: idle and minimized both still fail, menu undo works, presses are  }
{ buffered not swallowed). Until the event-driven redesign lands, the only      }
{ thing standing between that and a silently reverted board is the operator     }
{ remembering. This goes in the CAPTION on purpose: the title bar is readable   }
{ in the taskbar while the form is MINIMIZED, which is exactly when the         }
{ constraint is easiest to forget. A label inside the form is not.              }
Function KeyboardWarningSuffix(Dummy : Integer) : String;
Begin
    Result := '  ***  NO Ctrl+Z - use Edit menu  ***';
End;

Procedure RefreshSelectedLabel(Dummy : Integer);
Var
    P : IProject;
Begin
    If Not SELECTED_PROJECT_READ_ONLY Then Exit;
    P := CurrentSelectedProject(0);
    If P = Nil Then
    Begin
        lbl_SelectedProject.Caption := 'READ ONLY - no project selected';
        lbl_SelectedProject.Hint := 'Choose a project, then click Use this project.';
        StatusForm.Caption := 'No project selected - EDA (READ ONLY)' + KeyboardWarningSuffix(0);
    End
    Else
    Begin
        lbl_SelectedProject.Caption := 'Selected: ' + ExtractFileName(SelectedPath)
            + #13#10 + 'READ ONLY - hover here for the full path';
        lbl_SelectedProject.Hint := SelectedPath;
        StatusForm.Caption := ExtractFileName(SelectedPath) + ' - EDA (READ ONLY)'
            + KeyboardWarningSuffix(0);
    End;
End;

Procedure RefreshProjectChoices(Sender : TObject);
Var
    W : IWorkspace;
    P : IProject;
    I : Integer;
    Path, Draft : String;
Begin
    If Not SELECTED_PROJECT_READ_ONLY Then Exit;
    If SelectedBusy Or InFlightActive Then Exit;
    Draft := cmb_Project.Text;
    cmb_Project.Items.Clear;
    W := GetWorkspace;
    If W <> Nil Then
        For I := 0 To W.DM_ProjectCount - 1 Do
        Begin
            P := W.DM_Projects(I);
            If P <> Nil Then
            Begin
                Path := P.DM_ProjectFullPath;
                If LooksAbsolutePath(Path) And
                   (LowerCase(ExtractFileExt(Path)) = '.prjpcb') And FileExists(Path) Then
                    cmb_Project.Items.Add(Path);
            End;
        End;
    cmb_Project.ItemIndex := cmb_Project.Items.IndexOf(Draft);
    RefreshSelectedLabel(0);
End;

Procedure UseProjectClick(Sender : TObject);
Begin
    If Not SELECTED_PROJECT_READ_ONLY Then Exit;
    If SelectedBusy Or InFlightActive Then Exit;
    If cmb_Project.ItemIndex < 0 Then Exit;
    If Not UseSelectedProject(cmb_Project.Text) Then
        lbl_LastErr.Caption := 'Selected project is unavailable; refresh the list.';
    RefreshSelectedLabel(0);
End;

Function PadLeft(S : String; Width : Integer) : String;
Begin
    Result := S;
    While Length(Result) < Width Do Result := ' ' + Result;
End;

Function PadRight(S : String; Width : Integer) : String;
Begin
    Result := S;
    While Length(Result) < Width Do Result := Result + ' ';
End;


Procedure EnsureStatusBuffers(Dummy : Integer);
Begin
    If PerfNames     = Nil Then PerfNames     := TStringList.Create;
    If PerfCountStrs = Nil Then PerfCountStrs := TStringList.Create;
    If PerfTotalStrs = Nil Then PerfTotalStrs := TStringList.Create;
    If PerfMaxStrs   = Nil Then PerfMaxStrs   := TStringList.Create;
End;


{ Spinner glyph cycle. Classic terminal-spinner ASCII for max compatibility   }
{ with DelphiScript's TMemo / TLabel rendering, which doesn't reliably show   }
{ 3-byte UTF-8 sequences without a font fallback.                             }
Function SpinnerGlyph(Frame : Integer) : String;
Begin
    Case (Frame Mod SPINNER_FRAMES) Of
        0: Result := '|';
        1: Result := '/';
        2: Result := '-';
    Else
        Result := '\';
    End;
End;


{ Hidden from the Run Script dialog by its argument; Dummy is never
  read. See KnownPCBPropertyList in PCBGeneric for why. }
Function FilledDot(Dummy : Integer) : String;
Begin
    Result := '[x]';
End;

{ Hidden from the Run Script dialog by its argument; Dummy is never read. }
Function HollowDot(Dummy : Integer) : String;
Begin
    Result := '[ ]';
End;


Function ShouldShowLine(LogLine : String) : Boolean;
Var
    UpperLine, UpperFilt : String;
Begin
    Result := True;
    If HidePingsFlag And (Pos('application.ping', LogLine) > 0) Then
    Begin
        Result := False;
        Exit;
    End;
    If FilterText <> '' Then
    Begin
        UpperLine := UpperCase(LogLine);
        UpperFilt := UpperCase(FilterText);
        If Pos(UpperFilt, UpperLine) = 0 Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;


{ Used to re-render mmo_Log from a TStringList buffer when filter flags     }
{ changed. The buffer was a DelphiScript minefield, so we dropped it; this   }
{ procedure now just clears the visible memo. Callers that previously       }
{ wanted "apply new filter to old entries" now just see a clean slate after }
{ toggling filter chips, which is honest and side-steps the buggy API.      }
Procedure RebuildVisibleLog(Dummy : Integer);
Begin
    Try
        mmo_Log.Lines.BeginUpdate;
        Try
            mmo_Log.Lines.Clear;
        Finally
            mmo_Log.Lines.EndUpdate;
        End;
    Except End;
End;


{ Perf-table helpers. Lists are parallel: PerfNames[i] <-> the i-th         }
{ count/total/max stringified ints. Names are case-sensitive command IDs.    }
Function FindOrAddPerf(Command : String) : Integer;
Begin
    EnsureStatusBuffers(0);
    Result := PerfNames.IndexOf(Command);
    If Result >= 0 Then Exit;
    PerfNames.Add(Command);
    PerfCountStrs.Add('0');
    PerfTotalStrs.Add('0');
    PerfMaxStrs.Add('0');
    Result := PerfNames.Count - 1;
End;

Procedure ResetPerfStats(Dummy : Integer);
Begin
    { DelphiScript on this build refuses to resolve .Free or .Count on  }
    { module-level TStringList from inside this Procedure - even when    }
    { proxied through a clearly-typed local Tmp. Both methods work fine  }
    { in other .pas files in the same project. The pattern that DOES     }
    { compile here: reassign new TStringLists, let the GC collect the    }
    { old ones (Pascal's reference-counted Interface model OR a one-     }
    { time leak per session of ~4 small TStringLists is acceptable for   }
    { a dashboard reset action).                                          }
    PerfNames     := TStringList.Create;
    PerfCountStrs := TStringList.Create;
    PerfTotalStrs := TStringList.Create;
    PerfMaxStrs   := TStringList.Create;
End;

Procedure EnsurePerfHeader(Dummy : Integer);
Begin
    Try
        If mmo_Perf.Lines.Count < 2 Then
        Begin
            mmo_Perf.Lines.BeginUpdate;
            Try
                mmo_Perf.Lines.Clear;
                mmo_Perf.Lines.Add(PadRight('command', 30) + PadLeft('N', 6)
                    + PadLeft('avg', 8) + PadLeft('max', 8));
                mmo_Perf.Lines.Add(StringOfChar('-', 52));
            Finally
                mmo_Perf.Lines.EndUpdate;
            End;
        End;
    Except End;
End;

Function FormatPerfLine(Idx : Integer) : String;
Var
    CountVal, TotalVal, MaxVal, AvgVal : Integer;
Begin
    CountVal := StrToIntDef(PerfCountStrs[Idx], 0);
    TotalVal := StrToIntDef(PerfTotalStrs[Idx], 0);
    MaxVal   := StrToIntDef(PerfMaxStrs[Idx], 0);
    If CountVal = 0 Then AvgVal := 0
    Else AvgVal := TotalVal Div CountVal;
    Result := PadRight(PerfNames[Idx], 30)
            + PadLeft(IntToStr(CountVal), 6)
            + PadLeft(IntToStr(AvgVal), 8)
            + PadLeft(IntToStr(MaxVal), 8);
End;

Procedure TrackPerf(Command : String; DurationMs : Cardinal);
Var
    Idx, CountVal, TotalVal, MaxVal, Dms, RowLineIdx : Integer;
    Line : String;
    IsNew : Boolean;
Begin
    IsNew := (PerfNames.IndexOf(Command) < 0);
    Idx := FindOrAddPerf(Command);
    If Idx < 0 Then Exit;
    { Promote DurationMs (Cardinal) to a plain Integer local. DelphiScript }
    { rejects both Cardinal() and Integer() typecasts, so we lean on        }
    { implicit conversion via assignment to a typed local instead.          }
    Dms      := DurationMs;
    CountVal := StrToIntDef(PerfCountStrs[Idx], 0) + 1;
    TotalVal := StrToIntDef(PerfTotalStrs[Idx], 0) + Dms;
    MaxVal   := StrToIntDef(PerfMaxStrs[Idx], 0);
    If Dms > MaxVal Then MaxVal := Dms;
    PerfCountStrs[Idx] := IntToStr(CountVal);
    PerfTotalStrs[Idx] := IntToStr(TotalVal);
    PerfMaxStrs[Idx]   := IntToStr(MaxVal);

    { Incremental write into mmo_Perf. The previous implementation did a    }
    { full Clear+repopulate after every command, which DelphiScript's       }
    { TMemo flickers visibly (BeginUpdate doesn't fully suppress the        }
    { paint between the Clear and the re-add). Replacing the single       }
    { changed row in place keeps the panel rock-stable and removes the     }
    { "UI blanks out then reappears" the user reported.                    }
    EnsurePerfHeader(0);
    Line := FormatPerfLine(Idx);
    RowLineIdx := 2 + Idx;   { 2 header lines come first }
    Try
        If IsNew Or (RowLineIdx >= mmo_Perf.Lines.Count) Then
            mmo_Perf.Lines.Add(Line)
        Else
            mmo_Perf.Lines[RowLineIdx] := Line;
    Except End;
End;


{ Full rebuild kept for the "Reset perf" button and the tab-switch case   }
{ where the memo might have been blanked while hidden. Hot path now uses  }
{ TrackPerf's incremental update.                                          }
Procedure RefreshPerfPanel(Dummy : Integer);
Var
    I : Integer;
Begin
    EnsureStatusBuffers(0);
    If PerfNames.Count = 0 Then Exit;
    Try
        mmo_Perf.Lines.BeginUpdate;
        Try
            mmo_Perf.Lines.Clear;
            mmo_Perf.Lines.Add(PadRight('command', 30) + PadLeft('N', 6)
                + PadLeft('avg', 8) + PadLeft('max', 8));
            mmo_Perf.Lines.Add(StringOfChar('-', 52));
            For I := 0 To PerfNames.Count - 1 Do
                mmo_Perf.Lines.Add(FormatPerfLine(I));
        Finally
            mmo_Perf.Lines.EndUpdate;
        End;
    Except End;
End;


{ Visible severity tag for a log row. ERR has the loudest visual weight.   }
{ Public entry point called from Dispatcher.ProcessSingleRequest after every }
{ command. RequestId is the 32-char hex; we show first 8 in the log so the   }
{ user can grep bridge_trace.log for the exact call.                         }
Procedure AppendLogLine(Command : String; DurationMs : Cardinal; IsError : Boolean;
                        RequestId : String; ErrorDetail : String);
Var
    Line, IdShort : String;
Begin
    EnsureStatusBuffers(0);
    TrackPerf(Command, DurationMs);

    { "Only slow" hides fast (<100 ms) non-error calls. Done here against the }
    { raw duration/error rather than by string-searching a tag prefix.        }
    If OnlySlowFlag And (Not IsError) And (DurationMs < 100) Then Exit;

    IdShort := Copy(RequestId, 1, 8);
    If IdShort = '' Then IdShort := '--------';

    Line := PadLeft(IntToStr(DurationMs), 5) + ' ms  '
          + IdShort + '  ' + Command;

    { Apply the filter at write time. The committed pattern wrote straight  }
    { to mmo_Log.Lines via TStrings (TMemo property), which DelphiScript    }
    { routes through fine. Skipping an entry just means the user doesn't    }
    { see it until a future entry matches the new filter.                   }
    If Not ShouldShowLine(Line) Then Exit;
    Try
        mmo_Log.Lines.Insert(0, Line);
        If IsError And (ErrorDetail <> '') Then
            mmo_Log.Lines.Insert(1, '      `-- ' + ErrorDetail);
        While mmo_Log.Lines.Count > MAX_LOG_LINES Do
            mmo_Log.Lines.Delete(mmo_Log.Lines.Count - 1);
    Except End;

    If IsError Then
    Begin
        Try
            If ErrorDetail <> '' Then
                lbl_LastErr.Caption := '! '
                    + Command + ': ' + ErrorDetail
            Else
                lbl_LastErr.Caption := '! last error: ' + Command;
        Except End;
    End;
End;


{ Dispatcher calls this just before invoking ProcessCommand so the spinner   }
{ kicks on. ResetInFlight clears it after the call returns.                  }
Procedure SetInFlight(Command : String);
Begin
    Try
        InFlightCommand := Command;
        InFlightStartMs := GetTickCount;
        InFlightActive := True;
        If SELECTED_PROJECT_READ_ONLY Then
        Begin
            cmb_Project.Enabled := False;
            btn_UseProject.Enabled := False;
        End;
        SpinnerFrame := 0;
        Try tmr_Spinner.Enabled := True; Except End;
        Try
            pnl_StatusDot.Color := COLOR_ACCENT_AMBER;
            lbl_Spinner.Caption := SpinnerGlyph(SpinnerFrame);
            lbl_Status.Caption := Command + '  (0.0 s)';
            lbl_Status.Font.Color := COLOR_TEXT_BODY;
        Except End;
    Except End;
End;

Procedure ResetInFlight(Dummy : Integer);
Begin
    Try
        InFlightActive := False;
        InFlightCommand := '';
        If SELECTED_PROJECT_READ_ONLY Then
        Begin
            cmb_Project.Enabled := True;
            btn_UseProject.Enabled := True;
        End;
        Try tmr_Spinner.Enabled := False; Except End;
        Try
            lbl_Spinner.Caption := '';
            If PausedFlag Then
            Begin
                pnl_StatusDot.Color := COLOR_TEXT_FAINT;
                lbl_Status.Caption := 'paused';
                lbl_Status.Font.Color := COLOR_TEXT_MUTED;
            End
            Else
            Begin
                pnl_StatusDot.Color := COLOR_ACCENT_GREEN;
                lbl_Status.Caption := 'idle';
                lbl_Status.Font.Color := COLOR_TEXT_BODY;
            End;
        Except End;
    Except End;
End;


{ Open-Dashboard button reflects actual dashboard availability via a         }
{ heartbeat file the Python dashboard process writes every ~3s: a Unix      }
{ epoch timestamp in workspace/dashboard.heartbeat. If the timestamp is     }
{ within the last 15s the dashboard is up (could be the in-process one      }
{ MCP spawned OR a standalone `python -m eda_agent.server dashboard` run    }
{ -- both refresh the same file), button is active. Otherwise grey it out  }
{ and tell the user via caption that no dashboard is reachable.            }
Procedure UpdateOpenWebState(Dummy : Integer);
Var
    HeartbeatPath : String;
    HeartbeatStamp, ThresholdStamp : Integer;
    NewEnabled : Boolean;
Begin
    NewEnabled := False;
    Try
        HeartbeatPath := WorkspaceDir + 'dashboard.heartbeat';
        { Read the heartbeat's MODIFICATION TIME, not its content. The      }
        { dashboard rewrites this file every ~3s, so its file timestamp is  }
        { the last-seen time. Opening the file content (ReadFileContent)    }
        { trips a Windows sharing violation whenever the dashboard is       }
        { mid-write, and the script engine surfaces that as a modal that    }
        { stalls the loop. FileAge queries the directory entry instead of   }
        { locking the content, so it never raises here regardless of how    }
        { the dashboard writes. It returns a DOS date-time stamp (-1 if     }
        { missing); DOS stamps are chronologically ordered, so a plain >=   }
        { against the threshold stamp tests "updated within 15s".           }
        HeartbeatStamp := FileAge(HeartbeatPath);
        If HeartbeatStamp >= 0 Then
        Begin
            ThresholdStamp := DateTimeToFileDate(Now - (15.0 / 86400.0));
            If HeartbeatStamp >= ThresholdStamp Then
                NewEnabled := True;
        End;
    Except End;

    { Avoid pointless repaints on every tick. }
    If NewEnabled = OpenWebEnabled Then Exit;
    OpenWebEnabled := NewEnabled;

    Try
        If NewEnabled Then
        Begin
            btn_OpenWeb.Color := COLOR_ACCENT_BLUE;
            btn_OpenWeb.Font.Color := $00FFFFFF;
            btn_OpenWeb.Cursor := crHandPoint;
            btn_OpenWeb.Caption := 'Open Dashboard';
        End
        Else
        Begin
            btn_OpenWeb.Color := COLOR_BG_CARD;
            btn_OpenWeb.Font.Color := COLOR_TEXT_FAINT;
            btn_OpenWeb.Cursor := crDefault;
            btn_OpenWeb.Caption := 'Open Dashboard  (not running)';
        End;
    Except End;
End;


{ Color the IDLE TIMEOUT KPI according to remaining seconds.                }
Procedure ColorCountdown(IdleSecToShutdown : Integer);
Var
    Col : Cardinal;
    Caption : String;
Begin
    If IdleSecToShutdown <= 30 Then Col := COLOR_ACCENT_RED
    Else If IdleSecToShutdown <= 120 Then Col := COLOR_ACCENT_AMBER
    Else Col := COLOR_ACCENT_GREEN;

    If IdleSecToShutdown >= 60 Then
        Caption := IntToStr(IdleSecToShutdown Div 60) + 'm'
            + PadLeft(IntToStr(IdleSecToShutdown Mod 60), 2) + 's'
    Else
        Caption := IntToStr(IdleSecToShutdown) + 's';

    Try
        lbl_ValStop.Font.Color := Col;
        lbl_ValStop.Caption := Caption;
    Except End;
End;


Procedure UpdateStatusHeader(StatusStr : String);
Begin
    Try
        If Not InFlightActive Then
        Begin
            lbl_Status.Caption := StatusStr;
            lbl_Status.Font.Color := COLOR_TEXT_BODY;
        End;
    Except End;
End;


Procedure UpdateStatsLine(UptimeSec, Requests : Integer; AltiumMs : Cardinal;
                          IdleSecToShutdown : Integer);
Var
    UpStr, MsStr : String;
Begin
    { Uptime: humanize past a minute. }
    If UptimeSec >= 3600 Then
        UpStr := IntToStr(UptimeSec Div 3600) + 'h'
            + IntToStr((UptimeSec Mod 3600) Div 60) + 'm'
    Else If UptimeSec >= 60 Then
        UpStr := IntToStr(UptimeSec Div 60) + 'm'
            + PadLeft(IntToStr(UptimeSec Mod 60), 2) + 's'
    Else
        UpStr := IntToStr(UptimeSec) + 's';

    { Busy time: humanize ms past 1s. }
    If AltiumMs >= 60000 Then
        MsStr := IntToStr(AltiumMs Div 60000) + 'm'
            + IntToStr((AltiumMs Mod 60000) Div 1000) + 's'
    Else If AltiumMs >= 1000 Then
        MsStr := IntToStr(AltiumMs Div 1000) + '.'
            + PadLeft(IntToStr((AltiumMs Mod 1000) Div 100), 1) + 's'
    Else
        MsStr := IntToStr(AltiumMs) + 'ms';

    Try lbl_ValUp.Caption  := UpStr; Except End;
    If SELECTED_PROJECT_READ_ONLY Then RefreshSelectedLabel(0);
    Try lbl_ValReq.Caption := IntToStr(Requests); Except End;
    Try lbl_ValMs.Caption  := MsStr; Except End;
    ColorCountdown(IdleSecToShutdown);
    UpdateOpenWebState(0);
End;


{ Spinner tick: advance the rotating glyph and update the elapsed-ms      }
{ readout on the status line. Runs only while InFlightActive is True.    }
Procedure tmr_SpinnerTimer(Sender : TObject);
Var
    ElapsedMs : Cardinal;
    Tenths : Cardinal;
Begin
    If Not InFlightActive Then Exit;
    SpinnerFrame := (SpinnerFrame + 1) Mod SPINNER_FRAMES;
    Try lbl_Spinner.Caption := SpinnerGlyph(SpinnerFrame); Except End;
    ElapsedMs := GetTickCount - InFlightStartMs;
    Tenths := ElapsedMs Div 100;
    Try
        lbl_Status.Caption := InFlightCommand + '  ('
            + IntToStr(Tenths Div 10) + '.' + IntToStr(Tenths Mod 10) + ' s)';
    Except End;
End;


{ P2 probe tick. This handler is the whole experiment: if it runs at all      }
{ after StartTimerProbe has RETURNED, then a TTimer on this form survives the }
{ end of a script call, and the event-driven redesign is buildable. If it     }
{ never fires, the redesign is dead and the honest fallback is the blocking   }
{ loop plus the caption warning (DESIGN-event-driven-dispatch.md section 2).  }
{                                                                             }
{ Two readouts on purpose. The memo is the detailed record; the CAPTION is    }
{ the one that matters, because it stays readable in the taskbar while the    }
{ form is MINIMIZED - the same reason the Ctrl+Z warning lives there.         }
{                                                                             }
{ Reporting the ELAPSED seconds next to the count is what makes this a rate   }
{ measurement rather than a yes/no: 30 ticks in 30 s means the interval is    }
{ honoured, while 30 ticks in 300 s would say the timer fires but is being    }
{ starved, which is a different finding with a different fix.                 }
Procedure tmr_ProbeTimer(Sender : TObject);
Var
    ElapsedSec : Cardinal;
Begin
    ProbeTickCount := ProbeTickCount + 1;
    ElapsedSec := (GetTickCount - ProbeStartMs) Div 1000;
    Try
        mmo_Log.Lines.Insert(0, 'probe tick ' + IntToStr(ProbeTickCount)
            + '  at ' + IntToStr(ElapsedSec) + ' s');
    Except End;
    Try
        StatusForm.Caption := 'P2 PROBE  ticks=' + IntToStr(ProbeTickCount)
            + '  t=' + IntToStr(ElapsedSec) + 's' + KeyboardWarningSuffix(0);
    Except End;

    If ProbeTickCount >= PROBE_MAX_TICKS Then
    Begin
        Try tmr_Probe.Enabled := False; Except End;
        Try
            mmo_Log.Lines.Insert(0, 'probe auto-stopped at the '
                + IntToStr(PROBE_MAX_TICKS) + '-tick cap');
        Except End;
    End;
End;


{ MCP dispatch timer =========================================================}
{                                                                              }
{ tmr_MCP is a DFM component like tmr_Spinner and tmr_Probe, and everything    }
{ that touches it is in this file, because of two DelphiScript scope rules     }
{ learned the hard way on 2026-09-23/24:                                       }
{   1. A DFM control identifier is in scope ONLY in the .pas paired with the   }
{      .dfm - "Undeclared identifier: tmr_MCP" from Dispatcher.pas, while the  }
{      form itself loaded fine.                                                }
{   2. A DFM event handler binds only to a procedure in that same paired .pas, }
{      exactly as a real Delphi DFM resolves against the form class's          }
{      published methods. A handler named in the DFM but defined elsewhere     }
{      binds to NOTHING, SILENTLY: the timer enables, no error is raised, and  }
{      no tick ever runs.                                                      }
{                                                                              }
{ Both rules stand. What was wrong was the conclusion drawn from them - that   }
{ because the handler must call ProcessSingleRequest, which is in the          }
{ later-listed Dispatcher.pas, the handler could not live here and the timer   }
{ could not be a DFM component at all. THAT INFERENCE WAS FALSE. Calls across  }
{ documents of the script project resolve regardless of document order; this   }
{ very file already calls CurrentSelectedProject in SelectedProject.pas, the   }
{ LAST document in Altium_API.PrjScr, and has done so in production all along. }
{ The ordering rule that was cited applies to build.py's concatenated          }
{ Altium_MCP.pas, which is gitignored and is not a document in the PrjScr.     }
{                                                                              }
{ So the handler is here, it is three lines, and MCPTimerTick in Dispatcher.pas}
{ does the work.                                                               }

Procedure tmr_MCPTimer(Sender : TObject);
Begin
    MCPTimerTick(0);
End;

{ Arm, disable and re-pace. These live here rather than in Dispatcher.pas only }
{ because of rule 1 above: they name tmr_MCP.                                  }
{                                                                              }
{ ArmMCPTimer reads Enabled BACK instead of assuming the assignment took, the  }
{ same trap the P2 probe hit. Without it a form that failed to carry tmr_MCP   }
{ would leave a session that logged _session_start, set Running := True, and   }
{ will never serve a request - a bridge that looks up and is dead. StartMCPServer}
{ turns a False here into an explicit timer-arm-failed finalise.               }
Function ArmMCPTimer(IntervalMs : Integer) : Boolean;
Begin
    Result := False;
    Try
        tmr_MCP.Enabled  := False;
        tmr_MCP.Interval := IntervalMs;
        tmr_MCP.Enabled  := True;
        Result := tmr_MCP.Enabled;
    Except End;
End;

Procedure DisableMCPTimer(Dummy : Integer);
Begin
    Try tmr_MCP.Enabled := False; Except End;
End;

{ Adaptive pacing: the interval replaces the old Sleep. Written only when it   }
{ changes, so a steady state is not re-assigning the property every tick.      }
Procedure SetMCPTimerInterval(IntervalMs : Integer);
Begin
    Try
        If tmr_MCP.Interval <> IntervalMs Then
            tmr_MCP.Interval := IntervalMs;
    Except End;
End;


Procedure ApplyAlwaysOnTop(Dummy : Integer);
Begin
    Try
        If AlwaysOnTopFlag Then StatusForm.FormStyle := fsStayOnTop
        Else StatusForm.FormStyle := fsNormal;
    Except End;
End;


Procedure SetCheckCaption(Pnl : TPanel; Checked : Boolean; LabelText : String);
Begin
    Try
        If Checked Then
            Pnl.Caption := '  ' + FilledDot(0) + '  ' + LabelText
        Else
            Pnl.Caption := '  ' + HollowDot(0) + '  ' + LabelText;
    Except End;
End;


{ Hidden from the Run Script dialog by its argument. StartMCPServer
  calls it at startup, so the form appears without anyone choosing it. }
Procedure ShowStatusForm(Dummy : Integer);
Var
    NewLeft, NewTop : Integer;
    AvailL, AvailT, AvailW, AvailH : Integer;
    Margin : Integer;
Begin
    Try
        EnsureStatusBuffers(0);
        HidePingsFlag   := True;
        OnlySlowFlag    := False;
        AlwaysOnTopFlag := True;
        PausedFlag      := False;
        RenewRequested  := False;
        InFlightActive  := False;
        SpinnerFrame    := 0;
        FilterText      := '';
        LastPingMs      := 0;
        OpenWebEnabled  := False;

        SetCheckCaption(chk_HidePings, HidePingsFlag, 'pings');
        SetCheckCaption(chk_OnlySlow,  OnlySlowFlag,  '>100ms');
        SetCheckCaption(chk_OnTop,     AlwaysOnTopFlag, 'pin');
        ApplyAlwaysOnTop(0);

        ResetPerfStats(0);

        { Position bottom-right of the work area with margin.              }
        Margin := 24;
        AvailL := 0;
        AvailT := 0;
        AvailW := Screen.Width;
        AvailH := Screen.Height - 40;
        Try
            AvailL := Screen.WorkAreaLeft;
            AvailT := Screen.WorkAreaTop;
            AvailW := Screen.WorkAreaWidth;
            AvailH := Screen.WorkAreaHeight;
        Except End;
        NewLeft := AvailL + AvailW - StatusForm.Width  - Margin;
        NewTop  := AvailT + AvailH - StatusForm.Height - Margin;
        If NewLeft < AvailL Then NewLeft := AvailL;
        If NewTop  < AvailT Then NewTop  := AvailT;
        Try StatusForm.Left := NewLeft; Except End;
        Try StatusForm.Top  := NewTop;  Except End;

        If Not StatusForm.Visible Then StatusForm.Show;
        Try StatusForm.Caption := 'EDA Agent MCP' + KeyboardWarningSuffix(0); Except End;
        Try lbl_Version.Caption := 'v' + SCRIPT_VERSION; Except End;
        Try pnl_StatusDot.Color := COLOR_ACCENT_GREEN; Except End;
        Try lbl_Status.Caption := 'idle'; Except End;
        Try lbl_LastErr.Caption := ''; Except End;
        cmb_Project.Visible := SELECTED_PROJECT_READ_ONLY;
        btn_UseProject.Visible := SELECTED_PROJECT_READ_ONLY;
        lbl_SelectedProject.Visible := SELECTED_PROJECT_READ_ONLY;
        lbl_Permissions.Visible := SELECTED_PROJECT_READ_ONLY;
        If SELECTED_PROJECT_READ_ONLY Then
        Begin
            lbl_Permissions.Caption := 'Allowed: reads / compile (no CAD save)'
                + #13#10 + 'Unavailable: edits, saves, output jobs';
            { Hint only, not Caption: the label is a fixed two-line control     }
            { from the form resource, so a third caption line would clip and an }
            { invisible warning is worse than none. Hints expand freely.        }
            lbl_Permissions.Hint := 'Requires an explicitly selected project. '
                + 'Compile may create cache/report files. Editing permissions are not implemented.'
                + #13#10 + 'KEYBOARD UNDO IS DEFERRED while this bridge is attached: '
                + 'Ctrl+Z does nothing now and the presses REPLAY as an undo burst on detach. '
                + 'Use the Edit menu, which works normally. If you pressed it anyway, '
                + 'check the board after detaching and Ctrl+Y back any unwanted reverts.';
            { Children have already been DPI-scaled by the native form loader.
              Use their bounds and the scaled button/label gap, not raw pixels. }
            pnl_Header.Height := lbl_Permissions.Top + lbl_Permissions.Height
                + (lbl_Permissions.Top - lbl_SelectedProject.Top - lbl_SelectedProject.Height);
            StatusForm.Caption := 'EDA Agent - selected project (READ ONLY)'
                + KeyboardWarningSuffix(0);
            RefreshProjectChoices(Nil);
        End;
        { Non-shared mode retains the DFM's naturally scaled header height. }
        { Button is always enabled: dashboard can run standalone. }
        UpdateOpenWebState(0);
    Except End;
End;

Procedure HideStatusForm(Dummy : Integer);
Begin
    Try
        If StatusForm.Visible Then StatusForm.Hide;
    Except End;
End;


{ Arm the P2 probe and RETURN immediately. Returning is the point: the whole }
{ question is whether the timer keeps firing once this procedure is off the  }
{ stack and no script is running. Defined after ShowStatusForm because the   }
{ linter rejects a call that precedes its definition in the concatenation.   }
{                                                                            }
{ Nothing here touches CAD, writes a stop file, or starts the poll loop.     }
Procedure StartTimerProbe(Dummy : Integer);
Var
    Armed : Boolean;
Begin
    ShowStatusForm(0);
    ProbeTickCount := 0;
    ProbeStartMs   := GetTickCount;

    { Read Enabled BACK rather than trusting the assignment. Everything here   }
    { is wrapped in Try/Except, so a missing or unloadable tmr_Probe would     }
    { otherwise fail silently and leave the caption reading 'armed' forever -  }
    { which the runbook interprets as "the timer never fires, the redesign is  }
    { dead". A tooling failure must not be able to masquerade as an            }
    { engineering verdict, so the two outcomes get different captions.         }
    Armed := False;
    Try
        tmr_Probe.Interval := PROBE_INTERVAL_MS;
        tmr_Probe.Enabled  := True;
        Armed := tmr_Probe.Enabled;
    Except End;

    If Armed Then
    Begin
        Try
            mmo_Log.Lines.Insert(0, 'P2 probe armed - interval '
                + IntToStr(PROBE_INTERVAL_MS) + ' ms, cap '
                + IntToStr(PROBE_MAX_TICKS) + ' ticks. Caption shows the count.');
        Except End;
        Try
            StatusForm.Caption := 'P2 PROBE  armed' + KeyboardWarningSuffix(0);
        Except End;
    End
    Else
    Begin
        Try
            mmo_Log.Lines.Insert(0, 'P2 probe FAILED TO ARM - tmr_Probe is '
                + 'missing or would not enable. This is NOT a P2 result; '
                + 'check that StatusForm.dfm carries the tmr_Probe object.');
        Except End;
        Try
            StatusForm.Caption := 'P2 PROBE  FAILED TO ARM - not a result'
                + KeyboardWarningSuffix(0);
        Except End;
    End;
End;


Procedure StatusFormClose(Sender : TObject; Var Action : TCloseAction);
Begin
    Try Running := False; Except End;
    { Disable every timer BEFORE the form goes away. A live timer on a closed  }
    { form fires against freed controls, which section 7 of                     }
    { DESIGN-event-driven-dispatch.md calls the most likely crash in the whole  }
    { redesign - so the ordering it prescribes is established here, while the   }
    { only timers are a spinner and a probe and the blast radius is nil.        }
    { tmr_Spinner was already exposed to this: closing the form mid-request     }
    { left it enabled.                                                          }
    Try tmr_Probe.Enabled := False; Except End;
    Try tmr_Spinner.Enabled := False; Except End;

    { tmr_MCP is deliberately LEFT RUNNING for one more tick, which contradicts }
    { DESIGN section 7's "StatusFormClose must also disable the timer". That    }
    { note assumed closing FREES the form. It does not here: the pre-redesign   }
    { teardown called HideStatusForm(0) AFTER this handler had run, in          }
    { production, without crashing - so the close hides and the controls        }
    { survive. Setting Action := caHide explicitly would be better still, but   }
    { caHide is declared nowhere in this host and an undeclared identifier is a }
    { compile-time fatal, so the VCL default is what we rely on.                }
    {                                                                           }
    { Disabling it here would strand the session: FinaliseMCPServer is what     }
    { writes _session_end and clears the IPC files, and only a tick reaches it. }
    { Running := False above makes the very next tick finalise, and finalise    }
    { disables the timer FIRST exactly as section 7 prescribes. Exposure is one }
    { tick, 10-30 ms, against a form that still exists.                         }
    {                                                                           }
    { Calling FinaliseMCPServer straight from here WOULD now compile - the      }
    { one-way-visibility claim this comment used to make was wrong, see the     }
    { tmr_MCPTimer block above. It is still not done here, for a reason that    }
    { has nothing to do with scope: finalise calls HideStatusForm, so it would  }
    { hide the form from inside that form's own OnClose. That may well be fine, }
    { and it is a tidier teardown, but it is an untested re-entrant path and    }
    { bundling it with the Ctrl+Z fix would confound the one test this deploy   }
    { exists to run. Tracked in TODO as a follow-up.                            }
End;


{ Action buttons ============================================================ }

Procedure btn_DetachClick(Sender : TObject);
Begin
    Try Running := False; Except End;
End;

Procedure btn_ClearLogClick(Sender : TObject);
Begin
    Try mmo_Log.Lines.Clear; Except End;
    Try lbl_LastErr.Caption := ''; Except End;
End;

Procedure btn_PauseClick(Sender : TObject);
Begin
    Try
        PausedFlag := Not PausedFlag;
        If PausedFlag Then
        Begin
            btn_Pause.Caption := 'Resume';
            btn_Pause.Color := COLOR_ACCENT_AMBER;
            btn_Pause.Font.Color := $00111111;
            pnl_StatusDot.Color := COLOR_TEXT_FAINT;
            lbl_Status.Caption := 'paused';
            lbl_Status.Font.Color := COLOR_TEXT_MUTED;
        End
        Else
        Begin
            btn_Pause.Caption := 'Pause';
            btn_Pause.Color := $002A2C32;
            btn_Pause.Font.Color := COLOR_TEXT_BODY;
            If Not InFlightActive Then
            Begin
                pnl_StatusDot.Color := COLOR_ACCENT_GREEN;
                lbl_Status.Caption := 'idle';
                lbl_Status.Font.Color := COLOR_TEXT_BODY;
            End;
        End;
    Except End;
End;

Procedure btn_RenewClick(Sender : TObject);
Begin
    { Signal the Dispatcher to reset its REAL idle deadline (LastActivityMs,}
    { local to StartMCPServer) on its next poll -- without this the renew    }
    { only moved the visible countdown and the bridge still auto-shut-down.  }
    Try RenewRequested := True; Except End;
    { Also reset the local tick so the visible countdown jumps back to the   }
    { full window immediately, without waiting for the next poll.            }
    Try LastActivityTick := GetTickCount; Except End;
End;


{ Open the web dashboard. Writes a sentinel file the Python dashboard polls }
{ and calls webbrowser.open() on. Sync round-trip would freeze the UI,      }
{ this hand-off is fire-and-forget. If the heartbeat says no dashboard is   }
{ running we surface the hint instead of writing a sentinel nobody reads.   }
Procedure btn_OpenWebClick(Sender : TObject);
Var
    SentinelPath : String;
Begin
    If Not OpenWebEnabled Then
    Begin
        Try lbl_LastErr.Caption := 'no dashboard running - copy the command below'; Except End;
        Exit;
    End;
    Try
        SentinelPath := WorkspaceDir + 'open_dashboard.url';
        WriteFileContent(SentinelPath, 'http://127.0.0.1:8766/');
        Try lbl_LastErr.Caption := ''; Except End;
    Except End;
End;


{ Copy the dashboard standalone-launch command to the Windows clipboard. }
{ The status form's footer shows `eda-agent dashboard --port 8766` and  }
{ a Copy button so the user can paste it into a terminal to run the     }
{ dashboard without needing Claude / any MCP client open.                }
Procedure btn_CopyCmdClick(Sender : TObject);
Begin
    Try
        { Use the `python -m` form so the command works regardless of  }
        { whether the user has added Python's Scripts dir to PATH. The }
        { `eda-agent` console script is installed there by pip but the }
        { directory isn't on PATH by default on Windows.                }
        Clipboard.AsText := 'python -m eda_agent.server dashboard --port 8766';
        Try btn_CopyCmd.Caption := 'Copied'; Except End;
    Except End;
End;


{ Toggles ================================================================== }

Procedure chk_HidePingsClick(Sender : TObject);
Begin
    Try
        HidePingsFlag := Not HidePingsFlag;
        SetCheckCaption(chk_HidePings, HidePingsFlag, 'pings');
        RebuildVisibleLog(0);
    Except End;
End;

Procedure chk_OnlySlowClick(Sender : TObject);
Begin
    Try
        OnlySlowFlag := Not OnlySlowFlag;
        SetCheckCaption(chk_OnlySlow, OnlySlowFlag, '>100ms');
        RebuildVisibleLog(0);
    Except End;
End;

Procedure chk_OnTopClick(Sender : TObject);
Begin
    Try
        AlwaysOnTopFlag := Not AlwaysOnTopFlag;
        SetCheckCaption(chk_OnTop, AlwaysOnTopFlag, 'pin');
        ApplyAlwaysOnTop(0);
    Except End;
End;

Procedure edt_FilterChange(Sender : TObject);
Begin
    Try FilterText := edt_Filter.Text; Except End;
    RebuildVisibleLog(0);
End;


{ Hover handlers ============================================================ }

Procedure btn_DetachEnter(Sender : TObject);
Begin Try btn_Detach.Color := $00D05050; Except End; End;
Procedure btn_DetachLeave(Sender : TObject);
Begin Try btn_Detach.Color := $00B14545; Except End; End;

Procedure btn_ClearLogEnter(Sender : TObject);
Begin Try btn_ClearLog.Color := $003A3C42; Except End; End;
Procedure btn_ClearLogLeave(Sender : TObject);
Begin Try btn_ClearLog.Color := $002A2C32; Except End; End;

Procedure btn_PauseEnter(Sender : TObject);
Begin
    Try
        If PausedFlag Then btn_Pause.Color := $00B388F0
        Else btn_Pause.Color := $003A3C42;
    Except End;
End;
Procedure btn_PauseLeave(Sender : TObject);
Begin
    Try
        If PausedFlag Then btn_Pause.Color := COLOR_ACCENT_AMBER
        Else btn_Pause.Color := $002A2C32;
    Except End;
End;

Procedure btn_RenewEnter(Sender : TObject);
Begin Try btn_Renew.Color := $003A3C42; Except End; End;
Procedure btn_RenewLeave(Sender : TObject);
Begin Try btn_Renew.Color := $002A2C32; Except End; End;

Procedure btn_OpenWebEnter(Sender : TObject);
Begin
    If OpenWebEnabled Then
        Try btn_OpenWeb.Color := $00FFAE6A; Except End;
End;
Procedure btn_OpenWebLeave(Sender : TObject);
Begin
    If OpenWebEnabled Then
        Try btn_OpenWeb.Color := COLOR_ACCENT_BLUE; Except End
    Else
        Try btn_OpenWeb.Color := COLOR_BG_CARD; Except End;
End;

Procedure chk_HidePingsEnter(Sender : TObject);
Begin Try chk_HidePings.Color := $00252630; Except End; End;
Procedure chk_HidePingsLeave(Sender : TObject);
Begin Try chk_HidePings.Color := COLOR_BG_BASE; Except End; End;

Procedure chk_OnlySlowEnter(Sender : TObject);
Begin Try chk_OnlySlow.Color := $00252630; Except End; End;
Procedure chk_OnlySlowLeave(Sender : TObject);
Begin Try chk_OnlySlow.Color := COLOR_BG_BASE; Except End; End;

Procedure chk_OnTopEnter(Sender : TObject);
Begin Try chk_OnTop.Color := $00252630; Except End; End;
Procedure chk_OnTopLeave(Sender : TObject);
Begin Try chk_OnTop.Color := COLOR_BG_BASE; Except End; End;

Procedure tab_LogEnter(Sender : TObject);
Begin
    Try
        If mmo_Log.Visible Then tab_Log.Color := $00252630
        Else tab_Log.Color := $002A2C32;
    Except End;
End;
Procedure tab_LogLeave(Sender : TObject);
Begin
    Try
        If mmo_Log.Visible Then tab_Log.Color := COLOR_BG_BASE
        Else tab_Log.Color := COLOR_BG_CARD;
    Except End;
End;

Procedure tab_PerfEnter(Sender : TObject);
Begin
    Try
        If mmo_Perf.Visible Then tab_Perf.Color := $00252630
        Else tab_Perf.Color := $002A2C32;
    Except End;
End;
Procedure tab_PerfLeave(Sender : TObject);
Begin
    Try
        If mmo_Perf.Visible Then tab_Perf.Color := COLOR_BG_BASE
        Else tab_Perf.Color := COLOR_BG_CARD;
    Except End;
End;


Procedure tab_LogClick(Sender : TObject);
Begin
    Try
        mmo_Log.Visible := True;
        mmo_Perf.Visible := False;
        tab_Log.Color := COLOR_BG_BASE;
        tab_Log.Font.Color := COLOR_ACCENT_BLUE;
        tab_Perf.Color := COLOR_BG_CARD;
        tab_Perf.Font.Color := COLOR_TEXT_MUTED;
    Except End;
End;

Procedure tab_PerfClick(Sender : TObject);
Begin
    Try
        RefreshPerfPanel(0);
        mmo_Log.Visible := False;
        mmo_Perf.Visible := True;
        tab_Perf.Color := COLOR_BG_BASE;
        tab_Perf.Font.Color := COLOR_ACCENT_BLUE;
        tab_Log.Color := COLOR_BG_CARD;
        tab_Log.Font.Color := COLOR_TEXT_MUTED;
    Except End;
End;
