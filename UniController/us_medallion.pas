unit us_medallion;

{#############################################################################
'# Name: us_medallion.pas
'# The 3D medallion IS the controller's main window. This unit turns the
'# MEDALLION resource (PNG with alpha, see unicon_images.rc) into
'#   - an opaque background bitmap at the current window size, scaled with
'#     alpha-aware supersampling so the coin stays crisp at every DPI,
'#   - dark translucent "bands" baked into that bitmap under the text rows,
'#     so light captions keep WCAG-AA contrast on any part of the metal,
'#   - a window region cut from the alpha mask (SetWindowRgn) that clips the
'#     form to the coin; clicks outside the coin fall through to the desktop.
'# The form stays an ordinary opaque window, so native controls keep working;
'# only its outline is shaped. No per-pixel layered window is involved.
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils, Graphics, GraphType, IntfGraphics;

type

  { TUsMedallion }

  TUsMedallion = class
  private
    FSource : TLazIntfImage; // decoded resource, 32 bpp with alpha
    FAlpha  : array of Byte; // coverage of the last render, Size*Size, row-major
    FSize   : Integer;       // edge length of the last render (0 = none yet)
    function LoadSource: Boolean;
    function GetLoaded: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Scale the coin to Size x Size pixels into ABitmap (opaque). Every
      rounded rectangle in Bands is darkened with black at BandOpacity/255.
      False when the artwork is unavailable: the caller paints a fallback. }
    function Render(Size: Integer; ABitmap: Graphics.TBitmap;
                    const Bands: array of TRect; BandRadius: Integer;
                    BandOpacity: Byte): Boolean;
    { Region of every pixel the last Render left at least half opaque.
      The caller owns the handle; SetWindowRgn takes it over. }
    function CreateRegion: HRGN;
    property Loaded: Boolean read GetLoaded;
  end;

implementation

const
  MEDALLION_RES = 'MEDALLION'; // RCDATA name in unicon_images.rc

{Point test for a rounded rectangle; R is half-open like TRect}
function InRoundRect(const R: TRect; Radius, X, Y: Integer): Boolean;
var
  cx, cy, dx, dy: Integer;
begin
  Result := (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom);
  if (not Result) or (Radius <= 0) then Exit;

  // Inside the straight parts: done. Otherwise test against the corner circle.
  if X < R.Left + Radius then
    cx := R.Left + Radius
  else if X >= R.Right - Radius then
    cx := R.Right - Radius - 1
  else
    Exit;
  if Y < R.Top + Radius then
    cy := R.Top + Radius
  else if Y >= R.Bottom - Radius then
    cy := R.Bottom - Radius - 1
  else
    Exit;
  dx := X - cx;
  dy := Y - cy;
  Result := (dx * dx + dy * dy) <= (Radius * Radius);
end;

{ TUsMedallion }

constructor TUsMedallion.Create;
begin
  inherited Create;
  FSource := nil;
  FSize   := 0;
  LoadSource;
end;

destructor TUsMedallion.Destroy;
begin
  FSource.Free;
  inherited Destroy;
end;

function TUsMedallion.GetLoaded: Boolean;
begin
  Result := FSource <> nil;
end;

{Decode the PNG resource. Any problem (missing resource, unexpected pixel
 layout, corrupt data) leaves Loaded = False instead of raising.}
function TUsMedallion.LoadSource: Boolean;
var
  rs     : TResourceStream;
  reader : TLazReaderPNG;
  img    : TLazIntfImage;
begin
  Result := False;
  if Windows.FindResource(HInstance, MEDALLION_RES, RT_RCDATA) = 0 then Exit;

  img := nil;
  try
    rs := TResourceStream.Create(HInstance, MEDALLION_RES, RT_RCDATA);
    try
      img    := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
      reader := TLazReaderPNG.Create;
      try
        img.LoadFromStream(rs, reader);
      finally
        reader.Free;
      end;
    finally
      rs.Free;
    end;

    // Render reads 32 bpp pixels through the description's channel shifts;
    // anything else is treated like a missing resource.
    if (img.Width > 0) and (img.Height > 0)
       and (img.DataDescription.BitsPerPixel = 32) then
    begin
      FSource := img;
      Result  := True;
    end
    else
      img.Free;
  except
    on E: Exception do
    begin
      img.Free;
      FSource := nil;
      Result  := False;
    end;
  end;
end;

function TUsMedallion.Render(Size: Integer; ABitmap: Graphics.TBitmap;
  const Bands: array of TRect; BandRadius: Integer; BandOpacity: Byte): Boolean;
var
  src, dst        : TRawImageDescription;
  dest            : TLazIntfImage;
  srcLines        : array of PByte;   // row starts of the source, once
  sxIdx, syIdx    : array of Integer; // source coordinate of each sub-sample
  n, nn           : Integer;          // n x n sub-samples per output pixel
  scaleX, scaleY  : Double;
  hasAlpha        : Boolean;
  tx, ty, i, j    : Integer;
  dline           : PByte;
  pix             : DWord;
  a, r, g, b      : Cardinal;
  sumA, sumR      : Cardinal;
  sumG, sumB      : Cardinal;
  alpha           : Cardinal;
  bandIdx, bpp    : Integer;
  keep            : Cardinal;         // 255 - BandOpacity
