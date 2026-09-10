{ Shared read-only selection. Loaded after Project and before StatusForm/Dispatcher.
  No project opens, focus changes, saves or writes. UI is the only selection grant. }
Var
    SelectedPath : String;
    SelectedSession : String;
    SelectedGeneration : Integer;
    SelectedReference : IProject;
    SelectedBusy : Boolean;

Procedure ClearSelectedProject(Dummy : Integer);
Begin
    SelectedPath := '';
    SelectedReference := Nil;
    Inc(SelectedGeneration);
    SelectedCompileReady := False;
    SelectedCompileProject := Nil;
    InvalidateCompileCache(0);
End;

Procedure InitSelectedProject(Dummy : Integer);
Begin
    SelectedGeneration := 0;
    SelectedBusy := False;
    SelectedSession := FormatDateTime('yyyymmddhhnnsszzz', Now)
        + '-' + IntToStr(GetTickCount);
    ClearSelectedProject(0);
End;

Function OpenSelectedCandidate(Path : String) : IProject;
Var
    W : IWorkspace;
Begin
    Result := Nil;
    If Not LooksAbsolutePath(Path) Then Exit;
    If LowerCase(ExtractFileExt(Path)) <> '.prjpcb' Then Exit;
    If Not FileExists(Path) Then Exit;
    W := GetWorkspace;
    If W = Nil Then Exit;
    Result := FindProjectByPath(W, Path);
End;

Function CurrentSelectedProject(Dummy : Integer) : IProject;
Var
    Candidate : IProject;
Begin
    Result := Nil;
    If SelectedPath = '' Then Exit;
    Candidate := OpenSelectedCandidate(SelectedPath);
    { Compare interface identity without dereferencing the retained old object. }
    If (Candidate = Nil) Or (Candidate <> SelectedReference) Then
    Begin
        ClearSelectedProject(0);
        Exit;
    End;
    Result := Candidate;
End;

Function UseSelectedProject(Path : String) : Boolean;
Var
    Candidate : IProject;
Begin
    Result := False;
    If SelectedBusy Then Exit;
    Candidate := OpenSelectedCandidate(Path);
    ClearSelectedProject(0);
    If Candidate = Nil Then Exit;
    SelectedPath := Candidate.DM_ProjectFullPath;
    SelectedReference := Candidate;
    Result := True;
End;

Function SelectionJSON(Dummy : Integer) : String;
Var
    P : IProject;
Begin
    P := CurrentSelectedProject(0);
    Result := '{"project_path":"' + EscapeJsonString(SelectedPath)
        + '","session":"' + EscapeJsonString(SelectedSession)
        + '","generation":' + IntToStr(SelectedGeneration)
        + ',"access":"read-only","selected":' + BoolToJsonStr(P <> Nil) + '}';
End;

Function SelectedProjectsJSON(Dummy : Integer) : String;
Var
    W : IWorkspace;
    P : IProject;
    I, Count : Integer;
    Path, Body : String;
Begin
    W := GetWorkspace;
    Body := '';
    Count := 0;
    If W <> Nil Then
        For I := 0 To W.DM_ProjectCount - 1 Do
        Begin
            P := W.DM_Projects(I);
            If P <> Nil Then
            Begin
                Path := P.DM_ProjectFullPath;
                If LooksAbsolutePath(Path) And
                   (LowerCase(ExtractFileExt(Path)) = '.prjpcb') And FileExists(Path) Then
                Begin
                    If Count > 0 Then Body := Body + ',';
                    Body := Body + '{"project_name":"' + EscapeJsonString(ExtractFileName(Path))
                        + '","project_path":"' + EscapeJsonString(Path) + '"}';
                    Inc(Count);
                End;
            End;
        End;
    Result := '{"projects":[' + Body + '],"count":' + IntToStr(Count) + '}';
End;

{ Names the documents that break identity when SelectedFreshnessJSON gives
  up: a nil member or one whose DM_FullPath is not absolute (an unsaved new
  sheet carries only its virtual name). Diagnostic names only - content reads
  stay refused while any such member exists; this merely tells the operator
  WHICH document to save or discard instead of a bare INCOMPLETE_DOCUMENTS. }
Function SelectedIdentityProblems(Project : IProject) : String;
Var
    I : Integer;
    D : IDocument;
    Path : String;
