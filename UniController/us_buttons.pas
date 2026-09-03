unit us_buttons;

{#############################################################################
'# Name: us_buttons.pas
'# Flat, coloured, keyboard-accessible button used on the controller UI.
'# Native TButton ignores Color on win32; this control paints itself so the
'# UI can colour-code functions (green = start, amber = stop, blue = open,
'# brown = console) with WCAG-AA text contrast and a visible focus ring.
'#
'# The main window is the 3D medallion (us_medallion.pas): buttons sit on
'# brushed metal, so the corners outside the rounding are copied from the
'# form's background bitmap (UsButtonBackground) instead of a flat colour,
'# fills can be slightly translucent (FillOpacity) to let the metal shimmer
'# through, and the ubsTab style gives text-only "menu tabs" that replace
'# the classic menu bar.
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, Controls, Graphics, LCLType, LCLIntf, LMessages;

const
  // TColor is $00BBGGRR. All fills keep >= 4.5:1 contrast with their text.
  USB_GREEN    = TColor($327D2E);  // #2E7D32 start / positive actions
  USB_AMBER    = TColor($0953B4);  // #B45309 stop actions
  USB_BLUE     = TColor($C06515);  // #1565C0 open / view actions
  USB_BROWN    = TColor($414C6D);  // #6D4C41 console windows
  USB_GRAPHITE = TColor($423D3A);  // #3A3D42 window controls (minimize/close)

  USB_DISABLED_FILL = TColor($37322F);  // #2F3237 graphite, matches the coin
  USB_DISABLED_TEXT = TColor($D1CCC8);  // #C8CCD1 >= 7:1 on the disabled fill

type
  { ubsSolid: coloured pill (default). ubsTab: caption only, a dark pad
    appears on hover/press - used for the menu row on the medallion. }
  TUsButtonStyle = (ubsSolid, ubsTab);

  { TUsButton }

  TUsButton = class(TCustomControl)
  private
    FBaseColor  : TColor;
    FTextColor  : TColor;
    FBoldCaption: Boolean;
    FStyle      : TUsButtonStyle;
    FFillOpacity: Byte;
    FHover      : Boolean;
    FPressed    : Boolean;
    procedure SetBaseColor(AValue: TColor);
    procedure SetTextColor(AValue: TColor);
    procedure SetBoldCaption(AValue: Boolean);
    procedure SetStyle(AValue: TUsButtonStyle);
    procedure SetFillOpacity(AValue: Byte);
    procedure PaintBackground(const R: TRect);
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
    { Drop hover/pressed state, e.g. after a popup menu swallowed the mouse-up }
    procedure ResetVisualState;
  published
    property BaseColor: TColor read FBaseColor write SetBaseColor default USB_BLUE;
    property TextColor: TColor read FTextColor write SetTextColor default clWhite;
    property BoldCaption: Boolean read FBoldCaption write SetBoldCaption default False;
    property Style: TUsButtonStyle read FStyle write SetStyle default ubsSolid;
    { 255 = opaque fill; lower values let the parent background show through }
    property FillOpacity: Byte read FFillOpacity write SetFillOpacity default 255;
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

var
  { Set by the main form to its rendered background. Buttons that sit
    directly on that form copy their corner area from it, so the rounding
    shows the medallion instead of a flat colour. nil = use Parent.Color. }
  UsButtonBackground: Graphics.TBitmap = nil;

implementation

type
  TUsBlendFunction = packed record
    BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat: Byte;
  end;

{GDI AlphaBlend (msimg32) - the FPC Windows unit does not declare it}
function MsImgAlphaBlend(hdcDest: HDC; xDest, yDest, wDest, hDest: Integer;
  hdcSrc: HDC; xSrc, ySrc, wSrc, hSrc: Integer;
  ftn: TUsBlendFunction): BOOL; stdcall; external 'msimg32.dll' name 'AlphaBlend';

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

{Rounded rectangle filled with AColor at Opacity/255 over what is already on
 the canvas; Outline adds the usual darker border.}
procedure FillRoundRectAlpha(ACanvas: TCanvas; const R: TRect; Radius: Integer;
  AColor: TColor; Opacity: Byte; Outline: Boolean);
var
  tile: Graphics.TBitmap;
  rgn : HRGN;
  bf  : TUsBlendFunction;
begin
  if Opacity >= 255 then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
    if Outline then
      ACanvas.Pen.Color := ShadeColor(AColor, 0.85)
    else
      ACanvas.Pen.Color := AColor;
    ACanvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius);
    Exit;
  end;

  // Stretch a 1x1 tile of the colour through a rounded clip with constant alpha
  tile := Graphics.TBitmap.Create;
  try
    tile.PixelFormat := pf24bit;
    tile.SetSize(1, 1);
    tile.Canvas.Brush.Style := bsSolid;
    tile.Canvas.Brush.Color := AColor;
    tile.Canvas.FillRect(0, 0, 1, 1);

    rgn := Windows.CreateRoundRectRgn(R.Left, R.Top, R.Right + 1, R.Bottom + 1, Radius, Radius);
    Windows.SelectClipRgn(ACanvas.Handle, rgn);
    bf.BlendOp             := 0; // AC_SRC_OVER
    bf.BlendFlags          := 0;
    bf.SourceConstantAlpha := Opacity;
    bf.AlphaFormat         := 0; // ignore source alpha, constant only
    MsImgAlphaBlend(ACanvas.Handle, R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top,
                    tile.Canvas.Handle, 0, 0, 1, 1, bf);
    Windows.SelectClipRgn(ACanvas.Handle, 0);
    Windows.DeleteObject(rgn);
  finally
    tile.Free;
  end;

  if Outline then
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Color   := ShadeColor(AColor, 0.85);
    ACanvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Radius, Radius);
  end;
