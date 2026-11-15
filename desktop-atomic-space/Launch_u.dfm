object frmLaunch: TfrmLaunch
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 650
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object ScenePaintBox: TPaintBox
    Left = 0
    Top = 108
    Width = 900
    Height = 542
    Align = alClient
    OnPaint = ScenePaintBoxPaint
  end
  object FuelLabel: TLabel
    Left = 384
    Top = 571
    Width = 130
    Height = 23
    Caption = 'Fuel: not loaded'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object TankBar: TProgressBar
    Left = 384
    Top = 600
    Width = 500
    Height = 25
    TabOrder = 1
  end
  object ControlPanel: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 108
    Align = alTop
    BevelOuter = bvNone
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object TitleLabel: TLabel
      Left = 18
      Top = 12
      Width = 250
      Height = 25
      Caption = 'SKYWARD | ROCKET FLIGHT'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -19
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object HelpLabel: TLabel
      Left = 20
      Top = 42
      Width = 398
      Height = 15
      Caption = 
        'Thrust must exceed rocket weight (mass x 9.81 N) to lift off. No' +
        ' drag model.'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object AltitudeLabel: TLabel
      Left = 20
      Top = 76
      Width = 120
      Height = 17
      Caption = 'Distance up: 0.00 ft'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object VelocityLabel: TLabel
      Left = 190
      Top = 76
      Width = 98
      Height = 17
      Caption = 'Speed: 0.00 m/s'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object AccelerationLabel: TLabel
      Left = 345
      Top = 76
      Width = 133
      Height = 17
      Caption = 'Net accel: 0.00 m/s^2'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object FlightStatusLabel: TLabel
      Left = 530
      Top = 76
      Width = 78
      Height = 17
      Caption = 'Flight: ready'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object StartButton: TButton
      Left = 688
      Top = 30
      Width = 88
      Height = 34
      Caption = 'Start'
      TabOrder = 0
      OnClick = StartButtonClick
    end
    object ResetButton: TButton
      Left = 788
      Top = 30
      Width = 88
      Height = 34
      Caption = 'Reset'
      TabOrder = 1
      OnClick = ResetButtonClick
    end
  end
  object AnimationTimer: TTimer
    Enabled = False
    Interval = 16
    OnTimer = AnimationTimerTimer
    Left = 448
    Top = 16
  end
end
