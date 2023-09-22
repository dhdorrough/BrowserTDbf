object frmGotoRecNo: TfrmGotoRecNo
  Left = 778
  Top = 440
  Width = 267
  Height = 167
  Caption = 'Goto Record #'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  PixelsPerInch = 96
  TextHeight = 13
  object OvcNumericField1: TOvcNumericField
    Left = 16
    Top = 16
    Width = 130
    Height = 21
    Cursor = crIBeam
    DataType = nftLongInt
    CaretOvr.Shape = csBlock
    EFColors.Disabled.BackColor = clWindow
    EFColors.Disabled.TextColor = clGrayText
    EFColors.Error.BackColor = clRed
    EFColors.Error.TextColor = clBlack
    EFColors.Highlight.BackColor = clHighlight
    EFColors.Highlight.TextColor = clHighlightText
    Options = []
    PictureMask = '999,999,999,999'
    TabOrder = 0
    RangeHigh = {FFFFFF7F000000000000}
    RangeLow = {00000080000000000000}
  end
  object Button1: TButton
    Left = 176
    Top = 96
    Width = 75
    Height = 25
    Caption = 'Goto'
    ModalResult = 1
    TabOrder = 1
  end
end
