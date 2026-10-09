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
    Inc(SelectedGeneration);
    ParamEditGrantGeneration := SelectedGeneration;
    Result := True;
End;

Function PlaceEditGrantActive(Dummy : Integer) : Boolean;
Begin
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
    Inc(SelectedGeneration);
    PlaceEditGrantGeneration := SelectedGeneration;
    Result := True;
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
        Or (Command = 'pcb.get_diff_pair_rules')
        Or (Command = 'pcb.get_vias')
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
{ fails the batch: nothing is guessed at, and micro / Ohm signs are refused    }
{ until a Unicode round trip is qualified.                                     }
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
            If (Code < 32) Or (Code > 126) Then
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
Function SelectedMoveComponentsChecked(P : IProject; Params, RequestId : String) : String;
Var
    Mode, MovesStr, BatchHash, Rest, OpStr, D, Status, Problems, MovesJson, Binding, Blank : String;
    PcbPath, ErrCode, ErrMsg, LayerStr : String;
    OpDes, OpX, OpY, OpR, OpOX, OpOY, OpOR, OpOL, OpCX, OpCY, OpCR, OpCL, OpStatus, OpBX, OpBY, OpBR : TStringList;
    J, Count, WouldMove, Unchanged, Refused, Moved, NotMoved, NewX, NewY, NewR : Integer;
    Apply, PcbModified, Partial, Touched, Ok : Boolean;
    Board : IPCB_Board;
    Comp : IPCB_Component;
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
                Else If LayerStr <> 'TopLayer' Then Status := 'refused: the part is not on the top layer (no side changes)'
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
            Ok := PlaceEditNameOk(F0) And PlaceEditIntOk(F1) And PlaceEditIntOk(F2)
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
            Ok := PlaceEditNameOk(F0) And CopperLayerNameOk(F1) And PlaceEditIntOk(F2) And PlaceEditIntOk(F3)
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
                    VStatus[J] := 'refused: ' + What + ' within clearance (' + IntToStr(Round(Gap)) + ' of ' + IntToStr(C) + ')'
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
                        TStatus[J] := 'refused: ' + What + ' within clearance (' + IntToStr(Round(Gap)) + ' of ' + IntToStr(C) + ')'
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
                        Via.Size := StrToInt(VS[J]);
                        Via.HoleSize := StrToInt(VH[J]);
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
            If SetupField(Fields, 'pwmin') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwmin', Ok);
                Try RD.MinWidth(L) := N; Except Result := 'pwmin not accepted'; End;
            End;
            If SetupField(Fields, 'pwmax') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwmax', Ok);
                Try RD.MaxWidth(L) := N; Except Result := 'pwmax not accepted'; End;
            End;
            If SetupField(Fields, 'pwpref') <> '' Then
            Begin
                N := SetupFieldInt(Fields, 'pwpref', Ok);
                Try RD.PreferedWidth(L) := N; Except Result := 'pwpref not accepted'; End;
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
        RL := R;
        Allowed := ',' + SetupField(Fields, 'layers') + ',';
        For L := MinLayer To MaxLayer Do
        Begin
            If SetupIsCopperLayer(L) Then
            Begin
                Lyr := GetLayerString(L);
                Try RL.LayerAllowed(L) := (Pos(',' + Lyr + ',', Allowed) > 0); Except Result := 'layers not accepted'; End;
            End;
        End;
    End
    Else If Kind = 'polygon' Then
    Begin
        RP := R;
        V := SetupField(Fields, 'style');
        If V = 'direct' Then
        Begin
            Try RP.ConnectStyle := eDirectConnect; Except Result := 'style not accepted'; End;
        End
        Else If V = 'relief' Then
        Begin
            Try RP.ConnectStyle := eReliefConnect; Except Result := 'style not accepted'; End;
        End;
        If SetupField(Fields, 'relief_w') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'relief_w', Ok);
            Try RP.ReliefConductorWidth := N; Except Result := 'relief_w not accepted'; End;
        End;
        If SetupField(Fields, 'relief_entries') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'relief_entries', Ok);
            Try RP.ReliefEntries := N; Except Result := 'relief_entries not accepted'; End;
        End;
        If SetupField(Fields, 'relief_gap') <> '' Then
        Begin
            N := SetupFieldInt(Fields, 'relief_gap', Ok);
            Try RP.ReliefAirGap := N; Except Result := 'relief_gap not accepted'; End;
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
    Else If Kind = 'polygon' Then Result := eRule_PolygonConnectStyle;
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
                + ',"selection_api":1,"selection":' + SelectionJSON(0) + '}')
        Else If SELECTED_PARAM_EDITS Then
            Result := BuildSuccessResponse(RequestId, '{"pong":true,"script_version":"'
                + SCRIPT_VERSION + '","plt_profile":"eda-selected-paramedit-v1"'
                + ',"selection_api":1,"selection":' + SelectionJSON(0) + '}')
        Else
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
       (Command <> 'project.get_messages') And
       (Not IsSelectedPcbReadCommand(Command)) And
       (Not (SELECTED_PARAM_EDITS And (Command = 'project.set_component_params_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.move_components_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.place_copper_checked'))) And
       (Not (SELECTED_PLACE_EDITS And (Command = 'pcb.setup_board_checked'))) Then
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
                Reply := PCB_GetPolygonsForBoard(Board, RequestId)
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
