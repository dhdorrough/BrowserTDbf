object frmGetString: TfrmGetString
  Left = 732
  Top = 379
  Width = 421
  Height = 204
  Caption = 'Get String'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  DesignSize = (
    405
    166)
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 16
    Top = 16
    Width = 32
    Height = 13
    Caption = 'Label1'
  end
  object Label2: TLabel
    Left = 16
    Top = 40
    Width = 32
    Height = 13
    Caption = 'Label2'
  end
  object Edit1: TEdit
    Left = 16
    Top = 83
    Width = 361
    Height = 24
    TabOrder = 0
    Text = 'Edit1'
  end
  object Button1: TButton
    Left = 312
    Top = 119
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 1
  end
  object Button2: TButton
    Left = 232
    Top = 119
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Ok'
    Default = True
    ModalResult = 1
    TabOrder = 2
    OnClick = Button2Click
  end
end