Begin
    Result := '';
    If Project = Nil Then Exit;
    For I := 0 To Project.DM_LogicalDocumentCount - 1 Do
    Begin
        D := Project.DM_LogicalDocuments(I);
        If D = Nil Then
        Begin
            If Result <> '' Then Result := Result + ', ';
            Result := Result + 'document #' + IntToStr(I) + ' unresolved';
            Continue;
        End;
        Path := D.DM_FullPath;
        If Not LooksAbsolutePath(Path) Then
        Begin
            If Result <> '' Then Result := Result + ', ';
            Result := Result + 'unsaved/identityless: ' + Path;
        End;
    End;
End;

Function SelectedFreshnessJSON(Project : IProject) : String;
Var
    I, DirtyCount, OpenCount : Integer;
    D : IDocument;
    S : IServerDocument;
    Path, DirtyList : String;
Begin
    DirtyCount := 0;
    OpenCount := 0;
    DirtyList := '';
    For I := 0 To Project.DM_LogicalDocumentCount - 1 Do
    Begin
        D := Project.DM_LogicalDocuments(I);
        If D = Nil Then Begin Result := ''; Exit; End;
        Path := D.DM_FullPath;
        If Not LooksAbsolutePath(Path) Then Begin Result := ''; Exit; End;
        S := Client.GetDocumentByPath(Path);
        If S <> Nil Then
        Begin
            Inc(OpenCount);
            If S.Modified Then
            Begin
                If DirtyCount > 0 Then DirtyList := DirtyList + ',';
                DirtyList := DirtyList + '"' + EscapeJsonString(Path) + '"';
                Inc(DirtyCount);
            End;
        End;
    End;
    Result := '{"project":"' + EscapeJsonString(SelectedPath)
        + '","dirty_doc_count":' + IntToStr(DirtyCount)
        + ',"open_doc_count":' + IntToStr(OpenCount)
        + ',"dirty_docs":[' + DirtyList + ']}';
End;

Function SelectedDocumentsJSON(Project : IProject) : String;
Var
    I : Integer;
    D : IDocument;
    Body, Path : String;
Begin
    Body := '';
    For I := 0 To Project.DM_LogicalDocumentCount - 1 Do
    Begin
        D := Project.DM_LogicalDocuments(I);
        If D = Nil Then Begin Result := ''; Exit; End;
        Path := D.DM_FullPath;
        If Not LooksAbsolutePath(Path) Then Begin Result := ''; Exit; End;
        If I > 0 Then Body := Body + ',';
        Body := Body + '{"file_path":"' + EscapeJsonString(Path)
            + '","document_kind":"' + EscapeJsonString(D.DM_DocumentKind) + '"}';
    End;
    Result := '{"documents":[' + Body + '],"count":'
        + IntToStr(Project.DM_LogicalDocumentCount) + '}';
End;

{ PCB read scope: resolves the selected project's OWN PcbDoc as a live board.
  Fail-closed: exactly one PcbDoc member, already open in the PCB editor (the
  operator opens it - no auto-open, no focus change, unlike the upstream
  GetPCBBoardAnywhere which prefers the focused tab and force-opens documents
  across every project). PCBServer is only referenced once an open .PcbDoc
  proves the PCB server module is registered (the hazard GetPCBBoardAnywhere
  documents). PCB reads return LIVE editor state including unsaved edits;
  pcb_modified in the result says which it was. }
Function ResolveSelectedBoard(Project : IProject; Var PcbPath : String;
    Var PcbModified : Boolean; Var ErrCode : String; Var ErrMsg : String) : IPCB_Board;
Var
    I : Integer;
    D : IDocument;
    Path : String;
    S : IServerDocument;