begin
  Result := False;
  if (FSource = nil) or (Size <= 0) or (ABitmap = nil) then Exit;

  src      := FSource.DataDescription;
  hasAlpha := src.AlphaPrec > 0;
  scaleX   := FSource.Width  / Size;
  scaleY   := FSource.Height / Size;

  // Box-filter by supersampling: enough samples to cover the scale factor,
  // capped so a tiny window does not burn time (quality is moot there).
  n := Trunc(scaleX) + 1;
  if n < 2 then n := 2;
  if n > 5 then n := 5;
  nn := n * n;

  SetLength(srcLines, FSource.Height);
  for j := 0 to FSource.Height - 1 do
    srcLines[j] := PByte(FSource.GetDataLineStart(j));

  SetLength(sxIdx, Size * n);
  SetLength(syIdx, Size * n);
  for tx := 0 to Size - 1 do
    for i := 0 to n - 1 do
    begin
      j := Trunc((tx + (i + 0.5) / n) * scaleX);
      if j >= FSource.Width then j := FSource.Width - 1;
      sxIdx[tx * n + i] := j;
      j := Trunc((tx + (i + 0.5) / n) * scaleY);
      if j >= FSource.Height then j := FSource.Height - 1;
      syIdx[tx * n + i] := j;
    end;

  SetLength(FAlpha, Size * Size);
  FSize := Size;
  keep  := 255 - BandOpacity;

  dest := TLazIntfImage.Create(Size, Size, [riqfRGB]);
  try
    dst := dest.DataDescription;
    bpp := dst.BitsPerPixel div 8;
    if (bpp <> 3) and (bpp <> 4) then Exit; // device format we cannot fill

    for ty := 0 to Size - 1 do
    begin
      dline := PByte(dest.GetDataLineStart(ty));
      for tx := 0 to Size - 1 do
      begin
        sumA := 0; sumR := 0; sumG := 0; sumB := 0;
        for j := 0 to n - 1 do
          for i := 0 to n - 1 do
          begin
            pix := PDWord(srcLines[syIdx[ty * n + j]] + sxIdx[tx * n + i] * 4)^;
            if hasAlpha then
              a := (pix shr src.AlphaShift) and $FF
            else
              a := 255;
            r := (pix shr src.RedShift)   and $FF;
            g := (pix shr src.GreenShift) and $FF;
            b := (pix shr src.BlueShift)  and $FF;
            Inc(sumA, a);
            Inc(sumR, r * a);     // alpha-weighted, so transparent
            Inc(sumG, g * a);     // neighbours do not bleed colour
            Inc(sumB, b * a);
          end;

        alpha := sumA div nn;     // average coverage 0..255
        FAlpha[ty * Size + tx] := Byte(alpha);
        if sumA > 0 then
        begin
          r := sumR div sumA;
          g := sumG div sumA;
          b := sumB div sumA;
        end
        else
        begin
          r := 0; g := 0; b := 0;
        end;

        // The window is opaque: rim pixels are composited over black, which
        // matches the coin's own dark edge where the region cuts it off.
        r := r * alpha div 255;
        g := g * alpha div 255;
        b := b * alpha div 255;

        for bandIdx := 0 to High(Bands) do
          if InRoundRect(Bands[bandIdx], BandRadius, tx, ty) then
          begin
            r := r * keep div 255;
            g := g * keep div 255;
            b := b * keep div 255;
            Break;
          end;

        pix := (r shl dst.RedShift) or (g shl dst.GreenShift) or (b shl dst.BlueShift);
        if dst.AlphaPrec > 0 then
          pix := pix or (DWord(255) shl dst.AlphaShift);
        Move(pix, (dline + tx * bpp)^, bpp); // little-endian: low bytes first
      end;
    end;

    ABitmap.LoadFromIntfImage(dest);
    Result := True;
  finally
    dest.Free;
  end;
end;

function TUsMedallion.CreateRegion: HRGN;
var
  x, x0, y: Integer;
  row     : HRGN;
begin
  Result := Windows.CreateRectRgn(0, 0, 0, 0);
  if FSize = 0 then Exit;

  for y := 0 to FSize - 1 do
  begin
    x := 0;
    while x < FSize do
    begin
      while (x < FSize) and (FAlpha[y * FSize + x] < 128) do Inc(x);
      if x >= FSize then Break;
      x0 := x;
      while (x < FSize) and (FAlpha[y * FSize + x] >= 128) do Inc(x);
      row := Windows.CreateRectRgn(x0, y, x, y + 1);
      Windows.CombineRgn(Result, Result, row, RGN_OR);
      Windows.DeleteObject(row);
    end;
  end;
end;

end.
