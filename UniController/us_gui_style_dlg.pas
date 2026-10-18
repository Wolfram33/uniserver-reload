unit us_gui_style_dlg;

{#############################################################################
'# Name: us_gui_style_dlg.pas
'# First-start choice of the controller's window look: classic window or
'# modern medallion. Two coloured cards, each with a small preview, a short
'# explanation and its own button, so the choice is clear before the main
'# window ever appears. Built in code (no .lfm) because it is shown once.
'# The same choice stays available in the menu General > Window look.
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  LCLType, us_buttons, us_medallion, default_config_vars;

{ Shows the dialog. Result: GUI_CLASSIC, GUI_MODERN, or '' when the user
  closed it without choosing (Esc / title bar x). }
function us_ask_gui_style: string;

implementation

const
  // TColor is $00BBGGRR. Every text colour keeps >= 4.5:1 on its background.
  HEADER_COLOR        = TColor($C06515); // #1565C0 blue band, white text 5.7:1
  CLASSIC_CARD_COLOR  = TColor($FDF2E3); // #E3F2FD light blue
  CLASSIC_HEAD_COLOR  = TColor($A1470D); // #0D47A1 dark blue, 8.6:1 on the card
  CLASSIC_TEXT_COLOR  = TColor($372A1F); // #1F2A37 near black
  MODERN_CARD_COLOR   = TColor($2F2F2F); // #2F2F2F graphite like the medallion window
  MODERN_HEAD_COLOR   = TColor($4DB7FF); // #FFB74D orange, 8.3:1 on graphite
  MODERN_TEXT_COLOR   = TColor($EDEAE8); // #E8EAED light grey
  FOOTER_TEXT_COLOR   = TColor($514137); // #374151 on white

  // Layout in 96-dpi units, scaled to the screen in S()
  DLG_WIDTH   = 600;
  CARD_TOP    = 96;
  CARD_WIDTH  = 270;
  CARD_HEIGHT = 324;
  CARD_GAP    = 20;
  PREVIEW_H   = 128;

type

  { TGuiStyleDlg }

  TGuiStyleDlg = class(TForm)
  private
    FChoice : string;
    procedure ClassicClick(Sender: TObject);
    procedure ModernClick(Sender: TObject);
    procedure SketchPaint(Sender: TObject);
    procedure DlgKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function S(AValue: Integer): Integer;
    function AddLabel(AParent: TWinControl; const ACaption: string;
      ATop, AHeight: Integer; AColor: TColor; ABold: Boolean; ASize: Integer): TLabel;
    function AddCard(ALeft: Integer; AColor: TColor): TPanel;
    function CoinPreview(ASize: Integer; ABackground: TColor): Graphics.TBitmap;
  public
    constructor CreateDlg;
    property Choice: string read FChoice;
  end;

function TGuiStyleDlg.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

function TGuiStyleDlg.AddLabel(AParent: TWinControl; const ACaption: string;
  ATop, AHeight: Integer; AColor: TColor; ABold: Boolean; ASize: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent     := AParent;
  Result.AutoSize   := False;
  Result.WordWrap   := True;
  Result.SetBounds(S(14), S(ATop), AParent.ClientWidth - S(28), S(AHeight));
  Result.Caption    := ACaption;
  Result.Font.Name  := 'Segoe UI';
  Result.Font.Size  := ASize;
  Result.Font.Color := AColor;
  if ABold then Result.Font.Style := [fsBold];
  Result.Transparent := True;
end;

function TGuiStyleDlg.AddCard(ALeft: Integer; AColor: TColor): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent      := Self;
  Result.BevelOuter  := bvNone;
  Result.ParentColor := False;
  Result.Color       := AColor;
  Result.SetBounds(S(ALeft), S(CARD_TOP), S(CARD_WIDTH), S(CARD_HEIGHT));
end;

{The medallion artwork, scaled down, with everything outside the coin
 filled in the card colour (Render composites over black otherwise).}
function TGuiStyleDlg.CoinPreview(ASize: Integer; ABackground: TColor): Graphics.TBitmap;
var
  coin            : TUsMedallion;
  coinRgn, outRgn : HRGN;
  fillBrush       : HBRUSH;
  noBands         : array of Classes.TRect;
begin
  Result := nil;
  SetLength(noBands, 0);
  coin := TUsMedallion.Create;
  try
    Result := Graphics.TBitmap.Create;
    if not coin.Render(ASize, Result, noBands, 0, 0) then
    begin
      FreeAndNil(Result);                 // artwork missing: card without preview
      Exit;
    end;
    coinRgn := coin.CreateRegion;
    outRgn  := Windows.CreateRectRgn(0, 0, ASize, ASize);
    fillBrush := Windows.CreateSolidBrush(ColorToRGB(ABackground));
    try
      Windows.CombineRgn(outRgn, outRgn, coinRgn, RGN_DIFF);
      Windows.FillRgn(Result.Canvas.Handle, outRgn, fillBrush);
    finally
      Windows.DeleteObject(fillBrush);
      Windows.DeleteObject(outRgn);
      Windows.DeleteObject(coinRgn);
    end;
  finally
    coin.Free;
  end;
end;

{Small sketch of the classic window: title bar, menu bar, logo, green start
 buttons with LEDs and the two utility columns, in the real colours.}
procedure TGuiStyleDlg.SketchPaint(Sender: TObject);
var
  box  : TPaintBox;
  c    : TCanvas;
  w, h : Integer;
  i    : Integer;

  procedure Fill(fx1, fy1, fx2, fy2: Double; AColor: TColor);
  begin
    c.Brush.Color := AColor;
    c.Pen.Color   := AColor;
    c.RoundRect(Round(fx1 * w), Round(fy1 * h), Round(fx2 * w), Round(fy2 * h), S(4), S(4));
  end;

begin
  box := Sender as TPaintBox;
  c   := box.Canvas;
  w   := box.Width;
  h   := box.Height;
  c.Brush.Color := clWhite;
  c.Pen.Color   := TColor($AFA39C);           // #9CA3AF frame
  c.Rectangle(0, 0, w, h);
  Fill(0.005, 0.01, 0.995, 0.11, TColor($F6F4F3)); // title bar
  Fill(0.02, 0.03, 0.06, 0.09, HEADER_COLOR);       // window icon
  for i := 0 to 5 do                                 // menu bar entries
    Fill(0.03 + i * 0.12, 0.14, 0.12 + i * 0.12, 0.18, TColor($AFA39C));
  c.Brush.Color := HEADER_COLOR;                     // logo
  c.Pen.Color   := HEADER_COLOR;
  c.Ellipse(Round(0.08 * w), Round(0.25 * h), Round(0.08 * w) + Round(0.2 * h), Round(0.45 * h));
  Fill(0.50, 0.24, 0.86, 0.33, USB_GREEN);           // start buttons
  Fill(0.50, 0.37, 0.86, 0.46, USB_GREEN);
  c.Brush.Color := TColor($2929D6);                  // LEDs
  c.Pen.Color   := TColor($2929D6);
  c.Ellipse(Round(0.89 * w), Round(0.26 * h), Round(0.89 * w) + Round(0.06 * h), Round(0.32 * h));
  c.Ellipse(Round(0.89 * w), Round(0.39 * h), Round(0.89 * w) + Round(0.06 * h), Round(0.45 * h));
  for i := 0 to 3 do                                 // utility columns
  begin
    if i = 0 then
    begin
      Fill(0.05, 0.56 + i * 0.11, 0.46, 0.64 + i * 0.11, USB_BROWN);
      Fill(0.52, 0.56 + i * 0.11, 0.93, 0.64 + i * 0.11, USB_BROWN);
    end
    else
    begin
      Fill(0.05, 0.56 + i * 0.11, 0.46, 0.64 + i * 0.11, USB_BLUE);
      Fill(0.52, 0.56 + i * 0.11, 0.93, 0.64 + i * 0.11, USB_BLUE);
    end;
  end;
end;

procedure TGuiStyleDlg.ClassicClick(Sender: TObject);
begin
  FChoice     := GUI_CLASSIC;
  ModalResult := mrOK;
end;

procedure TGuiStyleDlg.ModernClick(Sender: TObject);
begin
  FChoice     := GUI_MODERN;
  ModalResult := mrOK;
end;

procedure TGuiStyleDlg.DlgKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    ModalResult := mrCancel;              // no choice: asked again next start
  end;
end;

constructor TGuiStyleDlg.CreateDlg;
var
  header, card : TPanel;
  sketch       : TPaintBox;
  img          : TImage;
  btn, first   : TUsButton;
  coin         : Graphics.TBitmap;
  lbl          : TLabel;
begin
  inherited CreateNew(nil);
  Scaled       := False;   // sizes below are already scaled to the screen in S()
  FChoice      := '';
  Caption      := 'UniServer Reload - choose the window look';
  BorderStyle  := bsDialog;
  Position     := poScreenCenter;
  Color        := clWhite;
  Font.Name    := 'Segoe UI';
  Font.Size    := 10;
  KeyPreview   := True;
  OnKeyDown    := @DlgKeyDown;
  ClientWidth  := S(DLG_WIDTH);
  ClientHeight := S(CARD_TOP + CARD_HEIGHT + 56);

  //--- Blue header band
  header := TPanel.Create(Self);
  header.Parent      := Self;
  header.SetBounds(0, 0, ClientWidth, S(80)); // width before the labels size themselves to it
  header.Align       := alTop;
  header.BevelOuter  := bvNone;
  header.ParentColor := False;
  header.Color       := HEADER_COLOR;
  AddLabel(header, 'Welcome to UniServer Reload', 12, 28, clWhite, True, 14);
  AddLabel(header, 'How should the control window look? Both looks offer exactly the same functions.',
           44, 24, clWhite, False, 10);

  //--- Classic card (light blue, sketch of the window)
  card := AddCard(CARD_GAP, CLASSIC_CARD_COLOR);
  sketch := TPaintBox.Create(Self);
  sketch.Parent  := card;
  sketch.SetBounds(S(14), S(12), card.ClientWidth - S(28), S(PREVIEW_H));
  sketch.OnPaint := @SketchPaint;
  AddLabel(card, 'Classic window', PREVIEW_H + 22, 26, CLASSIC_HEAD_COLOR, True, 12);
  AddLabel(card, 'Normal compact window with title bar and menu bar, like the original ' +
                 'Uniform Server Zero. About 460 x 320 pixels at 100 % display scaling.',
           PREVIEW_H + 50, 84, CLASSIC_TEXT_COLOR, False, 10);
  btn := TUsButton.Create(Self);
  btn.Parent    := card;
  btn.SetBounds(S(14), S(CARD_HEIGHT - 54), card.ClientWidth - S(28), S(40));
  btn.Caption   := 'Use classic window';
  btn.BaseColor := USB_GREEN;
  btn.BoldCaption := True;
  btn.OnClick   := @ClassicClick;
  first := btn;

  //--- Modern card (graphite, the coin itself)
  card := AddCard(CARD_GAP * 2 + CARD_WIDTH, MODERN_CARD_COLOR);
  coin := CoinPreview(S(PREVIEW_H), MODERN_CARD_COLOR);
  if coin <> nil then
  begin
    img := TImage.Create(Self);
    img.Parent := card;
    img.SetBounds(S(14), S(12), card.ClientWidth - S(28), S(PREVIEW_H));
    img.Center := True;
    img.Picture.Bitmap.Assign(coin);
    coin.Free;
  end;
  AddLabel(card, 'Modern medallion', PREVIEW_H + 22, 26, MODERN_HEAD_COLOR, True, 12);
  AddLabel(card, 'The round Reload coin is the window, with the menus as tabs on it. ' +
                 'About 640 x 640 pixels at 100 % display scaling.',
           PREVIEW_H + 50, 84, MODERN_TEXT_COLOR, False, 10);
  btn := TUsButton.Create(Self);
  btn.Parent    := card;
  btn.SetBounds(S(14), S(CARD_HEIGHT - 54), card.ClientWidth - S(28), S(40));
  btn.Caption   := 'Use modern medallion';
  btn.BaseColor := USB_GREEN;
  btn.BoldCaption := True;
  btn.OnClick   := @ModernClick;

  //--- Where to change it later
  lbl := AddLabel(Self, 'You can switch at any time: menu General > Window look.',
                  CARD_TOP + CARD_HEIGHT + 16, 24, FOOTER_TEXT_COLOR, False, 10);
  lbl.Alignment := taCenter;

  ActiveControl := first;
end;

function us_ask_gui_style: string;
var
  dlg: TGuiStyleDlg;
begin
  Result := '';
  dlg := TGuiStyleDlg.CreateDlg;
  try
    if dlg.ShowModal = mrOK then Result := dlg.Choice;
  finally
    dlg.Free;
  end;
end;

end.
