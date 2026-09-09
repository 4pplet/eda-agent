object ShutdownProbeForm: TShutdownProbeForm
  Left = 240
  Top = 180
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Shutdown probe v1 - no CAD / no MCP'
  ClientHeight = 175
  ClientWidth = 490
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  FormStyle = fsStayOnTop
  Position = poScreenCenter
  OnCloseQuery = ProbeFormCloseQuery
  OnClose = ProbeFormClose
  OnDestroy = ProbeFormDestroy
  object lbl_Description: TLabel
    Left = 16
    Top = 16
    Width = 455
    Height = 72
    AutoSize = False
    WordWrap = True
    Caption = 'Diagnostic only. Keep all CAD and bridge projects closed. First test: press Stop probe. A later test will use normal Altium Quit. The loop stops after roughly three minutes.'
  end
  object btn_Stop: TButton
    Left = 16
    Top = 110
    Width = 150
    Height = 30
    Caption = 'Stop probe'
    OnClick = ProbeStopClick
  end
  object lbl_Log: TLabel
    Left = 184
    Top = 112
    Width = 286
    Height = 45
    AutoSize = False
    WordWrap = True
    Caption = 'Completion is confirmed by run_end in the log, not by this window disappearing.'
  end
end