Begin
    Result := Nil;
    PcbPath := '';
    PcbModified := True;
    ErrCode := '';
    ErrMsg := '';
    For I := 0 To Project.DM_LogicalDocumentCount - 1 Do
    Begin
        D := Project.DM_LogicalDocuments(I);
        If D = Nil Then Continue;
        If UpperCase(D.DM_DocumentKind) <> 'PCB' Then Continue;
        Path := D.DM_FullPath;
        If PcbPath <> '' Then
        Begin
            ErrCode := 'AMBIGUOUS_PCB';
            ErrMsg := 'Selected project has more than one PcbDoc member';
            PcbPath := '';
            Exit;
        End;
        PcbPath := Path;
    End;
    If PcbPath = '' Then
    Begin
        ErrCode := 'NO_PCB_MEMBER';
        ErrMsg := 'Selected project has no PcbDoc member';
        Exit;
    End;
    If Not LooksAbsolutePath(PcbPath) Then
    Begin
        ErrCode := 'PCB_UNSAVED';
        ErrMsg := 'Selected project PcbDoc has no saved identity: ' + PcbPath;
        Exit;
    End;
    S := Client.GetDocumentByPath(PcbPath);
    If S = Nil Then
    Begin
        ErrCode := 'PCB_NOT_OPEN';
        ErrMsg := 'Open the selected project PcbDoc in Altium first: ' + PcbPath;
        Exit;
    End;
    Try PcbModified := S.Modified; Except PcbModified := True; End;
    Try Result := PCBServer.GetPCBBoardByPath(PcbPath); Except Result := Nil; End;
    If Result = Nil Then
    Begin
        ErrCode := 'PCB_NOT_AVAILABLE';
        ErrMsg := 'PCB editor did not resolve the selected PcbDoc: ' + PcbPath;
    End;
End;

Function IsSelectedPcbReadCommand(Command : String) : Boolean;
Begin
    Result := (Command = 'pcb.get_component_placements')
        Or (Command = 'pcb.get_board_outline')
        Or (Command = 'pcb.get_layer_stackup')
        Or (Command = 'pcb.get_differential_pairs')
        Or (Command = 'pcb.get_diff_pair_rules');
End;

Function ProcessSelectedCommand(Command, Params, RequestId : String) : String;
Var
    P : IProject;
    Binding, SafeParams, Body, Reply, Freshness : String;
    ExpectedSession, ExpectedGeneration, ExpectedPath : String;
    LimitValue : Integer;
    Compiled : Boolean;
    Board : IPCB_Board;
    PcbPath, PcbErrCode, PcbErrMsg : String;
    PcbModified : Boolean;
