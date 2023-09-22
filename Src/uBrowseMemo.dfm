object frmBrowseMemo: TfrmBrowseMemo
  Left = 78
  Top = 353
  Width = 434
  Height = 292
  VertScrollBar.Range = 30
  ActiveControl = Button1
  AutoScroll = False
  Caption = 'Memo Field'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = 11
  Font.Name = 'MS Sans Serif'
  Font.Pitch = fpVariable
  Font.Style = []
  Menu = MainMenu1
  OldCreateOrder = True
  Position = poDefaultPosOnly
  PixelsPerInch = 96
  TextHeight = 13
  object Panel1: TPanel
    Left = 0
    Top = 204
    Width = 418
    Height = 30
    Align = alBottom
    BevelInner = bvLowered
    TabOrder = 0
    OnResize = Panel1Resize
    DesignSize = (
      418
      30)
    object Button1: TButton
      Left = 243
      Top = 6
      Width = 54
      Height = 18
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      TabOrder = 0
      OnClick = Button1Click
    end
    object cbWordWrap: TCheckBox
      Left = 6
      Top = 9
      Width = 70
      Height = 12
      Caption = 'Word Wrap'
      TabOrder = 1
      OnClick = cbWordWrapClick
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 0
    Width = 418
    Height = 204
    Align = alClient
    TabOrder = 1
    object PageControl1: TPageControl
      Left = 1
      Top = 1
      Width = 416
      Height = 202
      ActivePage = Tabsheet_AsText
      Align = alClient
      TabOrder = 0
      object Tabsheet_AsText: TTabSheet
        Caption = 'Text'
        TabVisible = False
        object MemoText: TDBMemo
          Left = 0
          Top = 0
          Width = 408
          Height = 192
          Align = alClient
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Courier New'
          Font.Pitch = fpVariable
          Font.Style = []
          ParentFont = False
          ScrollBars = ssBoth
          TabOrder = 0
          WordWrap = False
        end
      end
      object Tabsheet_AsObject: TTabSheet
        Caption = 'Object'
        ImageIndex = 1
        TabVisible = False
        object MemoObject: TMemo
          Left = 0
          Top = 0
          Width = 306
          Height = 140
          Align = alClient
          ReadOnly = True
          ScrollBars = ssVertical
          TabOrder = 0
          WordWrap = False
        end
      end
    end
  end
  object MainMenu1: TMainMenu
    Left = 93
    Top = 41
    object File1: TMenuItem
      Caption = '&File'
      object Print1: TMenuItem
        Caption = '&Print'
        OnClick = Print1Click
      end
      object PrintSetup1: TMenuItem
        Caption = 'Print &Setup'
        OnClick = PrintSetup1Click
      end
      object Exit1: TMenuItem
        Caption = 'E&xit'
        OnClick = Exit1Click
      end
    end
    object Edit1: TMenuItem
      Caption = '&Edit'
      OnClick = Edit1Click
      object Find1: TMenuItem
        Caption = 'Find'
        ShortCut = 16454
        OnClick = Find1Click
      end
      object FindAgain1: TMenuItem
        Caption = 'Find Again'
        ShortCut = 114
        OnClick = FindAgain1Click
      end
    end
  end
  object FindDialog1: TFindDialog
    Options = [frDown, frHideWholeWord, frHideUpDown]
    Left = 256
    Top = 8
  end
end
