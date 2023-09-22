object Form_Browser: TForm_Browser
  Left = 681
  Top = 188
  Width = 600
  Height = 403
  VertScrollBar.Range = 36
  ActiveControl = DBGrid1
  AutoScroll = False
  Caption = 'TDBF Browser'
  Color = clBtnFace
  Constraints.MinHeight = 163
  Constraints.MinWidth = 316
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = 15
  Font.Name = 'lucida'
  Font.Pitch = fpVariable
  Font.Style = []
  Menu = MainMenu1
  OldCreateOrder = True
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 584
    Height = 309
    Align = alClient
    TabOrder = 0
    object Panel4: TPanel
      Left = 1
      Top = 1
      Width = 582
      Height = 28
      Align = alTop
      BevelInner = bvLowered
      TabOrder = 0
      DesignSize = (
        582
        28)
      object lblRecordNumber: TLabel
        Left = 80
        Top = 7
        Width = 88
        Height = 15
        Hint = 'Record Number Order'
        Caption = 'Record Number'
        ParentShowHint = False
        ShowHint = True
      end
      object lblIsNullField: TLabel
        Left = 325
        Top = 8
        Width = 65
        Height = 15
        Anchors = [akTop, akRight]
        Caption = 'Is Null Field'
        Color = clYellow
        ParentColor = False
        Visible = False
      end
      object lblHiddenRecord: TLabel
        Left = 234
        Top = 8
        Width = 83
        Height = 15
        Caption = 'Hidden Record'
        Color = clYellow
        ParentColor = False
        Visible = False
      end
      object btnRecNo: TButton
        Left = 14
        Top = 4
        Width = 57
        Height = 20
        Caption = 'Rec #'
        TabOrder = 1
        OnClick = btnRecNoClick
      end
      object DBNavigator1: TDBNavigator
        Left = 396
        Top = 4
        Width = 180
        Height = 22
        DataSource = DataSource1
        VisibleButtons = [nbFirst, nbPrior, nbNext, nbLast, nbInsert, nbDelete, nbPost, nbCancel, nbRefresh]
        Anchors = [akTop, akRight]
        ConfirmDelete = False
        TabOrder = 0
      end
    end
    object DBGrid1: TDBGrid
      Left = 1
      Top = 29
      Width = 582
      Height = 279
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = 15
      Font.Name = 'Courier New'
      Font.Pitch = fpVariable
      Font.Style = []
      ParentFont = False
      PopupMenu = PopupMenu1
      TabOrder = 1
      TitleFont.Charset = DEFAULT_CHARSET
      TitleFont.Color = clWindowText
      TitleFont.Height = 15
      TitleFont.Name = 'lucida'
      TitleFont.Pitch = fpVariable
      TitleFont.Style = []
      OnCellClick = DBGrid1CellClick
      OnColEnter = DBGrid1ColEnter
      OnDblClick = DBGrid1DblClick
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 309
    Width = 584
    Height = 36
    Align = alBottom
    TabOrder = 1
    object Label_DBFName: TLabel
      Left = 14
      Top = 14
      Width = 96
      Height = 15
      Caption = 'Label_DBFName'
    end
  end
  object OpenDialog1: TOpenDialog
    DefaultExt = 'DBF'
    FileName = '*.DBF'
    Filter = 'dBase (*.dbf, *.DBF)|*.DBF;*.dbf'
    FilterIndex = 0
    Left = 464
    Top = 64
  end
  object MainMenu1: TMainMenu
    AutoHotkeys = maManual
    Left = 48
    Top = 80
    object File1: TMenuItem
      AutoHotkeys = maManual
      Caption = '&File'
      object Open1: TMenuItem
        Caption = '&Open...'
        OnClick = Open1Click
      end
      object Close1: TMenuItem
        Caption = 'Close'
        Enabled = False
        OnClick = Close1Click
      end
      object N3: TMenuItem
        Caption = '-'
      end
      object RebuildIndexes1: TMenuItem
        Caption = 'Rebuild Indexes'
        Enabled = False
        OnClick = RebuildIndexes1Click
      end
      object PackTable1: TMenuItem
        Caption = 'Pack Table'
        Enabled = False
        OnClick = PackTable1Click
      end
      object N2: TMenuItem
        Caption = '-'
      end
      object RecentDBFs1: TMenuItem
        Caption = 'Recent DBF'#39's'
      end
      object N4: TMenuItem
        Caption = '-'
      end
      object Exit1: TMenuItem
        Caption = 'E&xit'
        OnClick = Exit1Click
      end
    end
    object Navigate1: TMenuItem
      AutoHotkeys = maManual
      Caption = 'Navigate'
      OnClick = Navigate1Click
      object FindRecord1: TMenuItem
        Caption = '&Find Record'
        ShortCut = 16454
        OnClick = FindRecord1Click
      end
      object AddRecord1: TMenuItem
        Caption = '&Add Record'
        ShortCut = 113
        OnClick = AddRecord1Click
      end
      object HideRecord1: TMenuItem
        Caption = 'Hi&de Record'
        ShortCut = 8238
        OnClick = HideRecord1Click
      end
      object TopRecord1: TMenuItem
        Caption = 'To&p Record'
        ShortCut = 16417
        OnClick = TopRecord1Click
      end
      object PreviousRecord1: TMenuItem
        Caption = '&Previous Record'
        ShortCut = 33
        OnClick = PreviousRecord1Click
      end
      object NextRepord1: TMenuItem
        Caption = 'Ne&xt Repord'
        ShortCut = 34
        OnClick = NextRepord1Click
      end
      object BottomRecord1: TMenuItem
        Caption = '&Bottom Record'
        ShortCut = 16418
        OnClick = BottomRecord1Click
      end
      object GotoRecord1: TMenuItem
        Caption = 'Goto Record #'
        ShortCut = 16455
        OnClick = GotoRecord1Click
      end
      object FindKey1: TMenuItem
        Caption = 'Find Key...'
        ShortCut = 16459
        OnClick = FindKey1Click
      end
      object N1: TMenuItem
        Caption = '-'
      end
      object Order1: TMenuItem
        Caption = 'Order'
        ShortCut = 16463
      end
      object SpecifyFilterExpression1: TMenuItem
        Caption = 'Specify Filter Expression...'
        OnClick = SpecifyFilterExpression1Click
      end
      object MovetoFirstColumn1: TMenuItem
        Caption = 'Move to First Column'
        ShortCut = 112
        OnClick = MovetoFirstColumn1Click
      end
      object N5: TMenuItem
        Caption = '-'
      end
      object ShowHiddenRecords1: TMenuItem
        Caption = 'Show Hidden Records'
        OnClick = ShowHiddenRecords1Click
      end
    end
    object Help1: TMenuItem
      Caption = 'Help'
      object AboutTDbfBrowser1: TMenuItem
        Caption = 'About TDbf Browser...'
        OnClick = AboutTDbfBrowser1Click
      end
    end
  end
  object FindDialog1: TFindDialog
    Options = [frDown, frHideMatchCase, frHideWholeWord, frHideUpDown]
    OnFind = FindDialog1Find
    Left = 369
    Top = 57
  end
  object PopupMenu1: TPopupMenu
    OnPopup = PopupMenu1Popup
    Left = 360
    Top = 56
    object DisplayMemoasText1: TMenuItem
      Caption = 'Display Memo as Text'
      OnClick = DisplayMemoasText1Click
    end
    object DisplayMemoasObjects1: TMenuItem
      Caption = 'Display Memo as Object(s)'
      OnClick = DisplayMemoasObjects1Click
    end
  end
  object DataSource1: TDataSource
    Left = 456
    Top = 41
  end
end
