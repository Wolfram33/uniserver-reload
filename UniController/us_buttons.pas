unit us_buttons;

{#############################################################################
'# Name: us_buttons.pas
'# Flat, coloured, keyboard-accessible button used on the controller UI.
'# Native TButton ignores Color on win32; this control paints itself so the
'# UI can colour-code functions (green = start, amber = stop, blue = open,
'# brown = console) with WCAG-AA text contrast and a visible focus ring.
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, LCLIntf, LMessages;

const
  // TColor is $00BBGGRR. All fills keep >= 4.5:1 contrast with white text.
  USB_GREEN = TColor($327D2E);  // #2E7D32 start / positive actions
  USB_AMBER = TColor($0953B4);  // #B45309 stop actions
  USB_BLUE  = TColor($C06515);  // #1565C0 open / view actions
  USB_BROWN = TColor($414C6D);  // #6D4C41 console windows

type

  { TUsButton }

  TUsButton = class(TCustomControl)
  private
    FBaseColor  : TColor;
    FTextColor  : TColor;
    FBoldCaption: Boolean;
    FHover      : Boolean;
    FPressed    : Boolean;
    procedure SetBaseColor(AValue: TColor);
    procedure SetTextColor(AValue: TColor);
    procedure SetBoldCaption(AValue: Boolean);
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
    procedure CMTextChanged(var Message: TLMessage); message CM_TEXTCHANGED;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property BaseColor: TColor read FBaseColor write SetBaseColor default USB_BLUE;
    property TextColor: TColor read FTextColor write SetTextColor default clWhite;
    property BoldCaption: Boolean read FBoldCaption write SetBoldCaption default False;
    property Caption;
    property Enabled;
    property Font;
    property ParentFont;
    property TabOrder;
    property TabStop;
    property Visible;
    property Hint;
    property ShowHint;
    property ParentShowHint;
    property Anchors;
    property OnClick;
  end;

implementation

{Scale each RGB channel; factor < 1.0 darkens (hover/pressed shades)}
function ShadeColor(AColor: TColor; Factor: Double): TColor;
var
  rgb: LongInt;
begin
  rgb := ColorToRGB(AColor);
  Result := RGBToColor(
    Round(Red(rgb)   * Factor),
    Round(Green(rgb) * Factor),
    Round(Blue(rgb)  * Factor));
end;

{ TUsButton }

constructor TUsButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBaseColor   := USB_BLUE;
  FTextColor   := clWhite;
  FBoldCaption := False;
  FHover       := False;
  FPressed     := False;
  TabStop      := True;
  Cursor       := crHandPoint;
  AccessibleRole := larButton;
  SetInitialBounds(0, 0, 180, 40);
end;

procedure TUsButton.SetBaseColor(AValue: TColor);
begin
  if FBaseColor = AValue then Exit;
  FBaseColor := AValue;
  Invalidate;
end;

procedure TUsButton.SetTextColor(AValue: TColor);
begin
  if FTextColor = AValue then Exit;
  FTextColor := AValue;
  Invalidate;
end;

procedure TUsButton.SetBoldCaption(AValue: Boolean);
begin
  if FBoldCaption = AValue then Exit;
  FBoldCaption := AValue;
  Invalidate;
end;

procedure TUsButton.CMEnabledChanged(var Message: TLMessage);
begin
  inherited;
  if not Enabled then
  begin
    FHover   := False;
    FPressed := False;
  end;
  Invalidate;
end;

procedure TUsButton.CMTextChanged(var Message: TLMessage);
begin
  inherited;
  AccessibleName := Caption;
  Invalidate;
end;

procedure TUsButton.Paint;
var
  r, inner : TRect;
  fill     : TColor;
  radius   : Integer;
  ts       : TTextStyle;
begin
  r := ClientRect;

  // Fill the corner area with the parent background so the rounding shows
  if Parent <> nil then
    Canvas.Brush.Color := Parent.Color
  else
    Canvas.Brush.Color := clWhite;
  Canvas.FillRect(r);

  if Enabled then
  begin
    fill := FBaseColor;
    if FPressed then
      fill := ShadeColor(FBaseColor, 0.75)
    else if FHover then
      fill := ShadeColor(FBaseColor, 0.86);
  end
  else
    fill := TColor($E2E7E9); // light grey, disabled

  radius := Height div 5;
  Canvas.Brush.Color := fill;
  Canvas.Pen.Color   := ShadeColor(fill, 0.85);
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, radius, radius);

  // Caption, centred; disabled text keeps >= 4.5:1 on the grey fill
  Canvas.Font := Font;
  if FBoldCaption then
    Canvas.Font.Style := Canvas.Font.Style + [fsBold];
  if Enabled then
    Canvas.Font.Color := FTextColor
  else
    Canvas.Font.Color := TColor($63554B); // #4B5563 grey-blue
  Canvas.Brush.Style := bsClear;
  ts := Canvas.TextStyle;
  ts.Alignment := taCenter;
  ts.Layout    := tlCenter;
  ts.Opaque    := False;
  ts.SingleLine:= True;
  Canvas.TextRect(r, 0, 0, Caption, ts);

  // Visible focus ring: light inner outline on the dark fill
  if Focused then
  begin
    inner := r;
    InflateRect(inner, -3, -3);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color   := clWhite;
    Canvas.Pen.Width   := 2;
    Canvas.RoundRect(inner.Left, inner.Top, inner.Right, inner.Bottom,
                     radius - 2, radius - 2);
    Canvas.Pen.Width   := 1;
  end;
end;

procedure TUsButton.MouseEnter;
begin
  inherited MouseEnter;
  if Enabled then
  begin
    FHover := True;
    Invalidate;
  end;
end;

procedure TUsButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover   := False;
  FPressed := False;
  Invalidate;
end;

procedure TUsButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Enabled and (Button = mbLeft) then
  begin
    SetFocus;
    FPressed := True;
    Invalidate;
  end;
end;

procedure TUsButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  WasPressed: Boolean;
begin
  WasPressed := FPressed;
  FPressed := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
  if Enabled and WasPressed and (Button = mbLeft)
    and PtInRect(ClientRect, Point(X, Y)) then
      Click;
end;

procedure TUsButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Enabled and ((Key = VK_SPACE) or (Key = VK_RETURN)) then
  begin
    FPressed := True;
    Invalidate;
    Key := 0;
  end;
end;

procedure TUsButton.KeyUp(var Key: Word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  if Enabled and FPressed and ((Key = VK_SPACE) or (Key = VK_RETURN)) then
  begin
    FPressed := False;
    Invalidate;
    Click;
    Key := 0;
  end;
end;

procedure TUsButton.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TUsButton.DoExit;
begin
  inherited DoExit;
  FPressed := False;
  Invalidate;
end;

initialization
  // Allow the class to be resolved when the .lfm is streamed at runtime
  RegisterClasses([TUsButton]);

end.
