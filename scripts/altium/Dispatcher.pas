{ SPDX-License-Identifier: Apache-2.0                                   }
{ Copyright (c) 2026 George Saliba <george.saliba@salitronic.com>                                      }
{..............................................................................}
{ Dispatcher.pas - Polling loop and per-request dispatcher.                     }
{ Compiles last so all Handle*Command functions are visible.                   }
{..............................................................................}

{ Dashboard counters fed to StatusForm.pas helpers each tick. }
Var
    StatusStartTick      : Cardinal;
    StatusRequestCount   : Integer;
    StatusLastCommand    : String;
    StatusTotalAltiumMs  : Cardinal;
    MCPHostClosing      : Boolean;
    MCPStopReason       : String;

    { Event-driven dispatch state - DESIGN-event-driven-dispatch.md section 4.  }
    { Every one of these was a LOCAL of the old blocking StartMCPServer loop.   }
    { Each tick is now a separate call, so anything the loop carried between    }
    { iterations has to live here instead. A variable missed in that migration  }
    { does not fail loudly, it quietly changes behaviour, which is why the      }
    { design lists them explicitly and why this block mirrors that table.       }
    MCPStopPath          : String;    { was StopPath, set once at arm          }
    MCPIdleCount         : Integer;   { was IdleCount, drives stats cadence    }
    MCPCurrentInterval   : Integer;   { was CurrentSleep; now written to       }
                                      { Timer.Interval instead of Sleep()      }
    MCPLastActivityMs    : Cardinal;  { was LastActivityMs, auto-shutdown      }
    MCPLoopFailed        : Boolean;   { was LoopFailed, read by finalise       }
    MCPInTick            : Boolean;   { re-entrancy guard, section 6           }
    MCPFaultStreak       : Integer;   { consecutive tick faults, section 8     }
    MCPTickCount         : Integer;   { ticks since arm; the first one is      }
                                      { logged, see tmr_MCPTimer              }
    { The dispatch timer, created HERE rather than placed on StatusForm.       }
    { A DFM event handler binds only to a procedure in the .pas paired with    }
    { the .dfm, and it fails SILENTLY when it cannot - the timer enables, no   }
    { error is raised, and no tick ever runs (observed 2026-09-24: an armed    }
    { session that logged _session_start and then went quiet). The handler     }
    { must call ProcessSingleRequest and so cannot live in StatusForm.pas, so  }
    { the timer cannot be a DFM component. Creating it in the same unit as its }
    { handler keeps the binding inside one file, where it can be assigned      }
    { directly. Owning it outside the form is also better for teardown: the    }
    { timer no longer dies with the window it used to sit on.                  }
    MCPTimerObj          : TTimer;
    { ActiveTickCount and I are deliberately GONE: the first only rationed      }
    { ProcessMessages calls and the second drove the Sleep sub-loop. Neither    }
    { call exists any more, and not calling them is the entire fix.             }

Const
    { Stop after this many consecutive failing ticks. The old design wrapped    }
    { the whole loop in one Try/Except, so a fault ended the session outright;  }
    { per-tick handling would otherwise let a repeating fault log forever.      }
    MCP_MAX_FAULT_STREAK = 5;

Function ProcessCommand(Command : String; Params : String; RequestId : String) : String;
Var
    Category, Action : String;
    DotPos : Integer;
Begin
    If SELECTED_PROJECT_READ_ONLY Then
    Begin
        Result := ProcessSelectedCommand(Command, Params, RequestId);
        Exit;
    End;
    DotPos := Pos('.', Command);
    If DotPos > 0 Then
    Begin
        Category := Copy(Command, 1, DotPos - 1);
        Action := Copy(Command, DotPos + 1, Length(Command));
    End
    Else
    Begin
        Category := Command;
        Action := '';
    End;

    Case Category Of
        'application': Result := HandleApplicationCommand(Action, Params, RequestId);
        'project':     Result := HandleProjectCommand(Action, Params, RequestId);
        'library':     Result := HandleLibraryCommand(Action, Params, RequestId);
        'generic':     Result := HandleGenericCommand(Action, Params, RequestId);
        'pcb':         Result := HandlePCBCommand(Action, Params, RequestId);
        'audit':       Result := HandleAuditCommand(Action, Params, RequestId);
    Else
        Result := BuildErrorResponse(RequestId, 'UNKNOWN_COMMAND',
            'Unknown command category: ' + Category +
            '. Use generic.* for object operations, pcb.* for PCB-specific ' +
            'commands, or audit.* for design-lint checks.');
    End;
