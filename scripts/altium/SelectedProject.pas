{ Shared read-only selection. Loaded after Project and before StatusForm/Dispatcher.
  No project opens, focus changes, saves or writes. UI is the only selection grant. }
Var
    SelectedPath : String;
    SelectedSession : String;
    SelectedGeneration : Integer;
    SelectedReference : IProject;
    SelectedBusy : Boolean;
    { Checked parameter edits: set only by the operator's status-form tick, }
    { valid only for the selection generation it was ticked in. }
    ParamEditGrant : Boolean;
    ParamEditGrantGeneration : Integer;
    { Checked placement edits: the same rules, a grant of their own. }
    PlaceEditGrant : Boolean;
    PlaceEditGrantGeneration : Integer;
    { When each grant was ticked (GetTickCount). A tick that no apply used     }
    { ends after GrantLimitMs (scripts 2026.11.25.2): on 2026-11-25 a tick     }
    { from the morning was still standing hours later.                         }
    ParamEditGrantTick : Integer;
    PlaceEditGrantTick : Integer;

Function GrantLimitMs(Dummy : Integer) : Integer;
Begin
    Result := 600000;
End;

{ True while a tick taken at Tick is younger than the limit. A negative age  }
{ (the counter wrapped) counts as expired.                                   }
Function GrantTickFresh(Tick : Integer) : Boolean;
Var
    Age : Integer;
Begin
    Age := GetTickCount - Tick;
    Result := (Age >= 0) And (Age <= GrantLimitMs(0));
End;

Procedure ClearSelectedProject(Dummy : Integer);
Begin
    SelectedPath := '';
    SelectedReference := Nil;
    ParamEditGrant := False;
    PlaceEditGrant := False;
    Inc(SelectedGeneration);
    SelectedCompileReady := False;
    SelectedCompileProject := Nil;
    InvalidateCompileCache(0);
End;

Procedure InitSelectedProject(Dummy : Integer);
Begin
    SelectedGeneration := 0;
    SelectedBusy := False;
    ParamEditGrantGeneration := -1;
    PlaceEditGrantGeneration := -1;
    ParamEditGrantTick := 0;
    PlaceEditGrantTick := 0;
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

Function ParamEditGrantActive(Dummy : Integer) : Boolean;
Begin
    If ParamEditGrant And (Not GrantTickFresh(ParamEditGrantTick)) Then ParamEditGrant := False;
    Result := SELECTED_PARAM_EDITS And ParamEditGrant
        And (ParamEditGrantGeneration = SelectedGeneration)
        And (SelectedPath <> '');
End;

{ Operator UI only (status form). Every change of the grant bumps the        }
{ selection generation, so a token or preview taken before it is refused.    }
Function ToggleParamEditGrant(Dummy : Integer) : Boolean;
Begin
    Result := False;
    If Not SELECTED_PARAM_EDITS Then Exit;
    If SelectedBusy Then Exit;
    If CurrentSelectedProject(0) = Nil Then
    Begin
        ParamEditGrant := False;
        Exit;
    End;
    ParamEditGrant := Not ParamEditGrant;
    ParamEditGrantTick := GetTickCount;
    Inc(SelectedGeneration);
    ParamEditGrantGeneration := SelectedGeneration;
    Result := True;
End;

Function PlaceEditGrantActive(Dummy : Integer) : Boolean;
Begin
    If PlaceEditGrant And (Not GrantTickFresh(PlaceEditGrantTick)) Then PlaceEditGrant := False;
    Result := SELECTED_PLACE_EDITS And PlaceEditGrant
        And (PlaceEditGrantGeneration = SelectedGeneration)
        And (SelectedPath <> '');
End;

{ Operator UI only. Like the parameter grant it bumps the generation, so the }
{ two grants can never be active at once: ticking one ends the other.         }
Function TogglePlaceEditGrant(Dummy : Integer) : Boolean;
Begin
    Result := False;
    If Not SELECTED_PLACE_EDITS Then Exit;
    If SelectedBusy Then Exit;
    If CurrentSelectedProject(0) = Nil Then
    Begin
        PlaceEditGrant := False;
        Exit;
    End;
    PlaceEditGrant := Not PlaceEditGrant;
    PlaceEditGrantTick := GetTickCount;
    Inc(SelectedGeneration);
    PlaceEditGrantGeneration := SelectedGeneration;
    Result := True;
End;

{ Seconds since each standing grant was ticked, -1 when it is not granted, and }
{ the limit (scripts 2026.11.25.2). In the ping, not in the selection object:   }
{ the clients compare that object for equality between calls.                   }
Function SelectedGrantAgesJson(Dummy : Integer) : String;
Var
    A, B : Integer;
Begin
    A := -1;
    B := -1;
    If ParamEditGrantActive(0) Then A := (GetTickCount - ParamEditGrantTick) Div 1000;
    If PlaceEditGrantActive(0) Then B := (GetTickCount - PlaceEditGrantTick) Div 1000;
    If A < -1 Then A := -1;
    If B < -1 Then B := -1;
    Result := '{"param_edits":' + IntToStr(A) + ',"place_edits":' + IntToStr(B)
        + ',"limit_s":' + IntToStr(GrantLimitMs(0) Div 1000) + '}';
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
        + ',"access":"read-only","selected":' + BoolToJsonStr(P <> Nil);
    { Only a param-edit runtime reports the grant, so the read-only runtime's }
    { selection identity stays byte-identical to before. }
    If SELECTED_PARAM_EDITS Then
    Begin
        If ParamEditGrantActive(0) Then
            Result := Result + ',"param_edits":"granted"'
        Else
            Result := Result + ',"param_edits":"off"';
    End;
    If SELECTED_PLACE_EDITS Then
    Begin
        If PlaceEditGrantActive(0) Then
            Result := Result + ',"place_edits":"granted"'
        Else
            Result := Result + ',"place_edits":"off"';
    End;
    Result := Result + '}';
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
    Path, DirtyList, OpenList, FocusPath, ActivePath : String;
    View : IServerDocumentView;
Begin
    DirtyCount := 0;
    OpenCount := 0;
    DirtyList := '';
    OpenList := '';
    ActivePath := '';
    { The focused document, as information only (scripts 2026.11.25.2): it is    }
    { reported when it is a member of the selected project and never selects     }
    { anything. Upstream reads the view the same way in Main.pas.                }
    FocusPath := '';
    Try
        View := Client.GetCurrentView;
        If View <> Nil Then FocusPath := View.OwnerDocument.FileName;
    Except
        FocusPath := '';
    End;
    For I := 0 To Project.DM_LogicalDocumentCount - 1 Do
    Begin
        D := Project.DM_LogicalDocuments(I);
        If D = Nil Then Begin Result := ''; Exit; End;
        Path := D.DM_FullPath;
        If Not LooksAbsolutePath(Path) Then Begin Result := ''; Exit; End;
        S := Client.GetDocumentByPath(Path);
        If S <> Nil Then
        Begin
            If OpenCount > 0 Then OpenList := OpenList + ',';
            OpenList := OpenList + '"' + EscapeJsonString(Path) + '"';
            Inc(OpenCount);
            If (FocusPath <> '') And (UpperCase(FocusPath) = UpperCase(Path)) Then ActivePath := Path;
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
        + ',"dirty_docs":[' + DirtyList + ']'
        + ',"open_docs":[' + OpenList + ']'
        + ',"active_doc":"' + EscapeJsonString(ActivePath) + '"}';
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
        Or (Command = 'pcb.get_diff_pair_rules')
        Or (Command = 'pcb.get_vias')
        Or (Command = 'pcb.get_texts')
        Or (Command = 'pcb.get_free_graphics')
        Or (Command = 'pcb.get_tracks')
        Or (Command = 'pcb.get_polygons')
        Or (Command = 'pcb.get_unrouted_nets')
        Or (Command = 'pcb.get_layer_primitive_counts')
        Or (Command = 'pcb.get_net_classes')
        Or (Command = 'pcb.get_object_classes')
        Or (Command = 'pcb.get_room_rules')
        Or (Command = 'pcb.get_clearance_violations')
        Or (Command = 'pcb.get_design_rules')
        Or (Command = 'pcb.get_trace_lengths')
        Or (Command = 'pcb.get_selected_objects')
        Or (Command = 'pcb.get_component_pads')
        Or (Command = 'pcb.get_board_statistics')
        Or (Command = 'pcb.audit_signal_vias_without_return')
        Or (Command = 'pcb.audit_via_antennas')
        Or (Command = 'pcb.audit_components_outside_outline')
        Or (Command = 'pcb.audit_pads_near_edge')
        Or (Command = 'pcb.audit_mixed_designator_rotation')
        Or (Command = 'pcb.audit_mirrored_text');
End;

{ ---- Checked parameter edits ----------------------------------------------- }
{ PROPOSAL-2026-09-28-metadata-write-increment: Gate 3's first slice. The code }
{ is in every runtime, but the command is reachable only when the runtime was  }
{ generated with SELECTED_PARAM_EDITS = True, and apply additionally needs the }
{ operator's session grant (status form checkbox). No command sets the grant,  }
{ so an agent cannot approve its own writes.                                   }
{                                                                              }
{ Fixes the audited upstream handler's F1-F7: exact sheet only, never the      }
{ focused one (F1); one named, EXISTING parameter per edit, matched by exact  }
{ name, never Designator, Footprint or a component property (F2; widened from }
{ LCSC Part # / Instruction on 2026-10-05, Stefan); blank is an ordinary value }
{ (F3); every value percent-encoded                                            }
{ (F4); per-field status with the text read back from the object (F5, F7);     }
{ existing parameters only, nothing created (F6). Never saves (F9).            }

Function ParamEditSafeChar(Ch : String) : Boolean;
Begin
    Result := (Length(Ch) = 1) And (Pos(Ch,
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-') > 0);
End;

{ Values cross as printable ASCII with every byte outside [A-Za-z0-9 ._-]      }
{ written %XX. A raw separator, a bad escape, a control or non-ASCII byte      }
{ fails the batch: nothing is guessed at. One exception since 2026.11.17.5:    }
{ %B5, the micro sign (U+00B5, below 256 so Chr makes it exactly). An Ohm sign }
{ (above 255, where Chr is unreliable per upstream f552f69) stays refused.     }
Function ParamEditDecode(S : String; Var Ok : Boolean) : String;
Var
    I, Hi, Lo, Code : Integer;
    Ch : String;
Begin
    Result := '';
    Ok := True;
    I := 1;
    While I <= Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        If Ch = '%' Then
        Begin
            If I + 2 > Length(S) Then
            Begin
                Ok := False;
                Exit;
            End;
            Hi := HexDigitValue(Copy(S, I + 1, 1));
            Lo := HexDigitValue(Copy(S, I + 2, 1));
            If (Hi < 0) Or (Lo < 0) Then
            Begin
                Ok := False;
                Exit;
            End;
            Code := Hi * 16 + Lo;
            If ((Code < 32) Or (Code > 126)) And (Code <> 181) Then
            Begin
                Ok := False;
                Exit;
            End;
            Result := Result + Chr(Code);
            I := I + 3;
        End
        Else If ParamEditSafeChar(Ch) Then
        Begin
            Result := Result + Ch;
            Inc(I);
        End
        Else
        Begin
            Ok := False;
            Exit;
        End;
    End;
End;

{ Returns Rest up to the first Sep and leaves the remainder in Rest. }
Function ParamEditTake(Var Rest : String; Sep : String) : String;
Var
    P : Integer;
Begin
    P := Pos(Sep, Rest);
    If P = 0 Then
    Begin
        Result := Rest;
        Rest := '';
    End
    Else
    Begin
        Result := Copy(Rest, 1, P - 1);
        Rest := Copy(Rest, P + Length(Sep), Length(Rest));
    End;
End;

Function ParamEditCountChar(S, Ch : String) : Integer;
Var
    I : Integer;
Begin
    Result := 0;
    For I := 1 To Length(S) Do
        If Copy(S, I, 1) = Ch Then Inc(Result);
End;

{ Any existing parameter by exact name, printable ASCII, 1-64 characters, except }
{ the names that are not parameters (Designator, Footprint, component          }
{ properties shown in the parameter table). Widened 2026-10-05 (Stefan) from    }
{ LCSC Part # / Instruction; the finder still never creates a parameter.        }
Function ParamEditFieldAllowed(Field : String) : Boolean;
Var
    I, C : Integer;
    Ch, U : String;
Begin
    Result := (Length(Field) >= 1) And (Length(Field) <= 64);
    If Not Result Then Exit;
    For I := 1 To Length(Field) Do
    Begin
        Ch := Copy(Field, I, 1);
        C := Ord(Ch[1]);
        If (C < 32) Or (C > 126) Then
        Begin
            Result := False;
            Exit;
        End;
    End;
    U := '|' + UpperCase(Field) + '|';
    Result := Pos(U, '|DESIGNATOR|FOOTPRINT|COMPONENT KIND|LIBRARY REFERENCE|LIBRARY NAME|'
        + 'PIN INFO|SIGNAL INTEGRITY|SIMULATION|IBIS MODEL|PCB3D|') = 0;
End;

Function ParamEditHashValid(H : String) : Boolean;
Var
    I : Integer;
Begin
    Result := Length(H) = 64;
    If Not Result Then Exit;
    For I := 1 To 64 Do
        If HexDigitValue(Copy(H, I, 1)) < 0 Then
        Begin
            Result := False;
            Exit;
        End;
End;

{ The single schematic component with this designator on Doc, and its one     }
{ parameter named exactly Field. Hits counts the matching                      }
{ parameters; UniqueId is the component's. Nil unless exactly one parameter    }
{ matched. Iterators are destroyed before the caller touches the parameter,    }
{ as SetCompParamText does: find first, then modify.                           }
Function ParamEditFind(Doc : ISch_Document; Designator, Field : String;
    Var UniqueId : String; Var Hits : Integer) : ISch_Parameter;
Var
    Iter, PIter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
    Param, Found : ISch_Parameter;
Begin
    Result := Nil;
    Found := Nil;
    UniqueId := '';
    Hits := 0;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Comp := Obj;
            If Comp.Designator.Text = Designator Then
            Begin
                Try UniqueId := Comp.UniqueId; Except UniqueId := ''; End;
                PIter := Comp.SchIterator_Create;
                Try
                    PIter.AddFilter_ObjectSet(MkSet(eParameter));
                    Param := PIter.FirstSchObject;
                    While Param <> Nil Do
                    Begin
                        If Param.Name = Field Then
                        Begin
                            Inc(Hits);
                            Found := Param;
                        End;
                        Param := PIter.NextSchObject;
                    End;
                Finally
                    Comp.SchIterator_Destroy(PIter);
                End;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
    If Hits = 1 Then Result := Found;
End;

{ Params: mode (preview | apply), sheet_path (exact member SchDoc), batch_hash  }
{ (64 hex, echoed), edits: 'designator|field|old|new|unique_id;...', all five  }
{ parts percent-encoded. Preview ignores old and unique_id and reports what     }
{ each edit would do. Apply refuses the whole batch unless every old value and  }
{ every component UniqueId still match the preview (compare-and-set on value    }
{ AND identity, so a re-annotation between preview and apply cannot retarget   }
{ an edit). An apply that touched anything clears the grant: one tick, one      }
{ batch. Error codes returned before PreProcess are the pre-write set the       }
{ client treats as "nothing written"; CHANGED_DURING_WRITE is not one of them.  }
Function SelectedSetParamsChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, SheetPath, EditsStr, BatchHash, Rest, OpStr, Part, Key : String;
    D, F, O, N, U, Problems, EditsJson, Back, Status, Path, TargetPath, Binding, Blank, Uid : String;
    OpDes, OpField, OpOld, OpNew, OpUidReq, OpUid, OpCur, OpStatus, OpBack, OpTotal, OpTarget, OpHits, Keys : TStringList;
    I, J, Count, Hits, WouldWrite, Unchanged, Refused, Written, NotWritten : Integer;
    Ok, Apply, IsTarget, FoundSheet, TargetModified, Partial, Touched : Boolean;
    Doc : IDocument;
    S : IServerDocument;
    SchDoc, TargetDoc : ISch_Document;
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
    Param : ISch_Parameter;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    SheetPath := ExtractJsonValue(Params, 'sheet_path');
    EditsStr := ExtractJsonValue(Params, 'edits');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not ParamEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Parameter edits are not granted: the operator ticks "Allow parameter edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    If (Not LooksAbsolutePath(SheetPath)) Or (LowerCase(ExtractFileExt(SheetPath)) <> '.schdoc') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_SHEET', 'sheet_path must be an absolute .SchDoc path');
        Exit;
    End;
    Binding := SelectionJSON(0);
    { DelphiScript trips on a literal '' as a call argument. }
    Blank := '';
    Touched := False;
    OpDes := TStringList.Create;
    OpField := TStringList.Create;
    OpOld := TStringList.Create;
    OpNew := TStringList.Create;
    OpUidReq := TStringList.Create;
    OpUid := TStringList.Create;
    OpCur := TStringList.Create;
    OpStatus := TStringList.Create;
    OpBack := TStringList.Create;
    OpTotal := TStringList.Create;
    OpTarget := TStringList.Create;
    OpHits := TStringList.Create;
    Keys := TStringList.Create;
    SelectedBusy := True;
    Try
        If SelectedFreshnessJSON(P) = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P) + '); save or discard the named document');
            Exit;
        End;

        { Parse. A malformed batch is a client defect: refused in both modes. }
        Rest := EditsStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 200) Or (ParamEditCountChar(OpStr, '|') <> 4) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Edit ' + IntToStr(Count) + ': expected designator|field|old|new|unique_id, at most 200 edits');
                Exit;
            End;
            Part := ParamEditTake(OpStr, '|');
            D := ParamEditDecode(Part, Ok);
            If Ok Then
            Begin
                Part := ParamEditTake(OpStr, '|');
                F := ParamEditDecode(Part, Ok);
            End;
            If Ok Then
            Begin
                Part := ParamEditTake(OpStr, '|');
                O := ParamEditDecode(Part, Ok);
            End;
            If Ok Then
            Begin
                Part := ParamEditTake(OpStr, '|');
                N := ParamEditDecode(Part, Ok);
            End;
            If Ok Then
                U := ParamEditDecode(OpStr, Ok);
            If (Not Ok) Or (D = '') Or (Length(D) > 40) Or (Apply And (U = '')) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Edit ' + IntToStr(Count) + ': bad encoding, designator or unique_id');
                Exit;
            End;
            If Not ParamEditFieldAllowed(F) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'FIELD_NOT_ALLOWED',
                    'Edit ' + IntToStr(Count) + ' (' + D + '): "' + F + '" may not be written (Designator, Footprint and component properties are not parameters)');
                Exit;
            End;
            Key := D + '|' + F;
            If Keys.IndexOf(Key) >= 0 Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Duplicate edit: ' + D + ' ' + F);
                Exit;
            End;
            Keys.Add(Key);
            OpDes.Add(D);
            OpField.Add(F);
            OpOld.Add(O);
            OpNew.Add(N);
            OpUidReq.Add(U);
            OpUid.Add(Blank);
            OpCur.Add(Blank);
            OpStatus.Add(Blank);
            OpBack.Add(Blank);
            OpTotal.Add('0');
            OpTarget.Add('0');
            OpHits.Add('0');
        End;
        If OpDes.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No edits');
            Exit;
        End;

        { Every schematic of the project must be open: a designator is counted }
        { across all of them, so a multi-part component split over sheets or a }
        { duplicate cannot pass as the single target. Nothing is opened here.  }
        FoundSheet := False;
        TargetDoc := Nil;
        TargetPath := '';
        TargetModified := True;
        For I := 0 To P.DM_LogicalDocumentCount - 1 Do
        Begin
            Doc := P.DM_LogicalDocuments(I);
            If Doc = Nil Then Continue;
            If UpperCase(Doc.DM_DocumentKind) <> 'SCH' Then Continue;
            Path := Doc.DM_FullPath;
            S := Client.GetDocumentByPath(Path);
            If S = Nil Then
            Begin
                Result := BuildErrorResponse(RequestId, 'SHEET_NOT_OPEN',
                    'Open every schematic of the selected project first (not open: ' + Path + ')');
                Exit;
            End;
            SchDoc := Nil;
            Try SchDoc := SchServer.GetSchDocumentByPath(Path); Except SchDoc := Nil; End;
            If SchDoc = Nil Then
            Begin
                Result := BuildErrorResponse(RequestId, 'SHEET_NOT_AVAILABLE',
                    'Schematic editor did not resolve: ' + Path);
                Exit;
            End;
            IsTarget := (UpperCase(Path) = UpperCase(SheetPath));
            If IsTarget Then
            Begin
                FoundSheet := True;
                TargetDoc := SchDoc;
                TargetPath := Path;
                Try TargetModified := S.Modified; Except TargetModified := True; End;
            End;
            Iter := SchDoc.SchIterator_Create;
            Try
                Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
                Obj := Iter.FirstSchObject;
                While Obj <> Nil Do
                Begin
                    Comp := Obj;
                    For J := 0 To OpDes.Count - 1 Do
                        If Comp.Designator.Text = OpDes[J] Then
                        Begin
                            OpTotal[J] := IntToStr(StrToIntDef(OpTotal[J], 0) + 1);
                            If IsTarget Then
                                OpTarget[J] := IntToStr(StrToIntDef(OpTarget[J], 0) + 1);
                        End;
                    Obj := Iter.NextSchObject;
                End;
            Finally
                SchDoc.SchIterator_Destroy(Iter);
            End;
        End;
        If Not FoundSheet Then
        Begin
            Result := BuildErrorResponse(RequestId, 'SHEET_NOT_IN_PROJECT',
                'sheet_path is not a schematic of the selected project: ' + SheetPath);
            Exit;
        End;
        If Apply And TargetModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'SHEET_DIRTY',
                'The target sheet has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;

        { Read each targeted parameter from the objects an apply would write. }
        For J := 0 To OpDes.Count - 1 Do
            If OpTotal[J] = '1' Then
            Begin
                Param := ParamEditFind(TargetDoc, OpDes[J], OpField[J], Uid, Hits);
                OpHits[J] := IntToStr(Hits);
                OpUid[J] := Uid;
                If Param <> Nil Then OpCur[J] := Param.Text;
            End;

        { Classify. }
        Problems := '';
        Refused := 0;
        WouldWrite := 0;
        Unchanged := 0;
        For J := 0 To OpDes.Count - 1 Do
        Begin
            Status := '';
            If OpTotal[J] = '0' Then Status := 'refused: designator not found in the project'
            Else If OpTarget[J] = '0' Then Status := 'refused: designator is on another sheet'
            Else If OpTotal[J] <> '1' Then Status := 'refused: multi-part or duplicate designator (' + OpTotal[J] + ' symbols)'
            Else If OpHits[J] = '0' Then Status := 'refused: component has no ' + OpField[J] + ' parameter (none is created)'
            Else If OpHits[J] <> '1' Then Status := 'refused: ' + OpField[J] + ' appears ' + OpHits[J] + ' times'
            Else If Apply And (OpUid[J] <> OpUidReq[J]) Then Status := 'refused: component identity changed since preview'
            Else If Apply And (OpCur[J] <> OpOld[J]) Then Status := 'refused: changed since preview'
            Else If OpCur[J] = OpNew[J] Then Status := 'unchanged'
            Else Status := 'would_write';
            OpStatus[J] := Status;
            If Copy(Status, 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 600 Then
                    Problems := Problems + OpDes[J] + ' ' + OpField[J] + ': ' + Copy(Status, 10, 200) + '; ';
            End
            Else If Status = 'unchanged' Then Inc(Unchanged)
            Else Inc(WouldWrite);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED',
                'Nothing written. ' + Problems);
            Exit;
        End;

        { Apply: one PreProcess / PostProcess pair. Per edit: find, compare     }
        { identity and value again, then write and read back. Stops at the     }
        { first surprise; what was written is reported, never rolled back.     }
        Written := 0;
        NotWritten := 0;
        Partial := False;
        If Apply And (WouldWrite > 0) Then
        Begin
            SchServer.ProcessControl.PreProcess(TargetDoc, '');
            Try
                For J := 0 To OpDes.Count - 1 Do
                Begin
                    If Partial Or (OpStatus[J] <> 'would_write') Then Continue;
                    Param := ParamEditFind(TargetDoc, OpDes[J], OpField[J], Uid, Hits);
                    If (Param = Nil) Or (Uid <> OpUidReq[J]) Then
                    Begin
                        OpStatus[J] := 'not_written: changed during apply';
                        Partial := True;
                        Continue;
                    End;
                    If Param.Text <> OpOld[J] Then
                    Begin
                        OpStatus[J] := 'not_written: changed during apply';
                        Partial := True;
                        Continue;
                    End;
                    { From here on the object may differ from the file: the sheet }
                    { is marked dirty whatever the read-back says.               }
                    Touched := True;
                    SchBeginModify(Param);
                    Param.Text := OpNew[J];
                    SchEndModify(Param);
                    Back := Param.Text;
                    OpBack[J] := Back;
                    If Back = OpNew[J] Then
                    Begin
                        OpStatus[J] := 'written';
                        Inc(Written);
                    End
                    Else
                    Begin
                        OpStatus[J] := 'written_readback_differs';
                        Partial := True;
                    End;
                End;
            Finally
                Try SchServer.ProcessControl.PostProcess(TargetDoc, 'Edit'); Except End;
                Try TargetDoc.GraphicallyInvalidate; Except End;
                { A write that leaves the document clean did not happen as far   }
                { as Save and compile are concerned (upstream 69374c2).          }
                If Touched Then MarkDocDirtyByPath(TargetPath);
            End;
            For J := 0 To OpDes.Count - 1 Do
                If OpStatus[J] = 'would_write' Then
                Begin
                    OpStatus[J] := 'not_written';
                    Inc(NotWritten);
                End;
        End;

        EditsJson := '';
        For J := 0 To OpDes.Count - 1 Do
        Begin
            If J > 0 Then EditsJson := EditsJson + ',';
            EditsJson := EditsJson + '{"designator":"' + EscapeJsonString(OpDes[J])
                + '","field":"' + EscapeJsonString(OpField[J])
                + '","unique_id":"' + EscapeJsonString(OpUid[J])
                + '","current":"' + EscapeJsonString(OpCur[J])
                + '","new":"' + EscapeJsonString(OpNew[J])
                + '","status":"' + EscapeJsonString(OpStatus[J]) + '"';
            If Apply Then
                EditsJson := EditsJson + ',"old":"' + EscapeJsonString(OpOld[J])
                    + '","readback":"' + EscapeJsonString(OpBack[J]) + '"';
            EditsJson := EditsJson + '}';
        End;
        S := Client.GetDocumentByPath(TargetPath);
        If S <> Nil Then
            Try TargetModified := S.Modified; Except TargetModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again before trusting the sheet'
                + ' (written: ' + IntToStr(Written) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode
                + '","sheet_path":"' + EscapeJsonString(TargetPath)
                + '","batch_hash":"' + LowerCase(BatchHash)
                + '","edit_count":' + IntToStr(OpDes.Count)
                + ',"would_write":' + IntToStr(WouldWrite)
                + ',"unchanged":' + IntToStr(Unchanged)
                + ',"refused":' + IntToStr(Refused)
                + ',"written":' + IntToStr(Written)
                + ',"not_written":' + IntToStr(NotWritten)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"sheet_modified":' + BoolToJsonStr(TargetModified)
                + ',"saved":false,"edits":[' + EditsJson + ']}}');
    Finally
        { One tick, one batch: an apply that touched the sheet ends the grant. }
        { The generation moves with it, so the token used here is spent.       }
        If Touched Then
        Begin
            ParamEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        OpDes.Free;
        OpField.Free;
        OpOld.Free;
        OpNew.Free;
        OpUidReq.Free;
        OpUid.Free;
        OpCur.Free;
        OpStatus.Free;
        OpBack.Free;
        OpTotal.Free;
        OpTarget.Free;
        OpHits.Free;
        Keys.Free;
    End;
End;

{ ---- Checked placement edits ------------------------------------------------ }
{ PROPOSAL-2026-10-07-placement-write-increment. Reachable only when the runtime }
{ was generated with SELECTED_PLACE_EDITS = True; apply additionally needs the   }
{ operator's own placement grant (status form). Fixes the audited upstream       }
{ PCB_MoveComponent / PCB_BatchMoveComponents M1-M6 and M10: the selected        }
{ project's own PcbDoc only (ResolveSelectedBoard, never the focused board);     }
{ raw coordinates as integers, never mils; a malformed number refuses the batch  }
{ instead of becoming 0; locked parts, parts off the top layer and parts with    }
{ copper routing over them are refused; every refusal is named; rotation 0, 90,  }
{ 180 or 270 only; the side never changes. Never saves.                          }

Function PlaceEditIntOk(S : String) : Boolean;
Var
    I : Integer;
    Ch : String;
Begin
    Result := (Length(S) >= 1) And (Length(S) <= 12);
    If Not Result Then Exit;
    For I := 1 To Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        If (Ch = '-') And (I = 1) And (Length(S) > 1) Then Continue;
        If Pos(Ch, '0123456789') = 0 Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;

Function PlaceEditNameOk(S : String) : Boolean;
Var
    I : Integer;
    Ch : String;
Begin
    Result := (Length(S) >= 1) And (Length(S) <= 40);
    If Not Result Then Exit;
    For I := 1 To Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        If Pos(Ch, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-') = 0 Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;

{ A net name in the copper and graphics writers (scripts 2026.11.23.10): the    }
{ designator characters plus + . [ ] (bus-style nets: IM[1], 22p 2026-11-23).   }
{ None of them is a separator of the batch line (| and ;).                      }
Function PlaceEditNetOk(S : String) : Boolean;
Var
    I : Integer;
    Ch : String;
Begin
    Result := (Length(S) >= 1) And (Length(S) <= 40);
    If Not Result Then Exit;
    For I := 1 To Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        If Pos(Ch, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-+.[]') = 0 Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;

Function PlaceEditRotation(Comp : IPCB_Component) : Integer;
Begin
    Result := Round(Comp.Rotation) Mod 360;
    If Result < 0 Then Result := Result + 360;
End;

{ The component's own extent: the union of its pads, tracks, arcs, regions and   }
{ fills (its courtyard lines are tracks, so they count). Comp.BoundingRectangle   }
{ also spans the designator and comment text, which can reach copper the part    }
{ itself does not: on 2026-10-07/08 it refused eight parts whose labels touched a }
{ mounting-hole ring (Stefan: "we should not be blocking based on designator      }
{ text"). Falls back to the bounding rectangle for a component with no such      }
{ primitive.                                                                       }
Function PlaceEditExtent(Comp : IPCB_Component) : TCoordRect;
Var
    GrIter : IPCB_GroupIterator;
    Prim : IPCB_Primitive;
    R : TCoordRect;
    First : Boolean;
Begin
    Result := Comp.BoundingRectangle;
    First := True;
    GrIter := Comp.GroupIterator_Create;
    Try
        GrIter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject, ePadObject, eRegionObject, eFillObject));
        Prim := GrIter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            R := Prim.BoundingRectangle;
            If First Then
            Begin
                Result := R;
                First := False;
            End
            Else
            Begin
                If R.X1 < Result.X1 Then Result.X1 := R.X1;
                If R.Y1 < Result.Y1 Then Result.Y1 := R.Y1;
                If R.X2 > Result.X2 Then Result.X2 := R.X2;
                If R.Y2 > Result.Y2 Then Result.Y2 := R.Y2;
            End;
            Prim := GrIter.NextPCBObject;
        End;
    Finally
        Comp.GroupIterator_Destroy(GrIter);
    End;
End;

{ True when a track, arc or via (not part of a footprint) on copper overlaps the }
{ component's own extent (PlaceEditExtent): routing is attached, or runs where   }
{ it sits. Conservative on purpose: placement comes before routing.              }
Function PlaceEditRouted(Board : IPCB_Board; Comp : IPCB_Component) : Boolean;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    CB, PB : TCoordRect;
    Copper : Boolean;
Begin
    Result := False;
    CB := PlaceEditExtent(Comp);
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject, eViaObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While (Prim <> Nil) And (Not Result) Do
        Begin
            If Not Prim.InComponent Then
            Begin
                Copper := (Prim.ObjectId = eViaObject);
                If Not Copper Then
                    Copper := PCB_IsCopperLayerName(GetLayerString(Prim.Layer));
                If Copper Then
                Begin
                    PB := Prim.BoundingRectangle;
                    If (PB.X1 <= CB.X2) And (CB.X1 <= PB.X2) And (PB.Y1 <= CB.Y2) And (CB.Y1 <= PB.Y2) Then
                        Result := True;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Params: mode (preview | apply), batch_hash (64 hex, echoed), moves:          }
{ 'designator|x|y|rotation|old_x|old_y|old_rotation|old_layer;...' with x / y  }
{ in raw Altium coordinates (integers) and rotation in degrees. Preview leaves  }
{ the old fields empty and reports what each move would do. Apply refuses the   }
{ whole batch unless every part still sits where the preview read it. An apply  }
{ that touched anything clears the grant: one tick, one batch.                   }
{ After a scripted move or delete the connection lines still run to where the }
{ objects were until the nets are analysed again; the editor does this itself  }
{ after a hand move. Board.AnalyzeNet per net, as upstream eda-agent's          }
{ PCB_BatchMoveComponents (it measured the same symptom). Seen 2026-11-18 on    }
{ the HDMI board after U502-U504 were moved.                                    }
Procedure CollectPadNets(Comp : IPCB_Component; Names : TStringList);
Var
    PadIter : IPCB_GroupIterator;
    Pad : IPCB_Pad;
Begin
    If Comp = Nil Then Exit;
    PadIter := Comp.GroupIterator_Create;
    Try
        PadIter.AddFilter_ObjectSet(MkSet(ePadObject));
        Pad := PadIter.FirstPCBObject;
        While Pad <> Nil Do
        Begin
            Try
                If Pad.Net <> Nil Then
                    If Names.IndexOf(Pad.Net.Name) < 0 Then Names.Add(Pad.Net.Name);
            Except
            End;
            Pad := PadIter.NextPCBObject;
        End;
    Finally
        Comp.GroupIterator_Destroy(PadIter);
    End;
End;

Procedure AnalyzeNetsByName(Board : IPCB_Board; Names : TStringList);
Var
    I : Integer;
    NetObj : IPCB_Net;
Begin
    For I := 0 To Names.Count - 1 Do
    Begin
        { A ground net is skipped: with the pours shelved its analysis took seven }
        { minutes on the 22p (2026-11-18, a delete of 13 GND vias).               }
        If Pos('GND', UpperCase(Names[I])) > 0 Then Continue;
        NetObj := Nil;
        Try NetObj := FindNetByName(Board, Names[I]); Except NetObj := Nil; End;
        If NetObj <> Nil Then
        Begin
            Try Board.AnalyzeNet(NetObj); Except End;
        End;
    End;
    { The connection lines still ran from the old places after a move (22p,    }
    { 2026-11-18): the nets were analysed but the view was not rebuilt.        }
    If Names.Count > 0 Then
    Begin
        Try Board.ViewManager_FullUpdate; Except End;
    End;
End;

Function SelectedMoveComponentsChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, MovesStr, BatchHash, Rest, OpStr, D, Status, Problems, MovesJson, Binding, Blank : String;
    PcbPath, ErrCode, ErrMsg, LayerStr : String;
    OpDes, OpX, OpY, OpR, OpOX, OpOY, OpOR, OpOL, OpCX, OpCY, OpCR, OpCL, OpStatus, OpBX, OpBY, OpBR : TStringList;
    J, Count, WouldMove, Unchanged, Refused, Moved, NotMoved, NewX, NewY, NewR : Integer;
    Apply, PcbModified, Partial, Touched, Ok : Boolean;
    Board : IPCB_Board;
    Comp : IPCB_Component;
    MovedNets : TStringList;
    { Eight named locals, not Array[0..7] Of String: fixed-size string arrays as }
    { function locals corrupt the return slot in DelphiScript (see             }
    { PCB_BatchMoveComponents).                                                 }
    F0, F1, F2, F3, F4, F5, F6, F7 : String;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    MovesStr := ExtractJsonValue(Params, 'moves');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Placement edits are not granted: the operator ticks "Allow placement edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    OpDes := TStringList.Create;
    OpX := TStringList.Create;
    OpY := TStringList.Create;
    OpR := TStringList.Create;
    OpOX := TStringList.Create;
    OpOY := TStringList.Create;
    OpOR := TStringList.Create;
    OpOL := TStringList.Create;
    OpCX := TStringList.Create;
    OpCY := TStringList.Create;
    OpCR := TStringList.Create;
    OpCL := TStringList.Create;
    OpStatus := TStringList.Create;
    OpBX := TStringList.Create;
    OpBY := TStringList.Create;
    OpBR := TStringList.Create;
    SelectedBusy := True;
    Try
        If SelectedFreshnessJSON(P) = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P) + '); save or discard the named document');
            Exit;
        End;

        { Parse. A malformed batch is a client defect: refused in both modes. }
        Rest := MovesStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 100) Or (ParamEditCountChar(OpStr, '|') <> 7) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Move ' + IntToStr(Count) + ': expected designator|x|y|rotation|old_x|old_y|old_rotation|old_layer, at most 100 moves');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|');
            F1 := ParamEditTake(OpStr, '|');
            F2 := ParamEditTake(OpStr, '|');
            F3 := ParamEditTake(OpStr, '|');
            F4 := ParamEditTake(OpStr, '|');
            F5 := ParamEditTake(OpStr, '|');
            F6 := ParamEditTake(OpStr, '|');
            F7 := OpStr;
            Ok := PlaceEditNameOk(F0) And PlaceEditIntOk(F1) And PlaceEditIntOk(F2)
                And PlaceEditIntOk(F3);
            If Ok Then
            Begin
                NewR := StrToInt(F3);
                Ok := (NewR = 0) Or (NewR = 90) Or (NewR = 180) Or (NewR = 270);
            End;
            If Ok And Apply Then
                Ok := PlaceEditIntOk(F4) And PlaceEditIntOk(F5) And PlaceEditIntOk(F6)
                    And PlaceEditNameOk(F7);
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Move ' + IntToStr(Count) + ': bad designator, coordinate or rotation (0 / 90 / 180 / 270, raw integer coordinates)');
                Exit;
            End;
            If OpDes.IndexOf(F0) >= 0 Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Duplicate move: ' + F0);
                Exit;
            End;
            OpDes.Add(F0);
            OpX.Add(F1);
            OpY.Add(F2);
            OpR.Add(F3);
            OpOX.Add(F4);
            OpOY.Add(F5);
            OpOR.Add(F6);
            OpOL.Add(F7);
            OpCX.Add(Blank);
            OpCY.Add(Blank);
            OpCR.Add(Blank);
            OpCL.Add(Blank);
            OpStatus.Add(Blank);
            OpBX.Add(Blank);
            OpBY.Add(Blank);
            OpBR.Add(Blank);
        End;
        If OpDes.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No moves');
            Exit;
        End;

        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;

        { Read and classify every part. }
        Problems := '';
        Refused := 0;
        WouldMove := 0;
        Unchanged := 0;
        For J := 0 To OpDes.Count - 1 Do
        Begin
            Comp := Board.GetPcbComponentByRefDes(OpDes[J]);
            Status := '';
            If Comp = Nil Then
                Status := 'refused: designator not on the board'
            Else
            Begin
                OpCX[J] := IntToStr(Comp.x);
                OpCY[J] := IntToStr(Comp.y);
                OpCR[J] := IntToStr(PlaceEditRotation(Comp));
                Try LayerStr := GetLayerString(Comp.Layer); Except LayerStr := 'Unknown'; End;
                OpCL[J] := LayerStr;
                If Not Comp.Moveable Then Status := 'refused: the part is locked'
                { A part on either outer layer moves on its side (bottom parts from scripts }
                { 2026.11.23.10); a side change is the edit op flip.                        }
                Else If (LayerStr <> 'TopLayer') And (LayerStr <> 'BottomLayer') Then
                    Status := 'refused: the part is on neither outer layer'
                Else If PlaceEditRouted(Board, Comp) Then Status := 'refused: copper routing overlaps the part (placement comes before routing)'
                Else If Apply And ((OpCX[J] <> OpOX[J]) Or (OpCY[J] <> OpOY[J]) Or (OpCR[J] <> OpOR[J]) Or (OpCL[J] <> OpOL[J])) Then
                    Status := 'refused: moved since preview'
                Else If (OpCX[J] = OpX[J]) And (OpCY[J] = OpY[J]) And (OpCR[J] = OpR[J]) Then
                    Status := 'unchanged'
                Else
                    Status := 'would_move';
            End;
            OpStatus[J] := Status;
            If Copy(Status, 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 600 Then
                    Problems := Problems + OpDes[J] + ': ' + Copy(Status, 10, 200) + '; ';
            End
            Else If Status = 'unchanged' Then Inc(Unchanged)
            Else Inc(WouldMove);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing moved. ' + Problems);
            Exit;
        End;

        { Apply: per part, read again, then rotate and move inside one          }
        { PreProcess / PostProcess pair, and read back. Rotation first, then    }
        { x / y, so the origin ends where asked whatever the pivot. Stops at    }
        { the first surprise; what moved is reported, never rolled back.        }
        Moved := 0;
        NotMoved := 0;
        Partial := False;
        If Apply And (WouldMove > 0) Then
        Begin
            MovedNets := TStringList.Create;
            Try
                For J := 0 To OpDes.Count - 1 Do
                Begin
                    If Partial Or (OpStatus[J] <> 'would_move') Then Continue;
                    Comp := Board.GetPcbComponentByRefDes(OpDes[J]);
                    If (Comp = Nil) Or (IntToStr(Comp.x) <> OpOX[J]) Or (IntToStr(Comp.y) <> OpOY[J])
                        Or (IntToStr(PlaceEditRotation(Comp)) <> OpOR[J]) Then
                    Begin
                        OpStatus[J] := 'not_moved: changed during apply';
                        Partial := True;
                        Continue;
                    End;
                    NewX := StrToInt(OpX[J]);
                    NewY := StrToInt(OpY[J]);
                    NewR := StrToInt(OpR[J]);
                    Touched := True;
                    PCBServer.PreProcess;
                    Try
                        PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast,
                            PCBM_BeginModify, c_NoEventData);
                        Comp.Rotation := NewR;
                        Comp.x := NewX;
                        Comp.y := NewY;
                        PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast,
                            PCBM_EndModify, c_NoEventData);
                    Finally
                        PCBServer.PostProcess;
                    End;
                    CollectPadNets(Comp, MovedNets);
                    OpBX[J] := IntToStr(Comp.x);
                    OpBY[J] := IntToStr(Comp.y);
                    OpBR[J] := IntToStr(PlaceEditRotation(Comp));
                    If (OpBX[J] = OpX[J]) And (OpBY[J] = OpY[J]) And (OpBR[J] = OpR[J]) Then
                    Begin
                        OpStatus[J] := 'moved';
                        Inc(Moved);
                    End
                    Else
                    Begin
                        OpStatus[J] := 'moved_readback_differs';
                        Partial := True;
                    End;
                End;
            Finally
                If Touched Then MarkDocDirtyByPath(PcbPath);
                If Touched Then AnalyzeNetsByName(Board, MovedNets);
                MovedNets.Free;
            End;
            For J := 0 To OpDes.Count - 1 Do
                If OpStatus[J] = 'would_move' Then
                Begin
                    OpStatus[J] := 'not_moved';
                    Inc(NotMoved);
                End;
        End;

        MovesJson := '';
        For J := 0 To OpDes.Count - 1 Do
        Begin
            If J > 0 Then MovesJson := MovesJson + ',';
            MovesJson := MovesJson + '{"designator":"' + EscapeJsonString(OpDes[J])
                + '","x":"' + OpCX[J] + '","y":"' + OpCY[J] + '","rotation":"' + OpCR[J]
                + '","layer":"' + EscapeJsonString(OpCL[J])
                + '","target_x":"' + OpX[J] + '","target_y":"' + OpY[J] + '","target_rotation":"' + OpR[J]
                + '","status":"' + EscapeJsonString(OpStatus[J]) + '"';
            If Apply Then
                MovesJson := MovesJson + ',"readback_x":"' + OpBX[J] + '","readback_y":"' + OpBY[J]
                    + '","readback_rotation":"' + OpBR[J] + '"';
            MovesJson := MovesJson + '}';
        End;
        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again before trusting the board'
                + ' (moved: ' + IntToStr(Moved) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode
                + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash)
                + '","move_count":' + IntToStr(OpDes.Count)
                + ',"would_move":' + IntToStr(WouldMove)
                + ',"unchanged":' + IntToStr(Unchanged)
                + ',"refused":' + IntToStr(Refused)
                + ',"moved":' + IntToStr(Moved)
                + ',"not_moved":' + IntToStr(NotMoved)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"moves":[' + MovesJson + ']}}');
    Finally
        { One tick, one batch. }
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        OpDes.Free;
        OpX.Free;
        OpY.Free;
        OpR.Free;
        OpOX.Free;
        OpOY.Free;
        OpOR.Free;
        OpOL.Free;
        OpCX.Free;
        OpCY.Free;
        OpCR.Free;
        OpCL.Free;
        OpStatus.Free;
        OpBX.Free;
        OpBY.Free;
        OpBR.Free;
    End;
End;

{ ---- Checked copper placement from a plan ---------------------------------- }
{ PROPOSAL-2026-10-09-copper-write-increment (Stefan 2026-10-09: "let's add the  }
{ tool support"). One command, pcb.place_copper_checked: free vias and track    }
{ segments from a checked layout plan (the U501 fanout), reachable only in a    }
{ runtime generated with SELECTED_PLACE_EDITS = True and, for apply, behind the }
{ same operator tick as the component moves ("Allow placement edits": one tick, }
{ one batch). What the audited upstream PCB_PlaceVia / PCB_PlaceTracks lack and  }
{ this has: the selected project's own PcbDoc (never the focused board), raw    }
{ coordinates as integers (never mils: a 0.30 mm via is 11.8 mils), a net that  }
{ must exist (upstream silently places an unassigned via), a clearance test     }
{ against the copper already on the board, a duplicate test (an object already  }
{ there is "unchanged", so a re-run is idempotent), compare-and-set on the       }
{ board's free via / track counts between preview and apply, a read-back of     }
{ every object, the dirty-board refusal, and never a save.                       }
{ Not checked here, by design: the batch's objects against EACH OTHER (the plan  }
{ checkers do that with the plan's own geometry), polygons and regions (none on  }
{ the board yet), and design rules (Altium DRC after the save).                  }

Function CopperLayerNameOk(S : String) : Boolean;
Var
    I : Integer;
    Ch : String;
Begin
    Result := (Length(S) >= 1) And (Length(S) <= 40);
    If Not Result Then Exit;
    For I := 1 To Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        If Pos(Ch, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-() .') = 0 Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;

{ Distance from point P to segment AB (all in raw coordinates, as Double). }
Function CopperPtSeg(PX, PY, AX, AY, BX, BY : Double) : Double;
Var
    DX, DY, T, QX, QY : Double;
Begin
    { DelphiScript keeps integer arithmetic for integer inputs whatever the parameter }
    { type says, and a product of two raw coordinates overflows 32 bits: the first  }
    { live preview (2026-10-09) called clear spots overlaps. Force floating point.   }
    PX := PX * 1.0;
    PY := PY * 1.0;
    AX := AX * 1.0;
    AY := AY * 1.0;
    BX := BX * 1.0;
    BY := BY * 1.0;
    DX := BX - AX;
    DY := BY - AY;
    If (DX = 0) And (DY = 0) Then T := 0
    Else
    Begin
        T := ((PX - AX) * DX + (PY - AY) * DY) / (DX * DX + DY * DY);
        If T < 0 Then T := 0;
        If T > 1 Then T := 1;
    End;
    QX := AX + T * DX;
    QY := AY + T * DY;
    Result := Sqrt((PX - QX) * (PX - QX) + (PY - QY) * (PY - QY));
End;

{ True when segments AB and CD properly cross. }
Function CopperSegsCross(AX, AY, BX, BY, CX, CY, DX, DY : Double) : Boolean;
Var
    D1, D2, D3, D4 : Double;
Begin
    AX := AX * 1.0;
    AY := AY * 1.0;
    BX := BX * 1.0;
    BY := BY * 1.0;
    CX := CX * 1.0;
    CY := CY * 1.0;
    DX := DX * 1.0;
    DY := DY * 1.0;
    D1 := (DX - CX) * (AY - CY) - (DY - CY) * (AX - CX);
    D2 := (DX - CX) * (BY - CY) - (DY - CY) * (BX - CX);
    D3 := (BX - AX) * (CY - AY) - (BY - AY) * (CX - AX);
    D4 := (BX - AX) * (DY - AY) - (BY - AY) * (DX - AX);
    Result := (((D1 > 0) And (D2 < 0)) Or ((D1 < 0) And (D2 > 0)))
          And (((D3 > 0) And (D4 < 0)) Or ((D3 < 0) And (D4 > 0)));
End;

{ Distance between segments AB and CD: 0 when they cross. }
Function CopperSegSeg(AX, AY, BX, BY, CX, CY, DX, DY : Double) : Double;
Var
    M, V : Double;
Begin
    If CopperSegsCross(AX, AY, BX, BY, CX, CY, DX, DY) Then
    Begin
        Result := 0;
        Exit;
    End;
    M := CopperPtSeg(AX, AY, CX, CY, DX, DY);
    V := CopperPtSeg(BX, BY, CX, CY, DX, DY);
    If V < M Then M := V;
    V := CopperPtSeg(CX, CY, AX, AY, BX, BY);
    If V < M Then M := V;
    V := CopperPtSeg(DX, DY, AX, AY, BX, BY);
    If V < M Then M := V;
    Result := M;
End;

{ Distance from segment AB to the axis-aligned rectangle R: 0 when an end lies inside. }
Function CopperSegRect(AX, AY, BX, BY, RX1, RY1, RX2, RY2 : Double) : Double;
Var
    M, V : Double;
Begin
    If ((AX >= RX1) And (AX <= RX2) And (AY >= RY1) And (AY <= RY2))
        Or ((BX >= RX1) And (BX <= RX2) And (BY >= RY1) And (BY <= RY2)) Then
    Begin
        Result := 0;
        Exit;
    End;
    M := CopperSegSeg(AX, AY, BX, BY, RX1, RY1, RX2, RY1);
    V := CopperSegSeg(AX, AY, BX, BY, RX2, RY1, RX2, RY2);
    If V < M Then M := V;
    V := CopperSegSeg(AX, AY, BX, BY, RX2, RY2, RX1, RY2);
    If V < M Then M := V;
    V := CopperSegSeg(AX, AY, BX, BY, RX1, RY2, RX1, RY1);
    If V < M Then M := V;
    Result := M;
End;

{ Free (not in a footprint) vias on the board, and free tracks on copper: the   }
{ board's copper signature for compare-and-set between preview and apply.      }
Procedure CopperCountFree(Board : IPCB_Board; Var Vias, Tracks : Integer);
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
Begin
    Vias := 0;
    Tracks := 0;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject, eViaObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If Not Prim.InComponent Then
            Begin
                If Prim.ObjectId = eViaObject Then Inc(Vias)
                Else If PCB_IsCopperLayerName(GetLayerString(Prim.Layer)) Then Inc(Tracks);
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ The nearest other-net copper to a new object: a segment AB (a via is A = B)   }
{ of half-width HW on `Layer` (eNoLayer for a via: every copper layer counts).  }
{ Pads, vias, tracks and arcs; a prim on the same net is a connection, not a    }
{ conflict. Returns the gap (raw units, negative when overlapping) and names     }
{ the nearest prim. The bounding-box test runs first so most prims cost one    }
{ comparison.                                                                   }
Function CopperNearest(Board : IPCB_Board; NetName : String; Layer : TLayer;
    AX, AY, BX, BY, HW, Clearance : Double; Var What : String) : Double;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Pad : IPCB_Pad;
    Via : IPCB_Via;
    Track : IPCB_Track;
    R : TCoordRect;
    LayerStr, PrimNet : String;
    Gap, Reach, LoX, LoY, HiX, HiY, Half, HX, HY, PRX1, PRY1, PRX2, PRY2 : Double;
    PadRot : Integer;
    Relevant, IsRound : Boolean;
Begin
    Result := 1.0E12;
    What := '';
    AX := AX * 1.0;
    AY := AY * 1.0;
    BX := BX * 1.0;
    BY := BY * 1.0;
    HW := HW * 1.0;
    Clearance := Clearance * 1.0;
    Reach := HW + Clearance;
    If AX < BX Then Begin LoX := AX; HiX := BX; End Else Begin LoX := BX; HiX := AX; End;
    If AY < BY Then Begin LoY := AY; HiY := BY; End Else Begin LoY := BY; HiY := AY; End;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(ePadObject, eViaObject, eTrackObject, eArcObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            Relevant := False;
            If Prim.ObjectId = eViaObject Then Relevant := True
            Else If Prim.ObjectId = ePadObject Then
            Begin
                If Prim.Layer = eMultiLayer Then Relevant := True
                Else Relevant := (Layer = eNoLayer) Or (Prim.Layer = Layer);
                If Relevant And (Layer <> eNoLayer) And (Prim.Layer <> eMultiLayer) Then
                    Relevant := PCB_IsCopperLayerName(GetLayerString(Prim.Layer));
            End
            Else
            Begin
                LayerStr := GetLayerString(Prim.Layer);
                If PCB_IsCopperLayerName(LayerStr) Then
                    Relevant := (Layer = eNoLayer) Or (Prim.Layer = Layer);
            End;
            If Relevant Then
            Begin
                R := Prim.BoundingRectangle;
                If Prim.ObjectId = ePadObject Then
                Begin
                    { A pad's BoundingRectangle includes its solder-mask expansion (an 0.85 x }
                    { 0.80 mm pad reported 1.05 x 1.00 on 2026-10-09): build the copper      }
                    { rectangle from the centre and size instead, turned with the pad. A pad  }
                    { at an odd angle gets the circumscribed square (conservative).           }
                    Pad := Prim;
                    HX := Pad.TopXSize / 2;
                    HY := Pad.TopYSize / 2;
                    PadRot := 0;
                    Try PadRot := Round(Pad.Rotation) Mod 180; Except PadRot := 0; End;
                    If PadRot < 0 Then PadRot := PadRot + 180;
                    If PadRot = 90 Then
                    Begin
                        Half := HX;
                        HX := HY;
                        HY := Half;
                    End
                    Else If PadRot <> 0 Then
                    Begin
                        Half := Sqrt(HX * HX + HY * HY);
                        HX := Half;
                        HY := Half;
                    End;
                    PRX1 := Pad.x - HX;
                    PRY1 := Pad.y - HY;
                    PRX2 := Pad.x + HX;
                    PRY2 := Pad.y + HY;
                End
                Else
                Begin
                    PRX1 := R.X1 * 1.0;
                    PRY1 := R.Y1 * 1.0;
                    PRX2 := R.X2 * 1.0;
                    PRY2 := R.Y2 * 1.0;
                End;
                { Cheap box test before any geometry. }
                If (PRX1 - Reach > HiX) Or (PRX2 + Reach < LoX) Or (PRY1 - Reach > HiY) Or (PRY2 + Reach < LoY) Then
                    Relevant := False;
            End;
            If Relevant Then
            Begin
                PrimNet := '';
                Try If Prim.Net <> Nil Then PrimNet := Prim.Net.Name; Except PrimNet := ''; End;
                If PrimNet = NetName Then Relevant := False;
            End;
            If Relevant Then
            Begin
                Gap := 1.0E12;
                If Prim.ObjectId = eViaObject Then
                Begin
                    Via := Prim;
                    Gap := CopperPtSeg(Via.x, Via.y, AX, AY, BX, BY) - HW - Via.Size / 2;
                End
                Else If Prim.ObjectId = ePadObject Then
                Begin
                    Pad := Prim;
                    IsRound := False;
                    Try
                        IsRound := (Pad.TopShape = eRounded) And (Pad.TopXSize = Pad.TopYSize);
                    Except
                        IsRound := False;
                    End;
                    If IsRound Then
                    Begin
                        Half := Pad.TopXSize / 2;
                        Gap := CopperPtSeg(Pad.x, Pad.y, AX, AY, BX, BY) - HW - Half;
                    End
                    Else
                        Gap := CopperSegRect(AX, AY, BX, BY, PRX1, PRY1, PRX2, PRY2) - HW;
                End
                Else If Prim.ObjectId = eTrackObject Then
                Begin
                    Track := Prim;
                    Gap := CopperSegSeg(AX, AY, BX, BY, Track.x1, Track.y1, Track.x2, Track.y2) - HW - Track.Width / 2;
                End
                Else
                    Gap := CopperSegRect(AX, AY, BX, BY, R.X1 * 1.0, R.Y1 * 1.0, R.X2 * 1.0, R.Y2 * 1.0) - HW;
                If Gap < Result Then
                Begin
                    Result := Gap;
                    If Prim.ObjectId = eViaObject Then What := 'via'
                    Else If Prim.ObjectId = ePadObject Then What := 'pad'
                    Else If Prim.ObjectId = eTrackObject Then What := 'track'
                    Else What := 'arc';
                    If Prim.InComponent Then
                    Begin
                        Try What := What + ' of ' + Prim.Component.Name.Text; Except End;
                    End;
                    If PrimNet <> '' Then What := What + ' on ' + PrimNet;
                    { The prim's bounding rectangle, raw units: the first live run (2026-10-09)  }
                    { refused spots the offline geometry found clear, so the refusal shows what  }
                    { Altium reported.                                                           }
                    What := What + ' rect [' + IntToStr(R.X1) + ',' + IntToStr(R.Y1) + ','
                        + IntToStr(R.X2) + ',' + IntToStr(R.Y2) + ']';
                    If Prim.ObjectId = ePadObject Then
                    Begin
                        Try
                            What := What + ' pad ' + Pad.Name + ' at ' + IntToStr(Pad.x) + ',' + IntToStr(Pad.y)
                                + ' size ' + IntToStr(Pad.TopXSize) + 'x' + IntToStr(Pad.TopYSize)
                                + ' shape ' + IntToStr(Pad.TopShape) + ' layer ' + GetLayerString(Pad.Layer);
                        Except
                        End;
                    End;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ CopperNearest with one primitive left out (scripts 2026.11.23.5): the object  }
{ whose net `setnet` changes still carries its old net and would be found as   }
{ other-net copper on its own spot. A copy, so that the qualified function the  }
{ copper, graphics and via writers use is not touched.                          }
Function CopperNearestExcept(Board : IPCB_Board; NetName : String; Layer : TLayer;
    AX, AY, BX, BY, HW, Clearance : Double; Skip : IPCB_Primitive; Var What : String) : Double;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Pad : IPCB_Pad;
    Via : IPCB_Via;
    Track : IPCB_Track;
    R : TCoordRect;
    LayerStr, PrimNet : String;
    Gap, Reach, LoX, LoY, HiX, HiY, Half, HX, HY, PRX1, PRY1, PRX2, PRY2 : Double;
    PadRot : Integer;
    Relevant, IsRound : Boolean;
Begin
    Result := 1.0E12;
    What := '';
    AX := AX * 1.0;
    AY := AY * 1.0;
    BX := BX * 1.0;
    BY := BY * 1.0;
    HW := HW * 1.0;
    Clearance := Clearance * 1.0;
    Reach := HW + Clearance;
    If AX < BX Then Begin LoX := AX; HiX := BX; End Else Begin LoX := BX; HiX := AX; End;
    If AY < BY Then Begin LoY := AY; HiY := BY; End Else Begin LoY := BY; HiY := AY; End;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(ePadObject, eViaObject, eTrackObject, eArcObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            Relevant := False;
            If Prim.ObjectId = eViaObject Then Relevant := True
            Else If Prim.ObjectId = ePadObject Then
            Begin
                If Prim.Layer = eMultiLayer Then Relevant := True
                Else Relevant := (Layer = eNoLayer) Or (Prim.Layer = Layer);
                If Relevant And (Layer <> eNoLayer) And (Prim.Layer <> eMultiLayer) Then
                    Relevant := PCB_IsCopperLayerName(GetLayerString(Prim.Layer));
            End
            Else
            Begin
                LayerStr := GetLayerString(Prim.Layer);
                If PCB_IsCopperLayerName(LayerStr) Then
                    Relevant := (Layer = eNoLayer) Or (Prim.Layer = Layer);
            End;
            If (Skip <> Nil) And (Prim.I_ObjectAddress = Skip.I_ObjectAddress) Then Relevant := False;
            If Relevant Then
            Begin
                R := Prim.BoundingRectangle;
                If Prim.ObjectId = ePadObject Then
                Begin
                    { A pad's BoundingRectangle includes its solder-mask expansion (an 0.85 x }
                    { 0.80 mm pad reported 1.05 x 1.00 on 2026-10-09): build the copper      }
                    { rectangle from the centre and size instead, turned with the pad. A pad  }
                    { at an odd angle gets the circumscribed square (conservative).           }
                    Pad := Prim;
                    HX := Pad.TopXSize / 2;
                    HY := Pad.TopYSize / 2;
                    PadRot := 0;
                    Try PadRot := Round(Pad.Rotation) Mod 180; Except PadRot := 0; End;
                    If PadRot < 0 Then PadRot := PadRot + 180;
                    If PadRot = 90 Then
                    Begin
                        Half := HX;
                        HX := HY;
                        HY := Half;
                    End
                    Else If PadRot <> 0 Then
                    Begin
                        Half := Sqrt(HX * HX + HY * HY);
                        HX := Half;
                        HY := Half;
                    End;
                    PRX1 := Pad.x - HX;
                    PRY1 := Pad.y - HY;
                    PRX2 := Pad.x + HX;
                    PRY2 := Pad.y + HY;
                End
                Else
                Begin
                    PRX1 := R.X1 * 1.0;
                    PRY1 := R.Y1 * 1.0;
                    PRX2 := R.X2 * 1.0;
                    PRY2 := R.Y2 * 1.0;
                End;
                { Cheap box test before any geometry. }
                If (PRX1 - Reach > HiX) Or (PRX2 + Reach < LoX) Or (PRY1 - Reach > HiY) Or (PRY2 + Reach < LoY) Then
                    Relevant := False;
            End;
            If Relevant Then
            Begin
                PrimNet := '';
                Try If Prim.Net <> Nil Then PrimNet := Prim.Net.Name; Except PrimNet := ''; End;
                If PrimNet = NetName Then Relevant := False;
            End;
            If Relevant Then
            Begin
                Gap := 1.0E12;
                If Prim.ObjectId = eViaObject Then
                Begin
                    Via := Prim;
                    Gap := CopperPtSeg(Via.x, Via.y, AX, AY, BX, BY) - HW - Via.Size / 2;
                End
                Else If Prim.ObjectId = ePadObject Then
                Begin
                    Pad := Prim;
                    IsRound := False;
                    Try
                        IsRound := (Pad.TopShape = eRounded) And (Pad.TopXSize = Pad.TopYSize);
                    Except
                        IsRound := False;
                    End;
                    If IsRound Then
                    Begin
                        Half := Pad.TopXSize / 2;
                        Gap := CopperPtSeg(Pad.x, Pad.y, AX, AY, BX, BY) - HW - Half;
                    End
                    Else
                        Gap := CopperSegRect(AX, AY, BX, BY, PRX1, PRY1, PRX2, PRY2) - HW;
                End
                Else If Prim.ObjectId = eTrackObject Then
                Begin
                    Track := Prim;
                    Gap := CopperSegSeg(AX, AY, BX, BY, Track.x1, Track.y1, Track.x2, Track.y2) - HW - Track.Width / 2;
                End
                Else
                    Gap := CopperSegRect(AX, AY, BX, BY, R.X1 * 1.0, R.Y1 * 1.0, R.X2 * 1.0, R.Y2 * 1.0) - HW;
                If Gap < Result Then
                Begin
                    Result := Gap;
                    If Prim.ObjectId = eViaObject Then What := 'via'
                    Else If Prim.ObjectId = ePadObject Then What := 'pad'
                    Else If Prim.ObjectId = eTrackObject Then What := 'track'
                    Else What := 'arc';
                    If Prim.InComponent Then
                    Begin
                        Try What := What + ' of ' + Prim.Component.Name.Text; Except End;
                    End;
                    If PrimNet <> '' Then What := What + ' on ' + PrimNet;
                    { The prim's bounding rectangle, raw units: the first live run (2026-10-09)  }
                    { refused spots the offline geometry found clear, so the refusal shows what  }
                    { Altium reported.                                                           }
                    What := What + ' rect [' + IntToStr(R.X1) + ',' + IntToStr(R.Y1) + ','
                        + IntToStr(R.X2) + ',' + IntToStr(R.Y2) + ']';
                    If Prim.ObjectId = ePadObject Then
                    Begin
                        Try
                            What := What + ' pad ' + Pad.Name + ' at ' + IntToStr(Pad.x) + ',' + IntToStr(Pad.y)
                                + ' size ' + IntToStr(Pad.TopXSize) + 'x' + IntToStr(Pad.TopYSize)
                                + ' shape ' + IntToStr(Pad.TopShape) + ' layer ' + GetLayerString(Pad.Layer);
                        Except
                        End;
                    End;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ An identical free via (same net, centre, size and hole) already on the board. }
Function CopperViaExists(Board : IPCB_Board; NetName : String; X, Y, Size, Hole : Integer) : Boolean;
Var
    Iter : IPCB_BoardIterator;
    Via : IPCB_Via;
    PrimNet : String;
Begin
    Result := False;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eViaObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Via := Iter.FirstPCBObject;
        While (Via <> Nil) And (Not Result) Do
        Begin
            If (Not Via.InComponent) And (Via.x = X) And (Via.y = Y) And (Via.Size = Size) And (Via.HoleSize = Hole) Then
            Begin
                PrimNet := '';
                Try If Via.Net <> Nil Then PrimNet := Via.Net.Name; Except PrimNet := ''; End;
                Result := (PrimNet = NetName);
            End;
            Via := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ An identical free track (same net, layer, width and ends in either order). }
Function CopperTrackExists(Board : IPCB_Board; NetName : String; Layer : TLayer;
    X1, Y1, X2, Y2, Width : Integer) : Boolean;
Var
    Iter : IPCB_BoardIterator;
    Track : IPCB_Track;
    PrimNet : String;
    Same : Boolean;
Begin
    Result := False;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Track := Iter.FirstPCBObject;
        While (Track <> Nil) And (Not Result) Do
        Begin
            If (Not Track.InComponent) And (Track.Width = Width) And (Track.Layer = Layer) Then
            Begin
                Same := ((Track.x1 = X1) And (Track.y1 = Y1) And (Track.x2 = X2) And (Track.y2 = Y2))
                     Or ((Track.x1 = X2) And (Track.y1 = Y2) And (Track.x2 = X1) And (Track.y2 = Y1));
                If Same Then
                Begin
                    PrimNet := '';
                    Try If Track.Net <> Nil Then PrimNet := Track.Net.Name; Except PrimNet := ''; End;
                    Result := (PrimNet = NetName);
                End;
            End;
            Track := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Params: mode (preview | apply), batch_hash (64 hex, echoed), old_vias and    }
{ old_tracks (apply: the free counts the preview reported; the batch is refused }
{ if the board's copper changed since), vias: 'net|x|y|size|hole|clr;...' and  }
{ tracks: 'net|layer|x1|y1|x2|y2|width|clr;...' with every number a raw Altium }
{ coordinate (integer; clr = the clearance this object must keep from other    }
{ nets' copper). Through vias (top to bottom). At most 300 vias and 500 tracks. }
{ Per object: would_place / unchanged (already there) / refused: reason; apply  }
{ places, reads back, marks the document dirty and clears the grant.            }
Function SelectedPlaceCopperChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, ViasStr, TracksStr, BatchHash, Rest, OpStr, Problems, Binding, Blank, What : String;
    PcbPath, ErrCode, ErrMsg, OldViasStr, OldTracksStr, LayerStr : String;
    VNet, VX, VY, VS, VH, VC, VStatus, VBX, VBY, VBS, VBH : TStringList;
    TNet, TLay, TX1, TY1, TX2, TY2, TW, TC, TStatus, TLayerName, TBX1, TBY1, TBX2, TBY2, TBW : TStringList;
    J, Count, WouldPlace, Unchanged, Refused, Placed, NotPlaced, FreeVias, FreeTracks : Integer;
    X, Y, S, H, C, X1, Y1, X2, Y2, W : Integer;
    Apply, PcbModified, Partial, Touched, Ok : Boolean;
    Board : IPCB_Board;
    Net : IPCB_Net;
    Via : IPCB_Via;
    Track : IPCB_Track;
    Lyr : TLayer;
    Gap : Double;
    F0, F1, F2, F3, F4, F5, F6, F7 : String;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    ViasStr := ExtractJsonValue(Params, 'vias');
    TracksStr := ExtractJsonValue(Params, 'tracks');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    OldViasStr := ExtractJsonValue(Params, 'old_vias');
    OldTracksStr := ExtractJsonValue(Params, 'old_tracks');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Placement edits are not granted: the operator ticks "Allow placement edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    If Apply And ((Not PlaceEditIntOk(OldViasStr)) Or (Not PlaceEditIntOk(OldTracksStr))) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'apply needs old_vias and old_tracks from the preview');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    VNet := TStringList.Create;
    VX := TStringList.Create;
    VY := TStringList.Create;
    VS := TStringList.Create;
    VH := TStringList.Create;
    VC := TStringList.Create;
    VStatus := TStringList.Create;
    VBX := TStringList.Create;
    VBY := TStringList.Create;
    VBS := TStringList.Create;
    VBH := TStringList.Create;
    TNet := TStringList.Create;
    TLay := TStringList.Create;
    TX1 := TStringList.Create;
    TY1 := TStringList.Create;
    TX2 := TStringList.Create;
    TY2 := TStringList.Create;
    TW := TStringList.Create;
    TC := TStringList.Create;
    TStatus := TStringList.Create;
    TLayerName := TStringList.Create;
    TBX1 := TStringList.Create;
    TBY1 := TStringList.Create;
    TBX2 := TStringList.Create;
    TBY2 := TStringList.Create;
    TBW := TStringList.Create;
    SelectedBusy := True;
    Try
        If SelectedFreshnessJSON(P) = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P) + '); save or discard the named document');
            Exit;
        End;

        { Parse. A malformed batch is a client defect: refused in both modes. }
        Rest := ViasStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 300) Or (ParamEditCountChar(OpStr, '|') <> 5) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Via ' + IntToStr(Count) + ': expected net|x|y|size|hole|clr, at most 300 vias');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|');
            F1 := ParamEditTake(OpStr, '|');
            F2 := ParamEditTake(OpStr, '|');
            F3 := ParamEditTake(OpStr, '|');
            F4 := ParamEditTake(OpStr, '|');
            F5 := OpStr;
            Ok := PlaceEditNetOk(F0) And PlaceEditIntOk(F1) And PlaceEditIntOk(F2)
                And PlaceEditIntOk(F3) And PlaceEditIntOk(F4) And PlaceEditIntOk(F5);
            If Ok Then
                Ok := (StrToInt(F3) > 0) And (StrToInt(F4) > 0) And (StrToInt(F4) < StrToInt(F3)) And (StrToInt(F5) >= 0);
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Via ' + IntToStr(Count) + ': bad net, coordinate, size, hole or clearance (raw integer coordinates, 0 < hole < size)');
                Exit;
            End;
            VNet.Add(F0);
            VX.Add(F1);
            VY.Add(F2);
            VS.Add(F3);
            VH.Add(F4);
            VC.Add(F5);
            VStatus.Add(Blank);
            VBX.Add(Blank);
            VBY.Add(Blank);
            VBS.Add(Blank);
            VBH.Add(Blank);
        End;
        Rest := TracksStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 500) Or (ParamEditCountChar(OpStr, '|') <> 7) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Track ' + IntToStr(Count) + ': expected net|layer|x1|y1|x2|y2|width|clr, at most 500 tracks');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|');
            F1 := ParamEditTake(OpStr, '|');
            F2 := ParamEditTake(OpStr, '|');
            F3 := ParamEditTake(OpStr, '|');
            F4 := ParamEditTake(OpStr, '|');
            F5 := ParamEditTake(OpStr, '|');
            F6 := ParamEditTake(OpStr, '|');
            F7 := OpStr;
            Ok := PlaceEditNetOk(F0) And CopperLayerNameOk(F1) And PlaceEditIntOk(F2) And PlaceEditIntOk(F3)
                And PlaceEditIntOk(F4) And PlaceEditIntOk(F5) And PlaceEditIntOk(F6) And PlaceEditIntOk(F7);
            If Ok Then
                Ok := (StrToInt(F6) > 0) And (StrToInt(F7) >= 0)
                    And ((StrToInt(F2) <> StrToInt(F4)) Or (StrToInt(F3) <> StrToInt(F5)));
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Track ' + IntToStr(Count) + ': bad net, layer, coordinate, width or clearance (raw integer coordinates, distinct ends)');
                Exit;
            End;
            TNet.Add(F0);
            TLay.Add(F1);
            TX1.Add(F2);
            TY1.Add(F3);
            TX2.Add(F4);
            TY2.Add(F5);
            TW.Add(F6);
            TC.Add(F7);
            TStatus.Add(Blank);
            TLayerName.Add(Blank);
            TBX1.Add(Blank);
            TBY1.Add(Blank);
            TBX2.Add(Blank);
            TBY2.Add(Blank);
            TBW.Add(Blank);
        End;
        If (VNet.Count = 0) And (TNet.Count = 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No vias and no tracks');
            Exit;
        End;

        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;
        CopperCountFree(Board, FreeVias, FreeTracks);
        If Apply And ((IntToStr(FreeVias) <> OldViasStr) Or (IntToStr(FreeTracks) <> OldTracksStr)) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED',
                'Nothing placed. The board''s free copper changed since the preview (vias '
                + IntToStr(FreeVias) + ', tracks ' + IntToStr(FreeTracks) + '); preview again');
            Exit;
        End;

        { Classify every object. }
        Problems := '';
        Refused := 0;
        WouldPlace := 0;
        Unchanged := 0;
        For J := 0 To VNet.Count - 1 Do
        Begin
            X := StrToInt(VX[J]);
            Y := StrToInt(VY[J]);
            S := StrToInt(VS[J]);
            H := StrToInt(VH[J]);
            C := StrToInt(VC[J]);
            Net := FindNetByName(Board, VNet[J]);
            If Net = Nil Then VStatus[J] := 'refused: net not on the board'
            Else If CopperViaExists(Board, VNet[J], X, Y, S, H) Then VStatus[J] := 'unchanged'
            Else
            Begin
                Gap := CopperNearest(Board, VNet[J], eNoLayer, X, Y, X, Y, S / 2, C, What);
                If Gap < C Then
                    VStatus[J] := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(C) + ' mm)'
                Else
                    VStatus[J] := 'would_place';
            End;
            If Copy(VStatus[J], 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 800 Then
                    Problems := Problems + 'via ' + IntToStr(J + 1) + ' (' + VNet[J] + '): ' + Copy(VStatus[J], 10, 200) + '; ';
            End
            Else If VStatus[J] = 'unchanged' Then Inc(Unchanged)
            Else Inc(WouldPlace);
        End;
        For J := 0 To TNet.Count - 1 Do
        Begin
            X1 := StrToInt(TX1[J]);
            Y1 := StrToInt(TY1[J]);
            X2 := StrToInt(TX2[J]);
            Y2 := StrToInt(TY2[J]);
            W := StrToInt(TW[J]);
            C := StrToInt(TC[J]);
            Lyr := ResolveLayerId(Board, TLay[J]);
            If Lyr <> eNoLayer Then
            Begin
                LayerStr := GetLayerString(Lyr);
                If Not PCB_IsCopperLayerName(LayerStr) Then Lyr := eNoLayer;
            End;
            Net := FindNetByName(Board, TNet[J]);
            If Lyr = eNoLayer Then TStatus[J] := 'refused: not a copper layer of this board'
            Else If Net = Nil Then TStatus[J] := 'refused: net not on the board'
            Else
            Begin
                TLayerName[J] := LayerStr;
                If CopperTrackExists(Board, TNet[J], Lyr, X1, Y1, X2, Y2, W) Then TStatus[J] := 'unchanged'
                Else
                Begin
                    Gap := CopperNearest(Board, TNet[J], Lyr, X1, Y1, X2, Y2, W / 2, C, What);
                    If Gap < C Then
                        TStatus[J] := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(C) + ' mm)'
                    Else
                        TStatus[J] := 'would_place';
                End;
            End;
            If Copy(TStatus[J], 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 800 Then
                    Problems := Problems + 'track ' + IntToStr(J + 1) + ' (' + TNet[J] + '): ' + Copy(TStatus[J], 10, 200) + '; ';
            End
            Else If TStatus[J] = 'unchanged' Then Inc(Unchanged)
            Else Inc(WouldPlace);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing placed. ' + Problems);
            Exit;
        End;

        { Apply: every object inside one PreProcess / PostProcess, each one    }
        { registered with the board and read back from the object itself.     }
        { Stops at the first surprise; what was placed is reported, never      }
        { rolled back.                                                         }
        Placed := 0;
        NotPlaced := 0;
        Partial := False;
        If Apply And (WouldPlace > 0) Then
        Begin
            Try
                PCBServer.PreProcess;
                Try
                    For J := 0 To VNet.Count - 1 Do
                    Begin
                        If Partial Or (VStatus[J] <> 'would_place') Then Continue;
                        Net := FindNetByName(Board, VNet[J]);
                        Via := PCBServer.PCBObjectFactory(eViaObject, eNoDimension, eCreate_Default);
                        If (Via = Nil) Or (Net = Nil) Then
                        Begin
                            VStatus[J] := 'not_placed: could not create the via';
                            Partial := True;
                            Continue;
                        End;
                        Touched := True;
                        Via.x := StrToInt(VX[J]);
                        Via.y := StrToInt(VY[J]);
                        { Never pass through a via with no annular ring (upstream   }
                        { c5c46f9): a new size at or below the default hole goes    }
                        { after the hole. The client refuses hole >= size.          }
                        If StrToInt(VS[J]) > Via.HoleSize Then
                        Begin
                            Via.Size := StrToInt(VS[J]);
                            Via.HoleSize := StrToInt(VH[J]);
                        End
                        Else
                        Begin
                            Via.HoleSize := StrToInt(VH[J]);
                            Via.Size := StrToInt(VS[J]);
                        End;
                        Via.LowLayer := eTopLayer;
                        Via.HighLayer := eBottomLayer;
                        Via.Net := Net;
                        Board.AddPCBObject(Via);
                        PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast,
                            PCBM_BoardRegisteration, Via.I_ObjectAddress);
                        VBX[J] := IntToStr(Via.x);
                        VBY[J] := IntToStr(Via.y);
                        VBS[J] := IntToStr(Via.Size);
                        VBH[J] := IntToStr(Via.HoleSize);
                        If (VBX[J] = VX[J]) And (VBY[J] = VY[J]) And (VBS[J] = VS[J]) And (VBH[J] = VH[J]) Then
                        Begin
                            VStatus[J] := 'placed';
                            Inc(Placed);
                        End
                        Else
                        Begin
                            VStatus[J] := 'placed_readback_differs';
                            Partial := True;
                        End;
                    End;
                    For J := 0 To TNet.Count - 1 Do
                    Begin
                        If Partial Or (TStatus[J] <> 'would_place') Then Continue;
                        Net := FindNetByName(Board, TNet[J]);
                        Lyr := ResolveLayerId(Board, TLay[J]);
                        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
                        If (Track = Nil) Or (Net = Nil) Or (Lyr = eNoLayer) Then
                        Begin
                            TStatus[J] := 'not_placed: could not create the track';
                            Partial := True;
                            Continue;
                        End;
                        Touched := True;
                        Track.x1 := StrToInt(TX1[J]);
                        Track.y1 := StrToInt(TY1[J]);
                        Track.x2 := StrToInt(TX2[J]);
                        Track.y2 := StrToInt(TY2[J]);
                        Track.Width := StrToInt(TW[J]);
                        Track.Layer := Lyr;
                        Track.Net := Net;
                        Board.AddPCBObject(Track);
                        PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast,
                            PCBM_BoardRegisteration, Track.I_ObjectAddress);
                        TBX1[J] := IntToStr(Track.x1);
                        TBY1[J] := IntToStr(Track.y1);
                        TBX2[J] := IntToStr(Track.x2);
                        TBY2[J] := IntToStr(Track.y2);
                        TBW[J] := IntToStr(Track.Width);
                        { Altium stores a track with its ends in its own order (the first live   }
                        { apply, 2026-10-09, read x1 / x2 swapped and stopped the batch after    }
                        { one correct track): either order is the same track.                   }
                        If (TBW[J] = TW[J]) And (((TBX1[J] = TX1[J]) And (TBY1[J] = TY1[J]) And (TBX2[J] = TX2[J]) And (TBY2[J] = TY2[J]))
                            Or ((TBX1[J] = TX2[J]) And (TBY1[J] = TY2[J]) And (TBX2[J] = TX1[J]) And (TBY2[J] = TY1[J]))) Then
                        Begin
                            TStatus[J] := 'placed';
                            Inc(Placed);
                        End
                        Else
                        Begin
                            TStatus[J] := 'placed_readback_differs';
                            Partial := True;
                        End;
                    End;
                Finally
                    PCBServer.PostProcess;
                End;
            Finally
                If Touched Then MarkDocDirtyByPath(PcbPath);
            End;
            For J := 0 To VNet.Count - 1 Do
                If VStatus[J] = 'would_place' Then
                Begin
                    VStatus[J] := 'not_placed';
                    Inc(NotPlaced);
                End;
            For J := 0 To TNet.Count - 1 Do
                If TStatus[J] = 'would_place' Then
                Begin
                    TStatus[J] := 'not_placed';
                    Inc(NotPlaced);
                End;
        End;

        ViasStr := '';
        For J := 0 To VNet.Count - 1 Do
        Begin
            If J > 0 Then ViasStr := ViasStr + ',';
            ViasStr := ViasStr + '{"net":"' + EscapeJsonString(VNet[J]) + '","x":"' + VX[J] + '","y":"' + VY[J]
                + '","size":"' + VS[J] + '","hole":"' + VH[J] + '","clearance":"' + VC[J]
                + '","status":"' + EscapeJsonString(VStatus[J]) + '"';
            If Apply Then
                ViasStr := ViasStr + ',"readback_x":"' + VBX[J] + '","readback_y":"' + VBY[J]
                    + '","readback_size":"' + VBS[J] + '","readback_hole":"' + VBH[J] + '"';
            ViasStr := ViasStr + '}';
        End;
        TracksStr := '';
        For J := 0 To TNet.Count - 1 Do
        Begin
            If J > 0 Then TracksStr := TracksStr + ',';
            TracksStr := TracksStr + '{"net":"' + EscapeJsonString(TNet[J]) + '","layer":"' + EscapeJsonString(TLay[J])
                + '","board_layer":"' + EscapeJsonString(TLayerName[J])
                + '","x1":"' + TX1[J] + '","y1":"' + TY1[J] + '","x2":"' + TX2[J] + '","y2":"' + TY2[J]
                + '","width":"' + TW[J] + '","clearance":"' + TC[J]
                + '","status":"' + EscapeJsonString(TStatus[J]) + '"';
            If Apply Then
                TracksStr := TracksStr + ',"readback_x1":"' + TBX1[J] + '","readback_y1":"' + TBY1[J]
                    + '","readback_x2":"' + TBX2[J] + '","readback_y2":"' + TBY2[J] + '","readback_width":"' + TBW[J] + '"';
            TracksStr := TracksStr + '}';
        End;
        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again before trusting the board'
                + ' (placed: ' + IntToStr(Placed) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode
                + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash)
                + '","via_count":' + IntToStr(VNet.Count)
                + ',"track_count":' + IntToStr(TNet.Count)
                + ',"free_vias":' + IntToStr(FreeVias)
                + ',"free_tracks":' + IntToStr(FreeTracks)
                + ',"would_place":' + IntToStr(WouldPlace)
                + ',"unchanged":' + IntToStr(Unchanged)
                + ',"refused":' + IntToStr(Refused)
                + ',"placed":' + IntToStr(Placed)
                + ',"not_placed":' + IntToStr(NotPlaced)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"vias":[' + ViasStr + '],"tracks":[' + TracksStr + ']}}');
    Finally
        { One tick, one batch. }
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        VNet.Free;
        VX.Free;
        VY.Free;
        VS.Free;
        VH.Free;
        VC.Free;
        VStatus.Free;
        VBX.Free;
        VBY.Free;
        VBS.Free;
        VBH.Free;
        TNet.Free;
        TLay.Free;
        TX1.Free;
        TY1.Free;
        TX2.Free;
        TY2.Free;
        TW.Free;
        TC.Free;
        TStatus.Free;
        TLayerName.Free;
        TBX1.Free;
        TBY1.Free;
        TBX2.Free;
        TBY2.Free;
        TBW.Free;
    End;
End;

{ ---- Checked board setup: stackup, classes, pairs, rooms and rules ----------- }
{ PROPOSAL-2026-10-09-setup-write-increment (Stefan 2026-10-09: "let's add       }
{ support for the bridge to do the rules and stackup edits"). One command,       }
{ pcb.setup_board_checked, in the SELECTED_PLACE_EDITS runtime behind the same   }
{ operator tick as the moves and the copper ("Allow board edits": one tick, one }
{ batch). Items, each compare-and-set on the state the preview read:             }
{   layer     a stack layer's copper thickness and the dielectric below it       }
{   netclass  a net class and its members (created, or members added)           }
{   pair      a differential pair from two nets                                  }
{   pairclass a differential-pair class and its members                          }
{   room      a confinement rule (the room other rules scope on)                 }
{   rule      a design rule by name: created, or updated in place; kinds         }
{             clearance, width, via, diffpair, matched, layers, polygon          }
{ Every number is a raw Altium coordinate (never mils; the upstream rule and    }
{ layer handlers round to mils), every write is read back, priorities are       }
{ reported and never written (writing Priority crashes the engine, see          }
{ PCB_SetRuleProperties). Nothing is deleted. Never saves.                       }

{ The value of key K in 'k=v^k=v^...' ('' when absent). }
Function SetupField(Fields, K : String) : String;
Var
    Rest, Item, Key : String;
Begin
    Result := '';
    Rest := Fields;
    While Rest <> '' Do
    Begin
        Item := ParamEditTake(Rest, '^');
        Key := ParamEditTake(Item, '=');
        If Key = K Then
        Begin
            Result := Item;
            Exit;
        End;
    End;
End;

Function SetupFieldInt(Fields, K : String; Var Ok : Boolean) : Integer;
Var
    V : String;
Begin
    Result := 0;
    V := SetupField(Fields, K);
    If V = '' Then Exit;
    If Not PlaceEditIntOk(V) Then
    Begin
        Ok := False;
        Exit;
    End;
    Result := StrToInt(V);
End;

Function SetupIsCopperLayer(L : TLayer) : Boolean;
Begin
    Result := False;
    Try Result := PCB_IsCopperLayerName(GetLayerString(L)); Except Result := False; End;
End;

Function SetupFindRule(Board : IPCB_Board; Name : String) : IPCB_Rule;
Begin
    Result := PCB_FindRuleByName(Board, Name);
End;

Function SetupFindClass(Board : IPCB_Board; Name : String; MemberKind : Integer) : IPCB_ObjectClass;
Var
    Iter : IPCB_BoardIterator;
    C : IPCB_ObjectClass;
Begin
    Result := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.SetState_FilterAll;
        Iter.AddFilter_ObjectSet(MkSet(eClassObject));
        C := Iter.FirstPCBObject;
        While (C <> Nil) And (Result = Nil) Do
        Begin
            If (C.MemberKind = MemberKind) And (C.Name = Name) Then Result := C;
            C := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ The members of a class, sorted, comma-joined (the compare-and-set state). }
Function SetupClassMembers(C : IPCB_ObjectClass) : String;
Var
    L : TStringList;
    I : Integer;
    N : String;
Begin
    Result := '';
    If C = Nil Then Exit;
    L := TStringList.Create;
    Try
        I := 0;
        While I < 10000 Do
        Begin
            N := '';
            Try N := C.MemberName(I); Except N := ''; End;
            If N = '' Then Break;
            L.Add(N);
            Inc(I);
        End;
        L.Sort;
        Result := L.CommaText;
    Finally
        L.Free;
    End;
End;

Function SetupFindPair(Board : IPCB_Board; Name : String) : IPCB_DifferentialPair;
Var
    Iter : IPCB_BoardIterator;
    P : IPCB_DifferentialPair;
Begin
    Result := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eDifferentialPairObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        P := Iter.FirstPCBObject;
        While (P <> Nil) And (Result = Nil) Do
        Begin
            If P.Name = Name Then Result := P;
            P := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function SetupPairState(P : IPCB_DifferentialPair) : String;
Var
    A, B : String;
Begin
    Result := '';
    If P = Nil Then Exit;
    A := '';
    B := '';
    Try If P.PositiveNet <> Nil Then A := P.PositiveNet.Name; Except A := ''; End;
    Try If P.NegativeNet <> Nil Then B := P.NegativeNet.Name; Except B := ''; End;
    Result := A + ',' + B;
End;

{ A rule's compare-and-set state: descriptor, scopes, enabled. }
Function SetupRuleState(R : IPCB_Rule) : String;
Var
    D, S1, S2, E : String;
Begin
    Result := '';
    If R = Nil Then Exit;
    D := '';
    S1 := '';
    S2 := '';
    E := '';
    Try D := R.Descriptor; Except D := ''; End;
    Try S1 := R.Scope1Expression; Except S1 := ''; End;
    Try S2 := R.Scope2Expression; Except S2 := ''; End;
    Try E := BoolToJsonStr(R.Enabled); Except E := ''; End;
    Result := D + ' / ' + S1 + ' / ' + S2 + ' / ' + E;
End;

Function SetupRulePriority(R : IPCB_Rule) : String;
Begin
    Result := '';
    Try Result := IntToStr(R.Priority); Except Result := ''; End;
End;

Function SetupLayerState(LayerObj : IPCB_LayerObject_V7) : String;
Var
    N, T : String;
    C, H : Integer;
    K : Double;
Begin
    Result := '';
    If LayerObj = Nil Then Exit;
    N := '';
    T := '';
    C := -1;
    H := -1;
    K := -1;
    Try N := LayerObj.Name; Except N := ''; End;
    Try C := LayerObj.CopperThickness; Except C := -1; End;
    Try T := DielectricTypeToken(LayerObj); Except T := ''; End;
    Try H := LayerObj.Dielectric.DielectricHeight; Except H := -1; End;
    Try K := LayerObj.Dielectric.DielectricConstant; Except K := -1; End;
    Result := N + ',' + IntToStr(C) + ',' + T + ',' + IntToStr(H) + ',' + FloatToJsonStr(K);
End;

Function SetupRoomState(R : IPCB_ConfinementConstraint) : String;
Var
    Rect : TCoordRect;
    S : String;
Begin
    Result := '';
    If R = Nil Then Exit;
    S := '';
    Try S := R.Scope1Expression; Except S := ''; End;
    Try
        Rect := R.BoundingRect;
        Result := IntToStr(Rect.Left) + ',' + IntToStr(Rect.Bottom) + ',' + IntToStr(Rect.Right) + ',' + IntToStr(Rect.Top) + ',' + S;
    Except
        Result := '?,' + S;
    End;
End;

{ The rule kind word for a batch 'rule' item, from the live rule's RuleKind. }
Function SetupKindWord(R : IPCB_Rule) : String;
Var
    K : Integer;
Begin
    Result := '';
    K := -1;
    Try K := R.RuleKind; Except K := -1; End;
    If K = eRule_Clearance Then Result := 'clearance'
    Else If K = eRule_MaxMinWidth Then Result := 'width'
    Else If K = eRule_RoutingViaStyle Then Result := 'via'
    Else If K = eRule_DifferentialPairsRouting Then Result := 'diffpair'
    Else If K = eRule_MatchedLengths Then Result := 'matched'
    Else If K = eRule_RoutingLayers Then Result := 'layers'
    Else If K = eRule_PolygonConnectStyle Then Result := 'polygon'
    Else If K = eRule_ConfinementConstraint Then Result := 'room'
    Else If K = eRule_MaxMinHoleSize Then Result := 'hole'
    Else If K = eRule_SolderMaskExpansion Then Result := 'maskexp'
    Else If K = eRule_SilkToSolderMaskClearance Then Result := 'silkmask'
    Else If K = eRule_MinimumSolderMaskSliver Then Result := 'sliver'
    Else Result := 'kind' + IntToStr(K);
End;

{ Write a rule's values from the fields; the rule is already of the right kind.  }
{ Each kind takes its typed view (constraint setters live on the subtype; a   }
{ base IPCB_Rule write faults with "Undeclared identifier", which Try cannot  }
{ catch). Returns '' or the first problem.                                     }
Function SetupWriteRule(Board : IPCB_Board; R : IPCB_Rule; Kind, Fields : String) : String;
Var
    RC : IPCB_ClearanceConstraint;
    RW : IPCB_MaxMinWidthConstraint;
    RV : IPCB_RoutingViaStyleRule;
    RD : IPCB_DifferentialPairsRoutingRule;
    RM : IPCB_MatchedNetLengthsConstraint;
    RL : IPCB_RoutingLayersRule;
    RP : IPCB_PolygonConnectStyleRule;
    RH : IPCB_MaxMinHoleSizeConstraint;
    RX : IPCB_SolderMaskExpansionRule;
    RS : IPCB_SilkToSolderMaskClearanceRule;
    RV2 : IPCB_MinimumSolderMaskSliverRule;
    L : TLayer;
    V, Allowed, Lyr, Rest : String;
    Ok : Boolean;
    N : Integer;
Begin
    Result := '';
    Ok := True;
    V := SetupField(Fields, 'scope1');
    If V <> '' Then
    Begin
        Try R.Scope1Expression := V; Except Result := 'scope1 not accepted'; End;
    End;
    V := SetupField(Fields, 'scope2');
    If V <> '' Then
    Begin
        Try R.Scope2Expression := V; Except Result := 'scope2 not accepted'; End;
    End;
    V := SetupField(Fields, 'enabled');
    If V <> '' Then
    Begin
        Try R.Enabled := (V = 'true'); Except Result := 'enabled not accepted'; End;
    End;
    V := SetupField(Fields, 'netscope');
    If V = 'different' Then
    Begin
        Try R.NetScope := eNetScope_DifferentNetsOnly; Except Result := 'netscope not accepted'; End;
    End
    Else If V = 'any' Then
    Begin
        Try R.NetScope := eNetScope_AnyNet; Except Result := 'netscope not accepted'; End;
    End;
    If Result <> '' Then Exit;

    If Kind = 'clearance' Then
    Begin
        RC := R;
        N := SetupFieldInt(Fields, 'gap', Ok);
        If Ok And (SetupField(Fields, 'gap') <> '') Then
        Begin
            Try RC.Gap := N; Except Result := 'gap not accepted'; End;
        End;
    End
    Else If Kind = 'width' Then
    Begin
        RW := R;
        For L := MinLayer To MaxLayer Do
        Begin
            If SetupField(Fields, 'wmin') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'wmin', Ok);
                Try RW.MinWidth(L) := N; Except Result := 'wmin not accepted'; End;
            End;
            If SetupField(Fields, 'wmax') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'wmax', Ok);
                Try RW.MaxWidth(L) := N; Except Result := 'wmax not accepted'; End;
            End;
            If SetupField(Fields, 'wpref') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'wpref', Ok);
                Try RW.FavoredWidth(L) := N; Except Result := 'wpref not accepted'; End;
            End;
        End;
    End
    Else If Kind = 'via' Then
    Begin
        RV := R;
        If SetupField(Fields, 'hmin') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'hmin', Ok);
            Try RV.MinHoleWidth := N; Except Result := 'hmin not accepted'; End;
        End;
        If SetupField(Fields, 'hmax') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'hmax', Ok);
            Try RV.MaxHoleWidth := N; Except Result := 'hmax not accepted'; End;
        End;
        If SetupField(Fields, 'hpref') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'hpref', Ok);
            Try RV.PreferedHoleWidth := N; Except Result := 'hpref not accepted'; End;
        End;
        If SetupField(Fields, 'vmin') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'vmin', Ok);
            Try RV.MinWidth := N; Except Result := 'vmin not accepted'; End;
        End;
        If SetupField(Fields, 'vmax') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'vmax', Ok);
            Try RV.MaxWidth := N; Except Result := 'vmax not accepted'; End;
        End;
        If SetupField(Fields, 'vpref') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'vpref', Ok);
            Try RV.PreferedWidth := N; Except Result := 'vpref not accepted'; End;
        End;
    End
    Else If Kind = 'diffpair' Then
    Begin
        RD := R;
        For L := MinLayer To MaxLayer Do
        Begin
            If SetupField(Fields, 'gmin') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'gmin', Ok);
                Try RD.MinGap(L) := N; Except Result := 'gmin not accepted'; End;
            End;
            If SetupField(Fields, 'gmax') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'gmax', Ok);
                Try RD.MaxGap(L) := N; Except Result := 'gmax not accepted'; End;
            End;
            If SetupField(Fields, 'gpref') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'gpref', Ok);
                Try RD.PreferedGap(L) := N; Except Result := 'gpref not accepted'; End;
            End;
            { Width triple through the SetState_ methods, whose names and signatures were  }
            { read from Altium.SDK.Interfaces.dll (2026-10-09): SetState_MinWidth(Layer,  }
            { Value), SetState_MaxWidth, SetState_PreferedWidth.                           }
            If SetupField(Fields, 'pwmin') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwmin', Ok);
                Try RD.SetState_MinWidth(L, N); Except Result := 'pwmin not accepted'; End;
            End;
            If SetupField(Fields, 'pwmax') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwmax', Ok);
                Try RD.SetState_MaxWidth(L, N); Except Result := 'pwmax not accepted'; End;
            End;
            If SetupField(Fields, 'pwpref') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwpref', Ok);
                Try RD.SetState_PreferedWidth(L, N); Except Result := 'pwpref not accepted'; End;
            End;
        End;
        If SetupField(Fields, 'uncoupled') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'uncoupled', Ok);
            Try RD.MaxUncoupledLength := N; Except Result := 'uncoupled not accepted'; End;
        End;
    End
    Else If Kind = 'matched' Then
    Begin
        RM := R;
        If SetupField(Fields, 'tol') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'tol', Ok);
            Try RM.Tolerance := N; Except Result := 'tol not accepted'; End;
        End;
    End
    Else If Kind = 'layers' Then
    Begin
        { SetState_RoutingLayers(Layer, Boolean) per copper layer (Altium.SDK.Interfaces.dll,   }
        { 2026-10-09); the property form LayerAllowed was an unknown identifier to DelphiScript. }
        RL := R;
        Allowed := ',' + SetupField(Fields, 'layers') + ',';
        For L := MinLayer To MaxLayer Do
        Begin
            If SetupIsCopperLayer(L) Then
            Begin
                Lyr := GetLayerString(L);
                Try RL.SetState_RoutingLayers(L, (Pos(',' + Lyr + ',', Allowed) > 0)); Except Result := 'layers not accepted'; End;
            End;
        End;
    End
    Else If Kind = 'polygon' Then
    Begin
        { SetState_ConnectStyle(Int32) (Altium.SDK.Interfaces.dll, 2026-10-09): 0 relief,     }
        { 1 direct, 2 none, the order of TPlaneConnectStyle; the constant eDirectConnect is   }
        { not known to DelphiScript. The descriptor read back says "Direct Connect".          }
        RP := R;
        V := SetupField(Fields, 'style');
        If V = 'direct' Then
        Begin
            Try RP.SetState_ConnectStyle(1); Except Result := 'style not accepted'; End;
        End
        Else If V = 'relief' Then
        Begin
            Try RP.SetState_ConnectStyle(0); Except Result := 'style not accepted'; End;
        End;
    End
    Else If Kind = 'hole' Then
    Begin
        { IPCB_MaxMinHoleSizeConstraint.SetState_MinLimit / MaxLimit (SDK assembly 2026-10-09). }
        RH := R;
        If SetupField(Fields, 'holemin') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'holemin', Ok);
            Try RH.SetState_MinLimit(N); Except Result := 'holemin not accepted'; End;
        End;
        If SetupField(Fields, 'holemax') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'holemax', Ok);
            Try RH.SetState_MaxLimit(N); Except Result := 'holemax not accepted'; End;
        End;
    End
    Else If Kind = 'maskexp' Then
    Begin
        { IPCB_SolderMaskExpansionRule.SetState_Expansion; a negative expansion closes the      }
        { opening (tented vias) since the rule interface has no tenting flag.                  }
        RX := R;
        If SetupField(Fields, 'expansion') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'expansion', Ok);
            Try RX.SetState_Expansion(N); Except Result := 'expansion not accepted'; End;
        End;
    End
    Else If Kind = 'silkmask' Then
    Begin
        RS := R;
        If SetupField(Fields, 'silkgap') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'silkgap', Ok);
            Try RS.SetState_SilkToMaskGap(N); Except Result := 'silkgap not accepted'; End;
        End;
    End
    Else If Kind = 'sliver' Then
    Begin
        RV2 := R;
        If SetupField(Fields, 'sliver') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'sliver', Ok);
            Try RV2.SetState_MinSolderMaskSliver(N); Except Result := 'sliver not accepted'; End;
        End;
    End
    Else
        Result := 'unknown rule kind ' + Kind;
    If (Result = '') And (Not Ok) Then Result := 'a value is not an integer';
End;

Function SetupRuleKindId(Kind : String) : Integer;
Begin
    Result := -1;
    If Kind = 'clearance' Then Result := eRule_Clearance
    Else If Kind = 'width' Then Result := eRule_MaxMinWidth
    Else If Kind = 'via' Then Result := eRule_RoutingViaStyle
    Else If Kind = 'diffpair' Then Result := eRule_DifferentialPairsRouting
    Else If Kind = 'matched' Then Result := eRule_MatchedLengths
    Else If Kind = 'layers' Then Result := eRule_RoutingLayers
    Else If Kind = 'polygon' Then Result := eRule_PolygonConnectStyle
    Else If Kind = 'hole' Then Result := eRule_MaxMinHoleSize
    Else If Kind = 'maskexp' Then Result := eRule_SolderMaskExpansion
    Else If Kind = 'silkmask' Then Result := eRule_SilkToSolderMaskClearance
    Else If Kind = 'sliver' Then Result := eRule_MinimumSolderMaskSliver;
End;

{ Params: mode (preview | apply), batch_hash, items: 'kind|name|fields|old;...'  }
{ where fields is 'k=v^k=v' (raw integer coordinates, lists comma-joined, scope }
{ expressions verbatim) and old is the state the preview reported for that item }
{ (apply refuses the batch if any differs now). At most 80 items.               }
Function SelectedSetupBoardChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, ItemsStr, BatchHash, Rest, OpStr, Problems, Binding, Blank, ItemsJson : String;
    PcbPath, ErrCode, ErrMsg, State, Kind, Name, Fields, Old, Problem, Lyr, Members, Net : String;
    IKind, IName, IFields, IOld, IState, IStatus, IBack, IPrio : TStringList;
    J, Count, WouldChange, Unchanged, Refused, Done, NotDone : Integer;
    Apply, PcbModified, Partial, Touched, Ok, Exists : Boolean;
    Board : IPCB_Board;
    LayerStack : IPCB_LayerStack_V7;
    LayerObj : IPCB_LayerObject_V7;
    Rule : IPCB_Rule;
    Room : IPCB_ConfinementConstraint;
    NetClass : IPCB_ObjectClass;
    Pair : IPCB_DifferentialPair;
    NetA, NetB : IPCB_Net;
    Rect : TCoordRect;
    N, KindId : Integer;
    KD : Double;
    F0, F1, F2, F3 : String;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    ItemsStr := ExtractJsonValue(Params, 'items');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Board edits are not granted: the operator ticks "Allow board edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    IKind := TStringList.Create;
    IName := TStringList.Create;
    IFields := TStringList.Create;
    IOld := TStringList.Create;
    IState := TStringList.Create;
    IStatus := TStringList.Create;
    IBack := TStringList.Create;
    IPrio := TStringList.Create;
    SelectedBusy := True;
    Try
        If SelectedFreshnessJSON(P) = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P) + '); save or discard the named document');
            Exit;
        End;

        { Parse. }
        Rest := ItemsStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 80) Or (ParamEditCountChar(OpStr, '|') <> 3) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Item ' + IntToStr(Count) + ': expected kind|name|fields|old, at most 80 items');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|');
            F1 := ParamEditTake(OpStr, '|');
            F2 := ParamEditTake(OpStr, '|');
            F3 := OpStr;
            Ok := (F0 = 'layer') Or (F0 = 'netclass') Or (F0 = 'pair') Or (F0 = 'pairclass') Or (F0 = 'room') Or (F0 = 'rule');
            Ok := Ok And (Length(F1) >= 1) And (Length(F1) <= 60);
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Item ' + IntToStr(Count) + ': bad kind or name');
                Exit;
            End;
            IKind.Add(F0);
            IName.Add(F1);
            IFields.Add(F2);
            IOld.Add(F3);
            IState.Add(Blank);
            IStatus.Add(Blank);
            IBack.Add(Blank);
            IPrio.Add(Blank);
        End;
        If IKind.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No items');
            Exit;
        End;

        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;
        LayerStack := Board.LayerStack_V7;

        { Read and classify. The state string is what apply compares with.        }
        Problems := '';
        Refused := 0;
        WouldChange := 0;
        Unchanged := 0;
        For J := 0 To IKind.Count - 1 Do
        Begin
            Kind := IKind[J];
            Name := IName[J];
            Fields := IFields[J];
            State := '';
            Problem := '';
            If Kind = 'layer' Then
            Begin
                LayerObj := Nil;
                If LayerStack <> Nil Then
                Begin
                    Try LayerObj := ResolveStackLayerObject(LayerStack, Name); Except LayerObj := Nil; End;
                End;
                If LayerObj = Nil Then Problem := 'layer not in the stack'
                Else State := SetupLayerState(LayerObj);
            End
            Else If Kind = 'netclass' Then
            Begin
                NetClass := SetupFindClass(Board, Name, eClassMemberKind_Net);
                State := SetupClassMembers(NetClass);
                Members := SetupField(Fields, 'nets');
                If Members = '' Then Problem := 'no nets';
            End
            Else If Kind = 'pairclass' Then
            Begin
                NetClass := SetupFindClass(Board, Name, eClassMemberKind_DifferentialPair);
                State := SetupClassMembers(NetClass);
                If SetupField(Fields, 'pairs') = '' Then Problem := 'no pairs';
            End
            Else If Kind = 'pair' Then
            Begin
                Pair := SetupFindPair(Board, Name);
                State := SetupPairState(Pair);
                NetA := FindNetByName(Board, SetupField(Fields, 'pos'));
                NetB := FindNetByName(Board, SetupField(Fields, 'neg'));
                If (NetA = Nil) Or (NetB = Nil) Then Problem := 'a net is not on the board';
            End
            Else If Kind = 'room' Then
            Begin
                Rule := SetupFindRule(Board, Name);
                If Rule <> Nil Then
                Begin
                    If SetupKindWord(Rule) <> 'room' Then Problem := 'a rule of another kind has this name'
                    Else
                    Begin
                        Room := Rule;
                        State := SetupRoomState(Room);
                    End;
                End;
                Ok := True;
                N := SetupFieldInt(Fields, 'x1', Ok);
                N := SetupFieldInt(Fields, 'y1', Ok);
                N := SetupFieldInt(Fields, 'x2', Ok);
                N := SetupFieldInt(Fields, 'y2', Ok);
                If Not Ok Then Problem := 'bad rectangle';
            End
            Else If Kind = 'rule' Then
            Begin
                KindId := SetupRuleKindId(SetupField(Fields, 'kind'));
                If KindId < 0 Then Problem := 'unknown rule kind'
                Else
                Begin
                    Rule := SetupFindRule(Board, Name);
                    If Rule <> Nil Then
                    Begin
                        If SetupKindWord(Rule) <> SetupField(Fields, 'kind') Then
                            Problem := 'the existing rule is of kind ' + SetupKindWord(Rule)
                        Else
                        Begin
                            State := SetupRuleState(Rule);
                            IPrio[J] := SetupRulePriority(Rule);
                        End;
                    End;
                End;
            End;
            IState[J] := State;
            If Problem <> '' Then IStatus[J] := 'refused: ' + Problem
            Else If Apply And (State <> IOld[J]) Then IStatus[J] := 'refused: changed since preview'
            Else If (Kind = 'netclass') And (State = SetupField(Fields, 'nets')) Then IStatus[J] := 'unchanged'
            Else If (Kind = 'pairclass') And (State = SetupField(Fields, 'pairs')) Then IStatus[J] := 'unchanged'
            Else If (Kind = 'pair') And (State = SetupField(Fields, 'pos') + ',' + SetupField(Fields, 'neg')) Then IStatus[J] := 'unchanged'
            Else If State = '' Then IStatus[J] := 'would_create'
            Else IStatus[J] := 'would_update';
            If Copy(IStatus[J], 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 800 Then
                    Problems := Problems + Kind + ' ' + Name + ': ' + Copy(IStatus[J], 10, 200) + '; ';
            End
            Else If IStatus[J] = 'unchanged' Then Inc(Unchanged)
            Else Inc(WouldChange);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing written. ' + Problems);
            Exit;
        End;

        { Apply, item by item in batch order, each read back. Stops at the first   }
        { surprise; what was done is reported, never rolled back.                  }
        Done := 0;
        NotDone := 0;
        Partial := False;
        If Apply And (WouldChange > 0) Then
        Begin
            Try
                For J := 0 To IKind.Count - 1 Do
                Begin
                    If Partial Or ((IStatus[J] <> 'would_create') And (IStatus[J] <> 'would_update')) Then Continue;
                    Kind := IKind[J];
                    Name := IName[J];
                    Fields := IFields[J];
                    Problem := '';
                    Touched := True;
                    PCBServer.PreProcess;
                    Try
                        If Kind = 'layer' Then
                        Begin
                            LayerObj := ResolveStackLayerObject(LayerStack, Name);
                            Ok := True;
                            If SetupField(Fields, 'rename') <> '' Then
                            Begin
                                Try LayerObj.Name := SetupField(Fields, 'rename'); Except Problem := 'rename not accepted'; End;
                            End;
                            If SetupField(Fields, 'copper') <> '' Then
                            Begin
                                N := SetupFieldInt(Fields, 'copper', Ok);
                                Try LayerObj.CopperThickness := N; Except Problem := 'copper not accepted'; End;
                            End;
                            Lyr := SetupField(Fields, 'dtype');
                            If Lyr = 'none' Then
                            Begin
                                Try LayerObj.Dielectric.DielectricType := eNoDielectric; Except Problem := 'dtype not accepted'; End;
                            End
                            Else If Lyr = 'core' Then
                            Begin
                                Try LayerObj.Dielectric.DielectricType := eCore; Except Problem := 'dtype not accepted'; End;
                            End
                            Else If Lyr = 'prepreg' Then
                            Begin
                                Try LayerObj.Dielectric.DielectricType := ePrePreg; Except Problem := 'dtype not accepted'; End;
                            End;
                            If SetupField(Fields, 'dheight') <> '' Then
                            Begin
                                N := SetupFieldInt(Fields, 'dheight', Ok);
                                Try LayerObj.Dielectric.DielectricHeight := N; Except Problem := 'dheight not accepted'; End;
                            End;
                            If SetupField(Fields, 'dconst') <> '' Then
                            Begin
                                KD := StrToFloatDef(SetupField(Fields, 'dconst'), -1);
                                Try LayerObj.Dielectric.DielectricConstant := KD; Except Problem := 'dconst not accepted'; End;
                            End;
                            If SetupField(Fields, 'material') <> '' Then
                            Begin
                                Try LayerObj.Dielectric.DielectricMaterial := SetupField(Fields, 'material'); Except Problem := 'material not accepted'; End;
                            End;
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, c_NoEventData);
                            IBack[J] := SetupLayerState(LayerObj);
                        End
                        Else If Kind = 'netclass' Then
                        Begin
                            NetClass := SetupFindClass(Board, Name, eClassMemberKind_Net);
                            If NetClass = Nil Then
                            Begin
                                NetClass := PCBServer.PCBClassFactoryByClassMember(eClassMemberKind_Net);
                                NetClass.SuperClass := False;
                                NetClass.Name := Name;
                                Board.AddPCBObject(NetClass);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, NetClass.I_ObjectAddress);
                            End;
                            Members := SetupField(Fields, 'nets');
                            While Members <> '' Do
                            Begin
                                Net := ParamEditTake(Members, ',');
                                If Net <> '' Then NetClass.AddMemberByName(Net);
                            End;
                            IBack[J] := SetupClassMembers(NetClass);
                        End
                        Else If Kind = 'pairclass' Then
                        Begin
                            NetClass := SetupFindClass(Board, Name, eClassMemberKind_DifferentialPair);
                            If NetClass = Nil Then
                            Begin
                                NetClass := PCBServer.PCBClassFactoryByClassMember(eClassMemberKind_DifferentialPair);
                                NetClass.SuperClass := False;
                                NetClass.Name := Name;
                                Board.AddPCBObject(NetClass);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, NetClass.I_ObjectAddress);
                            End;
                            Members := SetupField(Fields, 'pairs');
                            While Members <> '' Do
                            Begin
                                Net := ParamEditTake(Members, ',');
                                If Net <> '' Then NetClass.AddMemberByName(Net);
                            End;
                            IBack[J] := SetupClassMembers(NetClass);
                        End
                        Else If Kind = 'pair' Then
                        Begin
                            Pair := SetupFindPair(Board, Name);
                            NetA := FindNetByName(Board, SetupField(Fields, 'pos'));
                            NetB := FindNetByName(Board, SetupField(Fields, 'neg'));
                            If Pair = Nil Then
                            Begin
                                Pair := PCBServer.PCBObjectFactory(eDifferentialPairObject, eNoDimension, eCreate_Default);
                                Pair.Name := Name;
                                Pair.PositiveNet := NetA;
                                Pair.NegativeNet := NetB;
                                Board.AddPCBObject(Pair);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pair.I_ObjectAddress);
                            End
                            Else
                            Begin
                                Pair.PositiveNet := NetA;
                                Pair.NegativeNet := NetB;
                            End;
                            IBack[J] := SetupPairState(Pair);
                        End
                        Else If Kind = 'room' Then
                        Begin
                            Rule := SetupFindRule(Board, Name);
                            Ok := True;
                            { A room's region is a polygon that only its creation builds from the   }
                            { bounding rectangle: on 2026-10-09 an updated rectangle read back      }
                            { right while DRC kept scoping on the old region. So an existing room  }
                            { is removed and created again (the one delete this command does).     }
                            If Rule <> Nil Then
                            Begin
                                Board.RemovePCBObject(Rule);
                                Rule := Nil;
                            End;
                            If Rule = Nil Then
                            Begin
                                Room := PCBServer.PCBRuleFactory(eRule_ConfinementConstraint);
                                Room.Name := Name;
                                Room.Comment := 'Room: ' + Name;
                                Room.NetScope := eNetScope_AnyNet;
                                Room.LayerKind := eRuleLayerKind_SameLayer;
                                Room.Kind := eConfineIn;
                                Room.Enabled := True;
                                Exists := False;
                            End
                            Else
                            Begin
                                Room := Rule;
                                Exists := True;
                            End;
                            If SetupField(Fields, 'scope') <> '' Then Room.Scope1Expression := SetupField(Fields, 'scope');
                            Rect := Room.BoundingRect;
                            Rect.Left := SetupFieldInt(Fields, 'x1', Ok);
                            Rect.Bottom := SetupFieldInt(Fields, 'y1', Ok);
                            Rect.Right := SetupFieldInt(Fields, 'x2', Ok);
                            Rect.Top := SetupFieldInt(Fields, 'y2', Ok);
                            Room.BoundingRect := Rect;
                            If Not Exists Then
                            Begin
                                Board.AddPCBObject(Room);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Room.I_ObjectAddress);
                            End;
                            IBack[J] := SetupRoomState(Room);
                        End
                        Else If Kind = 'rule' Then
                        Begin
                            Rule := SetupFindRule(Board, Name);
                            KindId := SetupRuleKindId(SetupField(Fields, 'kind'));
                            Exists := (Rule <> Nil);
                            If Rule = Nil Then
                            Begin
                                Rule := PCBServer.PCBRuleFactory(KindId);
                                Rule.Name := Name;
                                Rule.Enabled := True;
                            End;
                            Problem := SetupWriteRule(Board, Rule, SetupField(Fields, 'kind'), Fields);
                            If Not Exists Then
                            Begin
                                Board.AddPCBObject(Rule);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Rule.I_ObjectAddress);
                            End;
                            IBack[J] := SetupRuleState(Rule);
                            IPrio[J] := SetupRulePriority(Rule);
                        End;
                    Finally
                        PCBServer.PostProcess;
                    End;
                    If Problem <> '' Then
                    Begin
                        IStatus[J] := 'not_done: ' + Problem;
                        Partial := True;
                    End
                    Else If IStatus[J] = 'would_create' Then
                    Begin
                        IStatus[J] := 'created';
                        Inc(Done);
                    End
                    Else
                    Begin
                        IStatus[J] := 'updated';
                        Inc(Done);
                    End;
                End;
            Finally
                If Touched Then MarkDocDirtyByPath(PcbPath);
            End;
            For J := 0 To IKind.Count - 1 Do
                If (IStatus[J] = 'would_create') Or (IStatus[J] = 'would_update') Then
                Begin
                    IStatus[J] := 'not_done';
                    Inc(NotDone);
                End;
        End;

        ItemsJson := '';
        For J := 0 To IKind.Count - 1 Do
        Begin
            If J > 0 Then ItemsJson := ItemsJson + ',';
            ItemsJson := ItemsJson + '{"kind":"' + EscapeJsonString(IKind[J]) + '","name":"' + EscapeJsonString(IName[J])
                + '","state":"' + EscapeJsonString(IState[J]) + '","priority":"' + EscapeJsonString(IPrio[J])
                + '","status":"' + EscapeJsonString(IStatus[J]) + '"';
            If Apply Then ItemsJson := ItemsJson + ',"readback":"' + EscapeJsonString(IBack[J]) + '"';
            ItemsJson := ItemsJson + '}';
        End;
        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again before trusting the board'
                + ' (done: ' + IntToStr(Done) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode
                + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash)
                + '","item_count":' + IntToStr(IKind.Count)
                + ',"would_change":' + IntToStr(WouldChange)
                + ',"unchanged":' + IntToStr(Unchanged)
                + ',"refused":' + IntToStr(Refused)
                + ',"done":' + IntToStr(Done)
                + ',"not_done":' + IntToStr(NotDone)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"items":[' + ItemsJson + ']}}');
    Finally
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        IKind.Free;
        IName.Free;
        IFields.Free;
        IOld.Free;
        IState.Free;
        IStatus.Free;
        IBack.Free;
        IPrio.Free;
    End;
End;

{ ---- Native actions (PROPOSAL-2026-11-17-native-actions-increment) ------- }
{ Batch DRC, repour and one OutJob container on the SELECTED project only.    }
{ Reachable only in a runtime with SELECTED_PLACE_EDITS. None of them saves.  }
{ Enum values are passed as literals read from AD23's SDK by reflection       }
{ (TDRCReportFileFormat eDRC_Text = 1, TPolygonRepourMode eAlwaysRepour = 2): }
{ an unknown identifier halts the script loop and cannot be caught.           }

Function ActionsPolyChildren(Poly : IPCB_Polygon) : Integer;
Var
    GIter : IPCB_GroupIterator;
    Child : IPCB_Primitive;
Begin
    Result := 0;
    Try
        GIter := Poly.GroupIterator_Create;
        Child := GIter.FirstPCBObject;
        While Child <> Nil Do
        Begin
            Inc(Result);
            Child := GIter.NextPCBObject;
        End;
        Poly.GroupIterator_Destroy(GIter);
    Except
        Result := -1;
    End;
End;

Function SelectedRunDrcChecked(P : IProject; Params, RequestId : String) : String;
Var
    Board : IPCB_Board;
    PcbPath, ErrCode, ErrMsg, ReportPath, Items, Binding : String;
    PcbModified, ModifiedAfter, BatchOk, Present : Boolean;
    Iterator : IPCB_BoardIterator;
    Violation : IPCB_Violation;
    Count, Listed : Integer;
Begin
    Binding := SelectionJSON(0);
    SelectedBusy := True;
    Try
        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        { The report goes to the runtime workspace, never the project folder; }
        { the old one is deleted first, so a report afterwards is this run's. }
        { Altium writes the text format as <name>.txt whatever extension it is   }
        { given (qualification 2026-11-17: .DRC asked, .txt written), so ask .txt. }
        ReportPath := WorkspaceDir + 'selected-drc.txt';
        Try If FileExists(ReportPath) Then DeleteFile(ReportPath); Except End;
        BatchOk := False;
        Try
            BatchOk := Board.RunBatchDesignRuleCheck(ReportPath, 1, False, False);
        Except
            BatchOk := False;
        End;
        Present := False;
        Try Present := FileExists(ReportPath); Except Present := False; End;

        Count := 0;
        Items := '';
        Iterator := Board.BoardIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(eViolationObject));
        Iterator.AddFilter_LayerSet(AllLayers);
        Iterator.AddFilter_Method(eProcessAll);
        Violation := Iterator.FirstPCBObject;
        While Violation <> Nil Do
        Begin
            Inc(Count);
            If Count <= 500 Then
            Begin
                If Items <> '' Then Items := Items + ',';
                Items := Items + BuildViolationJson(Violation);
            End;
            Violation := Iterator.NextPCBObject;
        End;
        Board.BoardIterator_Destroy(Iterator);
        Listed := Count;
        If Listed > 500 Then Listed := 500;

        Try ModifiedAfter := Client.GetDocumentByPath(PcbPath).Modified; Except ModifiedAfter := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'SELECTION_CHANGED', 'Project changed during the DRC; discard result')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"pcb_path":"' + EscapeJsonString(PcbPath)
                + '","report_path":"' + EscapeJsonString(ReportPath)
                + '","report_present":' + BoolToJsonStr(Present)
                + ',"batch_returned":' + BoolToJsonStr(BatchOk)
                + ',"violation_count":' + IntToStr(Count)
                + ',"violations_listed":' + IntToStr(Listed)
                + ',"pcb_modified_before":' + BoolToJsonStr(PcbModified)
                + ',"pcb_modified_after":' + BoolToJsonStr(ModifiedAfter)
                + ',"saved":false,"violations":[' + Items + ']}}');
    Finally
        SelectedBusy := False;
    End;
End;

Function SelectedRepourChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, BatchHash, PcbPath, ErrCode, ErrMsg, Items, NetName, Binding : String;
    Apply, PcbModified, Ok, Touched : Boolean;
    Board : IPCB_Board;
    Iter : IPCB_BoardIterator;
    Poly, Temp : IPCB_Polygon;
    Polys : TInterfaceList;
    I, J, Rebuilt, Shelved, Failed, Before, After, OldMode : Integer;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Board edits are not granted: the operator ticks "Allow board edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Touched := False;
    SelectedBusy := True;
    Try
        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;

        { Collected first: a rebuild adds and removes children under a live }
        { iterator. Never freed (TInterfaceList.Free on design objects      }
        { crashes Altium); the script host reclaims it.                     }
        Polys := CreateObject(TInterfaceList);
        Iter := Board.BoardIterator_Create;
        Iter.AddFilter_ObjectSet(MkSet(ePolyObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Poly := Iter.FirstPCBObject;
        While Poly <> Nil Do
        Begin
            Polys.Add(Poly);
            Poly := Iter.NextPCBObject;
        End;
        Board.BoardIterator_Destroy(Iter);
        For I := 0 To Polys.Count - 1 Do
            For J := 0 To Polys.Count - 2 - I Do
                If Polys[J].PourIndex > Polys[J + 1].PourIndex Then
                Begin
                    Temp := Polys[J];
                    Polys[J] := Polys[J + 1];
                    Polys[J + 1] := Temp;
                End;

        Rebuilt := 0; Shelved := 0; Failed := 0;
        Items := '';
        OldMode := PCBServer.SystemOptions.PolygonRepour;
        If Apply Then PCBServer.SystemOptions.PolygonRepour := 2;
        Try
            For I := 0 To Polys.Count - 1 Do
            Begin
                Poly := Polys[I];
                NetName := '';
                Try If Poly.Net <> Nil Then NetName := Poly.Net.Name; Except End;
                Before := ActionsPolyChildren(Poly);
                If Items <> '' Then Items := Items + ',';
                Items := Items + '{"name":"' + EscapeJsonString(Poly.Name)
                    + '","net":"' + EscapeJsonString(NetName)
                    + '","layer":"' + EscapeJsonString(GetLayerString(Poly.Layer))
                    + '","pour_index":' + IntToStr(Poly.PourIndex)
                    + ',"poured":' + BoolToJsonStr(Poly.Poured)
                    + ',"children_before":' + IntToStr(Before);
                If Not Poly.Poured Then
                Begin
                    Inc(Shelved);
                    Items := Items + ',"status":"shelved"}';
                End
                Else If Not Apply Then
                    Items := Items + ',"status":"would_rebuild"}'
                Else
                Begin
                    Ok := True;
                    Touched := True;
                    PCBServer.PreProcess;
                    Try
                        Poly.BeginModify;
                        Poly.SetState_CopperPourInvalid;
                        Poly.Rebuild;
                        Poly.EndModify;
                        Poly.GraphicallyInvalidate;
                    Except
                        Ok := False;
                    End;
                    PCBServer.PostProcess;
                    After := ActionsPolyChildren(Poly);
                    If Ok Then Inc(Rebuilt) Else Inc(Failed);
                    If Ok Then Items := Items + ',"status":"rebuilt"'
                    Else Items := Items + ',"status":"failed"';
                    Items := Items + ',"children_after":' + IntToStr(After) + '}';
                End;
            End;
        Finally
            PCBServer.SystemOptions.PolygonRepour := OldMode;
            If Touched Then MarkDocDirtyByPath(PcbPath);
        End;

        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again before trusting the board'
                + ' (rebuilt: ' + IntToStr(Rebuilt) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode
                + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash)
                + '","polygons":' + IntToStr(Polys.Count)
                + ',"rebuilt":' + IntToStr(Rebuilt)
                + ',"shelved":' + IntToStr(Shelved)
                + ',"failed":' + IntToStr(Failed)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"items":[' + Items + ']}}');
    Finally
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
    End;
End;

Function SelectedRunOutJobChecked(P : IProject; Params, RequestId : String) : String;
Var
    Wanted, Container, OutJobPath, Path, Freshness, Binding, Section, Name : String;
    ContainerType, BasePath, Focused : String;
    I, Found, G, J, MediumIndex : Integer;
    D : IDocument;
    IniFile : TIniFile;
    OutJobDoc : IServerDocument;
    Workspace : IWorkspace;
    Active, RunRaised, Opened : Boolean;
Begin
    Wanted := ExtractJsonValue(Params, 'outjob');
    Container := ExtractJsonValue(Params, 'container');
    If (Container = '') Or (Length(Container) > 80) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'container is required (at most 80 characters)');
        Exit;
    End;
    Binding := SelectionJSON(0);
    SelectedBusy := True;
    Try
        Freshness := SelectedFreshnessJSON(P);
        If Freshness = '' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'INCOMPLETE_DOCUMENTS',
                'Cannot establish selected-project document identity ('
                + SelectedIdentityProblems(P) + '); save or discard the named document');
            Exit;
        End;
        If ExtractJsonValue(Freshness, 'dirty_doc_count') <> '0' Then
        Begin
            Result := BuildErrorResponse(RequestId, 'DIRTY_PROJECT',
                'Save the project first: outputs must come from the saved files');
            Exit;
        End;

        { The selected project's own OutJob member: exactly one, or the named one. }
        OutJobPath := '';
        Found := 0;
        For I := 0 To P.DM_LogicalDocumentCount - 1 Do
        Begin
            D := P.DM_LogicalDocuments(I);
            If D = Nil Then Continue;
            If UpperCase(D.DM_DocumentKind) <> 'OUTPUTJOB' Then Continue;
            Path := D.DM_FullPath;
            If (Wanted <> '') And (UpperCase(ExtractFileName(Path)) <> UpperCase(Wanted)) Then Continue;
            Inc(Found);
            OutJobPath := Path;
        End;
        If Found = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'NO_OUTJOB', 'The selected project has no such OutJob member');
            Exit;
        End;
        If Found > 1 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'AMBIGUOUS_OUTJOB', 'More than one OutJob; name one with outjob');
            Exit;
        End;

        { Container, type and base folder from the OutJob file (INI). }
        ContainerType := '';
        BasePath := '';
        MediumIndex := 0;
        IniFile := TIniFile.Create(OutJobPath);
        Try
            G := 1;
            While (MediumIndex = 0) And (G <= 20) Do
            Begin
                Section := 'OutputGroup' + IntToStr(G);
                If IniFile.ReadString(Section, 'OutputMedium1', '') = '' Then Break;
                J := 1;
                While J <= 64 Do
                Begin
                    Name := IniFile.ReadString(Section, 'OutputMedium' + IntToStr(J), '');
                    If Name = '' Then Break;
                    If Name = Container Then
                    Begin
                        MediumIndex := J;
                        ContainerType := IniFile.ReadString(Section, 'OutputMedium' + IntToStr(J) + '_Type', '');
                        Break;
                    End;
                    Inc(J);
                End;
                Inc(G);
            End;
            If MediumIndex > 0 Then
                BasePath := IniFile.ReadString('PublishSettings', 'OutputBasePath' + IntToStr(MediumIndex), '');
        Finally
            IniFile.Free;
        End;
        If MediumIndex = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'CONTAINER_NOT_FOUND', 'No container named ' + Container);
            Exit;
        End;
        If (ContainerType <> 'GeneratedFiles') And (ContainerType <> 'Publish') Then
        Begin
            Result := BuildErrorResponse(RequestId, 'CONTAINER_REFUSED',
                'Only GeneratedFiles and Publish containers run; ' + Container + ' is ' + ContainerType);
            Exit;
        End;
        If (BasePath <> '') And (Not ((Length(BasePath) >= 2) And (Copy(BasePath, 2, 1) = ':'))) Then
            BasePath := ExtractFilePath(OutJobPath) + BasePath;

        { A container writes nothing unless the OutJob is the ACTIVE document  }
        { (upstream, AD25 / AD26): open it as the Projects panel does, show it, }
        { focus it, then check.                                                 }
        Opened := False;
        OutJobDoc := Nil;
        Try OutJobDoc := Client.GetDocumentByPath(OutJobPath); Except OutJobDoc := Nil; End;
        If OutJobDoc = Nil Then
        Begin
            ResetParameters;
            AddStringParameter('ObjectKind', 'Document');
            AddStringParameter('FileName', OutJobPath);
            RunProcess('WorkspaceManager:OpenObject');
            Try OutJobDoc := Client.GetDocumentByPath(OutJobPath); Except OutJobDoc := Nil; End;
            Opened := (OutJobDoc <> Nil);
        End;
        If OutJobDoc <> Nil Then
        Begin
            Try Client.ShowDocument(OutJobDoc); Except End;
            Try OutJobDoc.Focus; Except End;
        End;
        Active := False;
        Focused := '';
        Try
            Workspace := GetWorkspace;
            If Workspace <> Nil Then
                If Workspace.DM_FocusedDocument <> Nil Then
                    Focused := Workspace.DM_FocusedDocument.DM_FullPath;
        Except
        End;
        Active := (UpperCase(Focused) = UpperCase(OutJobPath));
        If Not Active Then
        Begin
            Result := BuildErrorResponse(RequestId, 'OUTJOB_NOT_ACTIVE',
                'The OutJob did not become the active document (focused: ' + Focused + '); nothing was run');
            Exit;
        End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'SELECTION_CHANGED', 'Project changed while opening the OutJob; nothing was run');
            Exit;
        End;

        RunRaised := False;
        Try
            ResetParameters;
            If ContainerType = 'Publish' Then
            Begin
                AddStringParameter('Action', 'PublishToPDF');
                AddStringParameter('OutputMedium', Container);
                AddStringParameter('ObjectKind', 'OutputBatch');
                AddStringParameter('DisableDialog', 'True');
                RunProcess('WorkspaceManager:Print');
            End
            Else
            Begin
                AddStringParameter('Action', 'Run');
                AddStringParameter('OutputMedium', Container);
                AddStringParameter('ObjectKind', 'OutputBatch');
                RunProcess('WorkspaceManager:GenerateReport');
            End;
        Except
            RunRaised := True;
        End;

        { NOT a success claim: the client compares the output folder before }
        { and after and decides what was written.                            }
        Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
            + ',"result":{"process_issued":true'
            + ',"outjob_path":"' + EscapeJsonString(OutJobPath)
            + '","outjob_opened":' + BoolToJsonStr(Opened)
            + ',"container":"' + EscapeJsonString(Container)
            + '","container_type":"' + EscapeJsonString(ContainerType)
            + '","base_path":"' + EscapeJsonString(BasePath)
            + '","run_raised":' + BoolToJsonStr(RunRaised)
            + ',"saved":false}}');
    Finally
        SelectedBusy := False;
    End;
End;

{ ---- Checked annotate of '?' designators (PROPOSAL-2026-11-17, slice 2) --- }
{ Preview lists every component of the project's schematics: sheet index,     }
{ unique id, designator, library reference, multi-part and locked flags. The  }
{ client proposes the new names (sheet-hundreds numbering) and apply writes    }
{ each one by compare-and-set: same sheet, same UniqueId, current text equal   }
{ to old and ending in '?', new not used anywhere in the project. Multi-part   }
{ and locked designators are refused. Parameter tick; never saves.            }

Function AnnotateSheets(P : IProject; Paths : TStringList; Docs : TInterfaceList;
    Var ErrCode, ErrMsg : String) : Boolean;
Var
    I : Integer;
    D : IDocument;
    Path : String;
    S : IServerDocument;
    SchDoc : ISch_Document;
Begin
    Result := False;
    For I := 0 To P.DM_LogicalDocumentCount - 1 Do
    Begin
        D := P.DM_LogicalDocuments(I);
        If D = Nil Then Continue;
        If UpperCase(D.DM_DocumentKind) <> 'SCH' Then Continue;
        Path := D.DM_FullPath;
        S := Client.GetDocumentByPath(Path);
        If S = Nil Then
        Begin
            ErrCode := 'SHEET_NOT_OPEN';
            ErrMsg := 'Open every schematic of the selected project first (not open: ' + Path + ')';
            Exit;
        End;
        SchDoc := Nil;
        Try SchDoc := SchServer.GetSchDocumentByPath(Path); Except SchDoc := Nil; End;
        If SchDoc = Nil Then
        Begin
            ErrCode := 'SHEET_NOT_AVAILABLE';
            ErrMsg := 'Schematic editor did not resolve: ' + Path;
            Exit;
        End;
        Paths.Add(Path);
        Docs.Add(SchDoc);
    End;
    If Paths.Count = 0 Then
    Begin
        ErrCode := 'NO_SHEETS';
        ErrMsg := 'The selected project has no schematic';
        Exit;
    End;
    Result := True;
End;

Function AnnotateFind(Doc : ISch_Document; Uid : String; Var Hits : Integer) : ISch_Component;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
    U : String;
Begin
    Result := Nil;
    Hits := 0;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Comp := Obj;
            U := '';
            Try U := Comp.UniqueId; Except U := ''; End;
            If U = Uid Then
            Begin
                Inc(Hits);
                Result := Comp;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
    If Hits <> 1 Then Result := Nil;
End;

Function SelectedAnnotateChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, BatchHash, ItemsStr, Rest, OpStr, F0, F1, F2, F3, ErrCode, ErrMsg, Binding : String;
    Rows, Status, Problems, Back, Uid, Txt, Lib, Blank : String;
    Apply, Ok, Touched, Multi, Locked, Partial : Boolean;
    Paths, Used, ISheet, IUid, IOld, INew, IStatus, IBack, TouchedPaths : TStringList;
    Docs : TInterfaceList;
    I, J, K, Hits, Count, Refused, Written, Pending : Integer;
    Doc : ISch_Document;
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    ItemsStr := ExtractJsonValue(Params, 'items');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not ParamEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Parameter edits are not granted: the operator ticks "Allow parameter edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    Partial := False;
    Paths := TStringList.Create;
    Used := TStringList.Create;
    ISheet := TStringList.Create;
    IUid := TStringList.Create;
    IOld := TStringList.Create;
    INew := TStringList.Create;
    IStatus := TStringList.Create;
    IBack := TStringList.Create;
    TouchedPaths := TStringList.Create;
    Docs := CreateObject(TInterfaceList);
    SelectedBusy := True;
    Try
        If Not AnnotateSheets(P, Paths, Docs, ErrCode, ErrMsg) Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;

        { Every designator in the project, and (preview) the component list. }
        Rows := '';
        Count := 0;
        For I := 0 To Docs.Count - 1 Do
        Begin
            Doc := Docs[I];
            Iter := Doc.SchIterator_Create;
            Try
                Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
                Obj := Iter.FirstSchObject;
                While Obj <> Nil Do
                Begin
                    Comp := Obj;
                    Txt := '';
                    Try Txt := Comp.Designator.Text; Except Txt := ''; End;
                    Used.Add(UpperCase(Txt));
                    If Not Apply Then
                    Begin
                        Uid := ''; Lib := ''; Multi := False; Locked := False;
                        Try Uid := Comp.UniqueId; Except End;
                        Try Lib := Comp.LibReference; Except End;
                        Try Multi := Comp.IsMultiPartComponent; Except Multi := True; End;
                        Try Locked := Comp.DesignatorLocked; Except Locked := False; End;
                        If Rows <> '' Then Rows := Rows + ',';
                        Rows := Rows + '{"sheet":' + IntToStr(I)
                            + ',"unique_id":"' + EscapeJsonString(Uid)
                            + '","designator":"' + EscapeJsonString(Txt)
                            + '","lib_ref":"' + EscapeJsonString(Lib)
                            + '","multi_part":' + BoolToJsonStr(Multi)
                            + ',"locked":' + BoolToJsonStr(Locked) + '}';
                        Inc(Count);
                    End;
                    Obj := Iter.NextSchObject;
                End;
            Finally
                Doc.SchIterator_Destroy(Iter);
            End;
        End;

        If Not Apply Then
        Begin
            Problems := '';
            For I := 0 To Paths.Count - 1 Do
            Begin
                If Problems <> '' Then Problems := Problems + ',';
                Problems := Problems + '"' + EscapeJsonString(Paths[I]) + '"';
            End;
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"preview","batch_hash":"' + LowerCase(BatchHash)
                + '","sheets":[' + Problems + '],"component_count":' + IntToStr(Count)
                + ',"saved":false,"touched":false,"components":[' + Rows + ']}}');
            Exit;
        End;

        { Apply: parse sheet|uid|old|new items. }
        Rest := ItemsStr;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            If (ISheet.Count >= 200) Or (ParamEditCountChar(OpStr, '|') <> 3) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Expected sheet|unique_id|old|new, at most 200 items');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|');
            F1 := ParamEditTake(OpStr, '|');
            F2 := ParamEditTake(OpStr, '|');
            F3 := OpStr;
            K := StrToIntDef(F0, -1);
            If (K < 0) Or (K >= Docs.Count) Or (F1 = '') Or (Length(F3) < 2) Or (Length(F3) > 12)
                Or (Copy(F2, Length(F2), 1) <> '?') Or (Pos('?', F3) > 0) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Bad item: ' + F0 + '|' + F1 + '|' + F2 + '|' + F3);
                Exit;
            End;
            ISheet.Add(F0); IUid.Add(F1); IOld.Add(F2); INew.Add(F3);
            IStatus.Add(Blank); IBack.Add(Blank);
        End;
        If ISheet.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No items');
            Exit;
        End;

        { Preflight every item; refuse the whole batch on the first problem. }
        Refused := 0;
        Problems := '';
        For J := 0 To ISheet.Count - 1 Do
        Begin
            Status := '';
            K := StrToInt(ISheet[J]);
            If Client.GetDocumentByPath(Paths[K]).Modified Then Status := 'sheet has unsaved edits'
            Else
            Begin
                Comp := AnnotateFind(Docs[K], IUid[J], Hits);
                If Comp = Nil Then Status := 'component not found once on its sheet (' + IntToStr(Hits) + ')'
                Else If Comp.Designator.Text <> IOld[J] Then Status := 'designator changed since preview'
                Else If Comp.IsMultiPartComponent Then Status := 'multi-part component (annotate by hand)'
                Else If Comp.DesignatorLocked Then Status := 'designator is locked'
                Else If Used.IndexOf(UpperCase(INew[J])) >= 0 Then Status := INew[J] + ' is already used in the project';
            End;
            For I := 0 To J - 1 Do
                If UpperCase(INew[I]) = UpperCase(INew[J]) Then Status := INew[J] + ' twice in the batch';
            If Status <> '' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 600 Then Problems := Problems + IOld[J] + ' -> ' + INew[J] + ': ' + Status + '; ';
            End;
        End;
        If Refused > 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing written. ' + Problems);
            Exit;
        End;

        { Write per sheet, one PreProcess / PostProcess pair per touched sheet. }
        Written := 0;
        For K := 0 To Docs.Count - 1 Do
        Begin
            Pending := 0;
            For J := 0 To ISheet.Count - 1 Do
                If StrToInt(ISheet[J]) = K Then Inc(Pending);
            If (Pending = 0) Or Partial Then Continue;
            Doc := Docs[K];
            SchServer.ProcessControl.PreProcess(Doc, '');
            Try
                For J := 0 To ISheet.Count - 1 Do
                Begin
                    If (StrToInt(ISheet[J]) <> K) Or Partial Then Continue;
                    Comp := AnnotateFind(Doc, IUid[J], Hits);
                    If (Comp = Nil) Or (Comp.Designator.Text <> IOld[J]) Then
                    Begin
                        IStatus[J] := 'not_written: changed during apply';
                        Partial := True;
                        Continue;
                    End;
                    Touched := True;
                    If TouchedPaths.IndexOf(Paths[K]) < 0 Then TouchedPaths.Add(Paths[K]);
                    SchBeginModify(Comp.Designator);
                    Comp.Designator.Text := INew[J];
                    SchEndModify(Comp.Designator);
                    Back := Comp.Designator.Text;
                    IBack[J] := Back;
                    If Back = INew[J] Then
                    Begin
                        IStatus[J] := 'written';
                        Inc(Written);
                    End
                    Else
                    Begin
                        IStatus[J] := 'written_readback_differs';
                        Partial := True;
                    End;
                End;
            Finally
                Try SchServer.ProcessControl.PostProcess(Doc, 'Edit'); Except End;
                Try Doc.GraphicallyInvalidate; Except End;
            End;
        End;
        For I := 0 To TouchedPaths.Count - 1 Do MarkDocDirtyByPath(TouchedPaths[I]);
        For J := 0 To ISheet.Count - 1 Do
            If IStatus[J] = '' Then IStatus[J] := 'not_written';

        Rows := '';
        For J := 0 To ISheet.Count - 1 Do
        Begin
            If J > 0 Then Rows := Rows + ',';
            Rows := Rows + '{"sheet":' + ISheet[J] + ',"unique_id":"' + EscapeJsonString(IUid[J])
                + '","old":"' + EscapeJsonString(IOld[J]) + '","new":"' + EscapeJsonString(INew[J])
                + '","readback":"' + EscapeJsonString(IBack[J]) + '","status":"' + EscapeJsonString(IStatus[J]) + '"}';
        End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again (written: ' + IntToStr(Written) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"apply","batch_hash":"' + LowerCase(BatchHash)
                + '","item_count":' + IntToStr(ISheet.Count)
                + ',"written":' + IntToStr(Written)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"saved":false,"items":[' + Rows + ']}}');
    Finally
        If Touched Then
        Begin
            ParamEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        Paths.Free; Used.Free; ISheet.Free; IUid.Free; IOld.Free; INew.Free;
        IStatus.Free; IBack.Free; TouchedPaths.Free;
    End;
End;

{ ---- Checked graphic objects (TOOLS.md backlog 2, PROPOSAL-2026-11-17-graphics) }
{ Free pads (plated or not), rectangular fills, text and lines on non-copper     }
{ layers, placed on the SELECTED project's PcbDoc from a checked plan. Add-only, }
{ board-edits tick, one batch per save, compare-and-set on the counts of free    }
{ objects, every object read back, never saves. Items:                           }
{   kind|layer|x1|y1|x2|y2|w|net|text   (raw coordinates, integers)              }
{   pad : x1,y1 centre; x2 size; y2 hole (0 = SMD); w 1 plated / 0 not; text     }
{         round|rect. Through-hole pads go on MultiLayer.                        }
{   fill: x1,y1,x2,y2 corners; any layer; net only on copper                     }
{   text: x1,y1 location; x2 height; y2 rotation 0/90/180/270; w stroke; text    }
{         the string (client-checked plain ASCII); non-copper layers only        }
{   line: x1..y2, w width; non-copper layers only (copper goes through copper)   }
{ Enum values as literals, read from AD23's SDK: eRounded 1, eRectangular 2.     }

Procedure GraphicsCount(Board : IPCB_Board; Var Pads, Fills, Texts, Lines : Integer);
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
Begin
    Pads := 0; Fills := 0; Texts := 0; Lines := 0;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(ePadObject, eFillObject, eTextObject, eTrackObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If Not Prim.InComponent Then
            Begin
                If Prim.ObjectId = ePadObject Then Inc(Pads)
                Else If Prim.ObjectId = eFillObject Then Inc(Fills)
                Else If Prim.ObjectId = eTextObject Then Inc(Texts)
                Else If Not PCB_IsCopperLayerName(GetLayerString(Prim.Layer)) Then Inc(Lines);
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function SelectedPlaceGraphicsChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, ItemsStr, BatchHash, OldCounts, Rest, OpStr, Problems, Binding, Blank, What, ItemsJson : String;
    PcbPath, ErrCode, ErrMsg, LayerStr, Counts, Back, Status : String;
    IKind, ILay, IX1, IY1, IX2, IY2, IW, INet, IText, IStatus, IBack : TStringList;
    J, Count, WouldPlace, Refused, Placed, NPads, NFills, NTexts, NLines, Clearance, A, B : Integer;
    X1, Y1, X2, Y2, W : Integer;
    Apply, PcbModified, Partial, Touched, Ok, IsCopper : Boolean;
    Board : IPCB_Board;
    Net : IPCB_Net;
    Pad : IPCB_Pad;
    Fill : IPCB_Fill;
    TextObj : IPCB_Text;
    Track : IPCB_Track;
    Lyr : TLayer;
    Gap : Double;
    F0, F1, F2, F3, F4, F5, F6, F7, F8 : String;
    LoX, LoY, HiX, HiY : Integer;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    ItemsStr := ExtractJsonValue(Params, 'items');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    OldCounts := ExtractJsonValue(Params, 'old_counts');
    Clearance := StrToIntDef(ExtractJsonValue(Params, 'clearance'), -1);
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Board edits are not granted: the operator ticks "Allow board edits" in the bridge window');
        Exit;
    End;
    If (Not ParamEditHashValid(BatchHash)) Or (Clearance < 0) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters and clearance a raw coordinate');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    Partial := False;
    IKind := TStringList.Create; ILay := TStringList.Create; IX1 := TStringList.Create; IY1 := TStringList.Create;
    IX2 := TStringList.Create; IY2 := TStringList.Create; IW := TStringList.Create; INet := TStringList.Create;
    IText := TStringList.Create; IStatus := TStringList.Create; IBack := TStringList.Create;
    SelectedBusy := True;
    Try
        Rest := ItemsStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 100) Or (ParamEditCountChar(OpStr, '|') <> 8) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Item ' + IntToStr(Count) + ': expected 9 fields, at most 100 items');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|'); F1 := ParamEditTake(OpStr, '|'); F2 := ParamEditTake(OpStr, '|');
            F3 := ParamEditTake(OpStr, '|'); F4 := ParamEditTake(OpStr, '|'); F5 := ParamEditTake(OpStr, '|');
            F6 := ParamEditTake(OpStr, '|'); F7 := ParamEditTake(OpStr, '|'); F8 := OpStr;
            Ok := ((F0 = 'pad') Or (F0 = 'fill') Or (F0 = 'text') Or (F0 = 'line')) And CopperLayerNameOk(F1)
                And PlaceEditIntOk(F2) And PlaceEditIntOk(F3) And PlaceEditIntOk(F4) And PlaceEditIntOk(F5) And PlaceEditIntOk(F6);
            If Ok And (F7 <> '') Then Ok := PlaceEditNetOk(F7);
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Item ' + IntToStr(Count) + ': bad kind, layer, number or net');
                Exit;
            End;
            IKind.Add(F0); ILay.Add(F1); IX1.Add(F2); IY1.Add(F3); IX2.Add(F4); IY2.Add(F5);
            IW.Add(F6); INet.Add(F7); IText.Add(F8); IStatus.Add(Blank); IBack.Add(Blank);
        End;
        If IKind.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No items');
            Exit;
        End;

        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;
        GraphicsCount(Board, NPads, NFills, NTexts, NLines);
        Counts := IntToStr(NPads) + ',' + IntToStr(NFills) + ',' + IntToStr(NTexts) + ',' + IntToStr(NLines);
        If Apply And (Counts <> OldCounts) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED',
                'Nothing placed. The board''s free objects changed since the preview (' + Counts + '); preview again');
            Exit;
        End;

        { Classify. }
        Problems := '';
        Refused := 0;
        WouldPlace := 0;
        For J := 0 To IKind.Count - 1 Do
        Begin
            X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]); X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
            W := StrToInt(IW[J]);
            If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
            If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
            Status := '';
            Lyr := ResolveLayerId(Board, ILay[J]);
            LayerStr := '';
            If Lyr <> eNoLayer Then LayerStr := GetLayerString(Lyr);
            IsCopper := (Lyr = eMultiLayer) Or ((LayerStr <> '') And PCB_IsCopperLayerName(LayerStr));
            Net := Nil;
            If INet[J] <> '' Then Net := FindNetByName(Board, INet[J]);
            If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
            Else If (INet[J] <> '') And (Net = Nil) Then Status := 'refused: net not on the board'
            Else If (INet[J] <> '') And (Not IsCopper) Then Status := 'refused: a net on a non-copper layer'
            Else If IKind[J] = 'pad' Then
            Begin
                If (X2 <= 0) Or (Y2 < 0) Or (Y2 >= X2) Or ((W <> 0) And (W <> 1)) Or ((IText[J] <> 'round') And (IText[J] <> 'rect')) Then
                    Status := 'refused: pad needs size > hole >= 0, plated 0/1, shape round|rect'
                Else If (Y2 > 0) And (Lyr <> eMultiLayer) Then Status := 'refused: a drilled pad goes on MultiLayer'
                Else If (Y2 = 0) And (Lyr = eMultiLayer) Then Status := 'refused: an SMD pad goes on a copper layer'
                Else If Not IsCopper Then Status := 'refused: a pad goes on MultiLayer or a copper layer'
            End
            Else If IKind[J] = 'fill' Then
            Begin
                If (X1 = X2) Or (Y1 = Y2) Then Status := 'refused: empty rectangle'
                Else If Lyr = eMultiLayer Then Status := 'refused: a fill goes on one layer'
            End
            Else If IKind[J] = 'text' Then
            Begin
                If IsCopper Then Status := 'refused: text goes on silk, mechanical or other non-copper layers'
                Else If (X2 <= 0) Or (W <= 0) Or ((Y2 <> 0) And (Y2 <> 90) And (Y2 <> 180) And (Y2 <> 270))
                    Or (Length(IText[J]) < 1) Or (Length(IText[J]) > 40) Then
                    Status := 'refused: text needs height, stroke, rotation 0/90/180/270 and 1-40 characters'
            End
            Else If IKind[J] = 'line' Then
            Begin
                If IsCopper Then Status := 'refused: copper lines go through the copper writer'
                Else If (W <= 0) Or ((X1 = X2) And (Y1 = Y2)) Then Status := 'refused: line needs width and two distinct ends'
            End;
            { Other-net copper within the clearance, for copper pads and fills. }
            If (Status = '') And IsCopper And ((IKind[J] = 'pad') Or (IKind[J] = 'fill')) Then
            Begin
                If IKind[J] = 'pad' Then
                Begin
                    If Lyr = eMultiLayer Then
                        Gap := CopperNearest(Board, INet[J], eNoLayer, X1, Y1, X1, Y1, X2 / 2, Clearance, What)
                    Else
                        Gap := CopperNearest(Board, INet[J], Lyr, X1, Y1, X1, Y1, X2 / 2, Clearance, What);
                End
                Else If (HiX - LoX) >= (HiY - LoY) Then
                    Gap := CopperNearest(Board, INet[J], Lyr, LoX + (HiY - LoY) Div 2, (LoY + HiY) Div 2,
                        HiX - (HiY - LoY) Div 2, (LoY + HiY) Div 2, (HiY - LoY) / 2, Clearance, What)
                Else
                    Gap := CopperNearest(Board, INet[J], Lyr, (LoX + HiX) Div 2, LoY + (HiX - LoX) Div 2,
                        (LoX + HiX) Div 2, HiY - (HiX - LoX) Div 2, (HiX - LoX) / 2, Clearance, What);
                If Gap < Clearance Then
                    Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)';
            End;
            If Status = '' Then Status := 'would_place';
            IStatus[J] := Status;
            If Copy(Status, 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 800 Then Problems := Problems + IKind[J] + ' ' + IntToStr(J + 1) + ': ' + Copy(Status, 10, 200) + '; ';
            End
            Else Inc(WouldPlace);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing placed. ' + Problems);
            Exit;
        End;

        Placed := 0;
        If Apply And (WouldPlace > 0) Then
        Begin
            PCBServer.PreProcess;
            Try
                For J := 0 To IKind.Count - 1 Do
                Begin
                    If Partial Or (IStatus[J] <> 'would_place') Then Continue;
                    X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]); X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
                    W := StrToInt(IW[J]);
                    If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
                    If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
                    Lyr := ResolveLayerId(Board, ILay[J]);
                    Net := Nil;
                    If INet[J] <> '' Then Net := FindNetByName(Board, INet[J]);
                    Touched := True;
                    Back := '';
                    Ok := False;
                    If IKind[J] = 'pad' Then
                    Begin
                        Pad := PCBServer.PCBObjectFactory(ePadObject, eNoDimension, eCreate_Default);
                        If Pad <> Nil Then
                        Begin
                            Pad.X := X1;
                            Pad.Y := Y1;
                            { Same no-ring order rule as the copper writer's vias. }
                            If X2 > Pad.HoleSize Then
                            Begin
                                Pad.TopXSize := X2;
                                Pad.TopYSize := X2;
                                Pad.HoleSize := Y2;
                            End
                            Else
                            Begin
                                Pad.HoleSize := Y2;
                                Pad.TopXSize := X2;
                                Pad.TopYSize := X2;
                            End;
                            Pad.Layer := Lyr;
                            If IText[J] = 'rect' Then Pad.TopShape := 2 Else Pad.TopShape := 1;
                            If Y2 > 0 Then Pad.Plated := (W = 1);
                            If Net <> Nil Then Pad.Net := Net;
                            Board.AddPCBObject(Pad);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pad.I_ObjectAddress);
                            Back := IntToStr(Pad.X) + ',' + IntToStr(Pad.Y) + ',' + IntToStr(Pad.TopXSize) + ',' + IntToStr(Pad.HoleSize)
                                + ',' + BoolToJsonStr(Pad.Plated);
                            Ok := (Pad.X = X1) And (Pad.Y = Y1) And (Pad.TopXSize = X2) And (Pad.HoleSize = Y2)
                                And ((Y2 = 0) Or (Pad.Plated = (W = 1)));
                        End;
                    End
                    Else If IKind[J] = 'fill' Then
                    Begin
                        Fill := PCBServer.PCBObjectFactory(eFillObject, eNoDimension, eCreate_Default);
                        If Fill <> Nil Then
                        Begin
                            Fill.X1Location := LoX;
                            Fill.Y1Location := LoY;
                            Fill.X2Location := HiX;
                            Fill.Y2Location := HiY;
                            Fill.Rotation := 0;
                            Fill.Layer := Lyr;
                            If Net <> Nil Then Fill.Net := Net;
                            Board.AddPCBObject(Fill);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Fill.I_ObjectAddress);
                            Back := IntToStr(Fill.X1Location) + ',' + IntToStr(Fill.Y1Location) + ',' + IntToStr(Fill.X2Location) + ',' + IntToStr(Fill.Y2Location);
                            Ok := (Fill.X1Location = LoX) And (Fill.Y1Location = LoY) And (Fill.X2Location = HiX) And (Fill.Y2Location = HiY);
                        End;
                    End
                    Else If IKind[J] = 'text' Then
                    Begin
                        TextObj := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
                        If TextObj <> Nil Then
                        Begin
                            TextObj.XLocation := X1;
                            TextObj.YLocation := Y1;
                            TextObj.Layer := Lyr;
                            TextObj.UseTTFonts := False;
                            { A text on a bottom layer reads from the bottom: mirrored (upstream }
                            { 5cfd20f). Scripts 2026.11.23.1.                                    }
                            If Pos('Bottom', GetLayerString(Lyr)) = 1 Then TextObj.MirrorFlag := True;
                            TextObj.Text := IText[J];
                            TextObj.Size := X2;
                            TextObj.Width := W;
                            TextObj.Rotation := Y2;
                            Board.AddPCBObject(TextObj);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, TextObj.I_ObjectAddress);
                            Back := TextObj.Text + ',' + IntToStr(TextObj.XLocation) + ',' + IntToStr(TextObj.YLocation) + ',' + IntToStr(TextObj.Size);
                            Ok := (TextObj.Text = IText[J]) And (TextObj.XLocation = X1) And (TextObj.YLocation = Y1) And (TextObj.Size = X2);
                        End;
                    End
                    Else
                    Begin
                        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
                        If Track <> Nil Then
                        Begin
                            Track.x1 := X1;
                            Track.y1 := Y1;
                            Track.x2 := X2;
                            Track.y2 := Y2;
                            Track.Width := W;
                            Track.Layer := Lyr;
                            Board.AddPCBObject(Track);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
                            Back := IntToStr(Track.x1) + ',' + IntToStr(Track.y1) + ',' + IntToStr(Track.x2) + ',' + IntToStr(Track.y2) + ',' + IntToStr(Track.Width);
                            Ok := (Track.Width = W) And ((((Track.x1 = X1) And (Track.y1 = Y1) And (Track.x2 = X2) And (Track.y2 = Y2)))
                                Or ((Track.x1 = X2) And (Track.y1 = Y2) And (Track.x2 = X1) And (Track.y2 = Y1)));
                        End;
                    End;
                    IBack[J] := Back;
                    If Back = '' Then
                    Begin
                        IStatus[J] := 'not_placed: could not create the object';
                        Partial := True;
                    End
                    Else If Ok Then
                    Begin
                        IStatus[J] := 'placed';
                        Inc(Placed);
                    End
                    Else
                    Begin
                        IStatus[J] := 'placed_readback_differs';
                        Partial := True;
                    End;
                End;
            Finally
                PCBServer.PostProcess;
                If Touched Then MarkDocDirtyByPath(PcbPath);
            End;
            For J := 0 To IKind.Count - 1 Do
                If IStatus[J] = 'would_place' Then IStatus[J] := 'not_placed';
        End;

        ItemsJson := '';
        For J := 0 To IKind.Count - 1 Do
        Begin
            If J > 0 Then ItemsJson := ItemsJson + ',';
            ItemsJson := ItemsJson + '{"kind":"' + IKind[J] + '","layer":"' + EscapeJsonString(ILay[J])
                + '","status":"' + EscapeJsonString(IStatus[J]) + '","readback":"' + EscapeJsonString(IBack[J]) + '"}';
        End;
        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again (placed: ' + IntToStr(Placed) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash) + '","counts":"' + Counts
                + '","item_count":' + IntToStr(IKind.Count) + ',"would_place":' + IntToStr(WouldPlace)
                + ',"refused":' + IntToStr(Refused) + ',"placed":' + IntToStr(Placed)
                + ',"partial":' + BoolToJsonStr(Partial) + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched) + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"items":[' + ItemsJson + ']}}');
    Finally
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        IKind.Free; ILay.Free; IX1.Free; IY1.Free; IX2.Free; IY2.Free; IW.Free; INet.Free;
        IText.Free; IStatus.Free; IBack.Free;
    End;
End;

{ ---- Checked edits of free objects (TOOLS.md backlog 2 / 4, 2026-11-18) -------- }
{ Delete a free line on a non-copper layer, delete or move a free via, edit a     }
{ free text in place, redefine the board shape from free lines. Every op names    }
{ its target by exact geometry (and text), so it is its own compare-and-set; the  }
{ batch also binds the counts of free objects and the board-shape point count.   }
{ Board-edits tick, saved PcbDoc, one batch per save, read back, never saves.     }
{ Items op|layer|x1|y1|x2|y2|w|s1|s2 (raw coordinates):                           }
{   delline: layer (non-copper), x1..y2 the exact ends (either order)            }
{   delvia : x1,y1 centre, x2 size, y2 hole                                      }
{   movevia: x1,y1 old centre, x2,y2 new centre, w size, s1 hole; the new place   }
{            is checked against other-net copper with `clearance`                 }
{   text   : layer, x1,y1 location, s1 the old text, s2 the new (1-40 chars)      }
{   shape  : layer, s1 'x,y x,y ...' (3-64 vertices, in order); every vertex must  }
{            be an end of a free line on that layer (the client checks coverage)  }

Function FreeLineCount(Board : IPCB_Board; Lyr : TLayer; X1, Y1, X2, Y2 : Integer; Var First : IPCB_Track) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Track : IPCB_Track;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Not Prim.InPolygon) And (Not Prim.InDimension) And (Prim.Layer = Lyr) Then
            Begin
                Track := Prim;
                If ((Track.X1 = X1) And (Track.Y1 = Y1) And (Track.X2 = X2) And (Track.Y2 = Y2))
                    Or ((Track.X1 = X2) And (Track.Y1 = Y2) And (Track.X2 = X1) And (Track.Y2 = Y1)) Then
                Begin
                    Inc(Result);
                    If First = Nil Then First := Track;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Empties a string list. TStringList.Clear is not declared in Altium's script  }
{ engine (lint rule tstringlist-clear), and an undeclared name is a script      }
{ error no Try catches; Delete is declared. Until 2026-11-25 the polygon and    }
{ shape branches called .Clear and had never been run in Altium.               }
Procedure EmptyList(L : TStringList);
Begin
    While L.Count > 0 Do L.Delete(L.Count - 1);
End;

{ ---- Scripts 2026.11.23.1: polygon outlines from a plan, more free-object deletes ---- }
{ A polygon outline 'x,y x,y,cx,cy,a1,a2 ...' (raw units, angles in             }
{ millidegrees): a token with two numbers is a line vertex, one with six an arc }
{ from this vertex to the next, centre cx,cy, from angle a1 to a2 counter-      }
{ clockwise. 3 to 64 vertices. The lists stay parallel ('' for a line's arc     }
{ fields).                                                                      }
Function PolyVertices(S : String; VX, VY, VCX, VCY, VA1, VA2 : TStringList) : Boolean;
Var
    Rest, Tok, A, B, C, D, E, Blank : String;
    Commas : Integer;
Begin
    Result := False;
    Blank := '';
    Rest := S;
    While Rest <> '' Do
    Begin
        Tok := ParamEditTake(Rest, ' ');
        If Tok = '' Then Continue;
        Commas := ParamEditCountChar(Tok, ',');
        If (Commas <> 1) And (Commas <> 5) Then Exit;
        A := ParamEditTake(Tok, ',');
        If Commas = 1 Then
        Begin
            If (Not PlaceEditIntOk(A)) Or (Not PlaceEditIntOk(Tok)) Then Exit;
            VX.Add(A); VY.Add(Tok); VCX.Add(Blank); VCY.Add(Blank); VA1.Add(Blank); VA2.Add(Blank);
        End
        Else
        Begin
            B := ParamEditTake(Tok, ','); C := ParamEditTake(Tok, ','); D := ParamEditTake(Tok, ',');
            E := ParamEditTake(Tok, ',');
            If (Not PlaceEditIntOk(A)) Or (Not PlaceEditIntOk(B)) Or (Not PlaceEditIntOk(C)) Or (Not PlaceEditIntOk(D))
                Or (Not PlaceEditIntOk(E)) Or (Not PlaceEditIntOk(Tok)) Then Exit;
            VX.Add(A); VY.Add(B); VCX.Add(C); VCY.Add(D); VA1.Add(E); VA2.Add(Tok);
        End;
        If VX.Count > 64 Then Exit;
    End;
    Result := VX.Count >= 3;
End;

{ Write an outline into a polygon: PointCount, every segment as a whole record, }
{ then the closing vertex one past PointCount (upstream ClosePolySegments). The }
{ record is instantiated as our shape op does it; an arc carries its radius.    }
Procedure PolyWriteOutline(Poly : IPCB_Polygon; VX, VY, VCX, VCY, VA1, VA2 : TStringList);
Var
    K : Integer;
    Seg : TPolySegment;
    DX, DY : Double;
Begin
    Poly.PointCount := VX.Count;
    For K := 0 To VX.Count - 1 Do
    Begin
        Seg := TPolySegment;
        Seg.vx := StrToInt(VX[K]);
        Seg.vy := StrToInt(VY[K]);
        If VCX[K] = '' Then
            Seg.Kind := ePolySegmentLine
        Else
        Begin
            Seg.Kind := ePolySegmentArc;
            Seg.cx := StrToInt(VCX[K]);
            Seg.cy := StrToInt(VCY[K]);
            DX := (StrToInt(VX[K]) - StrToInt(VCX[K])) * 1.0;
            DY := (StrToInt(VY[K]) - StrToInt(VCY[K])) * 1.0;
            Seg.Radius := Round(Sqrt(DX * DX + DY * DY));
            Seg.Angle1 := StrToInt(VA1[K]) / 1000.0;
            Seg.Angle2 := StrToInt(VA2[K]) / 1000.0;
        End;
        Poly.Segments[K] := Seg;
    End;
    Seg := Poly.Segments[0];
    Seg.Kind := ePolySegmentLine;
    Poly.Segments[VX.Count] := Seg;
End;

{ Repour one polygon as the repour action does it (the option forced to Always). }
Procedure PolyRepour(Poly : IPCB_Polygon);
Var
    OldMode : Integer;
Begin
    OldMode := PCBServer.SystemOptions.PolygonRepour;
    PCBServer.SystemOptions.PolygonRepour := 2;
    Try
        Poly.SetState_CopperPourInvalid;
        Poly.Rebuild;
    Finally
        PCBServer.SystemOptions.PolygonRepour := OldMode;
    End;
End;

{ Free arcs on a non-copper layer with this centre and radius whose start angle }
{ is within 0.002 degrees of StartMilli / 1000.                                 }
Function FreeArcCount(Board : IPCB_Board; Lyr : TLayer; XC, YC, R, StartMilli : Integer; Var First : IPCB_Arc) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Arc : IPCB_Arc;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eArcObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Not Prim.InPolygon) And (Not Prim.InDimension) And (Prim.Layer = Lyr) Then
            Begin
                Arc := Prim;
                If (Arc.XCenter = XC) And (Arc.YCenter = YC) And (Arc.Radius = R)
                    And (Abs(Round(Arc.StartAngle * 1000.0) - StartMilli) <= 2) Then
                Begin
                    Inc(Result);
                    If First = Nil Then First := Arc;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Free pads (not in a component) on a layer with this centre, size and hole.   }
Function FreePadCount(Board : IPCB_Board; Lyr : TLayer; X, Y, Size, Hole : Integer; Var First : IPCB_Pad) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Pad : IPCB_Pad;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(ePadObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Prim.Layer = Lyr) Then
            Begin
                Pad := Prim;
                If (Pad.x = X) And (Pad.y = Y) And (Pad.TopXSize = Size) And (Pad.HoleSize = Hole) Then
                Begin
                    Inc(Result);
                    If First = Nil Then First := Pad;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Free lines, arcs, fills and regions on a layer (not in a component, polygon  }
{ or dimension): the objects clearlayer removes. Texts are not counted.        }
Function FreeLayerObjects(Board : IPCB_Board; Lyr : TLayer; Var First : IPCB_Primitive) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject, eFillObject, eRegionObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Not Prim.InPolygon) And (Not Prim.InDimension) And (Prim.Layer = Lyr) Then
            Begin
                Inc(Result);
                If First = Nil Then First := Prim;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Design rules carrying this exact name (scripts 2026.11.23.4, delrule). }
Function RuleByName(Board : IPCB_Board; RuleName : String; Var First : IPCB_Rule) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Rule : IPCB_Rule;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eRuleObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Rule := Iter.FirstPCBObject;
        While Rule <> Nil Do
        Begin
            If Rule.Name = RuleName Then
            Begin
                Inc(Result);
                If First = Nil Then First := Rule;
            End;
            Rule := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Free texts on a layer (not in a component or dimension): what clearlayer     }
{ removes with the texts option (scripts 2026.11.23.2).                        }
Function FreeLayerTexts(Board : IPCB_Board; Lyr : TLayer; Var First : IPCB_Text) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Txt : IPCB_Text;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTextObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Txt := Iter.FirstPCBObject;
        While Txt <> Nil Do
        Begin
            If (Not Txt.InComponent) And (Not Txt.InDimension) And (Txt.Layer = Lyr) Then
            Begin
                Inc(Result);
                If First = Nil Then First := Txt;
            End;
            Txt := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Polygons on a layer whose FIRST outline vertex is exactly X, Y and that have }
{ NPts vertices (scripts 2026.11.20.2, movepoly). The first vertex and not the }
{ bounding rectangle names the polygon: a rectangle read after segment writes  }
{ can be stale until the document is reopened (the board shape, 2026-11-18).   }
Function PolyAtFirstVertex(Board : IPCB_Board; Lyr : TLayer; X, Y, NPts : Integer; Var First : IPCB_Polygon) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Poly : IPCB_Polygon;
    N : Integer;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(ePolyObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Poly := Iter.FirstPCBObject;
        While Poly <> Nil Do
        Begin
            If Poly.Layer = Lyr Then
            Begin
                N := 0;
                Try N := Poly.PointCount; Except N := 0; End;
                If (N = NPts) And (N >= 3) Then
                    If (Poly.Segments[0].vx = X) And (Poly.Segments[0].vy = Y) Then
                    Begin
                        Inc(Result);
                        If First = Nil Then First := Poly;
                    End;
            End;
            Poly := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Free fills on a layer (copper or not) with exactly these corners, either    }
{ way round. Scripts 2026.11.20.1 (delfill: the undo of a placed fill).       }
Function FreeFillCount(Board : IPCB_Board; Lyr : TLayer; X1, Y1, X2, Y2 : Integer; Var First : IPCB_Fill) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Fill : IPCB_Fill;
    LoX, LoY, HiX, HiY, FLoX, FLoY, FHiX, FHiY : Integer;
Begin
    Result := 0;
    First := Nil;
    If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
    If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eFillObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Not Prim.InPolygon) And (Not Prim.InDimension) And (Prim.Layer = Lyr) Then
            Begin
                Fill := Prim;
                If Fill.X1Location < Fill.X2Location Then Begin FLoX := Fill.X1Location; FHiX := Fill.X2Location; End
                Else Begin FLoX := Fill.X2Location; FHiX := Fill.X1Location; End;
                If Fill.Y1Location < Fill.Y2Location Then Begin FLoY := Fill.Y1Location; FHiY := Fill.Y2Location; End
                Else Begin FLoY := Fill.Y2Location; FHiY := Fill.Y1Location; End;
                If (FLoX = LoX) And (FLoY = LoY) And (FHiX = HiX) And (FHiY = HiY) Then
                Begin
                    Inc(Result);
                    If First = Nil Then First := Fill;
                End;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function FreeLineEndAt(Board : IPCB_Board; Lyr : TLayer; X, Y : Integer) : Boolean;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
    Track : IPCB_Track;
Begin
    Result := False;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While (Prim <> Nil) And (Not Result) Do
        Begin
            If (Not Prim.InComponent) And (Prim.Layer = Lyr) Then
            Begin
                Track := Prim;
                If ((Track.X1 = X) And (Track.Y1 = Y)) Or ((Track.X2 = X) And (Track.Y2 = Y)) Then Result := True;
            End;
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function FreeViaCount(Board : IPCB_Board; X, Y, Size, Hole : Integer; Var First : IPCB_Via) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Via : IPCB_Via;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eViaObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Via := Iter.FirstPCBObject;
        While Via <> Nil Do
        Begin
            { Within 5000 raw (0.5 mil): the vias read reports whole mils, so a plan    }
            { built from it cannot carry the exact raw values. Two vias closer than   }
            { that cannot coexist; the identical-via count still guards.              }
            If (Not Via.InComponent) And CoordWithinTol(Via.x, X, 5000) And CoordWithinTol(Via.y, Y, 5000)
                And CoordWithinTol(Via.Size, Size, 5000) And CoordWithinTol(Via.HoleSize, Hole, 5000) Then
            Begin
                Inc(Result);
                If First = Nil Then First := Via;
            End;
            Via := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function FreeTextCount(Board : IPCB_Board; Lyr : TLayer; X, Y : Integer; TextStr : String; Var First : IPCB_Text) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Txt : IPCB_Text;
    T : String;
Begin
    Result := 0;
    First := Nil;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTextObject));
        Iter.AddFilter_LayerSet(MkSet(Lyr));
        Iter.AddFilter_Method(eProcessAll);
        Txt := Iter.FirstPCBObject;
        While Txt <> Nil Do
        Begin
            If (Not Txt.InComponent) And (Not Txt.InDimension) And (Txt.Layer = Lyr)
                And (Txt.XLocation = X) And (Txt.YLocation = Y) Then
            Begin
                T := '';
                Try T := Txt.Text; Except End;
                If T = TextStr Then
                Begin
                    Inc(Result);
                    If First = Nil Then First := Txt;
                End;
            End;
            Txt := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function FreeViaTotal(Board : IPCB_Board) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Via : IPCB_Via;
Begin
    Result := 0;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eViaObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Via := Iter.FirstPCBObject;
        While Via <> Nil Do
        Begin
            If Not Via.InComponent Then Inc(Result);
            Via := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

Function EditFreeTextOk(S : String) : Boolean;
Var
    I, C : Integer;
    Ch : String;
Begin
    Result := (Length(S) >= 1) And (Length(S) <= 40);
    If Not Result Then Exit;
    For I := 1 To Length(S) Do
    Begin
        Ch := Copy(S, I, 1);
        C := Ord(Ch[1]);
        If (C < 32) Or (C > 126) Or (C = 124) Or (C = 59) Then
        Begin
            Result := False;
            Exit;
        End;
    End;
End;

{ 'x,y x,y ...' -> VX / VY; False on a malformed list or outside 3..64 vertices. }
Function ShapeVertices(S : String; VX, VY : TStringList) : Boolean;
Var
    Rest, Pair, A : String;
Begin
    Result := False;
    Rest := S;
    While Rest <> '' Do
    Begin
        Pair := ParamEditTake(Rest, ' ');
        If Pair = '' Then Continue;
        If ParamEditCountChar(Pair, ',') <> 1 Then Exit;
        A := ParamEditTake(Pair, ',');
        If (Not PlaceEditIntOk(A)) Or (Not PlaceEditIntOk(Pair)) Then Exit;
        VX.Add(A);
        VY.Add(Pair);
        If VX.Count > 64 Then Exit;
    End;
    Result := VX.Count >= 3;
End;

{ Free tracks on copper layers: the seventh count of the edit compare-and-set  }
{ (deltrack, scripts 2026.11.18.2).                                            }
Function FreeCopperTrackTotal(Board : IPCB_Board) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Prim : IPCB_Primitive;
Begin
    Result := 0;
    Iter := Board.BoardIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eTrackObject));
        Iter.AddFilter_LayerSet(AllLayers);
        Iter.AddFilter_Method(eProcessAll);
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            If (Not Prim.InComponent) And (Not Prim.InPolygon) And (Not Prim.InDimension) Then
                If PCB_IsCopperLayerName(GetLayerString(Prim.Layer)) Then Inc(Result);
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Board.BoardIterator_Destroy(Iter);
    End;
End;

{ Move a text to X, Y (raw). MoveByXY is how upstream moves a board text: it   }
{ carries the text's bounding rectangle along, where a write to XLocation /   }
{ YLocation left the selection box at the old place until the document was    }
{ reopened (22p, 2026-11-19). The direct write stays as the fallback when the }
{ text is not where it was sent. Call inside BeginModify / EndModify.          }
Procedure EditMoveText(Txt : IPCB_Text; X, Y : Integer);
Begin
    Try
        Txt.MoveByXY(X - Txt.XLocation, Y - Txt.YLocation);
    Except
    End;
    If (Txt.XLocation <> X) Or (Txt.YLocation <> Y) Then
    Begin
        Txt.XLocation := X;
        Txt.YLocation := Y;
    End;
End;

Function SelectedEditFreeChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, ItemsStr, BatchHash, OldCounts, Rest, OpStr, Problems, Binding, Blank, What, ItemsJson : String;
    PcbPath, ErrCode, ErrMsg, LayerStr, Counts, Back, Status, NetName : String;
    IOp, ILay, IX1, IY1, IX2, IY2, IW, IS1, IS2, IStatus, IBack, VX, VY : TStringList;
    J, K, Count, Would, Refused, Done, NPads, NFills, NTexts, NLines, NVias, NShape, Clearance, N : Integer;
    X1, Y1, X2, Y2, W, Hole, NTracks : Integer;
    NT, KT : Integer;
    Rule : IPCB_Rule;
    Body : IPCB_ComponentBody;
    Model : IPCB_Model;
    ModelPath : String;
    Apply, PcbModified, Partial, Touched, Ok, IsCopper : Boolean;
    Board : IPCB_Board;
    Lyr : TLayer;
    Track : IPCB_Track;
    Via : IPCB_Via;
    Txt : IPCB_Text;
    Comp : IPCB_Component;
    Fill : IPCB_Fill;
    Poly : IPCB_Polygon;
    Arc : IPCB_Arc;
    Pad : IPCB_Pad;
    Prim0 : IPCB_Primitive;
    Net : IPCB_Net;
    VCX, VCY, VA1, VA2 : TStringList;
    OldMode, PX0, PY0 : Integer;
    LoX, LoY, HiX, HiY : Integer;
    EditNets : TStringList;
    Seg, Seg2 : TPolySegment;
    Gap : Double;
    F0, F1, F2, F3, F4, F5, F6, F7, F8 : String;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    ItemsStr := ExtractJsonValue(Params, 'items');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    OldCounts := ExtractJsonValue(Params, 'old_counts');
    Clearance := StrToIntDef(ExtractJsonValue(Params, 'clearance'), -1);
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not PlaceEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Board edits are not granted: the operator ticks "Allow board edits" in the bridge window');
        Exit;
    End;
    If (Not ParamEditHashValid(BatchHash)) Or (Clearance < 0) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters and clearance a raw coordinate');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    Partial := False;
    IOp := TStringList.Create; ILay := TStringList.Create; IX1 := TStringList.Create; IY1 := TStringList.Create;
    IX2 := TStringList.Create; IY2 := TStringList.Create; IW := TStringList.Create; IS1 := TStringList.Create;
    IS2 := TStringList.Create; IStatus := TStringList.Create; IBack := TStringList.Create;
    VX := TStringList.Create; VY := TStringList.Create;
    VCX := TStringList.Create; VCY := TStringList.Create; VA1 := TStringList.Create; VA2 := TStringList.Create;
    EditNets := TStringList.Create;
    SelectedBusy := True;
    Try
        Rest := ItemsStr;
        Count := 0;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            Inc(Count);
            If (Count > 300) Or (ParamEditCountChar(OpStr, '|') <> 8) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Item ' + IntToStr(Count) + ': expected 9 fields, at most 300 items');
                Exit;
            End;
            F0 := ParamEditTake(OpStr, '|'); F1 := ParamEditTake(OpStr, '|'); F2 := ParamEditTake(OpStr, '|');
            F3 := ParamEditTake(OpStr, '|'); F4 := ParamEditTake(OpStr, '|'); F5 := ParamEditTake(OpStr, '|');
            F6 := ParamEditTake(OpStr, '|'); F7 := ParamEditTake(OpStr, '|'); F8 := OpStr;
            Ok := ((F0 = 'delline') Or (F0 = 'delvia') Or (F0 = 'movevia') Or (F0 = 'text') Or (F0 = 'shape')
                Or (F0 = 'deltrack') Or (F0 = 'deltext') Or (F0 = 'movetext') Or (F0 = 'movename')
                Or (F0 = 'showname') Or (F0 = 'hidename') Or (F0 = 'delfill') Or (F0 = 'movepoly')
                Or (F0 = 'addpoly') Or (F0 = 'setpoly') Or (F0 = 'delarc') Or (F0 = 'delpad') Or (F0 = 'clearlayer')
                Or (F0 = 'setnet') Or (F0 = 'addpad')
                Or (F0 = 'delpoly') Or (F0 = 'delrule') Or (F0 = 'flip') Or (F0 = 'body3d')
                Or (F0 = 'addtrack') Or (F0 = 'addline') Or (F0 = 'addfill') Or (F0 = 'addtext') Or (F0 = 'setplated'))
                And CopperLayerNameOk(F1) And PlaceEditIntOk(F2) And PlaceEditIntOk(F3) And PlaceEditIntOk(F4)
                And PlaceEditIntOk(F5) And PlaceEditIntOk(F6);
            If Not Ok Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Item ' + IntToStr(Count) + ': bad op, layer or number');
                Exit;
            End;
            IOp.Add(F0); ILay.Add(F1); IX1.Add(F2); IY1.Add(F3); IX2.Add(F4); IY2.Add(F5);
            IW.Add(F6); IS1.Add(F7); IS2.Add(F8); IStatus.Add(Blank); IBack.Add(Blank);
        End;
        If IOp.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No items');
            Exit;
        End;

        Board := ResolveSelectedBoard(P, PcbPath, PcbModified, ErrCode, ErrMsg);
        If Board = Nil Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;
        If Apply And PcbModified Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PCB_DIRTY',
                'The PcbDoc has unsaved edits; save or discard them first (one batch per save)');
            Exit;
        End;
        GraphicsCount(Board, NPads, NFills, NTexts, NLines);
        NVias := FreeViaTotal(Board);
        NShape := 0;
        Try NShape := Board.BoardOutline.PointCount; Except NShape := -1; End;
        NTracks := FreeCopperTrackTotal(Board);
        Counts := IntToStr(NPads) + ',' + IntToStr(NFills) + ',' + IntToStr(NTexts) + ',' + IntToStr(NLines)
            + ',' + IntToStr(NVias) + ',' + IntToStr(NShape) + ',' + IntToStr(NTracks);
        If Apply And (Counts <> OldCounts) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED',
                'Nothing changed. The board''s free objects changed since the preview (' + Counts + '); preview again');
            Exit;
        End;

        { Classify. }
        Problems := '';
        Refused := 0;
        Would := 0;
        For J := 0 To IOp.Count - 1 Do
        Begin
            X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]); X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
            W := StrToInt(IW[J]);
            Status := '';
            Lyr := ResolveLayerId(Board, ILay[J]);
            LayerStr := '';
            If Lyr <> eNoLayer Then LayerStr := GetLayerString(Lyr);
            IsCopper := (Lyr = eMultiLayer) Or ((LayerStr <> '') And PCB_IsCopperLayerName(LayerStr));
            If IOp[J] = 'delline' Then
            Begin
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: copper tracks are not deleted here'
                Else
                Begin
                    N := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                    If N = 0 Then Status := 'refused: no free line with these exact ends on this layer'
                    Else If N > 1 Then Status := 'would_delete (1 of ' + IntToStr(N) + ' identical)'
                    Else Status := 'would_delete';
                End;
            End
            Else If (IOp[J] = 'addpoly') Or (IOp[J] = 'setpoly') Then
            Begin
                { addpoly: a new polygon on `layer` from the outline in s1 (s2 its net, }
                { copper only). setpoly: the polygon whose first vertex is x1,y1 with w }
                { vertices takes the outline in s1. Both are repoured.                  }
                EmptyList(VX); EmptyList(VY); EmptyList(VCX); EmptyList(VCY); EmptyList(VA1); EmptyList(VA2);
                Net := Nil;
                If (IOp[J] = 'addpoly') And (IS2[J] <> '') Then Net := FindNetByName(Board, IS2[J]);
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: layer not on this board'
                Else If Not PolyVertices(IS1[J], VX, VY, VCX, VCY, VA1, VA2) Then
                    Status := 'refused: the outline must be 3-64 vertices x,y or x,y,cx,cy,a1,a2'
                Else If IOp[J] = 'addpoly' Then
                Begin
                    If (IS2[J] <> '') And (Net = Nil) Then Status := 'refused: net not on the board'
                    Else If (IS2[J] <> '') And (Not IsCopper) Then Status := 'refused: a net on a non-copper layer'
                    Else If PolyAtFirstVertex(Board, Lyr, StrToInt(VX[0]), StrToInt(VY[0]), VX.Count, Poly) > 0 Then
                        Status := 'refused: a polygon with this first vertex and vertex count is already on this layer'
                    Else Status := 'would_add (' + IntToStr(VX.Count) + ' vertices)';
                End
                Else
                Begin
                    N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                    If N = 0 Then Status := 'refused: no polygon with this first vertex and vertex count on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical polygons here'
                    Else Status := 'would_reshape (' + IntToStr(VX.Count) + ' vertices)';
                End;
            End
            Else If IOp[J] = 'delarc' Then
            Begin
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: copper arcs are not deleted here'
                Else
                Begin
                    N := FreeArcCount(Board, Lyr, X1, Y1, X2, Y2, Arc);
                    If N = 0 Then Status := 'refused: no free arc with this centre, radius and start angle on this layer'
                    Else If N > 1 Then Status := 'would_delete (1 of ' + IntToStr(N) + ' identical)'
                    Else Status := 'would_delete';
                End;
            End
            Else If IOp[J] = 'delpad' Then
            Begin
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else
                Begin
                    N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                    If N = 0 Then Status := 'refused: no free pad with this centre, size and hole on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical pads here'
                    Else Status := 'would_delete';
                End;
            End
            Else If IOp[J] = 'clearlayer' Then
            Begin
                { Every free line, arc, fill and region on a non-copper layer; w is the }
                { number the plan expects, so a layer that changed is refused.          }
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: a copper layer is not cleared'
                Else
                Begin
                    N := FreeLayerObjects(Board, Lyr, Prim0);
                    { s1 = 'texts' (scripts 2026.11.23.2): the free texts go too, s2 }
                    { is the number of texts the plan expects.                       }
                    NT := 0;
                    If IS1[J] = 'texts' Then NT := FreeLayerTexts(Board, Lyr, Txt);
                    If N <> W Then Status := 'refused: the layer holds ' + IntToStr(N) + ' free objects, the plan says ' + IntToStr(W)
                    Else If (IS1[J] = 'texts') And (NT <> StrToIntDef(IS2[J], -1)) Then
                        Status := 'refused: the layer holds ' + IntToStr(NT) + ' free texts, the plan says ' + IS2[J]
                    Else If (N = 0) And (NT = 0) Then Status := 'unchanged'
                    Else If IS1[J] = 'texts' Then
                        Status := 'would_clear (' + IntToStr(N) + ' objects, ' + IntToStr(NT) + ' texts)'
                    Else Status := 'would_clear (' + IntToStr(N) + ' objects)';
                End;
            End
            Else If IOp[J] = 'setnet' Then
            Begin
                { The net of a free via (x1,y1 centre, x2 size, y2 hole), of a free pad }
                { (the same, on `layer`) or of a polygon (x1,y1 first vertex, w vertex  }
                { count) becomes the net in s2; s1 names the kind. A via or pad is      }
                { tested against other-net copper; a polygon is repoured.               }
                Net := Nil;
                If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                NetName := '';
                N := -1;
                If IS1[J] = 'via' Then
                Begin
                    N := FreeViaCount(Board, X1, Y1, X2, Y2, Via);
                    If N = 1 Then
                    Begin
                        Try If Via.Net <> Nil Then NetName := Via.Net.Name; Except NetName := ''; End;
                    End;
                End
                Else If (IS1[J] = 'pad') And (Lyr <> eNoLayer) Then
                Begin
                    N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                    If N = 1 Then
                    Begin
                        Try If Pad.Net <> Nil Then NetName := Pad.Net.Name; Except NetName := ''; End;
                    End;
                End
                Else If (IS1[J] = 'poly') And (Lyr <> eNoLayer) And (Lyr <> eMultiLayer) Then
                Begin
                    N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                    If N = 1 Then
                    Begin
                        Try If Poly.Net <> Nil Then NetName := Poly.Net.Name; Except NetName := ''; End;
                    End;
                End
                Else If (IS1[J] = 'fill') And (Lyr <> eNoLayer) And (Lyr <> eMultiLayer) Then
                Begin
                    { A free fill by its corners x1,y1 - x2,y2 (scripts 2026.11.23.10). }
                    N := FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill);
                    If N = 1 Then
                    Begin
                        Try If Fill.Net <> Nil Then NetName := Fill.Net.Name; Except NetName := ''; End;
                    End;
                End;
                If N < 0 Then Status := 'refused: s1 must be via, pad, poly or fill, on a layer of this board'
                Else If Net = Nil Then Status := 'refused: net not on the board'
                Else If ((IS1[J] = 'poly') Or (IS1[J] = 'fill')) And (Not IsCopper) Then Status := 'refused: a net on a non-copper layer'
                Else If N = 0 Then Status := 'refused: no such free ' + IS1[J] + ' here'
                Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical objects here'
                Else If NetName = IS2[J] Then Status := 'unchanged'
                Else If IS1[J] = 'poly' Then Status := 'would_set (was "' + NetName + '")'
                Else If IS1[J] = 'fill' Then
                Begin
                    If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
                    If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
                    If (HiX - LoX) >= (HiY - LoY) Then
                        Gap := CopperNearest(Board, IS2[J], Lyr, LoX + (HiY - LoY) Div 2, (LoY + HiY) Div 2,
                            HiX - (HiY - LoY) Div 2, (LoY + HiY) Div 2, (HiY - LoY) / 2, Clearance, What)
                    Else
                        Gap := CopperNearest(Board, IS2[J], Lyr, (LoX + HiX) Div 2, LoY + (HiX - LoX) Div 2,
                            (LoX + HiX) Div 2, HiY - (HiX - LoX) Div 2, (HiX - LoX) / 2, Clearance, What);
                    If Gap < Clearance Then
                        Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                    Else Status := 'would_set (was "' + NetName + '")';
                End
                Else
                Begin
                    { A via or pad: other-net copper within the clearance of its spot }
                    { would be a short under the new net (scripts 2026.11.23.5). A    }
                    { pour is not copper to this test: it repours around the object.  }
                    If IS1[J] = 'via' Then
                        Gap := CopperNearestExcept(Board, IS2[J], eNoLayer, X1, Y1, X1, Y1, X2 / 2, Clearance, Via, What)
                    Else
                        Gap := CopperNearestExcept(Board, IS2[J], eNoLayer, X1, Y1, X1, Y1, X2 / 2, Clearance, Pad, What);
                    If Gap < Clearance Then
                        Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                    Else Status := 'would_set (was "' + NetName + '")';
                End;
            End
            Else If IOp[J] = 'addpad' Then
            Begin
                { A free round pad on MultiLayer: x1,y1 centre, x2 size, y2 hole, w 1 }
                { plated / 0 not, s2 its net. The graphics writer's pad, inside an    }
                { edit batch so that a via becomes a pad under one tick.              }
                Net := Nil;
                If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                If Lyr <> eMultiLayer Then Status := 'refused: addpad places on MultiLayer'
                Else If (X2 <= 0) Or (Y2 < 0) Or (Y2 >= X2) Then Status := 'refused: the size must exceed the hole'
                Else If (IS2[J] <> '') And (Net = Nil) Then Status := 'refused: net not on the board'
                Else If FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad) > 0 Then Status := 'unchanged'
                Else
                Begin
                    { A pad that takes the place of a via this batch deletes (same    }
                    { centre, the pad no larger than the via) stands where copper     }
                    { already stood: no clearance test, the via would be found as     }
                    { other-net copper when its net differs from the pad's.           }
                    Ok := False;
                    For K := 0 To IOp.Count - 1 Do
                        If (IOp[K] = 'delvia') And (IX1[K] = IX1[J]) And (IY1[K] = IY1[J])
                            And (StrToInt(IX2[K]) >= X2) Then Ok := True;
                    If Ok Then Status := 'would_place (replaces a via of this batch)'
                    Else
                    Begin
                        Gap := CopperNearest(Board, IS2[J], eNoLayer, X1, Y1, X1, Y1, X2 / 2, Clearance, What);
                        If Gap < Clearance Then
                            Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                        Else Status := 'would_place';
                    End;
                End;
            End
            Else If IOp[J] = 'addtrack' Then
            Begin
                { A copper track inside an edit batch (scripts 2026.11.23.10): x1,y1 - }
                { x2,y2, w its width, s1 its net. With a deltrack of the same batch a  }
                { track is cut or rerouted under one tick. The copper writer's tests.  }
                Net := Nil;
                If IS1[J] <> '' Then Net := FindNetByName(Board, IS1[J]);
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Or (Not IsCopper) Then
                    Status := 'refused: addtrack needs a copper layer of this board'
                Else If Net = Nil Then Status := 'refused: net not on the board'
                Else If (W <= 0) Or ((X1 = X2) And (Y1 = Y2)) Then Status := 'refused: a track needs a width and two distinct ends'
                Else If CopperTrackExists(Board, IS1[J], Lyr, X1, Y1, X2, Y2, W) Then Status := 'unchanged'
                Else
                Begin
                    Gap := CopperNearest(Board, IS1[J], Lyr, X1, Y1, X2, Y2, W / 2, Clearance, What);
                    If Gap < Clearance Then
                        Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                    Else Status := 'would_place';
                End;
            End
            Else If IOp[J] = 'addline' Then
            Begin
                { A free line on a non-copper layer: the graphics writer's line. }
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: a copper line is an addtrack'
                Else If (W <= 0) Or ((X1 = X2) And (Y1 = Y2)) Then Status := 'refused: a line needs a width and two distinct ends'
                Else If FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track) > 0 Then Status := 'unchanged'
                Else Status := 'would_place';
            End
            Else If IOp[J] = 'addfill' Then
            Begin
                { A free fill: x1,y1 - x2,y2 its corners, s2 its net (copper only). }
                Net := Nil;
                If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
                If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: a fill goes on one layer of this board'
                Else If (X1 = X2) Or (Y1 = Y2) Then Status := 'refused: empty rectangle'
                Else If (IS2[J] <> '') And (Net = Nil) Then Status := 'refused: net not on the board'
                Else If (IS2[J] <> '') And (Not IsCopper) Then Status := 'refused: a net on a non-copper layer'
                Else If FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill) > 0 Then Status := 'unchanged'
                Else If Not IsCopper Then Status := 'would_place'
                Else
                Begin
                    If (HiX - LoX) >= (HiY - LoY) Then
                        Gap := CopperNearest(Board, IS2[J], Lyr, LoX + (HiY - LoY) Div 2, (LoY + HiY) Div 2,
                            HiX - (HiY - LoY) Div 2, (LoY + HiY) Div 2, (HiY - LoY) / 2, Clearance, What)
                    Else
                        Gap := CopperNearest(Board, IS2[J], Lyr, (LoX + HiX) Div 2, LoY + (HiX - LoX) Div 2,
                            (LoX + HiX) Div 2, HiY - (HiX - LoX) Div 2, (HiX - LoX) / 2, Clearance, What);
                    If Gap < Clearance Then
                        Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                    Else Status := 'would_place';
                End;
            End
            Else If IOp[J] = 'addtext' Then
            Begin
                { A free text: x1,y1 its location, x2 its height, y2 its rotation, w }
                { its stroke, s1 the text. Not on copper.                            }
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: text goes on silk, mechanical or other non-copper layers'
                Else If (X2 <= 0) Or (W <= 0) Or ((Y2 <> 0) And (Y2 <> 90) And (Y2 <> 180) And (Y2 <> 270)) Then
                    Status := 'refused: text needs height, stroke and rotation 0/90/180/270'
                Else If Not EditFreeTextOk(IS1[J]) Then Status := 'refused: text needs 1-40 plain characters'
                Else If FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt) > 0 Then Status := 'unchanged'
                Else Status := 'would_place';
            End
            Else If IOp[J] = 'setplated' Then
            Begin
                { The Plated flag of a free drilled pad: x1,y1 centre, x2 size, y2 hole, }
                { w 1 plated / 0 not.                                                    }
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If (W <> 0) And (W <> 1) Then Status := 'refused: w is 1 (plated) or 0 (not plated)'
                Else If Y2 <= 0 Then Status := 'refused: only a drilled pad has a Plated flag'
                Else
                Begin
                    N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                    If N = 0 Then Status := 'refused: no such free pad here'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical pads here'
                    Else If Pad.Plated = (W = 1) Then Status := 'unchanged'
                    Else If W = 1 Then Status := 'would_set (plated)'
                    Else
                    Begin
                        NetName := '';
                        Try If Pad.Net <> Nil Then NetName := Pad.Net.Name; Except NetName := ''; End;
                        If NetName <> '' Then Status := 'refused: the pad is on net ' + NetName + '; a non-plated hole carries no net'
                        Else Status := 'would_set (not plated)';
                    End;
                End;
            End
            Else If IOp[J] = 'delpoly' Then
            Begin
                { A polygon removed: x1,y1 its first vertex, w its vertex count. }
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: layer not on this board'
                Else
                Begin
                    N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                    If N = 0 Then Status := 'refused: no polygon with this first vertex and vertex count on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical polygons here'
                    Else Status := 'would_delete';
                End;
            End
            Else If IOp[J] = 'delrule' Then
            Begin
                N := RuleByName(Board, IS1[J], Rule);
                If N = 0 Then Status := 'refused: no design rule with this name'
                Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' rules carry this name'
                Else Status := 'would_delete';
            End
            Else If IOp[J] = 'flip' Then
            Begin
                { A part to the other side of the board (upstream PCB_FlipComponent). }
                Comp := Nil;
                Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                If Comp = Nil Then Status := 'refused: no such part'
                Else If Comp.Layer = eTopLayer Then Status := 'would_flip (to the bottom)'
                Else If Comp.Layer = eBottomLayer Then Status := 'would_flip (to the top)'
                Else Status := 'refused: the part is on neither outer layer';
            End
            Else If IOp[J] = 'body3d' Then
            Begin
                { A STEP model as a free 3D body: s1 its path (forward slashes), x1,y1 }
                { where the model's origin goes, x2 the standoff, layer the side. No   }
                { rotation (upstream: assigning one is an undeclared identifier).      }
                ModelPath := StringReplace(IS1[J], '/', '\', -1);
                If (Lyr <> eTopLayer) And (Lyr <> eBottomLayer) Then Status := 'refused: a body goes on TopLayer or BottomLayer'
                Else If Not FileExists(ModelPath) Then Status := 'refused: no model file at that path'
                Else Status := 'would_place';
            End
            Else If IOp[J] = 'movepoly' Then
            Begin
                { A polygon (a pour, or a polygon on a mask or other layer) moved by   }
                { x2, y2: x1, y1 its first vertex, w its vertex count.                 }
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: layer not on this board'
                Else
                Begin
                    N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                    If N = 0 Then Status := 'refused: no polygon with this first vertex and vertex count on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical polygons here'
                    Else If (X2 = 0) And (Y2 = 0) Then Status := 'unchanged'
                    Else Status := 'would_move';
                End;
            End
            Else If IOp[J] = 'delfill' Then
            Begin
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Then Status := 'refused: layer not on this board'
                Else
                Begin
                    N := FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill);
                    If N = 0 Then Status := 'refused: no free fill with these exact corners on this layer'
                    Else If N > 1 Then Status := 'would_delete (1 of ' + IntToStr(N) + ' identical)'
                    Else Status := 'would_delete';
                End;
            End
            Else If IOp[J] = 'delvia' Then
            Begin
                N := FreeViaCount(Board, X1, Y1, X2, Y2, Via);
                If N = 0 Then Status := 'refused: no free via with this centre, size and hole'
                Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical vias here'
                Else Status := 'would_delete';
            End
            Else If IOp[J] = 'movevia' Then
            Begin
                If Not PlaceEditIntOk(IS1[J]) Then Status := 'refused: hole must be an integer'
                Else
                Begin
                    Hole := StrToInt(IS1[J]);
                    N := FreeViaCount(Board, X1, Y1, W, Hole, Via);
                    If N = 0 Then Status := 'refused: no free via with this centre, size and hole'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical vias here'
                    Else If (X1 = X2) And (Y1 = Y2) Then Status := 'refused: new centre equals the old'
                    Else
                    Begin
                        NetName := '';
                        Try
                            If Via.Net <> Nil Then NetName := Via.Net.Name;
                        Except
                            NetName := '';
                        End;
                        Gap := CopperNearest(Board, NetName, eNoLayer, X2, Y2, X2, Y2, W / 2, Clearance, What);
                        If Gap < Clearance Then
                            Status := 'refused: ' + What + ' within clearance (' + CoordToMMStr(Gap) + ' mm of ' + CoordToMMStr(Clearance) + ' mm)'
                        Else Status := 'would_move';
                    End;
                End;
            End
            Else If IOp[J] = 'text' Then
            Begin
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If Not EditFreeTextOk(IS2[J]) Then Status := 'refused: new text needs 1-40 plain characters'
                Else
                Begin
                    N := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                    If N = 0 Then Status := 'refused: no free text with this text and location on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical texts here'
                    Else If IS1[J] = IS2[J] Then Status := 'unchanged'
                    Else Status := 'would_edit';
                End;
            End
            Else If IOp[J] = 'deltrack' Then
            Begin
                If (Lyr = eNoLayer) Or (Lyr = eMultiLayer) Or (Not IsCopper) Then
                    Status := 'refused: deltrack needs a copper layer of this board'
                Else
                Begin
                    N := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                    If N = 0 Then Status := 'refused: no free track with these exact ends on this layer'
                    Else
                    Begin
                        NetName := '';
                        Try
                            If Track.Net <> Nil Then NetName := Track.Net.Name;
                        Except
                            NetName := '';
                        End;
                        If NetName <> IS1[J] Then Status := 'refused: the track is on another net than the one named'
                        Else If Track.Width <> W Then Status := 'refused: the track width differs'
                        Else If N > 1 Then Status := 'would_delete (1 of ' + IntToStr(N) + ' identical)'
                        Else Status := 'would_delete';
                    End;
                End;
            End
            Else If (IOp[J] = 'deltext') Or (IOp[J] = 'movetext') Then
            Begin
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If (IOp[J] = 'movetext') And (W <> 0) And (W <> 90) And (W <> 180) And (W <> 270) And (W <> 360) Then
                    Status := 'refused: rotation must be 0 (keep), 90, 180, 270 or 360'
                Else
                Begin
                    N := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                    If N = 0 Then Status := 'refused: no free text with this text and location on this layer'
                    Else If N > 1 Then Status := 'refused: ' + IntToStr(N) + ' identical texts here'
                    Else If IOp[J] = 'deltext' Then Status := 'would_delete'
                    Else If (X1 = X2) And (Y1 = Y2) And (W = 0) Then Status := 'unchanged'
                    Else Status := 'would_move';
                End;
            End
            Else If IOp[J] = 'movename' Then
            Begin
                Comp := Nil;
                Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                If Comp = Nil Then Status := 'refused: no component with this designator'
                Else If (W <> 0) And (W <> 90) And (W <> 180) And (W <> 270) And (W <> 360) Then
                    Status := 'refused: rotation must be 0 (keep), 90, 180, 270 or 360'
                Else If Comp.Name = Nil Then Status := 'refused: the component has no designator text'
                Else If (Comp.Name.XLocation = X2) And (Comp.Name.YLocation = Y2) And (W = 0) Then Status := 'unchanged'
                Else Status := 'would_move';
            End
            Else If (IOp[J] = 'showname') Or (IOp[J] = 'hidename') Then
            Begin
                { A part's designator text shown or hidden (Comp.NameOn, as upstream's  }
                { PCB_SetTextVisibility). Scripts 2026.11.20.1.                         }
                Comp := Nil;
                Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                If Comp = Nil Then Status := 'refused: no component with this designator'
                Else If Comp.NameOn = (IOp[J] = 'showname') Then Status := 'unchanged'
                Else If IOp[J] = 'showname' Then Status := 'would_show'
                Else Status := 'would_hide';
            End
            Else
            Begin
                EmptyList(VX);
                EmptyList(VY);
                If Lyr = eNoLayer Then Status := 'refused: layer not on this board'
                Else If IsCopper Then Status := 'refused: the shape comes from a non-copper layer'
                Else If Not ShapeVertices(IS1[J], VX, VY) Then Status := 'refused: vertices must be 3-64 x,y pairs'
                Else
                Begin
                    For K := 0 To VX.Count - 1 Do
                        If (Status = '') And (Not FreeLineEndAt(Board, Lyr, StrToInt(VX[K]), StrToInt(VY[K]))) Then
                            Status := 'refused: vertex ' + IntToStr(K + 1) + ' is not an end of a free line on this layer';
                    If Status = '' Then Status := 'would_reshape (' + IntToStr(VX.Count) + ' vertices)';
                End;
            End;
            IStatus[J] := Status;
            If Copy(Status, 1, 7) = 'refused' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 800 Then Problems := Problems + IOp[J] + ' ' + IntToStr(J + 1) + ': ' + Copy(Status, 10, 200) + '; ';
            End
            Else If Status <> 'unchanged' Then Inc(Would);
        End;
        If Apply And (Refused > 0) Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing changed. ' + Problems);
            Exit;
        End;

        Done := 0;
        If Apply And (Would > 0) Then
        Begin
            PCBServer.PreProcess;
            Try
                For J := 0 To IOp.Count - 1 Do
                Begin
                    If Partial Or (Copy(IStatus[J], 1, 5) <> 'would') Then Continue;
                    X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]); X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
                    W := StrToInt(IW[J]);
                    Lyr := ResolveLayerId(Board, ILay[J]);
                    Touched := True;
                    Back := '';
                    Ok := False;
                    If IOp[J] = 'delline' Then
                    Begin
                        N := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                        If Track <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
                            Board.RemovePCBObject(Track);
                            K := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = N - 1);
                        End;
                    End
                    Else If (IOp[J] = 'addpoly') Or (IOp[J] = 'setpoly') Then
                    Begin
                        EmptyList(VX); EmptyList(VY); EmptyList(VCX); EmptyList(VCY); EmptyList(VA1); EmptyList(VA2);
                        PolyVertices(IS1[J], VX, VY, VCX, VCY, VA1, VA2);
                        Poly := Nil;
                        If IOp[J] = 'addpoly' Then
                        Begin
                            Poly := PCBServer.PCBObjectFactory(ePolyObject, eNoDimension, eCreate_Default);
                            If Poly <> Nil Then
                            Begin
                                Poly.Layer := Lyr;
                                Poly.PolyHatchStyle := ePolySolid;
                                PolyWriteOutline(Poly, VX, VY, VCX, VCY, VA1, VA2);
                                Net := Nil;
                                If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                                If Net <> Nil Then
                                Begin
                                    Poly.Net := Net;
                                    If EditNets.IndexOf(IS2[J]) < 0 Then EditNets.Add(IS2[J]);
                                End;
                                Poly.PourOver := ePolygonPourOver_SameNet;
                                Board.AddPCBObject(Poly);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Poly.I_ObjectAddress);
                                PolyRepour(Poly);
                                Poly.GraphicallyInvalidate;
                            End;
                        End
                        Else
                        Begin
                            N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                            If Poly <> Nil Then
                            Begin
                                Try
                                    If Poly.Net <> Nil Then
                                        If EditNets.IndexOf(Poly.Net.Name) < 0 Then EditNets.Add(Poly.Net.Name);
                                Except
                                End;
                                Poly.BeginModify;
                                PolyWriteOutline(Poly, VX, VY, VCX, VCY, VA1, VA2);
                                PolyRepour(Poly);
                                Poly.EndModify;
                                Poly.GraphicallyInvalidate;
                            End;
                        End;
                        If Poly <> Nil Then
                        Begin
                            K := VX.Count - 1;
                            Back := 'first vertex ' + IntToStr(Poly.Segments[0].vx) + ',' + IntToStr(Poly.Segments[0].vy)
                                + ' points ' + IntToStr(Poly.PointCount);
                            Ok := (Poly.PointCount = VX.Count)
                                And (Poly.Segments[0].vx = StrToInt(VX[0])) And (Poly.Segments[0].vy = StrToInt(VY[0]))
                                And (Poly.Segments[K].vx = StrToInt(VX[K])) And (Poly.Segments[K].vy = StrToInt(VY[K]))
                                And (PolyAtFirstVertex(Board, Lyr, StrToInt(VX[0]), StrToInt(VY[0]), VX.Count, Poly) = 1);
                        End;
                    End
                    Else If IOp[J] = 'delarc' Then
                    Begin
                        N := FreeArcCount(Board, Lyr, X1, Y1, X2, Y2, Arc);
                        If Arc <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Arc.I_ObjectAddress);
                            Board.RemovePCBObject(Arc);
                            K := FreeArcCount(Board, Lyr, X1, Y1, X2, Y2, Arc);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = N - 1);
                        End;
                    End
                    Else If IOp[J] = 'delpad' Then
                    Begin
                        N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                        If Pad <> Nil Then
                        Begin
                            Try
                                If Pad.Net <> Nil Then
                                    If EditNets.IndexOf(Pad.Net.Name) < 0 Then EditNets.Add(Pad.Net.Name);
                            Except
                            End;
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pad.I_ObjectAddress);
                            Board.RemovePCBObject(Pad);
                            K := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = 0);
                        End;
                    End
                    Else If IOp[J] = 'clearlayer' Then
                    Begin
                        { One object at a time, found again after each removal: nothing is }
                        { removed while an iterator is open. W bounds the loop.            }
                        N := FreeLayerObjects(Board, Lyr, Prim0);
                        K := 0;
                        While (Prim0 <> Nil) And (K < W) Do
                        Begin
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Prim0.I_ObjectAddress);
                            Board.RemovePCBObject(Prim0);
                            Inc(K);
                            N := FreeLayerObjects(Board, Lyr, Prim0);
                        End;
                        Back := 'removed ' + IntToStr(K) + ' remaining ' + IntToStr(N);
                        Ok := (N = 0) And (K = W);
                        If IS1[J] = 'texts' Then
                        Begin
                            KT := 0;
                            NT := FreeLayerTexts(Board, Lyr, Txt);
                            While (Txt <> Nil) And (KT < StrToIntDef(IS2[J], 0)) Do
                            Begin
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Txt.I_ObjectAddress);
                                Board.RemovePCBObject(Txt);
                                Inc(KT);
                                NT := FreeLayerTexts(Board, Lyr, Txt);
                            End;
                            Back := Back + ' texts removed ' + IntToStr(KT) + ' remaining ' + IntToStr(NT);
                            Ok := Ok And (NT = 0);
                        End;
                    End
                    Else If IOp[J] = 'delpoly' Then
                    Begin
                        N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                        If Poly <> Nil Then
                        Begin
                            Try
                                If Poly.Net <> Nil Then
                                    If EditNets.IndexOf(Poly.Net.Name) < 0 Then EditNets.Add(Poly.Net.Name);
                            Except
                            End;
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Poly.I_ObjectAddress);
                            Board.RemovePCBObject(Poly);
                            K := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = 0);
                        End;
                    End
                    Else If IOp[J] = 'delrule' Then
                    Begin
                        N := RuleByName(Board, IS1[J], Rule);
                        If Rule <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Rule.I_ObjectAddress);
                            Board.RemovePCBObject(Rule);
                            K := RuleByName(Board, IS1[J], Rule);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = 0);
                        End;
                    End
                    Else If IOp[J] = 'flip' Then
                    Begin
                        Comp := Nil;
                        Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                        If Comp <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            If Comp.Layer = eTopLayer Then
                            Begin
                                Comp.Layer := eBottomLayer;
                                Ok := (Comp.Layer = eBottomLayer);
                            End
                            Else
                            Begin
                                Comp.Layer := eTopLayer;
                                Ok := (Comp.Layer = eTopLayer);
                            End;
                            PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Back := GetLayerString(Comp.Layer);
                        End;
                    End
                    Else If IOp[J] = 'body3d' Then
                    Begin
                        { Upstream's order (PCB_Place3DBody), measured there by crashes: }
                        { factory, load, SetState_FromModel, model, ADD and register,    }
                        { and only then layer, MoveByXY and the standoff.                }
                        ModelPath := StringReplace(IS1[J], '/', '\', -1);
                        Body := PCBServer.PCBObjectFactory(eComponentBodyObject, eNoDimension, eCreate_Default);
                        If Body <> Nil Then
                        Begin
                            Model := Body.ModelFactory_FromFilename(ModelPath, False);
                            If Model <> Nil Then
                            Begin
                                Body.SetState_FromModel;
                                Body.Model := Model;
                                Board.AddPCBObject(Body);
                                PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Body.I_ObjectAddress);
                                Body.Layer := Lyr;
                                Body.MoveByXY(X1 - Body.x, Y1 - Body.y);
                                If X2 <> 0 Then Body.StandoffHeight := X2;
                                Back := IntToStr(Body.x) + ',' + IntToStr(Body.y);
                                Ok := (Body.x = X1) And (Body.y = Y1);
                            End
                            Else Back := 'the model did not load';
                        End;
                    End
                    Else If IOp[J] = 'setnet' Then
                    Begin
                        Net := FindNetByName(Board, IS2[J]);
                        NetName := '';
                        If Net <> Nil Then
                        Begin
                            If EditNets.IndexOf(IS2[J]) < 0 Then EditNets.Add(IS2[J]);
                            If IS1[J] = 'via' Then
                            Begin
                                N := FreeViaCount(Board, X1, Y1, X2, Y2, Via);
                                If Via <> Nil Then
                                Begin
                                    PCBServer.SendMessageToRobots(Via.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                                    Via.Net := Net;
                                    PCBServer.SendMessageToRobots(Via.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                                    Try If Via.Net <> Nil Then NetName := Via.Net.Name; Except NetName := ''; End;
                                End;
                            End
                            Else If IS1[J] = 'pad' Then
                            Begin
                                N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                                If Pad <> Nil Then
                                Begin
                                    PCBServer.SendMessageToRobots(Pad.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                                    Pad.Net := Net;
                                    PCBServer.SendMessageToRobots(Pad.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                                    Try If Pad.Net <> Nil Then NetName := Pad.Net.Name; Except NetName := ''; End;
                                End;
                            End
                            Else If IS1[J] = 'fill' Then
                            Begin
                                N := FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill);
                                If Fill <> Nil Then
                                Begin
                                    PCBServer.SendMessageToRobots(Fill.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                                    Fill.Net := Net;
                                    PCBServer.SendMessageToRobots(Fill.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                                    Try If Fill.Net <> Nil Then NetName := Fill.Net.Name; Except NetName := ''; End;
                                End;
                            End
                            Else If IS1[J] = 'poly' Then
                            Begin
                                N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                                If Poly <> Nil Then
                                Begin
                                    Poly.BeginModify;
                                    Poly.Net := Net;
                                    PolyRepour(Poly);
                                    Poly.EndModify;
                                    Poly.GraphicallyInvalidate;
                                    Try If Poly.Net <> Nil Then NetName := Poly.Net.Name; Except NetName := ''; End;
                                End;
                            End;
                        End;
                        Back := 'net ' + NetName;
                        Ok := (NetName = IS2[J]) And (NetName <> '');
                    End
                    Else If IOp[J] = 'addpad' Then
                    Begin
                        Net := Nil;
                        If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                        Pad := PCBServer.PCBObjectFactory(ePadObject, eNoDimension, eCreate_Default);
                        If Pad <> Nil Then
                        Begin
                            Pad.X := X1;
                            Pad.Y := Y1;
                            { Same no-ring order rule as the graphics writer's pad. }
                            If X2 > Pad.HoleSize Then
                            Begin
                                Pad.TopXSize := X2;
                                Pad.TopYSize := X2;
                                Pad.HoleSize := Y2;
                            End
                            Else
                            Begin
                                Pad.HoleSize := Y2;
                                Pad.TopXSize := X2;
                                Pad.TopYSize := X2;
                            End;
                            Pad.Layer := Lyr;
                            Pad.TopShape := 1;
                            If Y2 > 0 Then Pad.Plated := (W = 1);
                            If Net <> Nil Then
                            Begin
                                Pad.Net := Net;
                                If EditNets.IndexOf(IS2[J]) < 0 Then EditNets.Add(IS2[J]);
                            End;
                            Board.AddPCBObject(Pad);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pad.I_ObjectAddress);
                            Back := IntToStr(Pad.X) + ',' + IntToStr(Pad.Y) + ',' + IntToStr(Pad.TopXSize) + ',' + IntToStr(Pad.HoleSize)
                                + ',' + BoolToJsonStr(Pad.Plated);
                            Ok := (Pad.X = X1) And (Pad.Y = Y1) And (Pad.TopXSize = X2) And (Pad.HoleSize = Y2)
                                And ((Y2 = 0) Or (Pad.Plated = (W = 1)));
                        End;
                    End
                    Else If IOp[J] = 'addtrack' Then
                    Begin
                        Net := FindNetByName(Board, IS1[J]);
                        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
                        If (Track <> Nil) And (Net <> Nil) Then
                        Begin
                            Track.x1 := X1;
                            Track.y1 := Y1;
                            Track.x2 := X2;
                            Track.y2 := Y2;
                            Track.Width := W;
                            Track.Layer := Lyr;
                            Track.Net := Net;
                            If EditNets.IndexOf(IS1[J]) < 0 Then EditNets.Add(IS1[J]);
                            Board.AddPCBObject(Track);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
                            Back := IntToStr(Track.x1) + ',' + IntToStr(Track.y1) + ',' + IntToStr(Track.x2) + ',' + IntToStr(Track.y2) + ',' + IntToStr(Track.Width);
                            Ok := (Track.Width = W) And ((((Track.x1 = X1) And (Track.y1 = Y1) And (Track.x2 = X2) And (Track.y2 = Y2)))
                                Or ((Track.x1 = X2) And (Track.y1 = Y2) And (Track.x2 = X1) And (Track.y2 = Y1)));
                        End;
                    End
                    Else If IOp[J] = 'addline' Then
                    Begin
                        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
                        If Track <> Nil Then
                        Begin
                            Track.x1 := X1;
                            Track.y1 := Y1;
                            Track.x2 := X2;
                            Track.y2 := Y2;
                            Track.Width := W;
                            Track.Layer := Lyr;
                            Board.AddPCBObject(Track);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
                            Back := IntToStr(Track.x1) + ',' + IntToStr(Track.y1) + ',' + IntToStr(Track.x2) + ',' + IntToStr(Track.y2) + ',' + IntToStr(Track.Width);
                            Ok := (Track.Width = W) And ((((Track.x1 = X1) And (Track.y1 = Y1) And (Track.x2 = X2) And (Track.y2 = Y2)))
                                Or ((Track.x1 = X2) And (Track.y1 = Y2) And (Track.x2 = X1) And (Track.y2 = Y1)));
                        End;
                    End
                    Else If IOp[J] = 'addfill' Then
                    Begin
                        Net := Nil;
                        If IS2[J] <> '' Then Net := FindNetByName(Board, IS2[J]);
                        If X1 < X2 Then Begin LoX := X1; HiX := X2; End Else Begin LoX := X2; HiX := X1; End;
                        If Y1 < Y2 Then Begin LoY := Y1; HiY := Y2; End Else Begin LoY := Y2; HiY := Y1; End;
                        Fill := PCBServer.PCBObjectFactory(eFillObject, eNoDimension, eCreate_Default);
                        If Fill <> Nil Then
                        Begin
                            Fill.X1Location := LoX;
                            Fill.Y1Location := LoY;
                            Fill.X2Location := HiX;
                            Fill.Y2Location := HiY;
                            Fill.Rotation := 0;
                            Fill.Layer := Lyr;
                            If Net <> Nil Then
                            Begin
                                Fill.Net := Net;
                                If EditNets.IndexOf(IS2[J]) < 0 Then EditNets.Add(IS2[J]);
                            End;
                            Board.AddPCBObject(Fill);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Fill.I_ObjectAddress);
                            Back := IntToStr(Fill.X1Location) + ',' + IntToStr(Fill.Y1Location) + ',' + IntToStr(Fill.X2Location) + ',' + IntToStr(Fill.Y2Location);
                            Ok := (Fill.X1Location = LoX) And (Fill.Y1Location = LoY) And (Fill.X2Location = HiX) And (Fill.Y2Location = HiY);
                        End;
                    End
                    Else If IOp[J] = 'addtext' Then
                    Begin
                        Txt := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
                        If Txt <> Nil Then
                        Begin
                            Txt.XLocation := X1;
                            Txt.YLocation := Y1;
                            Txt.Layer := Lyr;
                            Txt.UseTTFonts := False;
                            If Pos('Bottom', GetLayerString(Lyr)) = 1 Then Txt.MirrorFlag := True;
                            Txt.Text := IS1[J];
                            Txt.Size := X2;
                            Txt.Width := W;
                            Txt.Rotation := Y2;
                            Board.AddPCBObject(Txt);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Txt.I_ObjectAddress);
                            Back := Txt.Text + ',' + IntToStr(Txt.XLocation) + ',' + IntToStr(Txt.YLocation) + ',' + IntToStr(Txt.Size);
                            Ok := (Txt.Text = IS1[J]) And (Txt.XLocation = X1) And (Txt.YLocation = Y1) And (Txt.Size = X2);
                        End;
                    End
                    Else If IOp[J] = 'setplated' Then
                    Begin
                        N := FreePadCount(Board, Lyr, X1, Y1, X2, Y2, Pad);
                        If Pad <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Pad.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            Pad.Plated := (W = 1);
                            PCBServer.SendMessageToRobots(Pad.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Back := 'plated ' + BoolToJsonStr(Pad.Plated);
                            Ok := (Pad.Plated = (W = 1));
                        End;
                    End
                    Else If IOp[J] = 'movepoly' Then
                    Begin
                        N := PolyAtFirstVertex(Board, Lyr, X1, Y1, W, Poly);
                        If Poly <> Nil Then
                        Begin
                            Try
                                If Poly.Net <> Nil Then
                                    If EditNets.IndexOf(Poly.Net.Name) < 0 Then EditNets.Add(Poly.Net.Name);
                            Except
                            End;
                            { Every vertex and arc centre by the offset; then the closing    }
                            { vertex one past PointCount (upstream measured a spike when it   }
                            { kept the old first vertex); then the repour as `repour` does it }
                            { (the option forced to Always for the call).                     }
                            OldMode := PCBServer.SystemOptions.PolygonRepour;
                            PCBServer.SystemOptions.PolygonRepour := 2;
                            Try
                                Poly.BeginModify;
                                For K := 0 To W - 1 Do
                                Begin
                                    Seg := Poly.Segments[K];
                                    Seg.vx := Seg.vx + X2;
                                    Seg.vy := Seg.vy + Y2;
                                    If Seg.Kind <> ePolySegmentLine Then
                                    Begin
                                        Seg.cx := Seg.cx + X2;
                                        Seg.cy := Seg.cy + Y2;
                                    End;
                                    Poly.Segments[K] := Seg;
                                End;
                                Seg := Poly.Segments[0];
                                Seg.Kind := ePolySegmentLine;
                                Poly.Segments[W] := Seg;
                                Poly.SetState_CopperPourInvalid;
                                Poly.Rebuild;
                                Poly.EndModify;
                                Poly.GraphicallyInvalidate;
                            Finally
                                PCBServer.SystemOptions.PolygonRepour := OldMode;
                            End;
                            PX0 := Poly.Segments[0].vx;
                            PY0 := Poly.Segments[0].vy;
                            Back := 'first vertex ' + IntToStr(PX0) + ',' + IntToStr(PY0)
                                + ' points ' + IntToStr(Poly.PointCount);
                            Ok := (PX0 = X1 + X2) And (PY0 = Y1 + Y2) And (Poly.PointCount = W)
                                And (Poly.Segments[W - 1].vx - Poly.Segments[0].vx = StrToInt(IS1[J]))
                                And (Poly.Segments[W - 1].vy - Poly.Segments[0].vy = StrToInt(IS2[J]));
                        End;
                    End
                    Else If IOp[J] = 'delfill' Then
                    Begin
                        N := FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill);
                        If Fill <> Nil Then
                        Begin
                            Try
                                If Fill.Net <> Nil Then
                                    If EditNets.IndexOf(Fill.Net.Name) < 0 Then EditNets.Add(Fill.Net.Name);
                            Except
                            End;
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Fill.I_ObjectAddress);
                            Board.RemovePCBObject(Fill);
                            K := FreeFillCount(Board, Lyr, X1, Y1, X2, Y2, Fill);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = N - 1);
                        End;
                    End
                    Else If IOp[J] = 'delvia' Then
                    Begin
                        N := FreeViaCount(Board, X1, Y1, X2, Y2, Via);
                        If Via <> Nil Then
                        Begin
                            Try
                                If Via.Net <> Nil Then
                                    If EditNets.IndexOf(Via.Net.Name) < 0 Then EditNets.Add(Via.Net.Name);
                            Except
                            End;
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Via.I_ObjectAddress);
                            Board.RemovePCBObject(Via);
                            K := FreeViaCount(Board, X1, Y1, X2, Y2, Via);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = 0);
                        End;
                    End
                    Else If IOp[J] = 'movevia' Then
                    Begin
                        Hole := StrToInt(IS1[J]);
                        N := FreeViaCount(Board, X1, Y1, W, Hole, Via);
                        If Via <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Via.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            Via.x := X2;
                            Via.y := Y2;
                            PCBServer.SendMessageToRobots(Via.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Back := IntToStr(Via.x) + ',' + IntToStr(Via.y) + ',' + IntToStr(Via.Size) + ',' + IntToStr(Via.HoleSize);
                            Ok := (Via.x = X2) And (Via.y = Y2) And CoordWithinTol(Via.Size, W, 5000) And CoordWithinTol(Via.HoleSize, Hole, 5000);
                        End;
                    End
                    Else If IOp[J] = 'text' Then
                    Begin
                        N := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                        If Txt <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            Txt.Text := IS2[J];
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Back := Txt.Text + ',' + IntToStr(Txt.XLocation) + ',' + IntToStr(Txt.YLocation);
                            Ok := (Txt.Text = IS2[J]) And (Txt.XLocation = X1) And (Txt.YLocation = Y1);
                        End;
                    End
                    Else If IOp[J] = 'deltrack' Then
                    Begin
                        N := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                        If Track <> Nil Then
                        Begin
                            If EditNets.IndexOf(IS1[J]) < 0 Then EditNets.Add(IS1[J]);
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
                            Board.RemovePCBObject(Track);
                            K := FreeLineCount(Board, Lyr, X1, Y1, X2, Y2, Track);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = N - 1);
                        End;
                    End
                    Else If IOp[J] = 'deltext' Then
                    Begin
                        N := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                        If Txt <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Txt.I_ObjectAddress);
                            Board.RemovePCBObject(Txt);
                            K := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                            Back := 'remaining ' + IntToStr(K);
                            Ok := (K = 0);
                        End;
                    End
                    Else If IOp[J] = 'movetext' Then
                    Begin
                        N := FreeTextCount(Board, Lyr, X1, Y1, IS1[J], Txt);
                        If Txt <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            EditMoveText(Txt, X2, Y2);
                            If W <> 0 Then Txt.Rotation := W Mod 360;
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Try Txt.GraphicallyInvalidate; Except End;
                            Back := Txt.Text + ',' + IntToStr(Txt.XLocation) + ',' + IntToStr(Txt.YLocation);
                            Ok := (Txt.XLocation = X2) And (Txt.YLocation = Y2);
                        End;
                    End
                    Else If IOp[J] = 'movename' Then
                    Begin
                        Comp := Nil;
                        Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                        Txt := Nil;
                        If Comp <> Nil Then Txt := Comp.Name;
                        If Txt <> Nil Then
                        Begin
                            { A manually placed designator, as upstream's placement text move. }
                            Try Comp.ChangeNameAutoposition(eAutoPos_Manual); Except End;
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            EditMoveText(Txt, X2, Y2);
                            If W <> 0 Then Txt.Rotation := W Mod 360;
                            PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Try Txt.GraphicallyInvalidate; Except End;
                            Back := IS1[J] + ',' + IntToStr(Txt.XLocation) + ',' + IntToStr(Txt.YLocation);
                            Ok := (Txt.XLocation = X2) And (Txt.YLocation = Y2);
                        End;
                    End
                    Else If (IOp[J] = 'showname') Or (IOp[J] = 'hidename') Then
                    Begin
                        Comp := Nil;
                        Try Comp := Board.GetPcbComponentByRefDes(IS1[J]); Except Comp := Nil; End;
                        If Comp <> Nil Then
                        Begin
                            PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                            Comp.NameOn := (IOp[J] = 'showname');
                            PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                            Try Comp.GraphicallyInvalidate; Except End;
                            If Comp.NameOn Then Back := IS1[J] + ',shown' Else Back := IS1[J] + ',hidden';
                            Ok := (Comp.NameOn = (IOp[J] = 'showname'));
                        End;
                    End
                    Else
                    Begin
                        EmptyList(VX);
                        EmptyList(VY);
                        ShapeVertices(IS1[J], VX, VY);
                        Board.BoardOutline.PointCount := VX.Count;
                        Seg := TPolySegment;
                        Seg.Kind := ePolySegmentLine;
                        For K := 0 To VX.Count - 1 Do
                        Begin
                            Seg.vx := StrToInt(VX[K]);
                            Seg.vy := StrToInt(VY[K]);
                            Board.BoardOutline.Segments[K] := Seg;
                        End;
                        { The closing vertex one past PointCount (upstream ClosePolySegments: }
                        { a replaced outline kept the OLD first vertex there, a spike).       }
                        Try
                            Seg := Board.BoardOutline.Segments[0];
                            Seg.Kind := ePolySegmentLine;
                            Board.BoardOutline.Segments[VX.Count] := Seg;
                        Except
                        End;
                        Board.BoardOutline.Invalidate;
                        Board.BoardOutline.Rebuild;
                        Board.BoardOutline.Validate;
                        Ok := (Board.BoardOutline.PointCount = VX.Count);
                        Back := 'points ' + IntToStr(Board.BoardOutline.PointCount);
                        If Ok Then
                            For K := 0 To VX.Count - 1 Do
                            Begin
                                Seg2 := Board.BoardOutline.Segments[K];
                                If (Seg2.vx <> StrToInt(VX[K])) Or (Seg2.vy <> StrToInt(VY[K])) Then Ok := False;
                            End;
                    End;
                    IBack[J] := Back;
                    If Back = '' Then
                    Begin
                        IStatus[J] := 'not_done: target not found at apply';
                        Partial := True;
                    End
                    Else If Ok Then
                    Begin
                        IStatus[J] := 'done';
                        Inc(Done);
                    End
                    Else
                    Begin
                        IStatus[J] := 'done_readback_differs';
                        Partial := True;
                    End;
                End;
            Finally
                PCBServer.PostProcess;
                If Touched Then MarkDocDirtyByPath(PcbPath);
                If Touched Then AnalyzeNetsByName(Board, EditNets);
            End;
            For J := 0 To IOp.Count - 1 Do
                If Copy(IStatus[J], 1, 5) = 'would' Then IStatus[J] := 'not_done';
        End;

        ItemsJson := '';
        For J := 0 To IOp.Count - 1 Do
        Begin
            If J > 0 Then ItemsJson := ItemsJson + ',';
            ItemsJson := ItemsJson + '{"op":"' + IOp[J] + '","layer":"' + EscapeJsonString(ILay[J])
                + '","status":"' + EscapeJsonString(IStatus[J]) + '","readback":"' + EscapeJsonString(IBack[J]) + '"}';
        End;
        Try PcbModified := Client.GetDocumentByPath(PcbPath).Modified; Except PcbModified := True; End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; preview again (done: ' + IntToStr(Done) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"' + Mode + '","pcb_path":"' + EscapeJsonString(PcbPath)
                + '","batch_hash":"' + LowerCase(BatchHash) + '","counts":"' + Counts
                + '","item_count":' + IntToStr(IOp.Count) + ',"would_change":' + IntToStr(Would)
                + ',"refused":' + IntToStr(Refused) + ',"done":' + IntToStr(Done)
                + ',"partial":' + BoolToJsonStr(Partial) + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched) + ',"pcb_modified":' + BoolToJsonStr(PcbModified)
                + ',"saved":false,"items":[' + ItemsJson + ']}}');
    Finally
        If Touched Then
        Begin
            PlaceEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        IOp.Free; ILay.Free; IX1.Free; IY1.Free; IX2.Free; IY2.Free; IW.Free; IS1.Free;
        IS2.Free; IStatus.Free; IBack.Free; VX.Free; VY.Free; EditNets.Free;
        VCX.Free; VCY.Free; VA1.Free; VA2.Free;
    End;
End;

{ ---- Checked schematic edits (TOOLS.md backlog 5a / 5b,                        }
{      PROPOSAL-2026-11-18-schematic-edits)                                     }
{ Sheet-level objects of the SELECTED project's schematics, read and edited      }
{ from a checked plan: net labels, power ports, wires, free text, text frames    }
{ (notes), rectangles (boxes), lines, and sheet parameters (title block).        }
{ Never parts, pins, ports or sheet symbols. Raw coordinates (10000 per mil).    }
{ preview: params sheet (index, -1 = sheet list only) -> the sheet's objects,    }
{   the electrical end of every pin, the sheet parameters.                       }
{ apply: parameter-edits tick, every sheet open, the touched sheets saved,       }
{   every item preflighted before the first write (the exact old state must be   }
{   there once; an add must not duplicate), read back, never saves, the tick     }
{   clears. Items, at most 200:                                                  }
{     op|sheet|x1|y1|x2|y2|n|s1|s2|s3      (s* percent-encoded, %0A = new line)  }
{   add     s1 kind (label power wire text box line note), s2 power style,       }
{           s3 text; n orientation 0-3 (label, power, text) or line width 0-2    }
{   settext s1 kind (label power text note) at x1,y1; s2 old, s3 new             }
{   move    s1 kind (label power text) x1,y1 -> x2,y2; s2 its text               }
{   del     s1 kind, exact geometry; s2 its text (label power text note)         }
{   docparam s1 name, s2 old value, s3 new value (sheet-level parameter)         }
{   compparam s1 DESIGNATOR/Name, s2 old, s3 new; n 1 = add the parameter       }
{           (hidden) instead. Every part of the designator on the sheet.        }
{ Corner needs a typed local (ISch_Rectangle / ISch_Line / ISch_TextFrame):      }
{ late-bound Obj.Corner does not compile (Generic.pas GetSchProperty).           }

Function SchEditKindId(Kind : String) : Integer;
Begin
    Result := -1;
    If Kind = 'label' Then Result := eNetLabel
    Else If Kind = 'power' Then Result := ePowerObject
    Else If Kind = 'wire' Then Result := eWire
    Else If Kind = 'text' Then Result := eLabel
    Else If Kind = 'box' Then Result := eRectangle
    Else If Kind = 'line' Then Result := eLine
    Else If Kind = 'note' Then Result := eTextFrame
    Else If Kind = 'port' Then Result := ePort          { scripts 2026.11.23.6 }
    Else If Kind = 'noerc' Then Result := eNoERC
    Else If Kind = 'bus' Then Result := eBus            { scripts 2026.11.23.7 }
    Else If Kind = 'busentry' Then Result := eBusEntry
    Else If Kind = 'sheetsymbol' Then Result := eSheetSymbol;
End;

Function SchEditHasText(Kind : String) : Boolean;
Begin
    Result := (Kind = 'label') Or (Kind = 'power') Or (Kind = 'text') Or (Kind = 'note');
End;

Function SchEditHasCorner(Kind : String) : Boolean;
Begin
    Result := (Kind = 'box') Or (Kind = 'line') Or (Kind = 'note');
End;

{ %0A separates lines; every other byte goes through the parameter decoder. }
Function SchEditDecode(S : String; Var Ok : Boolean) : String;
Var
    P : Integer;
    Part : String;
    PartOk : Boolean;
Begin
    Result := '';
    Ok := True;
    While True Do
    Begin
        P := Pos('%0A', S);
        If P = 0 Then Part := S Else Part := Copy(S, 1, P - 1);
        Result := Result + ParamEditDecode(Part, PartOk);
        If Not PartOk Then Ok := False;
        If P = 0 Then Break;
        Result := Result + #13#10;
        S := Copy(S, P + 3, Length(S));
    End;
End;

Function SchEditCorner(Obj : ISch_GraphicalObject; Kind : String; Var CX, CY : Integer) : Boolean;
Var
    R : ISch_Rectangle;
    L : ISch_Line;
    T : ISch_TextFrame;
    Crn : TLocation;
Begin
    Result := False;
    CX := 0; CY := 0;
    Try
        If Kind = 'box' Then Begin R := Obj; Crn := R.Corner; Result := True; End
        Else If Kind = 'line' Then Begin L := Obj; Crn := L.Corner; Result := True; End
        Else If Kind = 'note' Then Begin T := Obj; Crn := T.Corner; Result := True; End;
        If Result Then Begin CX := Crn.X; CY := Crn.Y; End;
    Except
        Result := False;
    End;
End;

Function SchEditWireEnds(Obj : ISch_GraphicalObject; Var AX, AY, BX, BY, N : Integer) : Boolean;
Var
    V : TLocation;
Begin
    Result := False;
    N := 0;
    Try N := Obj.GetState_VerticesCount; Except N := 0; End;
    If N < 2 Then Exit;
    Try
        V := Obj.GetState_Vertex(1);
        AX := V.X; AY := V.Y;
        V := Obj.GetState_Vertex(N);
        BX := V.X; BY := V.Y;
        Result := True;
    Except
        Result := False;
    End;
End;

{ The object of Kind at exactly this geometry. Corner / far end are compared     }
{ when UseCorner (always for a wire's two ends, either order). Nil unless one.   }
Function SchEditFind(Doc : ISch_Document; Kind : String; X1, Y1, X2, Y2 : Integer;
    UseCorner : Boolean; Var Hits : Integer) : ISch_GraphicalObject;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Loc : TLocation;
    KindId, CX, CY, AX, AY, BX, BY, N : Integer;
    Match : Boolean;
Begin
    Result := Nil;
    Hits := 0;
    KindId := SchEditKindId(Kind);
    If KindId < 0 Then Exit;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.SetState_IterationDepth(eIterateFirstLevel);
        Iter.AddFilter_ObjectSet(MkSet(KindId));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Match := False;
            Try
                If Kind = 'wire' Then
                Begin
                    If SchEditWireEnds(Obj, AX, AY, BX, BY, N) Then
                        Match := ((AX = X1) And (AY = Y1) And (BX = X2) And (BY = Y2))
                            Or ((AX = X2) And (AY = Y2) And (BX = X1) And (BY = Y1));
                End
                Else
                Begin
                    Loc := Obj.GetState_Location;
                    Match := (Loc.X = X1) And (Loc.Y = Y1);
                    If Match And UseCorner And SchEditHasCorner(Kind) Then
                    Begin
                        If SchEditCorner(Obj, Kind, CX, CY) Then
                            Match := (CX = X2) And (CY = Y2)
                        Else
                            Match := False;
                    End;
                End;
            Except
                Match := False;
            End;
            If Match Then
            Begin
                Inc(Hits);
                Result := Obj;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
    If Hits <> 1 Then Result := Nil;
End;

Function SchEditFindParam(Doc : ISch_Document; Name : String; Var Hits : Integer) : ISch_GraphicalObject;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    N : String;
Begin
    Result := Nil;
    Hits := 0;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.SetState_IterationDepth(eIterateFirstLevel);
        Iter.AddFilter_ObjectSet(MkSet(eParameter));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            N := '';
            Try N := Obj.Name; Except N := ''; End;
            If UpperCase(N) = UpperCase(Name) Then
            Begin
                Inc(Hits);
                Result := Obj;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
    If Hits <> 1 Then Result := Nil;
End;

{ Upstream d23c50d: a Text write lands on a read-only parameter anyway. }
Function SchEditParamReadOnly(Obj : ISch_GraphicalObject) : Boolean;
Var
    Par : ISch_Parameter;
Begin
    Result := False;
    Try
        Par := Obj;
        Result := Par.ValueIsReadOnly;
    Except
        Result := False;
    End;
End;

Function SchEditObjText(Obj : ISch_GraphicalObject) : String;
Begin
    Result := '';
    Try Result := Obj.Text; Except Result := ''; End;
End;

{ One kind of sheet-level object as JSON rows (leading comma on each row). }
Function SchEditKindJSON(Doc : ISch_Document; Kind : String; Var Count : Integer) : String;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Loc, V : TLocation;
    KindId, CX, CY, N, I, Ori, Sty : Integer;
    Row, Txt : String;
Begin
    Result := '';
    KindId := SchEditKindId(Kind);
    If Kind = 'port' Then KindId := ePort;
    If KindId < 0 Then Exit;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.SetState_IterationDepth(eIterateFirstLevel);
        Iter.AddFilter_ObjectSet(MkSet(KindId));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Row := '';
            Try
                If Kind = 'wire' Then
                Begin
                    N := 0;
                    Try N := Obj.GetState_VerticesCount; Except N := 0; End;
                    Row := '{"k":"wire","v":[';
                    For I := 1 To N Do
                    Begin
                        V := Obj.GetState_Vertex(I);
                        If I > 1 Then Row := Row + ',';
                        Row := Row + IntToStr(V.X) + ',' + IntToStr(V.Y);
                    End;
                    Row := Row + ']}';
                End
                Else
                Begin
                    Loc := Obj.GetState_Location;
                    Row := '{"k":"' + Kind + '","x":' + IntToStr(Loc.X) + ',"y":' + IntToStr(Loc.Y);
                    If SchEditHasCorner(Kind) Then
                    Begin
                        If SchEditCorner(Obj, Kind, CX, CY) Then
                            Row := Row + ',"x2":' + IntToStr(CX) + ',"y2":' + IntToStr(CY);
                    End;
                    If Kind = 'port' Then
                    Begin
                        Txt := '';
                        Try Txt := Obj.Name; Except Txt := ''; End;
                        Row := Row + ',"t":"' + EscapeJsonString(Txt) + '"';
                    End
                    Else If SchEditHasText(Kind) Then
                        Row := Row + ',"t":"' + EscapeJsonString(SchEditObjText(Obj)) + '"';
                    If (Kind = 'label') Or (Kind = 'power') Or (Kind = 'text') Then
                    Begin
                        Ori := 0;
                        Try Ori := Obj.Orientation; Except Ori := 0; End;
                        Row := Row + ',"o":' + IntToStr(Ori);
                    End;
                    If Kind = 'power' Then
                    Begin
                        Sty := 0;
                        Try Sty := Obj.Style; Except Sty := 0; End;
                        Row := Row + ',"s":' + IntToStr(Sty);
                    End;
                    Row := Row + '}';
                End;
            Except
                Row := '';
            End;
            If Row <> '' Then
            Begin
                Result := Result + ',' + Row;
                Inc(Count);
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
End;

{ Electrical end of every pin of every part on the sheet (leading comma rows). }
Function SchEditPinsJSON(Doc : ISch_Document; Var Count : Integer) : String;
Var
    CompIter, PinIter : ISch_Iterator;
    CompObj, PinObj : ISch_GraphicalObject;
    Comp : ISch_Component;
    Pin : ISch_Pin;
    Loc : TLocation;
    Des, Num, Nam : String;
    X, Y, Len, Ori, PartId, OwnerId : Integer;
Begin
    Result := '';
    CompIter := Doc.SchIterator_Create;
    Try
        CompIter.AddFilter_ObjectSet(MkSet(eSchComponent));
        CompObj := CompIter.FirstSchObject;
        While CompObj <> Nil Do
        Begin
            Comp := CompObj;
            Des := '';
            Try Des := Comp.Designator.Text; Except Des := ''; End;
            PartId := -1;
            Try PartId := Comp.CurrentPartID; Except PartId := -1; End;
            PinIter := Comp.SchIterator_Create;
            If PinIter <> Nil Then
            Begin
                Try
                    PinIter.AddFilter_ObjectSet(MkSet(ePin));
                    PinObj := PinIter.FirstSchObject;
                    While PinObj <> Nil Do
                    Begin
                        Try
                            Pin := PinObj;
                            OwnerId := PartId;
                            Try OwnerId := Pin.OwnerPartId; Except OwnerId := PartId; End;
                            If (PartId < 0) Or (OwnerId = PartId) Or (OwnerId <= 0) Then
                            Begin
                                Num := ''; Nam := ''; Len := 0; Ori := 0;
                                Try Num := Pin.Designator; Except End;
                                Try Nam := Pin.Name; Except End;
                                Loc := Pin.GetState_Location;
                                X := Loc.X; Y := Loc.Y;
                                Try Len := Pin.PinLength; Except End;
                                Try Ori := Pin.Orientation; Except End;
                                If Ori = 0 Then X := X + Len
                                Else If Ori = 1 Then Y := Y + Len
                                Else If Ori = 2 Then X := X - Len
                                Else If Ori = 3 Then Y := Y - Len;
                                Result := Result + ',{"d":"' + EscapeJsonString(Des)
                                    + '","p":"' + EscapeJsonString(Num)
                                    + '","n":"' + EscapeJsonString(Nam)
                                    + '","x":' + IntToStr(X) + ',"y":' + IntToStr(Y)
                                    + ',"o":' + IntToStr(Ori) + '}';
                                Inc(Count);
                            End;
                        Except End;
                        PinObj := PinIter.NextSchObject;
                    End;
                Finally
                    Comp.SchIterator_Destroy(PinIter);
                End;
            End;
            CompObj := CompIter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(CompIter);
    End;
End;

Function SchEditParamsJSON(Doc : ISch_Document) : String;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    N, V : String;
Begin
    Result := '';
    Iter := Doc.SchIterator_Create;
    Try
        Iter.SetState_IterationDepth(eIterateFirstLevel);
        Iter.AddFilter_ObjectSet(MkSet(eParameter));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            N := ''; V := '';
            Try N := Obj.Name; Except N := ''; End;
            Try V := Obj.Text; Except V := ''; End;
            If N <> '' Then
                Result := Result + ',{"name":"' + EscapeJsonString(N)
                    + '","value":"' + EscapeJsonString(V) + '"}';
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
End;

Function SchEditLineWidth(N : Integer) : Integer;
Begin
    If N <= 0 Then Result := eSmall
    Else If N = 1 Then Result := eMedium
    Else Result := eLarge;
End;

{ Creates and registers one object. Caller holds PreProcess. Nil on failure. }
Function SchEditCreate(Doc : ISch_Document; Kind : String; X1, Y1, X2, Y2, N : Integer;
    Style, Txt : String) : ISch_GraphicalObject;
Var
    Obj : ISch_GraphicalObject;
    R : ISch_Rectangle;
    L : ISch_Line;
    T : ISch_TextFrame;
    W : ISch_Wire;
    Pt : ISch_Port;
    Bs : ISch_Bus;
    Be : ISch_BusEntry;
    Sym : ISch_SheetSymbol;
    FNObj : ISch_SheetFileName;
    NMObj : ISch_SheetName;
    Loc : TLocation;
    FontId, Color : Integer;
Begin
    Result := Nil;
    Obj := SchServer.SchObjectFactory(SchEditKindId(Kind), eCreate_Default);
    If Obj = Nil Then Exit;
    If Kind = 'wire' Then
    Begin
        W := Obj;
        W.Location := Point(X1, Y1);
        W.InsertVertex := 1;
        W.SetState_Vertex(1, Point(X1, Y1));
        W.InsertVertex := 2;
        W.SetState_Vertex(2, Point(X2, Y2));
        W.LineWidth := eSmall;
    End
    Else If Kind = 'box' Then
    Begin
        R := Obj;
        R.Location := Point(X1, Y1);
        R.Corner := Point(X2, Y2);
        R.IsSolid := False;
        Try R.LineWidth := SchEditLineWidth(N); Except End;
    End
    Else If Kind = 'line' Then
    Begin
        L := Obj;
        L.Location := Point(X1, Y1);
        L.Corner := Point(X2, Y2);
        Try L.LineWidth := SchEditLineWidth(N); Except End;
    End
    Else If Kind = 'note' Then
    Begin
        T := Obj;
        T.Location := Point(X1, Y1);
        T.Corner := Point(X2, Y2);
        T.Text := Txt;
        Try T.WordWrap := True; Except End;
        Try T.ClipToRect := True; Except End;
        Try T.ShowBorder := False; Except End;
    End
    Else If Kind = 'bus' Then
    Begin
        { Upstream Gen_PlaceBus: a two-vertex bus, written like the wire. }
        Bs := Obj;
        Bs.Location := Point(X1, Y1);
        Bs.InsertVertex := 1;
        Bs.SetState_Vertex(1, Point(X1, Y1));
        Bs.InsertVertex := 2;
        Bs.SetState_Vertex(2, Point(X2, Y2));
    End
    Else If Kind = 'busentry' Then
    Begin
        { Upstream Gen_PlaceBusEntry: ISch_BusEntry is a line, location and corner. }
        Be := Obj;
        Be.Location := Point(X1, Y1);
        Be.Corner := Point(X2, Y2);
    End
    Else If Kind = 'sheetsymbol' Then
    Begin
        { Upstream Gen_PlaceSheetSymbol: no Corner on a sheet symbol, the size is }
        { XSize / YSize from the bottom-left location. File name and name are     }
        { sub-objects, set after the registration below.                          }
        Sym := Obj;
        Sym.Location := Point(X1, Y1);
        Sym.XSize := X2 - X1;
        Sym.YSize := Y2 - Y1;
    End
    Else If Kind = 'port' Then
    Begin
        { Upstream Gen_PlacePort: location, name, style, IO type. N is the IO type: }
        { 0 unspecified, 1 output, 2 input, 3 bidirectional.                         }
        Pt := Obj;
        Pt.Location := Point(X1, Y1);
        Pt.Name := Txt;
        If Style = 'left' Then Pt.Style := ePortLeft
        Else If Style = 'right' Then Pt.Style := ePortRight
        Else If Style = 'left_right' Then Pt.Style := ePortLeftRight
        Else Pt.Style := ePortNone;
        If N = 1 Then Pt.IOType := ePortOutput
        Else If N = 2 Then Pt.IOType := ePortInput
        Else If N = 3 Then Pt.IOType := ePortBidirectional
        Else Pt.IOType := ePortUnspecified;
    End
    Else If Kind = 'noerc' Then
    Begin
        Obj.Location := Point(X1, Y1);
    End
    Else
    Begin
        { label, power, text }
        Loc := Obj.Location;
        Loc.X := X1;
        Loc.Y := Y1;
        Obj.Location := Loc;
        Obj.Text := Txt;
        Try Obj.Orientation := N; Except End;
        If Kind = 'label' Then
        Begin
            If InferNetLabelStyle(Doc, FontId, Color) Then
            Begin
                Try Obj.FontId := FontId; Except End;
                Obj.Color := Color;
            End;
        End
        Else If Kind = 'power' Then
        Begin
            Obj.ShowNetName := True;
            If Style = 'arrow' Then Obj.Style := ePowerArrow
            Else If Style = 'bar' Then Obj.Style := ePowerBar
            Else If Style = 'wave' Then Obj.Style := ePowerWave
            Else If Style = 'gnd_power' Then Obj.Style := ePowerGndPower
            Else If Style = 'gnd_signal' Then Obj.Style := ePowerGndSignal
            Else If Style = 'gnd_earth' Then Obj.Style := ePowerGndEarth
            Else Obj.Style := ePowerCircle;
        End;
    End;
    Doc.RegisterSchObjectInContainer(Obj);
    SchRegisterObject(Doc, Obj);
    If Kind = 'sheetsymbol' Then
    Begin
        { Style carries the child sheet's file name, Txt the displayed name. }
        Sym := Obj;
        FNObj := Nil;
        Try FNObj := Sym.GetState_SchSheetFileName; Except End;
        If FNObj <> Nil Then FNObj.SetState_Text(Style);
        NMObj := Nil;
        Try NMObj := Sym.GetState_SchSheetName; Except End;
        If NMObj <> Nil Then NMObj.SetState_Text(Txt);
    End;
    Result := Obj;
End;

{ compparam: one parameter on EVERY part of a designator on this sheet (so a   }
{ multi-part symbol is covered sheet by sheet). Create = the parameter must be }
{ absent on every part and is added hidden; otherwise it must be there once on }
{ every part with Text = OldV. DoWrite False = preflight only. Returns the     }
{ number of parts; Status says why not.                                        }
Function SchEditCompParam(Doc : ISch_Document; Des, Name, OldV, NewV : String;
    Create, DoWrite : Boolean; Var Status : String) : Integer;
Var
    Iter, PIter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
    Param, Found, NewParam : ISch_Parameter;
    Hits : Integer;
Begin
    Result := 0;
    Status := '';
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Comp := Obj;
            If Comp.Designator.Text = Des Then
            Begin
                Inc(Result);
                Hits := 0;
                Found := Nil;
                PIter := Comp.SchIterator_Create;
                Try
                    PIter.AddFilter_ObjectSet(MkSet(eParameter));
                    Param := PIter.FirstSchObject;
                    While Param <> Nil Do
                    Begin
                        If Param.Name = Name Then
                        Begin
                            Inc(Hits);
                            Found := Param;
                        End;
                        Param := PIter.NextSchObject;
                    End;
                Finally
                    Comp.SchIterator_Destroy(PIter);
                End;
                If Create Then
                Begin
                    If Hits > 0 Then Status := 'the parameter already exists on ' + Des
                    Else If DoWrite Then
                    Begin
                        NewParam := SchServer.SchObjectFactory(eParameter, eCreate_Default);
                        If NewParam = Nil Then Status := 'could not create the parameter'
                        Else
                        Begin
                            NewParam.Name := Name;
                            NewParam.Text := NewV;
                            Try NewParam.IsHidden := True; Except End;
                            Try NewParam.Location := Comp.Location; Except End;
                            Comp.AddSchObject(NewParam);
                            SchRegisterObject(Comp, NewParam);
                        End;
                    End;
                End
                Else
                Begin
                    If Hits <> 1 Then Status := 'parameter found ' + IntToStr(Hits) + ' times on a part of ' + Des
                    Else If Found.Text <> OldV Then Status := 'value changed since the read'
                    Else If DoWrite Then
                    Begin
                        SchBeginModify(Found);
                        Found.Text := NewV;
                        SchEndModify(Found);
                        If Found.Text <> NewV Then Status := 'text differs';
                    End;
                End;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
    If (Result = 0) And (Status = '') Then Status := Des + ' is not on this sheet';
End;

{ ---- Library items (scripts 2026.11.23.8) --------------------------------------- }
{ Create-only: a new symbol in a .SchLib or a new footprint in a .PcbLib, and the    }
{ primitives that go on it. Nothing that was in the library before is touched. The   }
{ library must be the ACTIVE document in Altium: upstream's library functions (the   }
{ calls copied here) are proven on the current library only.                         }

{ Field Index (0-based) of a '/'-separated string. }
Function SchEditSplit(S : String; Index : Integer) : String;
Var
    P, I : Integer;
    Rest : String;
Begin
    Rest := S;
    Result := '';
    For I := 0 To Index Do
    Begin
        P := Pos('/', Rest);
        If P = 0 Then
        Begin
            If I = Index Then Result := Rest Else Result := '';
            Rest := '';
        End
        Else
        Begin
            Result := Copy(Rest, 1, P - 1);
            Rest := Copy(Rest, P + 1, Length(Rest));
        End;
    End;
End;

{ Primitives of one kind on a library symbol (scripts 2026.11.23.9): the count }
{ before and after a write is the read-back of libpin and librect.             }
Function SchEditLibCount(Component : ISch_Component; KindId : Integer) : Integer;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
Begin
    Result := 0;
    Iter := Component.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(KindId));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Inc(Result);
            Obj := Iter.NextSchObject;
        End;
    Finally
        Component.SchIterator_Destroy(Iter);
    End;
End;

{ Primitives of one kind on a library footprint. Upstream's pad read skips    }
{ repeated objects in this iterator, so the count is only compared for        }
{ "more than before", not for "one more".                                     }
Function SchEditLibFpCount(Footprint : IPCB_LibComponent; KindId : Integer) : Integer;
Var
    Iter : IPCB_GroupIterator;
    Prim : IPCB_Primitive;
Begin
    Result := 0;
    Iter := Footprint.GroupIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(KindId));
        Prim := Iter.FirstPCBObject;
        While Prim <> Nil Do
        Begin
            Inc(Result);
            Prim := Iter.NextPCBObject;
        End;
    Finally
        Footprint.GroupIterator_Destroy(Iter);
    End;
End;

Function SchEditFocusedSchLib(LibPath : String) : ISch_Lib;
Begin
    Result := Nil;
    Try
        Result := SchServer.GetCurrentSchDocument;
        If (Result <> Nil) And (Result.ObjectId <> eSchLib) Then Result := Nil;
        If (Result <> Nil) And (Not SchLibIsAtPath(Result, LibPath)) Then Result := Nil;
    Except
        Result := Nil;
    End;
End;

Function SchEditFocusedPcbLib(LibPath : String) : IPCB_Library;
Begin
    Result := Nil;
    Try
        Result := PCBServer.GetCurrentPCBLibrary;
        If (Result <> Nil) And (UpperCase(Result.Board.FileName) <> UpperCase(LibPath)) Then Result := Nil;
    Except
        Result := Nil;
    End;
End;

{ Upstream Lib_CreateSymbol: part id and display mode before any primitive, the   }
{ reference set again after AddSchComponent, the component broadcast as new.      }
Function SchEditLibNewSymbol(SchLib : ISch_Lib; SymName, Prefix, Desc : String) : ISch_Component;
Var
    Component : ISch_Component;
Begin
    Result := Nil;
    Component := SchServer.SchObjectFactory(eSchComponent, eCreate_Default);
    If Component = Nil Then Exit;
    Component.CurrentPartID := 1;
    Component.DisplayMode := 0;
    Component.LibReference := SymName;
    Component.Designator.Text := Prefix + '?';
    Component.ComponentDescription := Desc;
    SchServer.ProcessControl.PreProcess(SchLib, '');
    SchLib.AddSchComponent(Component);
    Component.LibReference := SymName;
    SchServer.ProcessControl.PostProcess(SchLib, 'Edit');
    Try
        SchServer.RobotManager.SendMessage(Nil, Nil, SCHM_PrimitiveRegistration, Component.I_ObjectAddress);
    Except
    End;
    Try SchLib.GraphicallyInvalidate; Except End;
    MarkLibDirty(SchLib);
    If LookupLibComponent(SchLib, SymName) <> Nil Then Result := Component;
End;

{ Upstream Lib_AddPin. }
{ Flags (scripts 2026.11.25.2): 'n' hides the pin's name, 'd' its designator;   }
{ both are read back before the pin goes on the symbol.                        }
Function SchEditLibPin(SchLib : ISch_Lib; Component : ISch_Component; Des, PinName, EType, Flags : String;
    X, Y, Len, Orient : Integer) : Boolean;
Var
    Pin : ISch_Pin;
    Loc : TLocation;
    WantName, WantDes : Boolean;
Begin
    Result := False;
    Pin := SchServer.SchObjectFactory(ePin, eCreate_Default);
    If Pin = Nil Then Exit;
    Pin.Designator := Des;
    Pin.Name := PinName;
    { Read-modify-write: Location is a record returned by value, so      }
    { `Pin.Location.X := X` changes a copy and the pin stays at (0, 0)   }
    { (W27, 2026-11-25: every pin of five new symbols at the origin).    }
    Loc := Pin.Location;
    Loc.X := X;
    Loc.Y := Y;
    Pin.Location := Loc;
    { Read back before the pin goes on the symbol: a count alone passed W27. }
    Loc := Pin.Location;
    If (Loc.X <> X) Or (Loc.Y <> Y) Then Exit;
    Pin.PinLength := Len;
    Pin.Orientation := Orient;
    Pin.IsHidden := False;
    WantName := Pos('n', Flags) = 0;
    WantDes := Pos('d', Flags) = 0;
    Pin.ShowName := WantName;
    Pin.ShowDesignator := WantDes;
    If (Pin.ShowName <> WantName) Or (Pin.ShowDesignator <> WantDes) Then Exit;
    Pin.Electrical := StrToPinElectrical(EType);
    SchServer.ProcessControl.PreProcess(SchLib, '');
    SetOwnerPart(Pin, Component);
    Component.AddSchObject(Pin);
    SchRegisterObject(Component, Pin);
    SchServer.ProcessControl.PostProcess(SchLib, 'Edit');
    MarkLibDirty(SchLib);
    Result := True;
End;

{ Upstream Lib_AddSymbolRectangle. Not filled when FillColor is negative;      }
{ otherwise solid in FillColor with the border in BorderColor (scripts          }
{ 2026.11.25.2), each read back before the rectangle goes on the symbol.        }
Function SchEditLibRect(SchLib : ISch_Lib; Component : ISch_Component; X1, Y1, X2, Y2,
    FillColor, BorderColor : Integer) : Boolean;
Var
    Rect : ISch_Rectangle;
    Loc : TLocation;
Begin
    Result := False;
    Rect := SchServer.SchObjectFactory(eRectangle, eCreate_Default);
    If Rect = Nil Then Exit;
    Loc := Rect.Location;
    Loc.X := X1;
    Loc.Y := Y1;
    Rect.Location := Loc;
    Loc := Rect.Corner;
    Loc.X := X2;
    Loc.Y := Y2;
    Rect.Corner := Loc;
    Rect.IsSolid := False;
    If FillColor >= 0 Then
    Begin
        Rect.AreaColor := FillColor;
        Rect.IsSolid := True;
        If BorderColor >= 0 Then Rect.Color := BorderColor;
        If (Not Rect.IsSolid) Or (Rect.AreaColor <> FillColor) Then Exit;
        If (BorderColor >= 0) And (Rect.Color <> BorderColor) Then Exit;
    End;
    SchServer.ProcessControl.PreProcess(SchLib, '');
    SetOwnerPart(Rect, Component);
    Component.AddSchObject(Rect);
    SchRegisterObject(Component, Rect);
    SchServer.ProcessControl.PostProcess(SchLib, 'Edit');
    MarkLibDirty(SchLib);
    Try SchLib.GraphicallyInvalidate; Except End;
    Result := True;
End;

{ Upstream Lib_CreateFootprint. }
Function SchEditLibNewFootprint(PcbLib : IPCB_Library; FpName, Desc : String) : IPCB_LibComponent;
Var
    Footprint : IPCB_LibComponent;
Begin
    Result := Nil;
    Footprint := PCBServer.CreatePCBLibComp;
    If Footprint = Nil Then Exit;
    Footprint.Name := FpName;
    Footprint.Description := Desc;
    PcbLib.RegisterComponent(Footprint);
    PcbLib.CurrentComponent := Footprint;
    MarkDocDirtyByPath(PcbLib.Board.FileName);
    Result := Footprint;
End;

{ Upstream Lib_AddFootprintPad: the pad goes to the footprint AND to the library's }
{ backing board, with both registrations (without the second the save drops it).  }
Function SchEditLibPad(PcbLib : IPCB_Library; Footprint : IPCB_LibComponent; Des, Shape : String;
    X, Y, SX, SY, Hole : Integer) : Boolean;
Var
    Pad : IPCB_Pad;
Begin
    Result := False;
    PCBServer.PreProcess;
    Try
        Pad := PCBServer.PCBObjectFactory(ePadObject, eNoDimension, eCreate_Default);
        If Pad <> Nil Then
        Begin
            Pad.Name := Des;
            Pad.X := FootprintOriginX(Footprint) + X;
            Pad.Y := FootprintOriginY(Footprint) + Y;
            Pad.TopXSize := SX;
            Pad.TopYSize := SY;
            Pad.HoleSize := Hole;
            Pad.Rotation := 0;
            If Hole > 0 Then Pad.Layer := eMultiLayer Else Pad.Layer := eTopLayer;
            If Shape = 'rect' Then Pad.TopShape := eRectangular
            Else If Shape = 'roundrect' Then
            Begin
                Pad.SetState_StackShapeOnLayer(Pad.Layer, eRoundedRectangular);
                Pad.SetState_StackCRPctOnLayer(Pad.Layer, 25);
            End
            Else Pad.TopShape := eRounded;
            Footprint.AddPCBObject(Pad);
            PcbLib.Board.AddPCBObject(Pad);
            PCBServer.SendMessageToRobots(Footprint.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pad.I_ObjectAddress);
            PCBServer.SendMessageToRobots(PcbLib.Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Pad.I_ObjectAddress);
            Result := True;
        End;
    Finally
        PCBServer.PostProcess;
    End;
    MarkDocDirtyByPath(PcbLib.Board.FileName);
End;

{ Upstream Lib_AddFootprintTrack. }
Function SchEditLibTrack(PcbLib : IPCB_Library; Footprint : IPCB_LibComponent; LayerStr : String;
    X1, Y1, X2, Y2, Width : Integer) : Boolean;
Var
    Track : IPCB_Track;
    Lyr : TLayer;
Begin
    Result := False;
    Lyr := ResolveLayerId(PcbLib.Board, LayerStr);
    If Lyr = eNoLayer Then Exit;
    PCBServer.PreProcess;
    Try
        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
        If Track <> Nil Then
        Begin
            Track.X1 := FootprintOriginX(Footprint) + X1;
            Track.Y1 := FootprintOriginY(Footprint) + Y1;
            Track.X2 := FootprintOriginX(Footprint) + X2;
            Track.Y2 := FootprintOriginY(Footprint) + Y2;
            Track.Width := Width;
            Track.Layer := Lyr;
            Footprint.AddPCBObject(Track);
            PcbLib.Board.AddPCBObject(Track);
            PCBServer.SendMessageToRobots(Footprint.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
            PCBServer.SendMessageToRobots(PcbLib.Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Track.I_ObjectAddress);
            Result := True;
        End;
    Finally
        PCBServer.PostProcess;
    End;
    MarkDocDirtyByPath(PcbLib.Board.FileName);
End;

{ Sheet symbols on a sheet whose displayed name is SymName (scripts 2026.11.23.7, }
{ op `entry`). The name is a sub-object: its text is read through .Text.          }
Function SchEditSymbolByName(Doc : ISch_Document; SymName : String; Var First : ISch_SheetSymbol) : Integer;
Var
    Iter : ISch_Iterator;
    Sym : ISch_SheetSymbol;
    ThisName : String;
Begin
    Result := 0;
    First := Nil;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSheetSymbol));
        Sym := Iter.FirstSchObject;
        While Sym <> Nil Do
        Begin
            ThisName := '';
            Try
                If Sym.SheetName <> Nil Then ThisName := Sym.SheetName.Text;
            Except
            End;
            If ThisName = SymName Then
            Begin
                Inc(Result);
                If First = Nil Then First := Sym;
            End;
            Sym := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
End;

{ The footprint of a PLACED part (scripts 2026.11.23.7, op `footprint`): every }
{ PCBLIB implementation removed, one added and bound by name with an empty     }
{ location, as upstream Lib_LinkFootprint does it on a library component (the  }
{ factory AddSchImplementation; a path as location wedged AD26 there).         }
Function SchEditSetFootprint(Comp : ISch_Component; FootprintName : String) : Boolean;
Var
    ImplIter : ISch_Iterator;
    Impl, Impl2, Found : ISch_Implementation;
    Guard : Integer;
    MT, Blank, LibKind : String;
Begin
    Result := False;
    Blank := '';
    LibKind := 'PCBLib';
    Guard := 50;
    While Guard > 0 Do
    Begin
        Found := Nil;
        ImplIter := Comp.SchIterator_Create;
        Try
            ImplIter.AddFilter_ObjectSet(MkSet(eImplementation));
            Impl2 := ImplIter.FirstSchObject;
            While Impl2 <> Nil Do
            Begin
                MT := '';
                Try MT := Impl2.ModelType; Except End;
                If (MT = cDocKind_PcbLib) And (Found = Nil) Then Found := Impl2;
                Impl2 := ImplIter.NextSchObject;
            End;
        Finally
            Comp.SchIterator_Destroy(ImplIter);
        End;
        If Found = Nil Then Break;
        Try Comp.RemoveSchImplementation(Found); Except End;
        Dec(Guard);
    End;
    Impl := Comp.AddSchImplementation;
    If Impl <> Nil Then
    Begin
        Try Impl.ClearAllDatafileLinks; Except End;
        Impl.ModelName := FootprintName;
        Impl.ModelType := cDocKind_PcbLib;
        Try Impl.IsCurrent := True; Except End;
        Try Impl.AddDataFileLink(FootprintName, Blank, LibKind); Except End;
        Result := (Impl.ModelName = FootprintName);
    End;
End;

{ Parts on a sheet carrying the designator Des (scripts 2026.11.23.6: delpart,  }
{ movepart, rotpart). A multi-part symbol has one part per unit, so more than   }
{ one hit means the op is refused.                                              }
Function SchEditPartByDes(Doc : ISch_Document; Des : String; Var First : ISch_Component) : Integer;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
Begin
    Result := 0;
    First := Nil;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Comp := Obj;
            If Comp.Designator.Text = Des Then
            Begin
                Inc(Result);
                If First = Nil Then First := Comp;
            End;
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
End;

{ A new, empty schematic sheet beside the project file, saved and added to the  }
{ project (upstream Gen_AddSheet: OpenNewDocument names the document up front;  }
{ the WorkspaceManager process without a file name raised a modal dialog).      }
{ Returns 'ok' or why not. THIS WRITES A FILE and changes the project.          }
Function SchEditNewSheet(P : IProject; SheetName : String) : String;
Var
    NewPath : String;
    ServerDoc : IServerDocument;
Begin
    Result := 'exception';
    NewPath := ExtractFilePath(P.DM_ProjectFullPath) + SheetName + '.SchDoc';
    If FileExists(NewPath) Then
    Begin
        Result := 'a file with this name is already there';
        Exit;
    End;
    ServerDoc := Client.OpenNewDocument('SCH', NewPath, SheetName, False);
    If ServerDoc = Nil Then
    Begin
        Result := 'not created';
        Exit;
    End;
    Try ServerDoc.SetFileName(NewPath); Except End;
    Try
        ServerDoc.SetModified(True);
        ServerDoc.DoFileSave('');
    Except
    End;
    If Not FileExists(NewPath) Then
    Begin
        Result := 'not saved';
        Exit;
    End;
    Try
        P.DM_AddSourceDocument(NewPath);
        Result := 'ok';
    Except
        Result := 'not added to the project';
    End;
End;

{ Parts on a sheet whose location is X, Y; DesHits counts the parts that carry  }
{ the designator Des (scripts 2026.11.23.3, op `part`).                         }
Function SchEditPartAt(Doc : ISch_Document; X, Y : Integer; Des : String; Var DesHits : Integer) : Integer;
Var
    Iter : ISch_Iterator;
    Obj : ISch_GraphicalObject;
    Comp : ISch_Component;
    Loc : TLocation;
Begin
    Result := 0;
    DesHits := 0;
    Iter := Doc.SchIterator_Create;
    Try
        Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
        Obj := Iter.FirstSchObject;
        While Obj <> Nil Do
        Begin
            Comp := Obj;
            Loc := Obj.GetState_Location;
            If (Loc.X = X) And (Loc.Y = Y) Then Inc(Result);
            If Comp.Designator.Text = Des Then Inc(DesHits);
            Obj := Iter.NextSchObject;
        End;
    Finally
        Doc.SchIterator_Destroy(Iter);
    End;
End;

Function SchEditPowerStyleOk(S : String) : Boolean;
Begin
    Result := (S = 'circle') Or (S = 'arrow') Or (S = 'bar') Or (S = 'wave')
        Or (S = 'gnd_power') Or (S = 'gnd_signal') Or (S = 'gnd_earth');
End;

Function SelectedEditSchematicChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, BatchHash, ItemsStr, Rest, OpStr, ErrCode, ErrMsg, Binding, Blank : String;
    Op, Kind, S2, S3, Status, Problems, Rows, Back, Body, CDes, CName : String;
    Apply, Ok, Ok2, Ok3, Touched, Partial, Corner : Boolean;
    Paths, IOp, ISheet, IX1, IY1, IX2, IY2, IN_, IS1, IS2, IS3, IStatus, IBack, TouchedPaths : TStringList;
    Docs : TInterfaceList;
    I, J, K, Hits, Hits2, Refused, Written, Pending, SheetIdx, Count, PinCount : Integer;
    X1, Y1, X2, Y2, N : Integer;
    Doc : ISch_Document;
    Obj : ISch_GraphicalObject;
    Loc : TLocation;
    Comp : ISch_Component;
    Avail : String;
    Sym : ISch_SheetSymbol;
    Entry : ISch_SheetEntry;
    WantSide : Integer;
    SchLib : ISch_Lib;
    PcbLib : IPCB_Library;
    LibComp : ISch_Component;
    LibFp : IPCB_LibComponent;
    LibCompName, LibFpName : String;
Begin
    Mode := ExtractJsonValue(Params, 'mode');
    BatchHash := ExtractJsonValue(Params, 'batch_hash');
    ItemsStr := ExtractJsonValue(Params, 'items');
    If (Mode <> 'preview') And (Mode <> 'apply') Then
    Begin
        Result := BuildErrorResponse(RequestId, 'INVALID_MODE', 'mode must be preview or apply');
        Exit;
    End;
    Apply := (Mode = 'apply');
    If Apply And (Not ParamEditGrantActive(0)) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'NO_GRANT',
            'Schematic edits are not granted: the operator ticks "Allow schematic edits" in the bridge window');
        Exit;
    End;
    If Not ParamEditHashValid(BatchHash) Then
    Begin
        Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'batch_hash must be 64 hex characters');
        Exit;
    End;
    Binding := SelectionJSON(0);
    Blank := '';
    Touched := False;
    Partial := False;
    Paths := TStringList.Create;
    IOp := TStringList.Create;
    ISheet := TStringList.Create;
    IX1 := TStringList.Create;
    IY1 := TStringList.Create;
    IX2 := TStringList.Create;
    IY2 := TStringList.Create;
    IN_ := TStringList.Create;
    IS1 := TStringList.Create;
    IS2 := TStringList.Create;
    IS3 := TStringList.Create;
    IStatus := TStringList.Create;
    IBack := TStringList.Create;
    TouchedPaths := TStringList.Create;
    Docs := CreateObject(TInterfaceList);
    SelectedBusy := True;
    Try
        If Not AnnotateSheets(P, Paths, Docs, ErrCode, ErrMsg) Then
        Begin
            Result := BuildErrorResponse(RequestId, ErrCode, ErrMsg);
            Exit;
        End;

        If Not Apply Then
        Begin
            Rows := '';
            For I := 0 To Paths.Count - 1 Do
            Begin
                If I > 0 Then Rows := Rows + ',';
                Doc := Docs[I];
                Back := '';
                { Opt-in: not proven on this Altium version (upstream a98d70e, AD 25.8.1). }
                If ExtractJsonValue(Params, 'templates') = '1' Then
                Begin
                    Try Back := Doc.GetState_TemplateFileName; Except Back := ''; End;
                End;
                Rows := Rows + '{"index":' + IntToStr(I) + ',"path":"' + EscapeJsonString(Paths[I])
                    + '","template":"' + EscapeJsonString(Back)
                    + '","modified":' + BoolToJsonStr(Client.GetDocumentByPath(Paths[I]).Modified) + '}';
            End;
            Body := '';
            Count := 0;
            PinCount := 0;
            SheetIdx := StrToIntDef(ExtractJsonValue(Params, 'sheet'), -1);
            If (SheetIdx >= 0) And (SheetIdx < Docs.Count) Then
            Begin
                Doc := Docs[SheetIdx];
                Body := SchEditKindJSON(Doc, 'label', Count) + SchEditKindJSON(Doc, 'power', Count)
                    + SchEditKindJSON(Doc, 'port', Count) + SchEditKindJSON(Doc, 'wire', Count)
                    + SchEditKindJSON(Doc, 'text', Count) + SchEditKindJSON(Doc, 'note', Count)
                    + SchEditKindJSON(Doc, 'box', Count) + SchEditKindJSON(Doc, 'line', Count);
                If Body <> '' Then Body := Copy(Body, 2, Length(Body));
                Status := SchEditPinsJSON(Doc, PinCount);
                If Status <> '' Then Status := Copy(Status, 2, Length(Status));
                Problems := SchEditParamsJSON(Doc);
                If Problems <> '' Then Problems := Copy(Problems, 2, Length(Problems));
                Body := ',"sheet":' + IntToStr(SheetIdx) + ',"object_count":' + IntToStr(Count)
                    + ',"pin_count":' + IntToStr(PinCount)
                    + ',"objects":[' + Body + '],"pins":[' + Status + '],"parameters":[' + Problems + ']';
            End
            Else If SheetIdx >= Docs.Count Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_SHEET', 'sheet index out of range');
                Exit;
            End;
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"preview","batch_hash":"' + LowerCase(BatchHash)
                + '","sheets":[' + Rows + '],"saved":false,"touched":false' + Body + '}}');
            Exit;
        End;

        { Apply: parse the items. }
        Rest := ItemsStr;
        While Rest <> '' Do
        Begin
            OpStr := ParamEditTake(Rest, ';');
            If (IOp.Count >= 200) Or (ParamEditCountChar(OpStr, '|') <> 9) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH',
                    'Expected op|sheet|x1|y1|x2|y2|n|s1|s2|s3, at most 200 items');
                Exit;
            End;
            IOp.Add(ParamEditTake(OpStr, '|'));
            ISheet.Add(ParamEditTake(OpStr, '|'));
            IX1.Add(ParamEditTake(OpStr, '|'));
            IY1.Add(ParamEditTake(OpStr, '|'));
            IX2.Add(ParamEditTake(OpStr, '|'));
            IY2.Add(ParamEditTake(OpStr, '|'));
            IN_.Add(ParamEditTake(OpStr, '|'));
            Kind := SchEditDecode(ParamEditTake(OpStr, '|'), Ok);
            S2 := SchEditDecode(ParamEditTake(OpStr, '|'), Ok2);
            S3 := SchEditDecode(OpStr, Ok3);
            IS1.Add(Kind); IS2.Add(S2); IS3.Add(S3);
            IStatus.Add(Blank); IBack.Add(Blank);
            J := IOp.Count - 1;
            Op := IOp[J];
            K := StrToIntDef(ISheet[J], -1);
            If (Not Ok) Or (Not Ok2) Or (Not Ok3) Or (K < 0) Or (K >= Docs.Count)
                Or (Not PlaceEditIntOk(IX1[J])) Or (Not PlaceEditIntOk(IY1[J]))
                Or (Not PlaceEditIntOk(IX2[J])) Or (Not PlaceEditIntOk(IY2[J]))
                Or (Not PlaceEditIntOk(IN_[J])) Or (Length(S3) > 2000)
                Or ((Op <> 'add') And (Op <> 'settext') And (Op <> 'move') And (Op <> 'del') And (Op <> 'docparam')
                    And (Op <> 'compparam') And (Op <> 'part') And Not ((Op = 'newsheet') Or (Op = 'delpart') Or (Op = 'movepart') Or (Op = 'rotpart')
                    Or (Op = 'entry') Or (Op = 'footprint') Or (Copy(Op, 1, 3) = 'lib')))
                Or ((Op <> 'docparam') And (Op <> 'compparam') And (Op <> 'part') And Not ((Op = 'newsheet') Or (Op = 'delpart') Or (Op = 'movepart') Or (Op = 'rotpart')
                    Or (Op = 'entry') Or (Op = 'footprint') Or (Copy(Op, 1, 3) = 'lib'))
                    And (SchEditKindId(Kind) < 0))
                Or (((Op = 'newsheet') Or (Op = 'delpart') Or (Op = 'movepart') Or (Op = 'rotpart')
                    Or (Op = 'entry') Or (Op = 'footprint') Or (Copy(Op, 1, 3) = 'lib')) And (Kind = ''))
                Or ((Op = 'add') And (Kind = 'port') And (S3 = ''))
                Or ((Op = 'add') And (Kind = 'sheetsymbol') And ((S2 = '') Or (S3 = '')))
                Or (((Op = 'entry') Or (Op = 'footprint')) And (S3 = ''))
                Or ((Copy(Op, 1, 3) = 'lib') And ((S2 = '') Or ((Op <> 'libsym') And (Op <> 'libpin') And (Op <> 'librect')
                    And (Op <> 'liblink') And (Op <> 'libfp') And (Op <> 'libpad') And (Op <> 'libtrack'))))
                Or ((Op = 'part') And ((Kind = '') Or (S2 = '') Or (S3 = '')
                    Or (StrToIntDef(IN_[J], -1) < 0) Or (StrToIntDef(IN_[J], 9) > 3)))
                Or ((Op = 'compparam') And ((Pos('/', Kind) < 2) Or (Pos('/', Kind) = Length(Kind))
                    Or (Not ParamEditFieldAllowed(Copy(Kind, Pos('/', Kind) + 1, Length(Kind))))))
                Or ((Op = 'docparam') And (Kind = ''))
                Or ((Op = 'settext') And (Not SchEditHasText(Kind)))
                Or ((Op = 'settext') And (S3 = '') And (Kind <> 'note'))
                Or ((Op = 'move') And (Kind <> 'label') And (Kind <> 'power') And (Kind <> 'text'))
                Or ((Op = 'add') And SchEditHasText(Kind) And (S3 = ''))
                Or ((Op = 'add') And (Kind = 'power') And (Not SchEditPowerStyleOk(S2))) Then
            Begin
                Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'Bad item ' + IntToStr(J + 1) + ': ' + Op + ' ' + Kind);
                Exit;
            End;
        End;
        If IOp.Count = 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'BAD_BATCH', 'No items');
            Exit;
        End;

        { Preflight every item; refuse the whole batch on the first problem. }
        Refused := 0;
        Problems := '';
        For J := 0 To IOp.Count - 1 Do
        Begin
            Status := '';
            Op := IOp[J]; Kind := IS1[J]; S2 := IS2[J];
            K := StrToInt(ISheet[J]);
            X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]);
            X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
            Doc := Docs[K];
            If Client.GetDocumentByPath(Paths[K]).Modified Then Status := 'sheet has unsaved edits'
            Else If Op = 'docparam' Then
            Begin
                Obj := SchEditFindParam(Doc, Kind, Hits);
                If Obj = Nil Then Status := 'sheet parameter not found once (' + IntToStr(Hits) + ')'
                Else If SchEditObjText(Obj) <> S2 Then Status := 'value changed since the read'
                Else If SchEditParamReadOnly(Obj) Then Status := 'Altium keeps this parameter read-only';
            End
            Else If Op = 'compparam' Then
            Begin
                CDes := Copy(Kind, 1, Pos('/', Kind) - 1);
                CName := Copy(Kind, Pos('/', Kind) + 1, Length(Kind));
                SchEditCompParam(Doc, CDes, CName, S2, IS3[J], StrToInt(IN_[J]) = 1, False, Status);
            End
            Else If Copy(Op, 1, 3) = 'lib' Then
            Begin
                { s1 the symbol / footprint, s2 the library file. libsym and libfp: the  }
                { library is open, saved and the active document, and the name is free.  }
                { Every other lib item goes on what an earlier item of this batch makes. }
                If (Op = 'libsym') Or (Op = 'libfp') Then
                Begin
                    Try
                        If Client.GetDocumentByPath(S2).Modified Then Status := 'the library has unsaved edits';
                    Except
                        Status := 'the library is not open in Altium';
                    End;
                    If (Status = '') And (Op = 'libsym') Then
                    Begin
                        SchLib := SchEditFocusedSchLib(S2);
                        If SchLib = Nil Then Status := 'make the library the active document in Altium'
                        Else If LookupLibComponent(SchLib, Kind) <> Nil Then
                            Status := 'symbol ' + Kind + ' is already in the library (create-only)';
                    End
                    Else If Status = '' Then
                    Begin
                        PcbLib := SchEditFocusedPcbLib(S2);
                        If PcbLib = Nil Then Status := 'make the library the active document in Altium'
                        Else
                        Begin
                            LibFp := Nil;
                            Try LibFp := PcbLib.GetComponentByName(Kind); Except LibFp := Nil; End;
                            If LibFp <> Nil Then Status := 'footprint ' + Kind + ' is already in the library (create-only)';
                        End;
                    End;
                End
                Else
                Begin
                    Ok := False;
                    For Hits := 0 To J - 1 Do
                        If (IS1[Hits] = Kind) And (IS2[Hits] = S2) Then
                        Begin
                            If (IOp[Hits] = 'libsym') And ((Op = 'libpin') Or (Op = 'librect') Or (Op = 'liblink')) Then Ok := True;
                            If (IOp[Hits] = 'libfp') And ((Op = 'libpad') Or (Op = 'libtrack')) Then Ok := True;
                        End;
                    If Not Ok Then Status := Op + ' goes only on a symbol or footprint created earlier in this batch';
                End;
            End
            Else If Op = 'entry' Then
            Begin
                { A sheet entry on the sheet symbol named s1: s3 its name, s2 its side, }
                { n its IO type, x1 its distance from the symbol's top.                 }
                Hits := SchEditSymbolByName(Doc, Kind, Sym);
                If Hits <> 1 Then
                    Status := 'sheet symbol ' + Kind + ' found ' + IntToStr(Hits) + ' times on this sheet';
            End
            Else If Op = 'footprint' Then
            Begin
                Hits := SchEditPartByDes(Doc, Kind, Comp);
                If Hits = 0 Then Status := 'no part ' + Kind + ' on this sheet'
                Else If Hits > 1 Then Status := Kind + ' has ' + IntToStr(Hits) + ' parts on this sheet (a multi-part symbol)';
            End
            Else If Op = 'newsheet' Then
            Begin
                If FileExists(ExtractFilePath(P.DM_ProjectFullPath) + Kind + '.SchDoc') Then
                    Status := 'a file ' + Kind + '.SchDoc is already beside the project';
            End
            Else If (Op = 'delpart') Or (Op = 'movepart') Or (Op = 'rotpart') Then
            Begin
                { s1 the designator; movepart: x2,y2 the new reference point; rotpart: }
                { n the orientation 0-3. Wires do not follow a moved part.             }
                Hits := SchEditPartByDes(Doc, Kind, Comp);
                If Hits = 0 Then Status := 'no part ' + Kind + ' on this sheet'
                Else If Hits > 1 Then Status := Kind + ' has ' + IntToStr(Hits) + ' parts on this sheet (a multi-part symbol)'
                Else If (Op = 'movepart') And (SchEditPartAt(Doc, X2, Y2, Kind, Hits2) > 0) Then
                    Status := 'a part is already at the target';
            End
            Else If Op = 'part' Then
            Begin
                { A library part placed at x1,y1 (scripts 2026.11.23.3): s1 the library }
                { reference, s2 the .SchLib path, s3 the designator, n the orientation  }
                { 0-3. The reference is looked up off disk first: a load that fails     }
                { inside Altium raises a modal dialog that stops the loop (upstream).   }
                Avail := '';
                Hits := SchEditPartAt(Doc, X1, Y1, IS3[J], Hits2);
                If Not ResolveLibRef(S2, Kind, Avail) Then
                    Status := 'no part "' + Kind + '" in that library (it holds: ' + Avail + ')'
                Else If Hits > 0 Then Status := 'a part is already at this place'
                Else If (Hits2 > 0) And (Pos('?', IS3[J]) = 0) And (X2 = 0) Then
                    Status := 'designator ' + IS3[J] + ' is already on this sheet';
            End
            Else If Op = 'add' Then
            Begin
                Corner := (Kind = 'wire') Or SchEditHasCorner(Kind);
                Obj := SchEditFind(Doc, Kind, X1, Y1, X2, Y2, Corner, Hits);
                If Hits > 0 Then Status := 'the same ' + Kind + ' is already there'
                Else If Corner And (X1 = X2) And (Y1 = Y2) Then Status := 'zero size';
            End
            Else
            Begin
                Corner := (Op = 'del') And ((Kind = 'wire') Or SchEditHasCorner(Kind));
                Obj := SchEditFind(Doc, Kind, X1, Y1, X2, Y2, Corner, Hits);
                If Obj = Nil Then Status := Kind + ' not found once at its place (' + IntToStr(Hits) + ')'
                Else If SchEditHasText(Kind) And (SchEditObjText(Obj) <> S2) Then Status := 'text changed since the read'
                Else If Op = 'move' Then
                Begin
                    Obj := SchEditFind(Doc, Kind, X2, Y2, 0, 0, False, Hits2);
                    If Hits2 > 0 Then Status := 'a ' + Kind + ' is already at the target';
                End;
            End;
            If Status <> '' Then
            Begin
                Inc(Refused);
                If Length(Problems) < 700 Then
                    Problems := Problems + 'item ' + IntToStr(J + 1) + ' (' + Op + ' ' + Kind + '): ' + Status + '; ';
            End;
        End;
        If Refused > 0 Then
        Begin
            Result := BuildErrorResponse(RequestId, 'PREFLIGHT_REFUSED', 'Nothing written. ' + Problems);
            Exit;
        End;

        { New sheets first (scripts 2026.11.23.6): each is a file written and a }
        { document added to the project, outside any sheet's edit transaction.  }
        Written := 0;
        For J := 0 To IOp.Count - 1 Do
            If IOp[J] = 'newsheet' Then
            Begin
                Touched := True;
                Back := 'exception';
                Try Back := SchEditNewSheet(P, IS1[J]); Except Back := 'exception'; End;
                IBack[J] := Back;
                If Back = 'ok' Then
                Begin
                    IStatus[J] := 'written';
                    Inc(Written);
                End
                Else
                Begin
                    IStatus[J] := 'not_ok: ' + Back;
                    Partial := True;
                End;
            End;

        { Library items (scripts 2026.11.23.8), in batch order, outside any sheet's }
        { edit transaction. Create-only: see the helpers.                           }
        LibComp := Nil;
        LibCompName := '';
        LibFp := Nil;
        LibFpName := '';
        For J := 0 To IOp.Count - 1 Do
        Begin
            Op := IOp[J];
            If (Copy(Op, 1, 3) <> 'lib') Or Partial Then Continue;
            Kind := IS1[J]; S2 := IS2[J]; S3 := IS3[J];
            X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]);
            X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
            N := StrToInt(IN_[J]);
            Touched := True;
            Back := 'exception';
            Try
                Back := 'missing';
                If (Op = 'libsym') Or (Op = 'libpin') Or (Op = 'librect') Or (Op = 'liblink') Then
                Begin
                    SchLib := SchEditFocusedSchLib(S2);
                    If SchLib = Nil Then Back := 'the library is not the active document'
                    Else If Op = 'libsym' Then
                    Begin
                        LibComp := SchEditLibNewSymbol(SchLib, Kind, SchEditSplit(S3, 0), SchEditSplit(S3, 1));
                        LibCompName := Kind;
                        If LibComp <> Nil Then Back := 'ok' Else Back := 'the symbol does not resolve in the library';
                    End
                    Else If (LibComp = Nil) Or (LibCompName <> Kind) Then Back := 'the symbol was not created in this batch'
                    Else If Op = 'libpin' Then
                    Begin
                        Hits := SchEditLibCount(LibComp, ePin);
                        If SchEditLibPin(SchLib, LibComp, SchEditSplit(S3, 0), SchEditSplit(S3, 1), SchEditSplit(S3, 2),
                            SchEditSplit(S3, 3), X1, Y1, X2, N) Then
                        Begin
                            If SchEditLibCount(LibComp, ePin) = Hits + 1 Then Back := 'ok'
                            Else Back := 'the pin is not counted on the symbol';
                        End
                        Else Back := 'the pin was not created at its position or with its visibility';
                    End
                    Else If Op = 'librect' Then
                    Begin
                        Hits := SchEditLibCount(LibComp, eRectangle);
                        { text "fill/border" as colour integers; empty = not filled }
                        If SchEditLibRect(SchLib, LibComp, X1, Y1, X2, Y2,
                            StrToIntDef(SchEditSplit(S3, 0), -1), StrToIntDef(SchEditSplit(S3, 1), -1)) Then
                        Begin
                            If SchEditLibCount(LibComp, eRectangle) = Hits + 1 Then Back := 'ok'
                            Else Back := 'the rectangle is not counted on the symbol';
                        End
                        Else Back := 'the rectangle was not created with its fill';
                    End
                    Else
                    Begin
                        SchServer.ProcessControl.PreProcess(SchLib, '');
                        Try
                            If SchEditSetFootprint(LibComp, S3) Then Back := 'ok' Else Back := 'text differs';
                        Finally
                            SchServer.ProcessControl.PostProcess(SchLib, 'Link footprint');
                        End;
                        MarkLibDirty(SchLib);
                    End;
                End
                Else
                Begin
                    PcbLib := SchEditFocusedPcbLib(S2);
                    If PcbLib = Nil Then Back := 'the library is not the active document'
                    Else If Op = 'libfp' Then
                    Begin
                        LibFp := SchEditLibNewFootprint(PcbLib, Kind, S3);
                        LibFpName := Kind;
                        If LibFp <> Nil Then Back := 'ok';
                    End
                    Else If (LibFp = Nil) Or (LibFpName <> Kind) Then Back := 'the footprint was not created in this batch'
                    Else If Op = 'libpad' Then
                    Begin
                        Hits := SchEditLibFpCount(LibFp, ePadObject);
                        If SchEditLibPad(PcbLib, LibFp, SchEditSplit(S3, 0), SchEditSplit(S3, 1), X1, Y1, X2, Y2, N) Then
                        Begin
                            If SchEditLibFpCount(LibFp, ePadObject) > Hits Then Back := 'ok'
                            Else Back := 'the pad is not counted on the footprint';
                        End;
                    End
                    Else
                    Begin
                        Hits := SchEditLibFpCount(LibFp, eTrackObject);
                        If Not SchEditLibTrack(PcbLib, LibFp, SchEditSplit(S3, 0), X1, Y1, X2, Y2, N) Then
                            Back := 'layer not in the library'
                        Else If SchEditLibFpCount(LibFp, eTrackObject) > Hits Then Back := 'ok'
                        Else Back := 'the track is not counted on the footprint';
                    End;
                End;
            Except
                Back := 'exception';
            End;
            IBack[J] := Back;
            If Back = 'ok' Then
            Begin
                IStatus[J] := 'written';
                Inc(Written);
            End
            Else
            Begin
                IStatus[J] := 'not_ok: ' + Back;
                Partial := True;
            End;
        End;

        { Write per sheet, one PreProcess / PostProcess pair per touched sheet. }
        For K := 0 To Docs.Count - 1 Do
        Begin
            Pending := 0;
            For J := 0 To IOp.Count - 1 Do
                If (StrToInt(ISheet[J]) = K) And (IOp[J] <> 'newsheet') And (Copy(IOp[J], 1, 3) <> 'lib') Then Inc(Pending);
            If (Pending = 0) Or Partial Then Continue;
            Doc := Docs[K];
            SchServer.ProcessControl.PreProcess(Doc, '');
            Try
                For J := 0 To IOp.Count - 1 Do
                Begin
                    If (StrToInt(ISheet[J]) <> K) Or Partial Or (IOp[J] = 'newsheet') Or (Copy(IOp[J], 1, 3) = 'lib') Then Continue;
                    Op := IOp[J]; Kind := IS1[J]; S2 := IS2[J]; S3 := IS3[J];
                    X1 := StrToInt(IX1[J]); Y1 := StrToInt(IY1[J]);
                    X2 := StrToInt(IX2[J]); Y2 := StrToInt(IY2[J]);
                    N := StrToInt(IN_[J]);
                    Back := '';
                    Try
                        If Op = 'add' Then
                        Begin
                            Touched := True;
                            Obj := SchEditCreate(Doc, Kind, X1, Y1, X2, Y2, N, S2, S3);
                            Corner := (Kind = 'wire') Or SchEditHasCorner(Kind);
                            Obj := SchEditFind(Doc, Kind, X1, Y1, X2, Y2, Corner, Hits);
                            If Obj = Nil Then Back := 'missing'
                            Else If SchEditHasText(Kind) And (SchEditObjText(Obj) <> S3) Then Back := 'text differs'
                            Else Back := 'ok';
                        End
                        Else If Op = 'entry' Then
                        Begin
                            Hits := SchEditSymbolByName(Doc, Kind, Sym);
                            Entry := Nil;
                            If Sym <> Nil Then Entry := SchServer.SchObjectFactory(eSheetEntry, eCreate_Default);
                            If Entry = Nil Then Back := 'missing'
                            Else
                            Begin
                                Touched := True;
                                Entry.Name := S3;
                                Entry.DistanceFromTop := X1;
                                If N = 1 Then Entry.IOType := ePortOutput
                                Else If N = 2 Then Entry.IOType := ePortInput
                                Else If N = 3 Then Entry.IOType := ePortBidirectional
                                Else Entry.IOType := ePortUnspecified;
                                If S2 = 'right' Then WantSide := eRightSide
                                Else If S2 = 'top' Then WantSide := eTopSide
                                Else If S2 = 'bottom' Then WantSide := eBottomSide
                                Else WantSide := eLeftSide;
                                Entry.Side := WantSide;
                                { Upstream measured that AddAndPositionSchObject discards side }
                                { and distance: both are set again after it, then read back.   }
                                Sym.AddAndPositionSchObject(Entry);
                                Try Entry.Side := WantSide; Except End;
                                Try Entry.DistanceFromTop := X1; Except End;
                                SchRegisterObject(Sym, Entry);
                                If (Entry.Side = WantSide) And (Entry.DistanceFromTop = X1) Then Back := 'ok'
                                Else Back := 'placed, not where asked';
                            End;
                        End
                        Else If Op = 'footprint' Then
                        Begin
                            Hits := SchEditPartByDes(Doc, Kind, Comp);
                            If Comp = Nil Then Back := 'missing'
                            Else
                            Begin
                                Touched := True;
                                If SchEditSetFootprint(Comp, S3) Then Back := 'ok' Else Back := 'text differs';
                            End;
                        End
                        Else If Op = 'delpart' Then
                        Begin
                            Hits := SchEditPartByDes(Doc, Kind, Comp);
                            If Comp = Nil Then Back := 'missing'
                            Else
                            Begin
                                Touched := True;
                                Doc.RemoveSchObject(Comp);
                                SchRegisterObject(Doc, Comp);
                                Hits := SchEditPartByDes(Doc, Kind, Comp);
                                If Hits = 0 Then Back := 'ok' Else Back := 'still there';
                            End;
                        End
                        Else If Op = 'movepart' Then
                        Begin
                            Hits := SchEditPartByDes(Doc, Kind, Comp);
                            If Comp = Nil Then Back := 'missing'
                            Else
                            Begin
                                Touched := True;
                                SchBeginModify(Comp);
                                Comp.MoveToXY(X2, Y2);
                                SchEndModify(Comp);
                                Hits := SchEditPartAt(Doc, X2, Y2, Kind, Hits2);
                                If (Hits = 1) And (Hits2 = 1) Then Back := 'ok' Else Back := 'not at target';
                            End;
                        End
                        Else If Op = 'rotpart' Then
                        Begin
                            Hits := SchEditPartByDes(Doc, Kind, Comp);
                            If Comp = Nil Then Back := 'missing'
                            Else
                            Begin
                                Touched := True;
                                SchBeginModify(Comp);
                                Comp.SetState_Orientation(N);
                                SchEndModify(Comp);
                                Back := 'ok';
                            End;
                        End
                        Else If Op = 'part' Then
                        Begin
                            { Upstream's placement (Gen_PlaceSchComponentFromLibrary): load }
                            { (reference, path), add to the sheet, MoveToXY, orientation,   }
                            { designator, register.                                         }
                            Touched := True;
                            Comp := Nil;
                            Try Comp := SchServer.LoadComponentFromLibrary(Kind, S2); Except Comp := Nil; End;
                            If Comp = Nil Then Back := 'missing'
                            Else
                            Begin
                                Doc.AddSchObject(Comp);
                                Comp.MoveToXY(X1, Y1);
                                Comp.SetState_Orientation(N);
                                Comp.Designator.Text := S3;
                                { x2 > 0: the unit of a multi-part symbol (upstream sets it this way). }
                                If X2 > 0 Then
                                Begin
                                    Try Comp.CurrentPartID := X2; Except End;
                                End;
                                SchRegisterObject(Doc, Comp);
                                Hits := SchEditPartAt(Doc, X1, Y1, S3, Hits2);
                                If (Hits = 1) And (Hits2 >= 1) Then Back := 'ok' Else Back := 'missing';
                            End;
                        End
                        Else If Op = 'compparam' Then
                        Begin
                            CDes := Copy(Kind, 1, Pos('/', Kind) - 1);
                            CName := Copy(Kind, Pos('/', Kind) + 1, Length(Kind));
                            SchEditCompParam(Doc, CDes, CName, S2, S3, N = 1, False, Status);
                            If Status <> '' Then Back := 'changed during apply'
                            Else
                            Begin
                                Touched := True;
                                SchEditCompParam(Doc, CDes, CName, S2, S3, N = 1, True, Status);
                                If Status <> '' Then Back := 'text differs'
                                Else
                                Begin
                                    { read back: there once, with the new value, on every part }
                                    SchEditCompParam(Doc, CDes, CName, S3, S3, False, False, Status);
                                    If Status = '' Then Back := 'ok' Else Back := 'text differs';
                                End;
                            End;
                        End
                        Else If Op = 'docparam' Then
                        Begin
                            Obj := SchEditFindParam(Doc, Kind, Hits);
                            If (Obj = Nil) Or (SchEditObjText(Obj) <> S2) Then Back := 'changed during apply'
                            Else
                            Begin
                                Touched := True;
                                SchBeginModify(Obj);
                                Obj.Text := S3;
                                SchEndModify(Obj);
                                If SchEditObjText(Obj) = S3 Then Back := 'ok' Else Back := 'text differs';
                            End;
                        End
                        Else
                        Begin
                            Corner := (Op = 'del') And ((Kind = 'wire') Or SchEditHasCorner(Kind));
                            Obj := SchEditFind(Doc, Kind, X1, Y1, X2, Y2, Corner, Hits);
                            If (Obj = Nil) Or (SchEditHasText(Kind) And (SchEditObjText(Obj) <> S2)) Then
                                Back := 'changed during apply'
                            Else If Op = 'settext' Then
                            Begin
                                Touched := True;
                                SchBeginModify(Obj);
                                Obj.Text := S3;
                                SchEndModify(Obj);
                                If SchEditObjText(Obj) = S3 Then Back := 'ok' Else Back := 'text differs';
                            End
                            Else If Op = 'move' Then
                            Begin
                                Touched := True;
                                SchBeginModify(Obj);
                                Loc := Obj.Location;
                                Loc.X := X2;
                                Loc.Y := Y2;
                                Obj.Location := Loc;
                                SchEndModify(Obj);
                                Obj := SchEditFind(Doc, Kind, X2, Y2, 0, 0, False, Hits);
                                If (Obj <> Nil) And (SchEditObjText(Obj) = S2) Then Back := 'ok' Else Back := 'not at target';
                            End
                            Else
                            Begin
                                Touched := True;
                                Doc.RemoveSchObject(Obj);
                                { Announced, as upstream 160650b: without it the compiled }
                                { model kept a deleted object until the sheet reopened.   }
                                SchRegisterObject(Doc, Obj);
                                Obj := SchEditFind(Doc, Kind, X1, Y1, X2, Y2, Corner, Hits);
                                If Hits = 0 Then Back := 'ok' Else Back := 'still there';
                            End;
                        End;
                    Except
                        Back := 'exception';
                    End;
                    IBack[J] := Back;
                    If Touched And (TouchedPaths.IndexOf(Paths[K]) < 0) Then TouchedPaths.Add(Paths[K]);
                    If Back = 'ok' Then
                    Begin
                        IStatus[J] := 'written';
                        Inc(Written);
                    End
                    Else
                    Begin
                        IStatus[J] := 'not_ok: ' + Back;
                        Partial := True;
                    End;
                End;
            Finally
                Try SchServer.ProcessControl.PostProcess(Doc, 'Edit'); Except End;
                Try Doc.GraphicallyInvalidate; Except End;
            End;
        End;
        For I := 0 To TouchedPaths.Count - 1 Do MarkDocDirtyByPath(TouchedPaths[I]);
        For J := 0 To IOp.Count - 1 Do
            If IStatus[J] = '' Then IStatus[J] := 'not_written';

        Rows := '';
        For J := 0 To IOp.Count - 1 Do
        Begin
            If J > 0 Then Rows := Rows + ',';
            Rows := Rows + '{"op":"' + EscapeJsonString(IOp[J]) + '","sheet":' + ISheet[J]
                + ',"kind":"' + EscapeJsonString(IS1[J]) + '","status":"' + EscapeJsonString(IStatus[J]) + '"}';
        End;
        If (CurrentSelectedProject(0) <> P) Or (SelectionJSON(0) <> Binding) Then
            Result := BuildErrorResponse(RequestId, 'CHANGED_DURING_WRITE',
                'Selection or grant changed during the call; read again (written: ' + IntToStr(Written) + ')')
        Else
            Result := BuildSuccessResponse(RequestId, '{"selection":' + Binding
                + ',"result":{"mode":"apply","batch_hash":"' + LowerCase(BatchHash)
                + '","item_count":' + IntToStr(IOp.Count)
                + ',"written":' + IntToStr(Written)
                + ',"partial":' + BoolToJsonStr(Partial)
                + ',"touched":' + BoolToJsonStr(Touched)
                + ',"grant_cleared":' + BoolToJsonStr(Touched)
                + ',"saved":false,"items":[' + Rows + ']}}');
    Finally
        If Touched Then
        Begin
            ParamEditGrant := False;
            Inc(SelectedGeneration);
        End;
        SelectedBusy := False;
        Paths.Free; IOp.Free; ISheet.Free; IX1.Free; IY1.Free; IX2.Free; IY2.Free; IN_.Free;
        IS1.Free; IS2.Free; IS3.Free; IStatus.Free; IBack.Free; TouchedPaths.Free;
    End;
End;

{ UnitStamp_SelectedProject - which build of this file Altium compiled. 'dev' in the      }
{ repository; the runtime generator writes a hash of the file in its place, }
{ and the selected-mode ping reports every unit's stamp, so a unit that     }
{ Altium did not recompile is named instead of passing as current.          }
Function UnitStamp_SelectedProject(Dummy : Integer) : String;
Begin
    Result := 'dev';
End;

{ Every stamped unit's stamp as a JSON object. StatusForm.pas and Dispatcher.pas }
{ come after this file in the project and are not asked.                        }
Function SelectedUnitStampsJson(Dummy : Integer) : String;
Begin
    Result := '{"Main":"' + UnitStamp_Main(0)
        + '","Utils":"' + UnitStamp_Utils(0)
        + '","Application":"' + UnitStamp_Application(0)
        + '","Project":"' + UnitStamp_Project(0)
        + '","Library":"' + UnitStamp_Library(0)
        + '","PCBGeneric":"' + UnitStamp_PCBGeneric(0)
        + '","PCB":"' + UnitStamp_PCB(0)
        + '","Generic":"' + UnitStamp_Generic(0)
        + '","Audit":"' + UnitStamp_Audit(0)
        + '","SelectedProject":"' + UnitStamp_SelectedProject(0) + '"}';
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
        { A param-edit runtime names itself differently, so neither client can  }
        { be pointed at the other kind of runtime by mistake. }
        If SELECTED_PLACE_EDITS Then
            Result := BuildSuccessResponse(RequestId, '{"pong":true,"script_version":"'
                + SCRIPT_VERSION + '","plt_profile":"eda-selected-edits-v1"'
                + ',"selection_api":1,"unit_stamps":' + SelectedUnitStampsJson(0)
                + ',"grant_age_s":' + SelectedGrantAgesJson(0)
                + ',"selection":' + SelectionJSON(0) + '}')
        Else If SELECTED_PARAM_EDITS Then
            Result := BuildSuccessResponse(RequestId, '{"pong":true,"script_version":"'
                + SCRIPT_VERSION + '","plt_profile":"eda-selected-paramedit-v1"'
                + ',"selection_api":1,"unit_stamps":' + SelectedUnitStampsJson(0)
                + ',"grant_age_s":' + SelectedGrantAgesJson(0)
                + ',"selection":' + SelectionJSON(0) + '}')
        Else
            Result := BuildSuccessResponse(RequestId, '{"pong":true,"script_version":"'
                + SCRIPT_VERSION + '","plt_profile":"eda-selected-readonly-v1"'
                + ',"selection_api":1,"unit_stamps":' + SelectedUnitStampsJson(0)
                + ',"grant_age_s":' + SelectedGrantAgesJson(0)
                + ',"selection":' + SelectionJSON(0) + '}');
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
       (Command <> 'project.get_messages') And
       (Not IsSelectedPcbReadCommand(Command)) And
       (Not (SELECTED_PARAM_EDITS And (Command = 'project.set_component_params_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.move_components_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.place_copper_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.setup_board_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.run_drc_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.repour_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'project.run_outjob_checked'))) And
       (Not (SELECTED_PARAM_EDITS And (Command = 'project.annotate_checked'))) And
       (Not (SELECTED_PARAM_EDITS And (Command = 'project.edit_schematic_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.place_graphics_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.edit_free_checked'))) Then
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
    If Command = 'project.set_component_params_checked' Then
    Begin
        Result := SelectedSetParamsChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.move_components_checked' Then
    Begin
        Result := SelectedMoveComponentsChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.place_copper_checked' Then
    Begin
        Result := SelectedPlaceCopperChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.setup_board_checked' Then
    Begin
        Result := SelectedSetupBoardChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.run_drc_checked' Then
    Begin
        Result := SelectedRunDrcChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.repour_checked' Then
    Begin
        Result := SelectedRepourChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'project.run_outjob_checked' Then
    Begin
        Result := SelectedRunOutJobChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'project.annotate_checked' Then
    Begin
        Result := SelectedAnnotateChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'project.edit_schematic_checked' Then
    Begin
        Result := SelectedEditSchematicChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.place_graphics_checked' Then
    Begin
        Result := SelectedPlaceGraphicsChecked(P, Params, RequestId);
        Exit;
    End;
    If Command = 'pcb.edit_free_checked' Then
    Begin
        Result := SelectedEditFreeChecked(P, Params, RequestId);
        Exit;
    End;
    Binding := SelectionJSON(0);
    SafeParams := '{"project_path":"' + EscapeJsonString(SelectedPath) + '"';
    SelectedBusy := True;
    Try
        Compiled := (Command = 'project.get_bom') Or (Command = 'project.get_nets')
            Or (Command = 'project.get_messages');
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
            Else If Command = 'pcb.get_vias' Then
                Reply := PCB_GetViasForBoard(Board, RequestId)
            Else If Command = 'pcb.get_texts' Then
                Reply := PCB_GetTextsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_free_graphics' Then
                Reply := PCB_GetFreeGraphicsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_tracks' Then
                { Rebuilt params: only the whitelisted filter and page fields
                  cross into the handler, never the caller's object. }
                Reply := PCB_GetTracksForBoard(Board,
                    '{"net":"' + EscapeJsonString(ExtractJsonValue(Params, 'net'))
                    + '","layer":"' + EscapeJsonString(ExtractJsonValue(Params, 'layer'))
                    + '","offset":"' + EscapeJsonString(ExtractJsonValue(Params, 'offset'))
                    + '","limit":"' + EscapeJsonString(ExtractJsonValue(Params, 'limit')) + '"}',
                    RequestId)
            Else If Command = 'pcb.get_polygons' Then
                Reply := PCB_GetPolygonsForBoard(Board, StrToIntDef(ExtractJsonValue(Params, 'copper_index'), -1), RequestId)
            Else If Command = 'pcb.get_unrouted_nets' Then
                Reply := PCB_GetUnroutedNetsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_layer_primitive_counts' Then
                Reply := PCB_GetLayerPrimitiveCountsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_net_classes' Then
                Reply := PCB_GetNetClassesForBoard(Board, RequestId)
            Else If Command = 'pcb.get_object_classes' Then
                Reply := PCB_GetObjectClassesForBoard(Board, RequestId)
            Else If Command = 'pcb.get_room_rules' Then
                Reply := PCB_GetRoomRulesForBoard(Board, RequestId)
            Else If Command = 'pcb.get_clearance_violations' Then
                { Rebuild the params object rather than forwarding the caller's,
                  same as trace-lengths below: only the whitelisted net filter
                  crosses into the handler. }
                Reply := PCB_GetClearanceViolationsForBoard(Board,
                    '{"net":"' + EscapeJsonString(ExtractJsonValue(Params, 'net'))
                    + '","offset":"' + EscapeJsonString(ExtractJsonValue(Params, 'offset'))
                    + '","limit":"' + EscapeJsonString(ExtractJsonValue(Params, 'limit')) + '"}',
                    RequestId)
            Else If Command = 'pcb.get_design_rules' Then
                Reply := PCB_GetDesignRulesForBoard(Board, RequestId)
            Else If Command = 'pcb.get_board_statistics' Then
                Reply := PCB_GetBoardStatisticsForBoard(Board, RequestId)
            Else If Command = 'pcb.get_trace_lengths' Then
                Reply := PCB_GetTraceLengthsForBoard(Board,
                    '{"net":"' + EscapeJsonString(ExtractJsonValue(Params, 'net')) + '"}',
                    RequestId)
            Else If Command = 'pcb.get_selected_objects' Then
                { Forced default property set; caller-supplied lists are not forwarded. }
                Reply := PCB_GetSelectedObjectsForBoard(Board, '{}', RequestId)
            Else If Command = 'pcb.get_component_pads' Then
                Reply := PCB_GetComponentPadsForBoard(Board,
                    '{"designator":"' + EscapeJsonString(ExtractJsonValue(Params, 'designator')) + '"}',
                    RequestId)
            Else If Command = 'pcb.audit_signal_vias_without_return' Then
                Reply := Audit_FindSignalViasWithoutReturnForBoard(Board,
                    '{"radius_mils":"' + EscapeJsonString(ExtractJsonValue(Params, 'radius_mils')) + '"}',
                    RequestId)
            Else If Command = 'pcb.audit_via_antennas' Then
                Reply := Audit_FindViaAntennasForBoard(Board, '{}', RequestId)
            Else If Command = 'pcb.audit_components_outside_outline' Then
                Reply := Audit_FindComponentsOutsideBoardOutlineForBoard(Board, '{}', RequestId)
            Else If Command = 'pcb.audit_pads_near_edge' Then
                Reply := Audit_FindPadsNearBoardEdgeForBoard(Board,
                    '{"clearance_mils":"' + EscapeJsonString(ExtractJsonValue(Params, 'clearance_mils')) + '"}',
                    RequestId)
            Else If Command = 'pcb.audit_mixed_designator_rotation' Then
                Reply := Audit_FindMixedDesignatorRotationForBoard(Board, '{}', RequestId)
            Else If Command = 'pcb.audit_mirrored_text' Then
                Reply := Audit_FindMirroredPcbTextForBoard(Board, '{}', RequestId)
            Else
                { DANGER: this is a bare fallback, not a branch for a named    }
                { command. Any command that passes IsSelectedPcbReadCommand    }
                { without an explicit branch above lands HERE and silently      }
                { returns DIFF-PAIR RULES under the caller's requested name -   }
                { a wrong answer, not an error. When adding a read, add BOTH    }
                { the allowlist entry and an explicit branch; the allowlist     }
                { alone is worse than neither. Worth replacing with an explicit }
                { pcb.get_diff_pair_rules test plus an unknown-command error,   }
                { but not mid-deploy-window.                                    }
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
            Else If Command = 'project.get_messages' Then Reply := Proj_GetMessages(SafeParams, RequestId)
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
