{ Standalone lifecycle probe. No CAD, host Client, or MCP access. }
{ Deploy a copy with @LOG_DIRECTORY@ replaced by a dedicated absolute folder. }
Const
    ProbeLogDirectory = '@LOG_DIRECTORY@';
    ProbeTickLimit = 1800;

Var
    ProbeRunning : Boolean;
    ProbeLogFailed : Boolean;
    ProbeLogPath : String;
    ProbeSequence : Integer;

Procedure ProbeRecord(EventName : String);
Var
    F : TextFile;
Begin
    If ProbeLogFailed Then Exit;
    If ProbeLogPath = '' Then Exit;
    Try
        AssignFile(F, ProbeLogPath);
        Append(F);
        Try
            Inc(ProbeSequence);
            WriteLn(F, IntToStr(ProbeSequence) + ',' + EventName);
        Finally
            CloseFile(F);
        End;
    Except
        { Stop if evidence cannot be recorded. Do not show a modal here. }
        ProbeLogFailed := True;
        ProbeRunning := False;
    End;
End;

Procedure ProbeFormCloseQuery(Sender : TObject; Var CanClose : Boolean);
Begin
    ProbeRunning := False;
    ProbeRecord('form_close_query');
    CanClose := True;
End;

Procedure ProbeFormClose(Sender : TObject; Var Action : TCloseAction);
Begin
    ProbeRunning := False;
    ProbeRecord('form_close');
End;

Procedure ProbeFormDestroy(Sender : TObject);
Begin
    ProbeRunning := False;
    ProbeRecord('form_destroy');
End;

Procedure ProbeStopClick(Sender : TObject);
Begin
    ProbeRunning := False;
    ProbeRecord('stop_button');
    { No Hide/Close/Client call: leave UI cleanup out of the experiment. }
End;

Procedure RunShutdownProbe;
Var
    F : TextFile;
    Tick : Integer;
Begin
    If ProbeRunning Then Exit;
    ProbeRunning := False;
    ProbeLogFailed := False;
    ProbeSequence := 0;
    ProbeLogPath := '';
    If Pos('@', ProbeLogDirectory) > 0 Then
    Begin
        ShowMessage('Use the configured diagnostic copy, not the source template.');
        Exit;
    End;
    Try
        ForceDirectories(ProbeLogDirectory);
        ProbeLogPath := ProbeLogDirectory + '\probe-'
            + FormatDateTime('yyyymmdd-hhnnss-zzz', Now) + '.log';
        If FileExists(ProbeLogPath) Then
        Begin
            ProbeLogPath := '';
            ShowMessage('Log name already exists. Wait a second and retry.');
            Exit;
        End;
        AssignFile(F, ProbeLogPath);
        Rewrite(F);
        Try
            WriteLn(F, 'probe_version=1; events are sequence-numbered, not timestamps');
        Finally
            CloseFile(F);
        End;
    Except
        ProbeLogPath := '';
        ShowMessage('Cannot create diagnostic log. Check the configured log directory.');
        Exit;
    End;

    ProbeRecord('run_start');
    If ProbeLogFailed Then Exit;
    ProbeRunning := True;
    Try
        ShutdownProbeForm.Show;
        ProbeRecord('form_shown');
        For Tick := 1 To ProbeTickLimit Do
        Begin
            If Not ProbeRunning Then Break;
            ProbeRecord('before_yield');
            If Not ProbeRunning Then Break;
            Application.ProcessMessages;
            { First operation after yielding: local stop flag, never a host query. }
            If Not ProbeRunning Then
            Begin
                ProbeRecord('after_yield_stopped');
                Break;
            End;
            ProbeRecord('after_yield_running');
            If Not ProbeRunning Then Break;
            Sleep(100);
        End;
        If ProbeRunning Then ProbeRecord('tick_limit');
    Except
        ProbeRunning := False;
        ProbeRecord('loop_exception');
        ProbeRecord('run_aborted');
        Exit;
    End;
    ProbeRunning := False;
    ProbeRecord('run_end');
    { No host query, form access, ProcessMessages, or Sleep after this point. }
End;