Begin
    { This is the complete native allowlist in shared mode, not just MCP filtering. }
    If Command = 'application.ping' Then
    Begin
        Result := BuildSuccessResponse(RequestId, '{"pong":true,"script_version":"'
            + SCRIPT_VERSION + '","plt_profile":"eda-selected-readonly-v1"'
            + ',"selection_api":1,"selection":' + SelectionJSON(0) + '}');
        Exit;
    End;
    If Command = 'selection.get_projects' Then
    Begin
        Result := BuildSuccessResponse(RequestId, SelectedProjectsJSON(0));
        Exit;
    End;
    If Command = 'selection.get_selected' Then
    Begin
        Result := BuildSuccessResponse(RequestId, SelectionJSON(0));
        Exit;
    End;
    If (Command <> 'project.get_documents') And
       (Command <> 'project.get_compile_freshness') And
       (Command <> 'project.get_bom') And (Command <> 'project.get_nets') And
       (Command <> 'project.get_component_info') And
       (Command <> 'project.get_component_info_batch') And
       (Not IsSelectedPcbReadCommand(Command)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'READ_ONLY', 'Command unavailable in selected-project read-only mode');
        Exit;
    End;
    P := CurrentSelectedProject(0);
    ExpectedSession := ExtractJsonValue(Params, 'selection_session');
    ExpectedGeneration := ExtractJsonValue(Params, 'selection_generation');
    ExpectedPath := ExtractJsonValue(Params, 'project_path');
    If (P = Nil) Or (ExpectedSession <> SelectedSession) Or
       (ExpectedGeneration <> IntToStr(SelectedGeneration)) Or
       (UpperCase(ExpectedPath) <> UpperCase(SelectedPath)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'SELECTION_CHANGED', 'Select a project in Altium; stale requests are not redirected');
        Exit;
    End;
    Binding := SelectionJSON(0);
    SafeParams := '{"project_path":"' + EscapeJsonString(SelectedPath) + '"';
    SelectedBusy := True;
    Try
        Compiled := (Command = 'project.get_bom') Or (Command = 'project.get_nets');
        Freshness := SelectedFreshnessJSON(P);
        If Freshness = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P)
                + '); save or discard the named document');
            Exit;
        End;
        If Compiled Then
        Begin
            If ExtractJsonValue(Freshness, 'dirty_doc_count') <> '0' Then
            Begin
                Result := BuildErrorResponse(RequestId, 'DIRTY_PROJECT', 'Save intended edits manually before compiled reads');
                Exit;
            End;
            LimitValue := StrToIntDef(ExtractJsonValue(Params, 'limit'), 0);
            If (LimitValue < 1) Or (LimitValue > 50000) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'INVALID_LIMIT', 'Expected bounded positive limit');
                Exit;
            End;
            SafeParams := SafeParams + ',"limit":' + IntToStr(LimitValue);
            { Compile may pump native UI. Re-resolve before a handler reads objects. }
            P.DM_Compile;
            If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'SELECTION_CHANGED', 'Project changed during compile');
                Exit;
            End;
            Freshness := SelectedFreshnessJSON(P);
            If ExtractJsonValue(Freshness, 'dirty_doc_count') <> '0' Then
            Begin
                Result := BuildErrorResponse(RequestId, 'DIRTY_PROJECT', 'Project changed during compile');
                Exit;
            End;
            SelectedCompileProject := P;
            SelectedCompileReady := True;
        End;
        If Command = 'project.get_component_info' Then
            SafeParams := SafeParams + ',"designator":"'
                + EscapeJsonString(ExtractJsonValue(Params, 'designator'))
                + '","with_pin_nets":"false","with_parameters":"true"';
        { Bulk parameter read: the reviewed batch handler in its uncompiled
          parameters-only mode (same flags as the single lookup above). The
          Python client validates each designator and joins with '~~'. }
        If Command = 'project.get_component_info_batch' Then
            SafeParams := SafeParams + ',"designators":"'
                + EscapeJsonString(ExtractJsonValue(Params, 'designators'))
                + '","with_pin_nets":"false","with_parameters":"true"';
        SafeParams := SafeParams + '}';
        If IsSelectedPcbReadCommand(Command) Then
        Begin
            Board := ResolveSelectedBoard(P, PcbPath, PcbModified, PcbErrCode, PcbErrMsg);
            If Board = Nil Then
            Begin
                Result := BuildErrorResponse(RequestId, PcbErrCode, PcbErrMsg);
                Exit;
            End;
            If Command = 'pcb.get_component_placements' Then
                Reply := PCB_GetComponentsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_board_outline' Then
                Reply := PCB_GetBoardOutlineForBoard(Board, RequestId)
            Else If Command = 'pcb.get_layer_stackup' Then
                Reply := PCB_GetLayerStackupForBoard(Board, RequestId)
            Else If Command = 'pcb.get_differential_pairs' Then
                Reply := PCB_GetDifferentialPairsForBoard(Board, RequestId)
            Else
                Reply := PCB_GetDiffPairRulesForBoard(Board, RequestId);
            If ExtractJsonValue(Reply, 'success') <> 'true' Then
            Begin
                Result := Reply;
                Exit;
            End;
            Body := ExtractJsonValue(Reply, 'data');
            { Live-state honesty: splice the source document and its dirty
              state into the result so a caller can tell saved from live. }
            If Body = '{}' Then
                Body := '{"pcb_doc":"' + EscapeJsonString(PcbPath)
                    + '","pcb_modified":' + BoolToJsonStr(PcbModified) + '}'
            Else If (Body <> '') And (Copy(Body, 1, 1) = '{') Then
                Body := '{"pcb_doc":"' + EscapeJsonString(PcbPath)
                    + '","pcb_modified":' + BoolToJsonStr(PcbModified) + ','
                    + Copy(Body, 2, Length(Body) - 1);
        End
        Else If Command = 'project.get_documents' Then Body := SelectedDocumentsJSON(P)
        Else If Command = 'project.get_compile_freshness' Then Body := Freshness
        Else
        Begin
            If Command = 'project.get_bom' Then Reply := Proj_GetBOM(SafeParams, RequestId)
            Else If Command = 'project.get_nets' Then Reply := Proj_GetNets(SafeParams, RequestId)
            Else If Command = 'project.get_component_info_batch' Then Reply := Proj_GetComponentInfoBatch(SafeParams, RequestId)
            Else Reply := Proj_GetComponentInfo(SafeParams, RequestId);
            If ExtractJsonValue(Reply, 'success') <> 'true' Then
            Begin
                Result := Reply;
                Exit;
            End;
            Body := ExtractJsonValue(Reply, 'data');
        End;
        If Body = '' Then
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_RESULT', 'Selected-project read returned no data')
        Else If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'SELECTION_CHANGED', 'Project changed during read; discard result')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding + ',"result":' + Body + '}');
    Finally
        SelectedCompileReady := False;
        SelectedCompileProject := Nil;
        SelectedBusy := False;
    End;
End;