end;

{ TUsButton }

constructor TUsButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBaseColor   := USB_BLUE;
  FTextColor   := clWhite;
  FBoldCaption := False;
  FStyle       := ubsSolid;
  FFillOpacity := 255;
  FHover       := False;
  FPressed     := False;
  TabStop      := True;
  Cursor       := crHandPoint;
  AccessibleRole := larButton;
  SetInitialBounds(0, 0, 180, 40);
end;

procedure TUsButton.ResetVisualState;
begin
  FHover   := False;
  FPressed := False;
  Invalidate;
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

procedure TUsButton.SetStyle(AValue: TUsButtonStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  Invalidate;
end;

procedure TUsButton.SetFillOpacity(AValue: Byte);
begin
  if FFillOpacity = AValue then Exit;
  FFillOpacity := AValue;
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
  // A hand cursor on something that does nothing would promise a click
  if Enabled then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

procedure TUsButton.CMTextChanged(var Message: TLMessage);
begin
  inherited;
  AccessibleName := Caption;
  Invalidate;
end;

{Corner area behind the rounding: the form's background bitmap when the
 button sits directly on the top-level form, otherwise the parent colour.}
procedure TUsButton.PaintBackground(const R: TRect);
begin
  if (UsButtonBackground <> nil) and (Parent <> nil) and (Parent.Parent = nil)
     and (Left >= 0) and (Top >= 0)
     and (Left + Width  <= UsButtonBackground.Width)
     and (Top  + Height <= UsButtonBackground.Height) then
  begin
    Canvas.CopyRect(R, UsButtonBackground.Canvas, Bounds(Left, Top, Width, Height));
    Exit;
  end;
  if Parent <> nil then
    Canvas.Brush.Color := Parent.Color
  else
    Canvas.Brush.Color := clWhite;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(R);
end;

procedure TUsButton.Paint;
var
  r, inner : TRect;
  fill     : TColor;
  radius   : Integer;
  ts       : TTextStyle;
begin
  r := ClientRect;
  PaintBackground(r);
  radius := Height div 5;

  case FStyle of
    ubsSolid:
      begin
        if Enabled then
        begin
          fill := FBaseColor;
          if FPressed then
            fill := ShadeColor(FBaseColor, 0.75)
          else if FHover then
            fill := ShadeColor(FBaseColor, 0.86);
        end
        else
          fill := USB_DISABLED_FILL;
        FillRoundRectAlpha(Canvas, r, radius, fill, FFillOpacity, True);
      end;
    ubsTab:
      // Resting tab is caption only; hover/press add a dark translucent pad
      if Enabled and (FHover or FPressed) then
      begin
        if FPressed then
          FillRoundRectAlpha(Canvas, r, radius, clBlack, 150, False)
        else
          FillRoundRectAlpha(Canvas, r, radius, clBlack, 100, False);
      end;
  end;

  // Caption, centred; disabled text keeps >= 4.5:1 on its background
  Canvas.Font := Font;
  if FBoldCaption then
    Canvas.Font.Style := Canvas.Font.Style + [fsBold];
  if Enabled then
    Canvas.Font.Color := FTextColor
  else
    Canvas.Font.Color := USB_DISABLED_TEXT;
  Canvas.Brush.Style := bsClear;
  ts := Canvas.TextStyle;
  ts.Alignment := taCenter;
  ts.Layout    := tlCenter;
  ts.Opaque    := False;
  ts.SingleLine:= True;
  Canvas.TextRect(r, 0, 0, Caption, ts);

  // Visible focus ring: light inner outline
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
begin
  FPressed := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
  // No explicit Click here: the LCL fires OnClick itself on mouse-up inside
  // the control (csClickEvents). Calling Click as well ran every handler
  // twice per click - Stop Apache/MySQL immediately restarted the server.
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