End;

{..............................................................................}
{ Process a single request if one exists. Returns True iff a request was found.}
{                                                                                }
{ The dispatcher scans for any request_*.json file in the workspace, extracts  }
{ the ID from the filename, reads and deletes the request, dispatches, and    }
{ writes response_<id>.json. The handler returns the JSON envelope as a       }
{ String; the dispatcher writes the file. Handlers that previously bypassed    }
{ the dispatcher's write via the ResponseAlreadyWritten flag have all been     }
{ migrated to the standard pattern.                                            }
{..............................................................................}

{..............................................................................}
{ CommandIsReadOnly - whether a command leaves the design untouched.           }
{                                                                              }
{ Used for ONE thing: deciding whether the compiled-netlist cache survives a   }
{ command. SmartCompile skips DM_Compile for COMPILE_CACHE_TTL_MS when the     }
{ project reports no dirty documents, and InvalidateCompileCache existed but   }
{ was never called from anywhere, so a write followed within that window by a  }
{ connectivity read handed back the netlist from BEFORE the write. Whether it  }
{ did depended on whether that particular handler happened to dirty the        }
{ document, which is not uniform: many go through ProcessControl, which marks  }
{ the document modified, and others assign through SetState_ and do not.       }
{                                                                              }
{ THE UNKNOWN CASE COUNTS AS A WRITE. Only the prefixes below are treated as   }
{ leaving the design alone, so a command this list has never heard of, and     }
{ every command added later, invalidates. An unnecessary invalidation costs    }
{ one recompile; a missed one returns connectivity that predates the edit.     }
{..............................................................................}

Function ActionHasPrefix(Verb : String; Prefix : String) : Boolean;
Begin
    Result := Copy(Verb, 1, Length(Prefix)) = Prefix;
End;

Function CommandIsReadOnly(Command : String) : Boolean;
Var
    Verb : String;
    DotPos : Integer;
Begin
    Verb := LowerCase(Trim(Command));
    DotPos := Pos('.', Verb);
    If DotPos > 0 Then Verb := Copy(Verb, DotPos + 1, Length(Verb) - DotPos);

    Result := ActionHasPrefix(Verb, 'get_')
           Or ActionHasPrefix(Verb, 'list_')
           Or ActionHasPrefix(Verb, 'query')
           Or ActionHasPrefix(Verb, 'read_')
           Or ActionHasPrefix(Verb, 'find_')
           Or ActionHasPrefix(Verb, 'count')
           Or ActionHasPrefix(Verb, 'audit_')
           Or ActionHasPrefix(Verb, 'check_')
           Or ActionHasPrefix(Verb, 'calc_')
           Or ActionHasPrefix(Verb, 'export_')
           Or ActionHasPrefix(Verb, 'render_')
           Or ActionHasPrefix(Verb, 'probe_')
           Or ActionHasPrefix(Verb, 'inspect_')
           Or ActionHasPrefix(Verb, 'diff_')
           Or ActionHasPrefix(Verb, 'compare_')
           Or (Verb = 'ping');
End;

Function ProcessSingleRequest(Dummy : Integer): Boolean;
Var
    RequestPath, RequestId : String;
    RequestContent, ResponseContent : String;
    Command, Params, ProtoVer, EnvelopeError : String;
    ExceptionMsg : String;
    FocusBefore, FocusAfter : String;
    StartMs, DurationMs : Cardinal;
    ResultTag : String;
    DashIsError : Boolean;
    DashDetail, DashErrPayload, DashCode : String;
Begin
    Result := False;
    EnsureWorkspaceDir(0);

    If Not ScanForRequestFile(RequestPath, RequestId) Then Exit;

    // Read the request file
    RequestContent := ReadFileContent(RequestPath);
    // Remove the request file regardless of read outcome so we never reprocess
    DeleteFile(RequestPath);

    If RequestContent = '' Then
    Begin
        { ReadFileContent already retried 12 times over ~180ms for a       }
        { transient sharing violation, so an empty result here means the   }
        { file was genuinely empty or still locked. Deleting it and        }
        { exiting SILENTLY left the caller to wait out its entire deadline }
        { and report a plain timeout, which reads exactly like a wedged    }
        { polling loop and sends the user hunting the wrong fault.          }
        {                                                                   }
        { The id came from the FILENAME via ScanForRequestFile and has not  }
        { been overwritten by the body's id yet, so the call can still be   }
        { answered with the actual reason.                                  }
        If IsValidRequestId(RequestId) Then
            WriteResponseFile(RequestId,
                BuildErrorResponse(RequestId, 'REQUEST_UNREADABLE',
                    'Request file was empty or unreadable after 12 retries '
                    + 'and has been discarded. The polling loop is healthy; '
                    + 'retry the call.'));
        Exit;
    End;

    // ID arrives in the JSON body. Per-request response files use it for
    // the filename so concurrent callers each get an isolated response file.
    RequestId := ExtractJsonValue(RequestContent, 'id');
    Command := ExtractJsonValue(RequestContent, 'command');
    Params := ExtractJsonValue(RequestContent, 'params');
    ProtoVer := ExtractJsonValue(RequestContent, 'protocol_version');

    EnvelopeError := ValidateRequestEnvelope(RequestId, Command);
    If EnvelopeError <> '' Then
    Begin
        // Without a valid id we can't write a per-request response file;
        // fall back to writing response.json so Python can still pick it up.
        If IsValidRequestId(RequestId) Then
            WriteResponseFile(RequestId,
                BuildErrorResponse(RequestId, 'MALFORMED_REQUEST', EnvelopeError))
        Else
            WriteFileContent(WorkspaceDir + 'response.json',
                BuildErrorResponse('', 'MALFORMED_REQUEST', EnvelopeError));
        Result := True;
        Exit;
    End;

    If (ProtoVer <> '') And (ProtoVer <> IntToStr(PROTOCOL_VERSION)) Then
    Begin
        WriteResponseFile(RequestId,
            BuildErrorResponseDetailed(RequestId, 'PROTOCOL_VERSION_MISMATCH',
                'Client protocol_version=' + ProtoVer +
                ' does not match server PROTOCOL_VERSION=' + IntToStr(PROTOCOL_VERSION) +
                '. Update the eda-agent client or restart the Altium script.',
                '{"client_version":' + ProtoVer +
                ',"server_version":' + IntToStr(PROTOCOL_VERSION) + '}'));
        Result := True;
        Exit;
    End;

    StatusLastCommand := Command;
    Inc(StatusRequestCount);
    StartMs := GetTickCount;
    ResultTag := 'OK';

    { MCP liveness: any inbound command (typically application.ping every }
    { 30 s) keeps the Open Dashboard button enabled.                       }
    LastPingMs := StartMs;

    { Spinner + in-flight readout on the dashboard. Reset on exit so the }
    { status pill drops back to idle/paused/green when we're done.       }
    SetInFlight(Command);

    { WHERE THE CALLER WAS LOOKING, BEFORE THE HANDLER RAN.
      Nearly every tool acts on the focused document, and several change
      it as a side effect of doing their job. Nothing announced that.
      Measured: lib_probe_footprint focused a PcbLib to read it, the
      obj_switch_view that followed switched the LIBRARY into 3D, and the
      session spent a long time looking for a placement bug that was not
      there.
      Captured here rather than per handler because there are hundreds of
      them and this is the one place every command passes through. }
    FocusBefore := CurrentFocusedDocPath(0);
    ResetNextStep(0);

    ExceptionMsg := '';
    { Heartbeat: write progress_<id>.json so Python can distinguish "still      }
    { working" from "polling loop dead" when the 10 s default deadline runs   }
    { out on a legitimately-slow handler. Delete only AFTER writing the       }
    { response, so at no point are both files missing.                        }
    StartProgress(RequestId);
    Try
        Try
            ResponseContent := ProcessCommand(Command, Params, RequestId);
        Except
            ExceptionMsg := 'Unhandled exception processing: ' + Command;
            ResponseContent := BuildErrorResponse(RequestId, 'INTERNAL_ERROR', ExceptionMsg);
            ResultTag := 'EXCEPTION';
        End;

        { The compiled netlist is stale the moment anything is written, and
          this is the one place every command passes through, so it is done
          here rather than in each of the hundreds of handlers.

          On the exception path too, deliberately: a handler that threw part
          way through may well have written something first, and that is
          exactly when a cached netlist is worth least. }
        If Not CommandIsReadOnly(Command) Then InvalidateCompileCache(0);

        If ResponseContent = '' Then
        Begin
            // Handler returned nothing, degenerate but recoverable. Synthesise
            // an INTERNAL_ERROR rather than leaving the caller polling forever.
            ResponseContent := BuildErrorResponse(RequestId, 'INTERNAL_ERROR',
                'Handler returned empty response for: ' + Command);
            ResultTag := 'EMPTY';
        End;

        { Say so if the active document moved. Appended as a sibling of
          data rather than merged into it, because data is whatever the
          handler chose to return and this must not depend on its shape.
          Silent when nothing moved, which is the overwhelming majority. }
        { The follow-up this reply owes, if the handler named one. }
        If PendingNextStep(0) <> '' Then
            ResponseContent := AppendEnvelopeField(ResponseContent,
                JsonStr('next_step', PendingNextStep(0)));

        FocusAfter := CurrentFocusedDocPath(0);
        If FocusAfter <> FocusBefore Then
            ResponseContent := AppendEnvelopeField(ResponseContent,
                '"active_document_changed":' + JsonObj(
                    JsonStr('from', FocusBefore) + ',' +
                    JsonStr('to', FocusAfter) + ',' +
                    JsonStr('note', 'this command moved the focused '
                        + 'document. Tools that act on the focused '
                        + 'document will now act on the new one.')));

        WriteResponseFile(RequestId, ResponseContent);
    Finally
        EndProgress(RequestId);
    End;

    DurationMs := GetTickCount - StartMs;
    StatusTotalAltiumMs := StatusTotalAltiumMs + DurationMs;

    AppendLog(FormatLogStamp(0) + ',' + IntToStr(DurationMs) + ',' + Command + ',' + ResultTag
              + ',' + IntToStr(Length(ResponseContent)) + ',' + Copy(ResponseContent, 1, 200));

    { Surface the error message to the dashboard (inline detail row + last- }
    { error banner) when the response is success=false. ExtractJsonValue   }
    { handles the nested error/code/message path via two successive calls. }
    DashIsError := (ResultTag = 'EXCEPTION');
    DashErrPayload := ExtractJsonValue(ResponseContent, 'error');
    DashDetail := '';
    DashCode := '';
    If (DashErrPayload <> '') And (DashErrPayload <> 'null') Then
    Begin
        DashIsError := True;
        DashCode    := ExtractJsonValue(DashErrPayload, 'code');
        DashDetail  := ExtractJsonValue(DashErrPayload, 'message');
        { Explicit Begin/End around each branch, DelphiScript parser   }
        { trips on `Else If` without them.                               }
        If (DashCode <> '') And (DashDetail <> '') Then
        Begin
            DashDetail := DashCode + ': ' + DashDetail;
        End
        Else
        Begin
            If (DashCode <> '') Then DashDetail := DashCode;
        End;
    End;
    AppendLogLine(Command, DurationMs, DashIsError, RequestId, DashDetail);

    ResetInFlight(0);

    Result := True;
End;

{..............................................................................}
{ Clean up state left by the MCP server before exiting. Deletes any leftover   }
{ per-request IPC files. Never pump UI messages during teardown.               }
{..............................................................................}

Procedure CleanupMCPServer(Dummy : Integer);
Begin
    CleanupOrphanRequests(0);
    CleanupOrphanProgress(0);
End;

{ Recheck after every UI yield: quitting can begin inside ProcessMessages.
  These checks cannot recover a VM destroyed inside that native call. Stop
  the bridge before closing its script project or exiting Altium. }
Function MCPHostAvailable(Dummy : Integer) : Boolean;
Begin
    Result := False;
    If MCPHostClosing Then Exit;
    Try
        If Client.IsQuitting Then
        Begin
            MCPHostClosing := True;
            MCPStopReason := 'host-quitting';
        End;
    Except
        MCPHostClosing := True;
        MCPStopReason := 'host-unavailable';
    End;
    If MCPHostClosing Then
    Begin
        Running := False;
        Exit;
    End;
    Result := True;
End;

Function MCPContinuePolling(StopPath : String) : Boolean;
Begin
    Result := False;
    If Not MCPHostAvailable(0) Then Exit;
    If Not Running Then Exit;
    If FileExists(StopPath) Then
    Begin
        { Latch the stop before file I/O: deletion failure must not resume. }
        Running := False;
        MCPStopReason := 'stop-file';
        DeleteFile(StopPath);
        Exit;
    End;
    Result := True;
End;

Function MCPYield(StopPath : String) : Boolean;
Begin
    Result := False;
    If Not MCPContinuePolling(StopPath) Then Exit;
    Application.ProcessMessages;
    { No Sleep, status access or new request before this post-yield check. }
    Result := MCPContinuePolling(StopPath);
End;

{..............................................................................}
{ Start MCP server, adaptive polling loop.                                  }
{                                                                            }
{ Uses ADAPTIVE POLLING to avoid blocking Altium:                             }
{   - Active (just processed a request): polls fast (PollIntervalActiveMs)   }
{   - Idle: polls slow (PollIntervalIdleMs) with extra ProcessMessages calls }
{   - Auto-shuts down after AutoShutdownMs of inactivity                      }
{                                                                            }
{ All tunables come from mcp_config.json via LoadMCPConfig at startup.       }
{ Stop methods: send application.stop_server, drop a 'stop' file in the      }
{ workspace, or wait for auto-shutdown.                                      }
{..............................................................................}

{..............................................................................}
{ DIAGNOSTIC ENTRY POINT for the Ctrl+Z P0. Parameterless on purpose, so it    }
{ appears in the Run Script dialog next to StartMCPServer.                     }
{                                                                              }
{ Why it exists. On detach TWO things change at once: the polling loop exits   }
{ AND HideStatusForm runs (see the shutdown path below). Every test so far has }
{ changed both together, which is why "is it the running script or is it the   }
{ form" has stayed open. Operator evidence 2026-09-23 already killed the       }
{ message-starvation theory: Ctrl+Z fails even when the bridge is IDLE, where  }
{ ProcessMessages runs about every 6 ms.                                       }
{                                                                              }
{ This shows the status form and RETURNS IMMEDIATELY. No loop, no script left  }
{ running, no CAD touched. Then press Ctrl+Z in the editor:                    }
{   - Undo still broken -> the FORM alone is responsible. VCL Show activates   }
{     the window, so it becomes Screen.ActiveForm and shortcut dispatch is     }
{     resolved against a form that has no Undo. Fix is form activation:        }
{     show without activating, or hand activation straight back to Altium.     }
{   - Undo fine -> the form is exonerated and the running script owning the    }
{     thread is the cause. The fix is then the event-driven TTimer dispatch    }
{     (see ShowStatusFormTimerProbe below). NOT flush-on-shutdown: that needed }
{     PeekMessage, and Project.pas:2145 records that DelphiScript blocks       }
{     external DLL imports, so user32 is unreachable from here.                }
{                                                                              }
{ If the form disappears the moment this returns, that is itself the answer to }
{ a different question (the VM does not outlive the call) - report it.         }
{ Close the form by hand afterwards; nothing here registers a stop file.       }
Procedure ShowStatusFormDiagnostic;
Begin
    ShowStatusForm(0);
End;

{..............................................................................}
{ P2 PREREQUISITE PROBE for the event-driven redesign. Also parameterless so   }
{ it lands in the Run Script dialog beside the P1 diagnostic above.            }
{                                                                              }
{ The redesign in docs/DESIGN-event-driven-dispatch.md turns StartMCPServer    }
{ into "arm a TTimer and return", which is the only surviving fix for BOTH     }
{ P0s - the shutdown crash and the deferred Ctrl+Z. All of it rests on one     }
{ unverified assumption: that a TTimer on this form still fires after the      }
{ script that armed it has returned. Section 2 calls P2 the real gate and      }
{ forbids writing section 3 onward until it passes. This is that test, and     }
{ nothing more.                                                                }
{                                                                              }
{ Read the answer off the FORM CAPTION, which keeps counting in the taskbar    }
{ while the form is minimized:                                                 }
{   - caption stays at "armed"        -> the timer never fires once the call   }
{     returns. The redesign is DEAD; record it, keep the blocking loop and     }
{     the caption warning, and the only candidate left is the OnMessage hook   }
{     in TODO P0 (flush-on-shutdown is NOT a fallback - it needed user32,      }
{     which DelphiScript cannot import; see Project.pas:2145).                 }
{   - count climbs ~1/s              -> P2 PASSES. The VM and the timer both   }
{     outlive the call and the redesign is buildable.                          }
{   - count climbs far slower than 1/s -> fires but starved. A real finding    }
{     with a different fix; report the count and the elapsed seconds, both of  }
{     which the caption shows.                                                 }
{   - form vanishes on return        -> answers P1 instead: the VM does not    }
{     outlive the call. Report it; P2 needs another shape.                     }
{                                                                              }
{ Self-bounding: the probe stops itself at PROBE_MAX_TICKS (120 s) and         }
{ StatusFormClose disables it, so a probe walked away from cannot be left      }
{ firing against a closed form. No loop, no stop file, no CAD touched.         }
Procedure ShowStatusFormTimerProbe;
Begin
    StartTimerProbe(0);
End;

{ Dispatch-timer control. Defined before the routines that use them; ArmMCPTimer}
{ has to wait until after tmr_MCPTimer exists, so it lives further down.        }

Procedure DisableMCPTimer(Dummy : Integer);
Begin
    Try
        If MCPTimerObj <> Nil Then MCPTimerObj.Enabled := False;
    Except End;
End;

{ Adaptive pacing: the interval replaces the old Sleep. Written only when it   }
{ changes, so a steady state is not re-assigning the property every tick.      }
Procedure SetMCPTimerInterval(IntervalMs : Integer);
Begin
    Try
        If MCPTimerObj <> Nil Then
            If MCPTimerObj.Interval <> IntervalMs Then
                MCPTimerObj.Interval := IntervalMs;
    Except End;
End;


{..............................................................................}
{ Teardown, reached from every path that ends a session: the stop file or      }
{ application.stop_server, the Detach button, auto-shutdown, and a tick that   }
{ has failed too many times in a row.                                          }
{                                                                              }
{ The ORDER is prescribed by DESIGN section 7 and is not cosmetic: disable the }
{ timer FIRST, before anything else, so no tick can re-enter cleanup or fire   }
{ against controls HideStatusForm is about to take away. A live timer on a     }
{ closed form is the single most likely crash in this whole redesign.          }
{..............................................................................}
Procedure FinaliseMCPServer(Dummy : Integer);
Begin
    DisableMCPTimer(0);
    Running := False;

    If Not MCPLoopFailed Then
    Begin
        If MCPHostAvailable(0) Then HideStatusForm(0);
    End;
    Try
        CleanupMCPServer(0);
    Except
        MCPLoopFailed := True;
        MCPStopReason := 'cleanup-exception';
    End;
    Try
        If MCPLoopFailed Then
            AppendLog(FormatLogStamp(0) + ',0,_session_aborted,reason=' + MCPStopReason)
        Else
            AppendLog(FormatLogStamp(0) + ',0,_session_end,requests='
                + IntToStr(StatusRequestCount) + ',reason=' + MCPStopReason);
    Except End;
End;


{..............................................................................}
{ One poll's worth of work, on a timer instead of inside a blocking loop.      }
{                                                                              }
{ NOTHING HERE SLEEPS AND NOTHING CALLS Application.ProcessMessages. That is   }
{ the whole point: the host is pumping its own message loop normally now, so   }
{ keyboard-to-command dispatch is never deferred and Ctrl+Z reaches Altium at  }
{ the moment it is pressed. Re-introducing either call would restore both P0s. }
{                                                                              }
{ Wired from StatusForm.dfm as tmr_MCP.OnTimer. It lives in Dispatcher.pas     }
{ rather than StatusForm.pas because it calls ProcessSingleRequest and friends,}
{ which are only defined by this point in the concatenation.                   }
{..............................................................................}
Procedure tmr_MCPTimer(Sender : TObject);
Var
    NowMs      : Cardinal;
    HadRequest : Boolean;
Begin
    { Re-entrancy (section 6). A handler that outruns its interval, or a        }
    { request that pumps messages internally inside Altium, can re-enter here.  }
    { DROP the coincident tick rather than queueing it: the next one is 10-30   }
    { ms away and the work is idempotent polling, whereas queueing would let a  }
    { slow request build a backlog that then stampedes - the very shape of the  }
    { bug being fixed.                                                          }
    If MCPInTick Then Exit;
    MCPInTick := True;
    Try
        Try
            { Log the FIRST tick and nothing after. Under timer dispatch a      }
            { handler that never binds produces a form that is up, a session    }
            { that logged _session_start, and total silence - indistinguishable }
            { by eye from a dozen other failures. This one line separates       }
            { "armed but never fired" from "firing and something else is        }
            { wrong", which is the first question to ask of any tick problem.   }
            Inc(MCPTickCount);
            If MCPTickCount = 1 Then
                Try
                    AppendLog(FormatLogStamp(0) + ',0,_tick_first,interval='
                        + IntToStr(MCPCurrentInterval));
                Except End;

            If Not Running Then
            Begin
                FinaliseMCPServer(0);
                Exit;
            End;
            If Not MCPContinuePolling(MCPStopPath) Then
            Begin
                FinaliseMCPServer(0);
                Exit;
            End;

            { Renew button: reset the real idle deadline once per click. }
            If RenewRequested Then
            Begin
                MCPLastActivityMs := GetTickCount;
                RenewRequested := False;
                UpdateStatsLine(
                    (GetTickCount - StatusStartTick) Div 1000,
                    StatusRequestCount,
                    StatusTotalAltiumMs,
                    AutoShutdownMs Div 1000);
            End;

            { Paused sessions never auto-shut-down, so the user can step away. }
            If PausedFlag Then
                MCPLastActivityMs := GetTickCount;
            If AutoShutdownMs > 0 Then
            Begin
                NowMs := GetTickCount;
                If NowMs >= MCPLastActivityMs Then
                Begin
                    If (NowMs - MCPLastActivityMs) > AutoShutdownMs Then
                    Begin
                        MCPStopReason := 'idle-timeout';
                        Running := False;
                        FinaliseMCPServer(0);
                        Exit;
                    End;
                End;
            End;

            If PausedFlag Then
            Begin
                { Skip dispatch entirely, but keep the countdown alive. No      }
                { yield call is needed now - the host never stopped pumping.    }
                UpdateStatsLine(
                    (GetTickCount - StatusStartTick) Div 1000,
                    StatusRequestCount,
                    StatusTotalAltiumMs,
                    AutoShutdownMs Div 1000);
                MCPCurrentInterval := PollIntervalIdleMs;
            End
            Else
            Begin
                HadRequest := ProcessSingleRequest(0);
                If Not MCPContinuePolling(MCPStopPath) Then
                Begin
                    FinaliseMCPServer(0);
                    Exit;
                End;

                If HadRequest Then
                Begin
                    MCPIdleCount := 0;
                    MCPCurrentInterval := PollIntervalActiveMs;
                    MCPLastActivityMs := GetTickCount;
                    UpdateStatusHeader('MCP: idle');
                    UpdateStatsLine(
                        (GetTickCount - StatusStartTick) Div 1000,
                        StatusRequestCount,
                        StatusTotalAltiumMs,
                        (AutoShutdownMs - (GetTickCount - MCPLastActivityMs)) Div 1000);
                End
                Else
                Begin
                    Inc(MCPIdleCount);
                    If MCPIdleCount > IdleThreshold Then
                        MCPCurrentInterval := PollIntervalIdleMs;
                    If (MCPIdleCount Mod 10) = 0 Then
                        UpdateStatsLine(
                            (GetTickCount - StatusStartTick) Div 1000,
                            StatusRequestCount,
                            StatusTotalAltiumMs,
                            (AutoShutdownMs - (GetTickCount - MCPLastActivityMs)) Div 1000);
                End;
            End;

            { Adaptive pacing survives as an INTERVAL change, which is strictly }
            { better than sleeping: the thread is genuinely free between ticks. }
            SetMCPTimerInterval(MCPCurrentInterval);

            { A clean tick clears the streak, so only CONSECUTIVE faults count. }
            MCPFaultStreak := 0;
        Except
            Inc(MCPFaultStreak);
            Try
                AppendLog(FormatLogStamp(0) + ',0,_tick_exception,streak='
                    + IntToStr(MCPFaultStreak));
            Except End;
            If MCPFaultStreak >= MCP_MAX_FAULT_STREAK Then
            Begin
                MCPLoopFailed := True;
                MCPStopReason := 'loop-exception';
                Running := False;
                FinaliseMCPServer(0);
            End;
        End;
    Finally
        MCPInTick := False;
    End;
End;


{ Create the timer if needed, bind the handler, and start it. Defined here     }
{ rather than beside the other two because it names tmr_MCPTimer, which must   }
{ already exist at this point in the file.                                      }
{                                                                              }
{ The OnTimer assignment is the whole reason this timer is not a DFM component:}
{ binding it HERE, in the same unit as the handler, is the one arrangement that}
{ can work. Result is read back from Enabled rather than assumed, so a failure }
{ to create or bind surfaces as timer-arm-failed instead of a silently dead    }
{ bridge - which is exactly how the DFM attempt failed on 2026-09-24.          }
Function ArmMCPTimer(IntervalMs : Integer) : Boolean;
Begin
    Result := False;
    Try
        If MCPTimerObj = Nil Then MCPTimerObj := TTimer.Create(Nil);
        MCPTimerObj.Enabled  := False;
        MCPTimerObj.Interval := IntervalMs;
        MCPTimerObj.OnTimer  := tmr_MCPTimer;
        MCPTimerObj.Enabled  := True;
        Result := MCPTimerObj.Enabled;
    Except End;
End;


Procedure StartMCPServer;
Begin
    If Running Then Exit;
    MCPHostClosing := False;
    MCPStopReason := 'stop-requested';
    MCPLoopFailed := False;
    MCPInTick := False;
    MCPFaultStreak := 0;
    MCPTickCount := 0;
    If Not MCPHostAvailable(0) Then Exit;

    InitDefaultConfig(0);
    EnsureWorkspaceDir(0);
    LoadMCPConfig(0);
    { Startup purge: nothing on disk can belong to a live exchange, because no
      loop was running to serve it. Responses are purged here but NOT in
      CleanupMCPServer(0) -- on shutdown a client may still be reading one. }
    CleanupOrphanRequests(0);
    CleanupOrphanResponses(0);
    CleanupOrphanProgress(0);
    Running := True;
    MCPStopPath := WorkspaceDir + 'stop';
    If FileExists(MCPStopPath) Then DeleteFile(MCPStopPath);

    MCPIdleCount := 0;
    MCPCurrentInterval := PollIntervalActiveMs;
    MCPLastActivityMs := GetTickCount;

    StatusStartTick := GetTickCount;
    StatusRequestCount := 0;
    StatusLastCommand := '';
    StatusTotalAltiumMs := 0;
    If SELECTED_PROJECT_READ_ONLY Then InitSelectedProject(0);
    ShowStatusForm(0);
    UpdateStatusHeader('MCP: idle');
    UpdateStatsLine(0, 0, 0, AutoShutdownMs Div 1000);
    AppendLog(FormatLogStamp(0) + ',0,_session_start,version=' + SCRIPT_VERSION
              + ',protocol=' + IntToStr(PROTOCOL_VERSION) + ',dispatch=timer');
    { YieldIterations and YieldEveryNActive are DEAD CONFIG under timer         }
    { dispatch - they only ever rationed Sleep and ProcessMessages calls, and   }
    { neither exists now. Still parsed so an existing mcp_config.json keeps     }
    { loading; say so once rather than letting a tuned value look effective.    }
    If (YieldIterations <> 0) Or (YieldEveryNActive <> 0) Then
        AppendLog(FormatLogStamp(0) + ',0,_config_ignored,'
            + 'yield_iterations_and_yield_every_n_active_are_unused_under_timer_dispatch');

    { ARM AND RETURN. Returning is the fix: Altium's own message loop resumes,  }
    { nothing holds the thread, and the keyboard behaves normally. Everything   }
    { the loop used to do now happens in tmr_MCPTimer.                          }
    { ArmMCPTimer returns whether the timer is ACTUALLY enabled afterwards,     }
    { read back rather than assumed - the same trap the P2 probe hit. Without   }
    { that check a missing control leaves a session that logged _session_start, }
    { set Running := True, and will never serve a request: a bridge that looks  }
    { up and is dead. Fail loudly instead.                                      }
    If Not ArmMCPTimer(MCPCurrentInterval) Then
    Begin
        MCPLoopFailed := True;
        MCPStopReason := 'timer-arm-failed';
        Running := False;
        FinaliseMCPServer(0);
    End;
End;


{..............................................................................}
{ Write the 'stop' file so a running StartMCPServer exits on its next poll.   }
{                                                                              }
{ HIDDEN FROM THE RUN SCRIPT DIALOG, because it cannot be useful there.       }
{ The scripting engine runs one script at a time, so while the polling loop   }
{ holds it there is no way to pick this out of the dialog and run it, and     }
{ when the loop is NOT running there is nothing to stop: the sentinel would   }
{ just sit there, and StartMCPServer deletes a stale one at startup anyway.   }
{                                                                              }
{ Nothing calls it. Python stops the loop with the application.stop_server    }
{ COMMAND, and the dashboard's Detach button sets Running := False directly,  }
{ which is the same result by a shorter route. It is kept rather than deleted }
{ because the sentinel it writes is the documented out-of-band stop and a     }
{ future caller may want it; the argument keeps it out of a list of four      }
{ things a human is choosing between.                                          }
{..............................................................................}

Procedure StopMCPServer(Dummy : Integer);
Var
    StopPath : String;
    F : TextFile;
Begin
    EnsureWorkspaceDir(0);
    StopPath := WorkspaceDir + 'stop';
    Try
        AssignFile(F, StopPath);
        Rewrite(F);
        Writeln(F, '1');
        CloseFile(F);
        ShowMessage('MCP server stop signal sent. The server will exit within 500ms.');
    Except
        ShowMessage('Failed to write stop file: ' + StopPath);
    End;
End;
