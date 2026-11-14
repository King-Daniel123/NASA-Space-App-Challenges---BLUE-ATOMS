unit WebDraw;

{ TradeSpace - everything drawn on a canvas.

  All pictures in the game are drawn by this code from the numbers in the
  mission design: the spacecraft blueprint, the orbit view, the launch, the
  cruise and the charts. The only image files are NASA's: a sunset sky and
  clouds photographed at Kennedy Space Center, and the Blue Marble world map.

  AI-assistance note: this drawing code was written with the help of Claude
  (Anthropic). No AI-generated images are used. }

{$mode objfpc}

interface

uses
  JS, Web, SysUtils, Math, TsTypes, TsSim;

type
  TCtx = TJSCanvasRenderingContext2D;

procedure LoadImages;
function Prep(const Id: string; W, H: Integer; out Ctx: TCtx): Boolean;
procedure DrawStars;
procedure DrawOrbitView(Ctx: TCtx; W, H: Double; const D: TDesign; T: Double);
procedure DrawCraft(Ctx: TCtx; W, H: Double; const D: TDesign; const A: TAnalysis);
procedure DrawEarthMap(Ctx: TCtx; W, H: Double; const D: TDesign; ShowOrbit: Boolean);
procedure DrawLaunch(Ctx: TCtx; W, H, T: Double; Size: Integer; Fail: Boolean);
procedure DrawCruise(Ctx: TCtx; W, H: Double; const S: TSimState; T: Double);
procedure DrawChart(Ctx: TCtx; W, H: Double; const S: TSimState);
function CategoryColor(const Cat: string): string;

const
  LaunchSeconds = 15.0;

implementation

uses
  TsCatalog, TsScenarios, TsEngine, TsFmt;

const
  ColLine = '#5ad1ff';
  ColDim = 'rgba(90,209,255,0.35)';
  ColText = '#e8eef9';
  ColMuted = '#93a4c3';
  FontSmall = '11px ui-monospace, Consolas, monospace';
  FontMid = '12.5px ui-monospace, Consolas, monospace';
  FontBig = 'bold 15px ui-monospace, Consolas, monospace';

var
  ImgSky, ImgMap: TJSHTMLImageElement;
  ImgCloud: array[0..2] of TJSHTMLImageElement;

function NewImage(const Src: string): TJSHTMLImageElement;
begin
  Result := TJSHTMLImageElement(document.createElement('img'));
  Result.src := Src;
end;

procedure LoadImages;
begin
  ImgSky := NewImage('assets/launch_sky.jpg');
  ImgMap := NewImage('assets/earth_map.jpg');
  ImgCloud[0] := NewImage('assets/cloud_1.png');
  ImgCloud[1] := NewImage('assets/cloud_2.png');
  ImgCloud[2] := NewImage('assets/cloud_3.png');
end;

function Ready(Img: TJSHTMLImageElement): Boolean;
begin
  Result := (Img <> nil) and Img.complete and (Img.naturalWidth > 0);
end;

function Prep(const Id: string; W, H: Integer; out Ctx: TCtx): Boolean;
var
  C: TJSHTMLCanvasElement;
begin
  Result := False;
  Ctx := nil;
  C := TJSHTMLCanvasElement(document.getElementById(Id));
  if C = nil then
    Exit;
  { Draw at twice the size for sharp lines on high-density screens. }
  if (C.width <> W * 2) or (C.height <> H * 2) then
  begin
    C.width := W * 2;
    C.height := H * 2;
  end;
  Ctx := C.getContextAs2DContext('2d');
  Ctx.setTransform(2, 0, 0, 2, 0, 0);
  Result := True;
end;

function NextRand(var Seed: Double): Double;
begin
  Seed := Seed * 16807.0;
  Seed := Seed - 2147483647.0 * Trunc(Seed / 2147483647.0);
  Result := Seed / 2147483647.0;
end;

function Rgba(R, G, B: Integer; A: Double): string;
begin
  Result := 'rgba(' + IntToStr(R) + ',' + IntToStr(G) + ',' + IntToStr(B) + ',' + FmtNum(A, 2) + ')';
end;

procedure Disc(Ctx: TCtx; X, Y, R: Double; const Fill: string);
begin
  Ctx.beginPath;
  Ctx.arc(X, Y, R, 0, 2 * Pi);
  Ctx.fillStyle := Fill;
  Ctx.fill;
end;

procedure Line(Ctx: TCtx; X1, Y1, X2, Y2: Double);
begin
  Ctx.beginPath;
  Ctx.moveTo(X1, Y1);
  Ctx.lineTo(X2, Y2);
  Ctx.stroke;
end;

procedure Txt(Ctx: TCtx; const S: string; X, Y: Double; const Font, Color, Align: string);
begin
  Ctx.font := Font;
  Ctx.fillStyle := Color;
  Ctx.textAlign := Align;
  Ctx.fillText(S, X, Y);
end;

{ ---- starfield --------------------------------------------------------- }

procedure DrawStars;
var
  C: TJSHTMLCanvasElement;
  Ctx: TCtx;
  W, H, I, N: Integer;
  Seed, X, Y, R, A: Double;
  G: TJSCanvasGradient;
begin
  C := TJSHTMLCanvasElement(document.getElementById('cv-stars'));
  if C = nil then
    Exit;
  W := window.innerWidth;
  H := window.innerHeight;
  C.width := W;
  C.height := H;
  Ctx := C.getContextAs2DContext('2d');
  G := Ctx.createLinearGradient(0, 0, 0, H);
  G.addColorStop(0, '#0a1226');
  G.addColorStop(1, '#05070e');
  Ctx.fillStyle := G;
  Ctx.fillRect(0, 0, W, H);
  Seed := 20261114;
  N := (W * H) div 5200;
  for I := 1 to N do
  begin
    X := NextRand(Seed) * W;
    Y := NextRand(Seed) * H;
    R := 0.3 + NextRand(Seed) * 1.0;
    A := 0.2 + NextRand(Seed) * 0.6;
    if I mod 9 = 0 then
      Disc(Ctx, X, Y, R, Rgba(160, 200, 255, A))
    else if I mod 13 = 0 then
      Disc(Ctx, X, Y, R, Rgba(255, 225, 180, A))
    else
      Disc(Ctx, X, Y, R, Rgba(255, 255, 255, A));
  end;
end;

{ ---- worlds ------------------------------------------------------------ }

procedure Shade(Ctx: TCtx; Cx, Cy, R: Double);
var
  G: TJSCanvasGradient;
begin
  { Night side: the Sun is always to the left. }
  G := Ctx.createLinearGradient(Cx - R, 0, Cx + R, 0);
  G.addColorStop(0, 'rgba(0,0,0,0)');
  G.addColorStop(0.5, 'rgba(0,0,0,0.08)');
  G.addColorStop(1, 'rgba(0,0,0,0.82)');
  Ctx.fillStyle := G;
  Ctx.fillRect(Cx - R, Cy - R, 2 * R, 2 * R);
end;

procedure Blob(Ctx: TCtx; X, Y, Rx, Ry, Rot: Double; const Fill: string);
begin
  Ctx.beginPath;
  Ctx.ellipse(X, Y, Rx, Ry, Rot, 0, 2 * Pi);
  Ctx.fillStyle := Fill;
  Ctx.fill;
end;

procedure DrawBody(Ctx: TCtx; const Body: string; Cx, Cy, R: Double);
var
  G: TJSCanvasGradient;
  I: Integer;
  Seed, A, Rr, X, Y: Double;
begin
  Ctx.save;
  Ctx.beginPath;
  if Body = 'Apophis' then
  begin
    { A lumpy rock, not a sphere. }
    Seed := 99942;
    for I := 0 to 11 do
    begin
      A := I / 12 * 2 * Pi;
      Rr := R * (0.78 + 0.3 * NextRand(Seed));
      if I = 0 then
        Ctx.moveTo(Cx + Rr * Cos(A) * 1.25, Cy + Rr * Sin(A) * 0.85)
      else
        Ctx.lineTo(Cx + Rr * Cos(A) * 1.25, Cy + Rr * Sin(A) * 0.85);
    end;
    Ctx.closePath;
  end
  else
    Ctx.arc(Cx, Cy, R, 0, 2 * Pi);
  Ctx.clip;

  G := Ctx.createRadialGradient(Cx - R * 0.35, Cy - R * 0.35, R * 0.1, Cx, Cy, R * 1.3);
  if Body = 'Earth' then
  begin
    G.addColorStop(0, '#8fd8ff');
    G.addColorStop(0.55, '#2f7fdc');
    G.addColorStop(1, '#0f3272');
  end
  else if Body = 'Moon' then
  begin
    G.addColorStop(0, '#f2f2f2');
    G.addColorStop(0.6, '#a9adb5');
    G.addColorStop(1, '#5d626c');
  end
  else if Body = 'Mars' then
  begin
    G.addColorStop(0, '#ffb991');
    G.addColorStop(0.55, '#d2603a');
    G.addColorStop(1, '#74290f');
  end
  else if Body = 'Jupiter' then
  begin
    G.addColorStop(0, '#f1dcb9');
    G.addColorStop(1, '#b98a5c');
  end
  else if Body = 'Europa' then
  begin
    G.addColorStop(0, '#fff7e6');
    G.addColorStop(0.6, '#d3bf9f');
    G.addColorStop(1, '#7c6649');
  end
  else
  begin
    G.addColorStop(0, '#cfc5b3');
    G.addColorStop(0.6, '#857b6b');
    G.addColorStop(1, '#40392f');
  end;
  Ctx.fillStyle := G;
  Ctx.fillRect(Cx - R * 1.4, Cy - R * 1.4, R * 2.8, R * 2.8);

  if Body = 'Earth' then
  begin
    Blob(Ctx, Cx - R * 0.28, Cy - R * 0.22, R * 0.34, R * 0.24, 0.5, 'rgba(70,150,90,0.85)');
    Blob(Ctx, Cx + R * 0.2, Cy + R * 0.12, R * 0.26, R * 0.4, -0.3, 'rgba(84,150,84,0.85)');
    Blob(Ctx, Cx - R * 0.15, Cy + R * 0.5, R * 0.22, R * 0.12, 0.2, 'rgba(160,140,90,0.8)');
    Blob(Ctx, Cx + R * 0.5, Cy - R * 0.4, R * 0.2, R * 0.13, 0.8, 'rgba(70,150,90,0.8)');
    Blob(Ctx, Cx, Cy - R * 0.93, R * 0.5, R * 0.12, 0, 'rgba(255,255,255,0.9)');
    Blob(Ctx, Cx, Cy + R * 0.95, R * 0.55, R * 0.13, 0, 'rgba(255,255,255,0.9)');
    Blob(Ctx, Cx - R * 0.1, Cy - R * 0.02, R * 0.55, R * 0.06, -0.25, 'rgba(255,255,255,0.35)');
    Blob(Ctx, Cx + R * 0.25, Cy - R * 0.55, R * 0.4, R * 0.05, 0.3, 'rgba(255,255,255,0.3)');
  end
  else if (Body = 'Moon') or (Body = 'Apophis') then
  begin
    Seed := 1737;
    if Body = 'Moon' then
    begin
      Blob(Ctx, Cx - R * 0.3, Cy - R * 0.25, R * 0.36, R * 0.26, 0.4, 'rgba(70,74,84,0.4)');
      Blob(Ctx, Cx + R * 0.15, Cy + R * 0.05, R * 0.25, R * 0.2, -0.2, 'rgba(70,74,84,0.35)');
    end;
    for I := 1 to 16 do
    begin
      X := Cx + (NextRand(Seed) * 2 - 1) * R * 0.9;
      Y := Cy + (NextRand(Seed) * 2 - 1) * R * 0.9;
      Rr := R * (0.03 + 0.08 * NextRand(Seed));
      Disc(Ctx, X, Y, Rr, 'rgba(40,42,50,0.35)');
      Disc(Ctx, X - Rr * 0.2, Y - Rr * 0.2, Rr * 0.7, 'rgba(255,255,255,0.08)');
    end;
  end
  else if Body = 'Mars' then
  begin
    Blob(Ctx, Cx - R * 0.2, Cy + R * 0.1, R * 0.45, R * 0.18, 0.2, 'rgba(96,36,18,0.45)');
    Blob(Ctx, Cx + R * 0.35, Cy - R * 0.25, R * 0.25, R * 0.14, -0.4, 'rgba(96,36,18,0.4)');
    Blob(Ctx, Cx + R * 0.1, Cy + R * 0.55, R * 0.3, R * 0.1, 0.1, 'rgba(96,36,18,0.35)');
    Blob(Ctx, Cx, Cy - R * 0.95, R * 0.34, R * 0.1, 0, 'rgba(255,255,255,0.92)');
  end
  else if Body = 'Jupiter' then
  begin
    for I := -5 to 5 do
      if I mod 2 = 0 then
      begin
        Ctx.fillStyle := 'rgba(150,96,58,0.45)';
        Ctx.fillRect(Cx - R * 1.4, Cy + I * R * 0.17 - R * 0.06, R * 2.8, R * 0.12);
      end;
    Blob(Ctx, Cx + R * 0.3, Cy + R * 0.28, R * 0.2, R * 0.1, 0, 'rgba(190,80,50,0.75)');
  end
  else if Body = 'Europa' then
  begin
    Ctx.strokeStyle := 'rgba(140,82,52,0.55)';
    Ctx.lineWidth := Max(0.8, R * 0.025);
    Seed := 1561;
    for I := 1 to 9 do
    begin
      Ctx.beginPath;
      Ctx.moveTo(Cx - R, Cy + (NextRand(Seed) * 2 - 1) * R);
      Ctx.quadraticCurveTo(Cx + (NextRand(Seed) - 0.5) * R, Cy + (NextRand(Seed) * 2 - 1) * R,
        Cx + R, Cy + (NextRand(Seed) * 2 - 1) * R);
      Ctx.stroke;
    end;
  end;
  Shade(Ctx, Cx, Cy, R * 1.3);
  Ctx.restore;
  if Body = 'Earth' then
  begin
    Ctx.beginPath;
    Ctx.arc(Cx, Cy, R + 1.5, 0, 2 * Pi);
    Ctx.strokeStyle := 'rgba(120,200,255,0.35)';
    Ctx.lineWidth := 2.5;
    Ctx.stroke;
  end;
end;

procedure DrawSunHint(Ctx: TCtx; H: Double);
var
  I: Integer;
begin
  { Rays coming in from the left edge, to show where the Sun is. }
  Ctx.strokeStyle := 'rgba(255,214,120,0.5)';
  Ctx.lineWidth := 1;
  for I := 0 to 4 do
    Line(Ctx, 4, H * (0.26 + I * 0.12), 22, H * (0.26 + I * 0.12));
  Txt(Ctx, 'SUN', 6, H * 0.2, FontSmall, 'rgba(255,214,120,0.8)', 'left');
end;

{ ---- orbit view -------------------------------------------------------- }

procedure OrbitPoint(Nu, Rp, Ra, Inc, Omega: Double; out X, Y, Depth, Xs, Dist: Double);
var
  A, E, R, Px, Py, Y3, Z3, Phi: Double;
begin
  A := (Rp + Ra) / 2;
  E := 0;
  if Ra + Rp > 0 then
    E := (Ra - Rp) / (Ra + Rp);
  R := A * (1 - E * E) / (1 + E * Cos(Nu));
  Px := R * Cos(Nu + Omega);
  Py := R * Sin(Nu + Omega);
  { Tilt the orbit plane by its inclination, then look from 18 degrees above. }
  Y3 := Py * Cos(Inc);
  Z3 := Py * Sin(Inc);
  Phi := 18 * Pi / 180;
  X := Px;
  Depth := Y3 * Cos(Phi) + Z3 * Sin(Phi);
  Y := -(-Y3 * Sin(Phi) + Z3 * Cos(Phi));
  Xs := Px;                         // distance along the Sun line
  Dist := Sqrt(Y3 * Y3 + Z3 * Z3);  // distance from the Sun line
end;

procedure DrawRing(Ctx: TCtx; Cx, Cy, Rb, Rp, Ra, Inc, Omega: Double; Front: Boolean; const Color: string);
var
  I: Integer;
  Nu, X, Y, Dp, Xs, Ds, X2, Y2, Dp2, Xs2, Ds2: Double;
  Hidden, Dark: Boolean;
begin
  Ctx.lineWidth := 1.6;
  for I := 0 to 143 do
  begin
    Nu := I / 144 * 2 * Pi;
    OrbitPoint(Nu, Rp, Ra, Inc, Omega, X, Y, Dp, Xs, Ds);
    OrbitPoint((I + 1) / 144 * 2 * Pi, Rp, Ra, Inc, Omega, X2, Y2, Dp2, Xs2, Ds2);
    if (Dp <= 0) <> Front then
      Continue;
    Hidden := (Dp > 0) and (Sqrt(X * X + Y * Y) < Rb);
    if Hidden then
      Continue;
    Dark := (Xs > 0) and (Ds < Rb);   // in the world's shadow
    if Dark then
      Ctx.strokeStyle := 'rgba(120,130,160,0.55)'
    else if Front then
      Ctx.strokeStyle := Color
    else
      Ctx.strokeStyle := ColDim;
    Line(Ctx, Cx + X, Cy + Y, Cx + X2, Cy + Y2);
  end;
end;

procedure DrawProbe(Ctx: TCtx; X, Y: Double; Lit: Boolean);
begin
  if Lit then
    Ctx.fillStyle := '#ffffff'
  else
    Ctx.fillStyle := '#7f8aa6';
  Ctx.fillRect(X - 2.5, Y - 2.5, 5, 5);
  Ctx.fillStyle := ColLine;
  Ctx.fillRect(X - 8, Y - 1, 5, 2);
  Ctx.fillRect(X + 3, Y - 1, 5, 2);
end;

function ScaleAlt(AltKm, BodyKm: Double): Double;
begin
  { Squeeze huge altitude ranges onto one picture: low orbits hug the world,
    high ones sit further out, but not to true scale. }
  Result := 1.28 + 1.25 * Log10(1 + 1.2 * AltKm / BodyKm);
end;

procedure DrawOrbitView(Ctx: TCtx; W, H: Double; const D: TDesign; T: Double);
var
  Sc: TScenario;
  O: TOrbit;
  Cx, Cy, Rb, BodyKm, Rp, Ra, Lim, Inc, Omega, Tvis, M, Nu, E: Double;
  X, Y, Dp, Xs, Ds, F: Double;
  Body, Label2: string;
  Flyby, AtJupiter: Boolean;
begin
  Sc := Scenarios[D.Scenario];
  O := Sc.Orbits[D.Orbit];
  Ctx.clearRect(0, 0, W, H);
  Cx := W * 0.5;
  Cy := H * 0.52;
  Rb := Min(W, H) * 0.17;
  Lim := Min(W * 0.47, H * 0.46);
  Body := Sc.Body;
  BodyKm := 6371;
  if Body = 'Moon' then BodyKm := 1737
  else if Body = 'Mars' then BodyKm := 3390
  else if Body = 'Apophis' then BodyKm := 0.17
  else if Body = 'Europa' then BodyKm := 1561;
  Flyby := O.TauFactor < 0.1;
  AtJupiter := (Sc.Id = 'europa') and (O.Id <> 'orbiter');
  DrawSunHint(Ctx, H);

  if Flyby then
  begin
    { One fast pass: a straight line that sweeps by the asteroid. }
    DrawBody(Ctx, Body, Cx, Cy + H * 0.1, Rb * 0.8);
    Ctx.strokeStyle := ColLine;
    Ctx.lineWidth := 1.6;
    Ctx.setLineDash([5, 4]);
    Line(Ctx, 30, Cy - H * 0.3, W - 10, Cy - H * 0.12);
    Ctx.setLineDash([]);
    F := Frac(T / 6);
    DrawProbe(Ctx, 30 + F * (W - 40), Cy - H * 0.3 + F * H * 0.18, True);
    Txt(Ctx, 'One pass at several km/s', W - 8, H - 10, FontSmall, ColMuted, 'right');
    Txt(Ctx, UpperCase(Body), 30, H - 10, FontBig, ColText, 'left');
    Exit;
  end;

  if AtJupiter then
  begin
    { The spacecraft orbits Jupiter and meets Europa on the way round. }
    Body := 'Jupiter';
    Rb := Min(W, H) * 0.2;
    Ra := Lim;
    if O.Id = 'tour' then
    begin
      Rp := Rb * 1.9;
      Inc := 8 * Pi / 180;
    end
    else
    begin
      Rp := Rb * 1.15;
      Inc := 88 * Pi / 180;
    end;
    Omega := 0;
    { Europa's own orbit around Jupiter }
    DrawRing(Ctx, Cx, Cy, Rb, Rb * 1.9, Rb * 1.9, 2 * Pi / 180, 0, False, 'rgba(255,255,255,0.25)');
    DrawRing(Ctx, Cx, Cy, Rb, Rp, Ra, Inc, Omega, False, ColLine);
    DrawBody(Ctx, Body, Cx, Cy, Rb);
    DrawRing(Ctx, Cx, Cy, Rb, Rb * 1.9, Rb * 1.9, 2 * Pi / 180, 0, True, 'rgba(255,255,255,0.4)');
    DrawRing(Ctx, Cx, Cy, Rb, Rp, Ra, Inc, Omega, True, ColLine);
    OrbitPoint(Frac(T / 23) * 2 * Pi, Rb * 1.9, Rb * 1.9, 2 * Pi / 180, 0, X, Y, Dp, Xs, Ds);
    if not ((Dp > 0) and (Sqrt(X * X + Y * Y) < Rb)) then
    begin
      Disc(Ctx, Cx + X, Cy + Y, 4, '#f3e6cc');
      Txt(Ctx, 'Europa', Cx + X + 7, Cy + Y - 6, FontSmall, ColMuted, 'left');
    end;
    Tvis := 11;
  end
  else
  begin
    Rp := Rb * ScaleAlt(O.AltKm, BodyKm);
    Ra := Rb * ScaleAlt(O.ApoKm, BodyKm);
    if Ra > Lim then
    begin
      Rp := Rp * Lim / Ra;
      if Rp < Rb * 1.12 then
        Rp := Rb * 1.12;
      Ra := Lim;
    end;
    Inc := O.IncDeg * Pi / 180;
    if Inc > Pi / 2 then
      Inc := Pi / 2 - (Inc - Pi / 2);
    Omega := -Pi / 2;   // lowest point at the bottom (south) for tilted, stretched orbits
    if O.IncDeg < 10 then
      Omega := 0;
    if Sc.Id = 'europa' then
      DrawBody(Ctx, 'Jupiter', W * 0.93, H * 0.12, Min(W, H) * 0.3);
    DrawRing(Ctx, Cx, Cy, Rb, Rp, Ra, Inc, Omega, False, ColLine);
    DrawBody(Ctx, Body, Cx, Cy, Rb);
    DrawRing(Ctx, Cx, Cy, Rb, Rp, Ra, Inc, Omega, True, ColLine);
    Tvis := Max(4, Min(14, 3 + 2.2 * Ln(1 + O.PeriodHr)));
  end;

  { The spacecraft, moving faster when it is low (Kepler's second law). }
  E := 0;
  if Ra + Rp > 0 then
    E := (Ra - Rp) / (Ra + Rp);
  M := Frac(T / Tvis) * 2 * Pi;
  Nu := M + 2 * E * Sin(M) + 1.25 * E * E * Sin(2 * M);
  OrbitPoint(Nu, Rp, Ra, Inc, Omega, X, Y, Dp, Xs, Ds);
  if not ((Dp > 0) and (Sqrt(X * X + Y * Y) < Rb)) then
    DrawProbe(Ctx, Cx + X, Cy + Y, not ((Xs > 0) and (Ds < Rb)));

  Txt(Ctx, UpperCase(Sc.Body), 30, H - 26, FontBig, ColText, 'left');
  if O.ApoKm > O.AltKm * 1.05 then
    Label2 := FmtNum(O.AltKm, 0) + ' x ' + FmtNum(O.ApoKm, 0) + ' km'
  else
    Label2 := FmtNum(O.AltKm, 0) + ' km';
  Txt(Ctx, Label2 + '  |  tilt ' + FmtNum(O.IncDeg, 0) + ' deg  |  one lap ' + FmtAuto(O.PeriodHr) + ' h',
    30, H - 10, FontSmall, ColMuted, 'left');
  Ctx.fillStyle := 'rgba(120,130,160,0.9)';
  Ctx.fillRect(W - 150, H - 17, 14, 3);
  Txt(Ctx, 'in shadow ' + FmtPct(O.EclipseFrac), W - 132, H - 10, FontSmall, ColMuted, 'left');
end;

{ ---- spacecraft blueprint ---------------------------------------------- }

function InstrCode(const Id: string): string;
begin
  if Id = 'cam_ctx' then Result := 'CAM'
  else if Id = 'cam_hires' then Result := 'TELE'
  else if Id = 'spec_vnir' then Result := 'SPEC'
  else if Id = 'tir' then Result := 'TIR'
  else if Id = 'sar' then Result := 'RADAR'
  else if Id = 'lidar' then Result := 'LIDAR'
  else if Id = 'neutron' then Result := 'NEUT'
  else if Id = 'mag' then Result := 'MAG'
  else if Id = 'plasma' then Result := 'PLAS'
  else if Id = 'massspec' then Result := 'MASS'
  else if Id = 'radiometer' then Result := 'MWR'
  else if Id = 'uvs' then Result := 'UV'
  else if Id = 'dust' then Result := 'DUST'
  else if Id = 'radio' then Result := 'RSCI'
  else if Id = 'relay' then Result := 'RELAY'
  else Result := '?';
end;

procedure DrawCraft(Ctx: TCtx; W, H: Double; const D: TDesign; const A: TAnalysis);
var
  Bus, Prop, Ant, Shield, Band: TPart;
  Cx, Cy, Bw, Bh, Pm, WingH, WingL, MaxL, AreaHalf, DishW, X, Y, Bx, By: Double;
  I, N, Seg, K, Col, PerRow: Integer;
  Scaled: Boolean;
  Code: string;
begin
  Bus := Parts[pkBus][D.Part[pkBus]];
  Prop := Parts[pkPropulsion][D.Part[pkPropulsion]];
  Ant := Parts[pkAntenna][D.Part[pkAntenna]];
  Shield := Parts[pkShield][D.Part[pkShield]];
  Band := Parts[pkBand][D.Part[pkBand]];
  Ctx.clearRect(0, 0, W, H);

  { blueprint grid }
  Ctx.strokeStyle := 'rgba(90,209,255,0.07)';
  Ctx.lineWidth := 1;
  I := 0;
  while I * 17 < W do
  begin
    Line(Ctx, I * 17 + 0.5, 0, I * 17 + 0.5, H);
    Inc(I);
  end;
  I := 0;
  while I * 17 < H do
  begin
    Line(Ctx, 0, I * 17 + 0.5, W, I * 17 + 0.5);
    Inc(I);
  end;

  Cx := W / 2;
  Cy := H * 0.5;
  case Bus.Tier of
    0: begin Bw := 30; Pm := 40; end;
    1: begin Bw := 48; Pm := 17; end;
    2: begin Bw := 66; Pm := 9.5; end;
  else
    begin Bw := 84; Pm := 6.5; end;
  end;
  Bh := Bw * 1.15;

  { solar wings: sized from the real array area }
  Scaled := False;
  if D.SolarM2 > 0 then
  begin
    AreaHalf := D.SolarM2 / 2;
    WingH := Sqrt(AreaHalf / 2.6) * Pm;        // wings are about 2.6 times longer than tall
    WingL := 2.6 * Sqrt(AreaHalf / 2.6) * Pm;
    MaxL := W / 2 - Bw / 2 - 16;
    if WingL > MaxL then
    begin
      WingH := WingH * MaxL / WingL;
      WingL := MaxL;
      Scaled := True;
    end;
    if WingH > H * 0.5 then
      WingH := H * 0.5;
    if WingH < 5 then
      WingH := 5;
    Seg := Round(WingL / Max(10, WingH * 0.8));
    if Seg < 1 then
      Seg := 1;
    for K := 0 to 1 do
    begin
      if K = 0 then
        X := Cx - Bw / 2 - 8 - WingL
      else
        X := Cx + Bw / 2 + 8;
      Ctx.fillStyle := 'rgba(40,90,170,0.45)';
      Ctx.fillRect(X, Cy - WingH / 2, WingL, WingH);
      Ctx.strokeStyle := ColLine;
      Ctx.lineWidth := 1.2;
      Ctx.strokeRect(X, Cy - WingH / 2, WingL, WingH);
      Ctx.strokeStyle := 'rgba(90,209,255,0.45)';
      for I := 1 to Seg - 1 do
        Line(Ctx, X + I * WingL / Seg, Cy - WingH / 2, X + I * WingL / Seg, Cy + WingH / 2);
      Ctx.strokeStyle := ColLine;
      if K = 0 then
        Line(Ctx, X + WingL, Cy, Cx - Bw / 2, Cy)
      else
        Line(Ctx, Cx + Bw / 2, Cy, X, Cy);
    end;
  end;

  { nuclear batteries on a boom }
  for I := 0 to D.RtgCount - 1 do
  begin
    X := Cx + Bw / 2 + 14 + I * 13;
    Y := Cy + Bh / 2 + 6;
    Ctx.strokeStyle := '#ffb547';
    Ctx.lineWidth := 1.2;
    Line(Ctx, Cx + Bw / 2, Cy + Bh / 2 - 4, X, Y);
    Ctx.fillStyle := 'rgba(255,181,71,0.25)';
    Ctx.fillRect(X - 4, Y, 8, 22);
    Ctx.strokeRect(X - 4, Y, 8, 22);
    Line(Ctx, X - 7, Y + 5, X + 7, Y + 5);
    Line(Ctx, X - 7, Y + 11, X + 7, Y + 11);
    Line(Ctx, X - 7, Y + 17, X + 7, Y + 17);
  end;

  { engine }
  if Prop.Tier > 0 then
  begin
    Ctx.strokeStyle := ColLine;
    Ctx.lineWidth := 1.2;
    Y := Cy + Bh / 2;
    if Prop.Tier = 4 then
    begin
      Ctx.fillStyle := 'rgba(90,209,255,0.35)';
      Ctx.fillRect(Cx - 7, Y, 14, 6);
      Ctx.strokeRect(Cx - 7, Y, 14, 6);
      Ctx.fillStyle := 'rgba(120,230,255,0.25)';
      Ctx.beginPath;
      Ctx.moveTo(Cx - 6, Y + 6);
      Ctx.lineTo(Cx + 6, Y + 6);
      Ctx.lineTo(Cx, Y + 26);
      Ctx.closePath;
      Ctx.fill;
    end
    else
    begin
      K := 5 + Prop.Tier * 2;
      Ctx.beginPath;
      Ctx.moveTo(Cx - K * 0.5, Y);
      Ctx.lineTo(Cx + K * 0.5, Y);
      Ctx.lineTo(Cx + K, Y + K * 1.3);
      Ctx.lineTo(Cx - K, Y + K * 1.3);
      Ctx.closePath;
      Ctx.fillStyle := 'rgba(147,164,195,0.25)';
      Ctx.fill;
      Ctx.stroke;
    end;
  end;

  { the bus itself }
  Bx := Cx - Bw / 2;
  By := Cy - Bh / 2;
  Ctx.fillStyle := 'rgba(19,28,48,0.95)';
  Ctx.fillRect(Bx, By, Bw, Bh);
  Ctx.strokeStyle := ColLine;
  Ctx.lineWidth := 1.6;
  Ctx.strokeRect(Bx, By, Bw, Bh);
  if Shield.Tier = 2 then
  begin
    Ctx.strokeStyle := '#ffb547';
    Ctx.lineWidth := 2;
    Ctx.strokeRect(Bx + 4, By + 4, Bw - 8, Bh - 8);
  end
  else if Shield.Tier = 1 then
  begin
    Ctx.strokeStyle := 'rgba(255,181,71,0.6)';
    Ctx.lineWidth := 1;
    Ctx.setLineDash([3, 3]);
    Ctx.strokeRect(Bx + 4, By + 4, Bw - 8, Bh - 8);
    Ctx.setLineDash([]);
  end;

  { antenna on top }
  Ctx.strokeStyle := ColLine;
  Ctx.lineWidth := 1.4;
  if Band.Tier = 4 then
  begin
    Ctx.fillStyle := 'rgba(196,161,255,0.4)';
    Ctx.fillRect(Cx - 5, By - 10, 10, 10);
    Ctx.strokeStyle := '#c4a1ff';
    Ctx.strokeRect(Cx - 5, By - 10, 10, 10);
    Ctx.setLineDash([2, 3]);
    Line(Ctx, Cx, By - 10, Cx + 26, By - 40);
    Ctx.setLineDash([]);
  end
  else if Ant.A < 0.3 then
  begin
    Ctx.fillStyle := 'rgba(90,209,255,0.3)';
    Ctx.fillRect(Cx - 5, By - 4, 10, 4);
    Ctx.strokeRect(Cx - 5, By - 4, 10, 4);
  end
  else
  begin
    DishW := Max(12, Ant.A * Pm);
    if DishW > W * 0.5 then
      DishW := W * 0.5;
    Ctx.beginPath;
    Ctx.ellipse(Cx, By - 6, DishW / 2, Max(3, DishW * 0.17), 0, 0, Pi);
    Ctx.fillStyle := 'rgba(90,209,255,0.18)';
    Ctx.fill;
    Ctx.stroke;
    Line(Ctx, Cx - DishW / 2, By - 6, Cx + DishW / 2, By - 6);
    Line(Ctx, Cx, By - 6, Cx, By - 6 - Max(6, DishW * 0.3));
    Disc(Ctx, Cx, By - 6 - Max(6, DishW * 0.3), 1.8, ColLine);
  end;

  { instruments: one labelled box each }
  N := A.InstrumentCount;
  if N > 0 then
  begin
    PerRow := 2;
    if Bus.Tier >= 2 then
      PerRow := 3;
    if Bus.Tier = 0 then
      PerRow := 1;
    Col := 0;
    K := 0;
    for I := 0 to High(Instruments) do
      if (I <= High(A.InstrQuality)) and (A.InstrQuality[I] > 0) then
      begin
        X := Bx + 4 + Col * ((Bw - 8) / PerRow);
        Y := By + 5 + K * 11;
        if Y + 10 > By + Bh - 2 then
          Break;
        if A.InstrQuality[I] < 1 then
          Ctx.fillStyle := 'rgba(255,181,71,0.35)'
        else
          Ctx.fillStyle := 'rgba(196,161,255,0.35)';
        Ctx.fillRect(X, Y, (Bw - 8) / PerRow - 2, 9);
        Code := InstrCode(Instruments[I].Id);
        if (Bw - 8) / PerRow < 26 then
          Code := Copy(Code, 1, 3);
        Txt(Ctx, Code, X + ((Bw - 8) / PerRow - 2) / 2, Y + 7.5, '7px ui-monospace, Consolas, monospace', '#ffffff', 'center');
        Inc(Col);
        if Col >= PerRow then
        begin
          Col := 0;
          Inc(K);
        end;
      end;
  end;

  Txt(Ctx, UpperCase(Bus.Name), 8, 16, FontSmall, ColMuted, 'left');
  Txt(Ctx, 'dry ' + FmtMass(A.DryKg) + '  fuel ' + FmtMass(A.PropKg), 8, H - 8, FontSmall, ColMuted, 'left');
  if Scaled then
    Txt(Ctx, 'wings not to scale', W - 8, 16, FontSmall, ColMuted, 'right')
  else if D.SolarM2 > 0 then
    Txt(Ctx, FmtNum(D.SolarM2, 1) + ' m2 solar', W - 8, 16, FontSmall, ColMuted, 'right');
  if D.RtgCount > 0 then
    Txt(Ctx, IntToStr(D.RtgCount) + ' x RTG', W - 8, H - 8, FontSmall, '#ffb547', 'right');
end;

{ ---- Earth map with real events ---------------------------------------- }

function CategoryColor(const Cat: string): string;
begin
  if Cat = 'wildfires' then Result := '#ff8a4c'
  else if Cat = 'severeStorms' then Result := '#8fb4ff'
  else if Cat = 'floods' then Result := '#38d6f8'
  else if Cat = 'seaLakeIce' then Result := '#ffffff'
  else if Cat = 'volcanoes' then Result := '#ff4d6d'
  else Result := '#c4a1ff';
end;

procedure DrawEarthMap(Ctx: TCtx; W, H: Double; const D: TDesign; ShowOrbit: Boolean);
var
  Sc: TScenario;
  O: TOrbit;
  I: Integer;
  X, Y, Lim, A, Lat, Lon, Ang, Az, La, Lo, IncEff, Th, La0, Lo0: Double;
  Vis: Boolean;
begin
  Sc := Scenarios[D.Scenario];
  O := Sc.Orbits[D.Orbit];
  if Ready(ImgMap) then
    Ctx.drawImage(ImgMap, 0, 0, W, H)
  else
  begin
    Ctx.fillStyle := '#0b2545';
    Ctx.fillRect(0, 0, W, H);
  end;
  Ctx.fillStyle := 'rgba(4,8,18,0.35)';
  Ctx.fillRect(0, 0, W, H);

  { graticule }
  Ctx.strokeStyle := 'rgba(255,255,255,0.10)';
  Ctx.lineWidth := 1;
  for I := 1 to 5 do
    Line(Ctx, 0, I * H / 6, W, I * H / 6);
  for I := 1 to 11 do
    Line(Ctx, I * W / 12, 0, I * W / 12, H);

  if ShowOrbit then
  begin
    Ctx.fillStyle := 'rgba(2,5,12,0.62)';
    if O.IsGeo then
    begin
      { Darken everything outside the disc a geostationary satellite can see. }
      Ctx.beginPath;
      Ctx.rect(0, 0, W, H);
      La0 := 0;
      Lo0 := O.GeoLon * Pi / 180;
      Ang := 62 * Pi / 180;
      for I := 0 to 72 do
      begin
        Az := I / 72 * 2 * Pi;
        La := ArcSin(Sin(La0) * Cos(Ang) + Cos(La0) * Sin(Ang) * Cos(Az));
        Lo := Lo0 + ArcTan2(Sin(Az) * Sin(Ang) * Cos(La0), Cos(Ang) - Sin(La0) * Sin(La));
        X := (Lo * 180 / Pi + 180) / 360 * W;
        Y := (90 - La * 180 / Pi) / 180 * H;
        if I = 0 then
          Ctx.moveTo(X, Y)
        else
          Ctx.lineTo(X, Y);
      end;
      Ctx.closePath;
      Ctx.fill('evenodd');
      Disc(Ctx, (O.GeoLon + 180) / 360 * W, H / 2, 4, '#ffffff');
    end
    else
    begin
      if O.IncDeg >= 90 then
        Lim := 86
      else
        Lim := O.IncDeg + 4;
      Y := (90 - Lim) / 180 * H;
      Ctx.fillRect(0, 0, W, Y);
      Ctx.fillRect(0, H - Y, W, Y);
      Ctx.strokeStyle := 'rgba(90,209,255,0.8)';
      Ctx.setLineDash([6, 5]);
      Line(Ctx, 0, Y, W, Y);
      Line(Ctx, 0, H - Y, W, H - Y);
      Ctx.setLineDash([]);
      { two laps of ground track }
      IncEff := O.IncDeg;
      if IncEff > 90 then
        IncEff := 180 - IncEff;
      Ctx.strokeStyle := 'rgba(90,209,255,0.55)';
      Ctx.lineWidth := 1.3;
      Ctx.beginPath;
      for I := 0 to 240 do
      begin
        Th := I / 120 * 2 * Pi;
        Lat := ArcSin(Sin(IncEff * Pi / 180) * Sin(Th)) * 180 / Pi;
        Lon := -180 + Frac(I / 120 * (1 - O.PeriodHr / 24) + 0.08) * 360;
        X := (Lon + 180) / 360 * W;
        Y := (90 - Lat) / 180 * H;
        if (I = 0) or (I = 120) or (Abs(Lon - Lo0) > 180) then
          Ctx.moveTo(X, Y)
        else
          Ctx.lineTo(X, Y);
        Lo0 := Lon;
      end;
      Ctx.stroke;
    end;
  end;

  { the real events }
  for I := 0 to High(EarthEvents) do
  begin
    X := (EarthEvents[I].Lon + 180) / 360 * W;
    Y := (90 - EarthEvents[I].Lat) / 180 * H;
    Vis := (not ShowOrbit) or EventVisible(O, EarthEvents[I].Lat, EarthEvents[I].Lon);
    if Vis then
      A := 0.95
    else
      A := 0.3;
    Ctx.globalAlpha := A;
    if Vis then
      Disc(Ctx, X, Y, 2.4, CategoryColor(EarthEvents[I].Category))
    else
      Disc(Ctx, X, Y, 1.6, CategoryColor(EarthEvents[I].Category));
  end;
  Ctx.globalAlpha := 1;
  if ShowOrbit and (O.EventsTotal > 0) then
  begin
    Ctx.fillStyle := 'rgba(4,8,18,0.75)';
    Ctx.fillRect(6, H - 24, 232, 18);
    Txt(Ctx, 'In view: ' + IntToStr(O.EventsSeen) + ' of ' + IntToStr(O.EventsTotal) + ' real events',
      12, H - 11, FontSmall, ColText, 'left');
  end;
end;

{ ---- launch ------------------------------------------------------------ }

procedure DrawRocket(Ctx: TCtx; X, Y, Hgt, Wid: Double; Size: Integer; Boosters: Boolean; Fire: Double);
var
  G: TJSCanvasGradient;
  K: Integer;
  Bx, Fl: Double;
begin
  { exhaust plume }
  if Fire > 0 then
  begin
    Fl := Hgt * (0.55 + 0.25 * Fire);
    G := Ctx.createLinearGradient(0, Y, 0, Y + Fl);
    G.addColorStop(0, 'rgba(255,255,255,0.95)');
    G.addColorStop(0.25, 'rgba(255,220,120,0.9)');
    G.addColorStop(0.6, 'rgba(255,130,50,0.5)');
    G.addColorStop(1, 'rgba(255,90,30,0)');
    Ctx.fillStyle := G;
    Ctx.beginPath;
    Ctx.moveTo(X - Wid * 0.5, Y);
    Ctx.quadraticCurveTo(X - Wid * 1.3, Y + Fl * 0.5, X, Y + Fl);
    Ctx.quadraticCurveTo(X + Wid * 1.3, Y + Fl * 0.5, X + Wid * 0.5, Y);
    Ctx.closePath;
    Ctx.fill;
  end;
  { side boosters }
  if Boosters then
    for K := 0 to 1 do
    begin
      if K = 0 then
        Bx := X - Wid * 1.05
      else
        Bx := X + Wid * 1.05;
      Ctx.fillStyle := '#d9dee8';
      Ctx.fillRect(Bx - Wid * 0.42, Y - Hgt * 0.62, Wid * 0.84, Hgt * 0.62);
      Ctx.beginPath;
      Ctx.moveTo(Bx - Wid * 0.42, Y - Hgt * 0.62);
      Ctx.quadraticCurveTo(Bx, Y - Hgt * 0.78, Bx + Wid * 0.42, Y - Hgt * 0.62);
      Ctx.closePath;
      Ctx.fill;
      Ctx.fillStyle := '#2b3243';
      Ctx.fillRect(Bx - Wid * 0.3, Y, Wid * 0.6, Hgt * 0.035);
    end;
  { core stage }
  Ctx.fillStyle := '#eef2f8';
  Ctx.fillRect(X - Wid / 2, Y - Hgt * 0.86, Wid, Hgt * 0.86);
  { payload fairing }
  Ctx.beginPath;
  Ctx.moveTo(X - Wid * 0.6, Y - Hgt * 0.84);
  Ctx.lineTo(X - Wid * 0.6, Y - Hgt * 0.92);
  Ctx.quadraticCurveTo(X - Wid * 0.5, Y - Hgt, X, Y - Hgt * 1.03);
  Ctx.quadraticCurveTo(X + Wid * 0.5, Y - Hgt, X + Wid * 0.6, Y - Hgt * 0.92);
  Ctx.lineTo(X + Wid * 0.6, Y - Hgt * 0.84);
  Ctx.closePath;
  Ctx.fill;
  { markings }
  Ctx.fillStyle := '#2b3243';
  Ctx.fillRect(X - Wid / 2, Y - Hgt * 0.52, Wid, Hgt * 0.03);
  Ctx.fillRect(X - Wid / 2, Y - Hgt * 0.84, Wid, Hgt * 0.012);
  case Size of
    0: Ctx.fillStyle := '#1c2333';
    1: Ctx.fillStyle := '#e2572f';
    2: Ctx.fillStyle := '#5ad1ff';
  else
    Ctx.fillStyle := '#ffb547';
  end;
  Ctx.fillRect(X - Wid / 2, Y - Hgt * 0.32, Wid, Hgt * 0.05);
  { fins and engine }
  Ctx.fillStyle := '#aab3c4';
  Ctx.beginPath;
  Ctx.moveTo(X - Wid / 2, Y - Hgt * 0.1);
  Ctx.lineTo(X - Wid * 0.95, Y);
  Ctx.lineTo(X - Wid / 2, Y);
  Ctx.closePath;
  Ctx.fill;
  Ctx.beginPath;
  Ctx.moveTo(X + Wid / 2, Y - Hgt * 0.1);
  Ctx.lineTo(X + Wid * 0.95, Y);
  Ctx.lineTo(X + Wid / 2, Y);
  Ctx.closePath;
  Ctx.fill;
  Ctx.fillStyle := '#2b3243';
  Ctx.fillRect(X - Wid * 0.34, Y, Wid * 0.68, Hgt * 0.035);
  { shading down the right side so it looks round }
  G := Ctx.createLinearGradient(X - Wid / 2, 0, X + Wid / 2, 0);
  G.addColorStop(0, 'rgba(0,0,0,0)');
  G.addColorStop(1, 'rgba(0,0,0,0.3)');
  Ctx.fillStyle := G;
  Ctx.fillRect(X - Wid / 2, Y - Hgt * 0.86, Wid, Hgt * 0.86);
end;

procedure DrawLaunch(Ctx: TCtx; W, H, T: Double; Size: Integer; Fail: Boolean);
var
  G: TJSCanvasGradient;
  P, Tt, YOff, SkyA, Hgt, Wid, Rx, Ry, GroundY, Alt, Vel, Seed, Sx, Sy, Fire, BoostP, K: Double;
  I: Integer;
  Msg, Clock: string;
  Blown: Boolean;
begin
  Tt := T - 3;                       // seconds after liftoff
  P := Clamp(Tt / 10, 0, 1);         // how far through the climb
  Blown := Fail and (T >= 7.2);

  { space behind everything }
  G := Ctx.createLinearGradient(0, 0, 0, H);
  G.addColorStop(0, '#02040a');
  G.addColorStop(1, '#0b1730');
  Ctx.fillStyle := G;
  Ctx.fillRect(0, 0, W, H);
  Seed := 4242;
  for I := 1 to 90 do
  begin
    Sx := NextRand(Seed) * W;
    Sy := Frac(NextRand(Seed) + P * 0.25) * H;
    Disc(Ctx, Sx, Sy, 0.4 + NextRand(Seed), Rgba(255, 255, 255, Clamp((P - 0.3) * 1.6, 0, 0.9)));
  end;

  { the sky near the ground: NASA's photograph, sliding down as we climb }
  YOff := P * P * H * 2.4;
  SkyA := Clamp(1 - P * 1.5, 0, 1);
  if SkyA > 0 then
  begin
    Ctx.globalAlpha := SkyA;
    if Ready(ImgSky) then
      Ctx.drawImage(ImgSky, 0, -H * 0.25 + YOff * 0.35, W, H * 1.25)
    else
    begin
      G := Ctx.createLinearGradient(0, 0, 0, H);
      G.addColorStop(0, '#5a6fd0');
      G.addColorStop(1, '#f2a37c');
      Ctx.fillStyle := G;
      Ctx.fillRect(0, 0, W, H);
    end;
    Ctx.globalAlpha := 1;
  end;

  { clouds drifting past }
  for I := 0 to 2 do
    if Ready(ImgCloud[I]) and (P < 0.75) then
    begin
      Ctx.globalAlpha := Clamp(1 - P * 1.4, 0, 0.9);
      Sy := -H * (0.5 + I * 0.75) + YOff * (1.5 + I * 0.25);
      Sx := W * (0.05 + I * 0.36) - 60;
      Ctx.drawImage(ImgCloud[I], Sx, Sy, 260, 150);
      Ctx.globalAlpha := 1;
    end;

  { ground and launch tower }
  GroundY := H - 34 + YOff * 2.6;
  if GroundY < H + 60 then
  begin
    Ctx.fillStyle := '#0b0f17';
    Ctx.fillRect(0, GroundY, W, H);
    Ctx.strokeStyle := '#2a3142';
    Ctx.lineWidth := 2;
    Sx := W / 2 + 34;
    Line(Ctx, Sx, GroundY, Sx, GroundY - 170);
    Line(Ctx, Sx + 12, GroundY, Sx + 12, GroundY - 170);
    for I := 0 to 8 do
    begin
      Line(Ctx, Sx, GroundY - I * 20, Sx + 12, GroundY - I * 20 - 20);
      Line(Ctx, Sx + 12, GroundY - I * 20, Sx, GroundY - I * 20 - 20);
    end;
    if Tt < 0.4 then
      Line(Ctx, Sx, GroundY - 120, W / 2 + 8, GroundY - 120);
  end;

  case Size of
    0: begin Hgt := 96; Wid := 9; end;
    1: begin Hgt := 124; Wid := 12; end;
    2: begin Hgt := 150; Wid := 14; end;
  else
    begin Hgt := 168; Wid := 15; end;
  end;
  Rx := W / 2;
  if Tt < 0 then
    Ry := H - 36
  else
    Ry := H - 36 - Clamp(Tt / 2.2, 0, 1) * H * 0.27 - P * H * 0.06;
  if (Tt > 0) and (Tt < 3) then
    Rx := Rx + Sin(T * 55) * 0.9;   // launch vibration

  { smoke rolling out at liftoff }
  if (Tt > -0.6) and (P < 0.3) then
    for I := 0 to 9 do
    begin
      K := Clamp((Tt + 0.6) / 2.5, 0, 1);
      Disc(Ctx, W / 2 + (I - 4.5) * 26 * K, GroundY - 6 - Abs(I - 4.5) * 2, 10 + 22 * K + (I mod 3) * 5,
        Rgba(225, 225, 232, 0.5 * (1 - P * 3.2)));
    end;

  Fire := 0;
  if Tt > -0.5 then
    Fire := 0.6 + 0.4 * Sin(T * 40);
  if P >= 1 then
    Fire := 0;
  BoostP := Clamp((P - 0.6) / 0.25, 0, 1);

  if not Blown then
  begin
    DrawRocket(Ctx, Rx, Ry, Hgt, Wid, Size, (Size = 3) and (BoostP <= 0), Fire);
    { spent boosters falling away }
    if (Size = 3) and (BoostP > 0) and (BoostP < 1) then
      for I := 0 to 1 do
      begin
        Ctx.save;
        Ctx.translate(Rx + (I * 2 - 1) * (Wid * 1.05 + BoostP * 70), Ry - Hgt * 0.3 + BoostP * 90);
        Ctx.rotate((I * 2 - 1) * BoostP * 1.1);
        Ctx.fillStyle := '#d9dee8';
        Ctx.fillRect(-Wid * 0.42, -Hgt * 0.31, Wid * 0.84, Hgt * 0.62);
        Ctx.restore;
      end;
  end
  else
  begin
    { loss of vehicle }
    K := Clamp((T - 7.2) / 2.5, 0, 1);
    G := Ctx.createRadialGradient(Rx, Ry - Hgt * 0.5, 2, Rx, Ry - Hgt * 0.5, 30 + K * 190);
    G.addColorStop(0, Rgba(255, 255, 255, 0.95 * (1 - K)));
    G.addColorStop(0.4, Rgba(255, 190, 90, 0.8 * (1 - K)));
    G.addColorStop(1, 'rgba(255,90,30,0)');
    Ctx.fillStyle := G;
    Ctx.fillRect(0, 0, W, H);
    Seed := 777;
    Ctx.strokeStyle := Rgba(230, 230, 240, 1 - K);
    Ctx.lineWidth := 2;
    for I := 1 to 22 do
    begin
      Sx := (NextRand(Seed) * 2 - 1) * 240 * K;
      Sy := (NextRand(Seed) * 2 - 1) * 170 * K + K * K * 120;
      Line(Ctx, Rx + Sx, Ry - Hgt * 0.5 + Sy, Rx + Sx * 1.08 + 3, Ry - Hgt * 0.5 + Sy * 1.08 + 4);
    end;
  end;

  { flight data }
  Alt := 0;
  Vel := 0;
  if Tt > 0 then
  begin
    Alt := 1.55 * Power(Min(Tt, 10), 2.1);
    Vel := Min(7.8, 0.0125 * Power(Min(Tt, 10), 2.8));
  end;
  if Tt < 0 then
    Clock := 'T-' + IntToStr(Ceil(-Tt))
  else
    Clock := 'T+' + FmtNum(Tt * 52, 0) + ' s';
  Ctx.fillStyle := 'rgba(3,6,13,0.6)';
  Ctx.fillRect(10, 10, 168, 62);
  Txt(Ctx, Clock, 20, 30, FontBig, ColText, 'left');
  Txt(Ctx, 'altitude ' + FmtNum(Alt, 0) + ' km', 20, 47, FontMid, ColText, 'left');
  Txt(Ctx, 'speed    ' + FmtNum(Vel, 2) + ' km/s', 20, 63, FontMid, ColText, 'left');

  Msg := '';
  if Tt < 0 then Msg := 'All stations are go'
  else if Blown then Msg := 'LOSS OF VEHICLE'
  else if Tt < 1.6 then Msg := 'LIFTOFF'
  else if (Tt > 3) and (Tt < 4.6) then Msg := 'Maximum aerodynamic pressure'
  else if (Size = 3) and (P > 0.6) and (P < 0.8) then Msg := 'Booster separation'
  else if (P > 0.82) and (P < 0.97) then Msg := 'Fairing jettisoned: the spacecraft sees space'
  else if P >= 1 then Msg := 'Spacecraft separation confirmed';
  if Msg <> '' then
  begin
    Ctx.fillStyle := 'rgba(3,6,13,0.6)';
    Ctx.fillRect(W / 2 - 190, H - 30, 380, 22);
    if Blown then
      Txt(Ctx, Msg, W / 2, H - 14, FontBig, '#ff6b78', 'center')
    else
      Txt(Ctx, Msg, W / 2, H - 14, FontBig, ColText, 'center');
  end;
  Txt(Ctx, 'Sky and clouds: NASA / KSC-08pd1628', W - 8, 16, '9px ui-monospace, Consolas, monospace',
    Rgba(255, 255, 255, 0.55 * SkyA), 'right');
end;

{ ---- cruise ------------------------------------------------------------ }

procedure DrawCruise(Ctx: TCtx; W, H: Double; const S: TSimState; T: Double);
var
  Sc: TScenario;
  Cx, Cy, Scale, Re, Rt, F, A0, A1, Ang, R, X, Y, Bx: Double;
  I: Integer;
begin
  Sc := Scenarios[S.D.Scenario];
  Ctx.clearRect(0, 0, W, H);
  F := 0;
  if S.CruiseWeeks > 0 then
    F := Clamp(S.Week / S.CruiseWeeks, 0, 1);

  if Sc.Id = 'moon' then
  begin
    { Earth on the left, Moon on the right, and the path between them. }
    DrawBody(Ctx, 'Earth', W * 0.16, H * 0.56, 40);
    DrawBody(Ctx, 'Moon', W * 0.84, H * 0.44, 18);
    Ctx.strokeStyle := ColDim;
    Ctx.setLineDash([5, 5]);
    Ctx.lineWidth := 1.4;
    Ctx.beginPath;
    Ctx.moveTo(W * 0.16 + 40, H * 0.52);
    if S.D.Transfer = 1 then
      Bx := -H * 0.9   // the long looping ballistic route
    else
      Bx := H * 0.1;
    Ctx.quadraticCurveTo(W * 0.5, Bx, W * 0.84 - 20, H * 0.42);
    Ctx.stroke;
    Ctx.setLineDash([]);
    X := (1 - F) * (1 - F) * (W * 0.16 + 40) + 2 * (1 - F) * F * (W * 0.5) + F * F * (W * 0.84 - 20);
    Y := (1 - F) * (1 - F) * (H * 0.52) + 2 * (1 - F) * F * Bx + F * F * (H * 0.42);
    DrawProbe(Ctx, X, Clamp(Y, 12, H - 12), True);
    Txt(Ctx, 'EARTH TO MOON', 14, H - 12, FontBig, ColText, 'left');
    Exit;
  end;

  Cx := W * 0.5;
  Cy := H * 0.52;
  Scale := H * 0.42 / Max(1.0, Sc.SunAU);
  Re := Scale;
  Rt := Scale * Sc.SunAU;
  Disc(Ctx, Cx, Cy, 7, '#ffd678');
  Ctx.strokeStyle := 'rgba(255,255,255,0.22)';
  Ctx.lineWidth := 1;
  Ctx.beginPath;
  Ctx.arc(Cx, Cy, Re, 0, 2 * Pi);
  Ctx.stroke;
  Ctx.beginPath;
  Ctx.ellipse(Cx, Cy, Rt, Rt * 0.97, 0.3, 0, 2 * Pi);
  Ctx.stroke;

  { A simple outward spiral from Earth's orbit to the target's. }
  A0 := 2.4;
  A1 := A0 - (2.6 + 0.9 * Sc.Transfers[S.D.Transfer].CruiseYears);
  Ctx.strokeStyle := ColDim;
  Ctx.setLineDash([5, 5]);
  Ctx.lineWidth := 1.4;
  Ctx.beginPath;
  for I := 0 to 60 do
  begin
    Ang := A0 + (A1 - A0) * I / 60;
    R := Re + (Rt - Re) * (I / 60);
    if I = 0 then
      Ctx.moveTo(Cx + R * Cos(Ang), Cy + R * Sin(Ang))
    else
      Ctx.lineTo(Cx + R * Cos(Ang), Cy + R * Sin(Ang));
  end;
  Ctx.stroke;
  Ctx.setLineDash([]);
  Disc(Ctx, Cx + Re * Cos(A0 - F * 1.4), Cy + Re * Sin(A0 - F * 1.4), 4.5, '#5aa8ff');
  Txt(Ctx, 'Earth', Cx + Re * Cos(A0 - F * 1.4) + 8, Cy + Re * Sin(A0 - F * 1.4) + 4, FontSmall, ColMuted, 'left');
  Disc(Ctx, Cx + Rt * Cos(A1), Cy + Rt * Sin(A1), 4.5, '#ffb38a');
  Txt(Ctx, Sc.Body, Cx + Rt * Cos(A1) + 8, Cy + Rt * Sin(A1) + 4, FontSmall, ColMuted, 'left');
  Ang := A0 + (A1 - A0) * F;
  R := Re + (Rt - Re) * F;
  DrawProbe(Ctx, Cx + R * Cos(Ang), Cy + R * Sin(Ang), True);
  Txt(Ctx, 'CRUISE TO ' + UpperCase(Sc.Body), 14, H - 12, FontBig, ColText, 'left');
  if T < 0 then
    Exit;
end;

{ ---- charts ------------------------------------------------------------ }

procedure Series(Ctx: TCtx; const V: TDoubleArray; X0, Y0, Pw, Ph, MaxV: Double; const Color: string; Wd: Double);
var
  I, N: Integer;
begin
  N := Length(V);
  if N < 2 then
    Exit;
  Ctx.strokeStyle := Color;
  Ctx.lineWidth := Wd;
  Ctx.beginPath;
  for I := 0 to N - 1 do
    if I = 0 then
      Ctx.moveTo(X0, Y0 + Ph - Clamp(V[I] / MaxV, 0, 1) * Ph)
    else
      Ctx.lineTo(X0 + Pw * I / (N - 1), Y0 + Ph - Clamp(V[I] / MaxV, 0, 1) * Ph);
  Ctx.stroke;
end;

procedure DrawChart(Ctx: TCtx; W, H: Double; const S: TSimState);
var
  X0, Y0, Pw, Ph, MaxV, Thr: Double;
  I, N: Integer;
begin
  Ctx.clearRect(0, 0, W, H);
  X0 := 34;
  Y0 := 22;
  Pw := W - X0 - 10;
  Ph := H - Y0 - 22;
  MaxV := 100;
  if S.SciencePct > 100 then
    MaxV := Ceil(S.SciencePct / 25) * 25;
  Ctx.lineWidth := 1;
  { one grid line every 25 % }
  N := Round(MaxV / 25);
  for I := 0 to N do
  begin
    Ctx.strokeStyle := 'rgba(255,255,255,0.08)';
    Line(Ctx, X0, Y0 + Ph * I / N, X0 + Pw, Y0 + Ph * I / N);
    Txt(Ctx, FmtNum(MaxV * (N - I) / N, 0), X0 - 6, Y0 + Ph * I / N + 4, FontSmall, ColMuted, 'right');
  end;
  { the line a mission must clear to count as a success }
  Thr := Scenarios[S.D.Scenario].ThresholdPct;
  Ctx.strokeStyle := 'rgba(255,181,71,0.6)';
  Ctx.setLineDash([4, 4]);
  Line(Ctx, X0, Y0 + Ph - Thr / MaxV * Ph, X0 + Pw, Y0 + Ph - Thr / MaxV * Ph);
  Ctx.setLineDash([]);
  Txt(Ctx, 'minimum', X0 + Pw - 4, Y0 + Ph - Thr / MaxV * Ph - 4, FontSmall, 'rgba(255,181,71,0.9)', 'right');

  Series(Ctx, S.HistPower, X0, Y0, Pw, Ph, 100, 'rgba(255,181,71,0.75)', 1.2);
  Series(Ctx, S.HistData, X0, Y0, Pw, Ph, 100, 'rgba(74,222,128,0.75)', 1.2);
  Series(Ctx, S.HistScience, X0, Y0, Pw, Ph, MaxV, ColLine, 2.4);

  Ctx.fillStyle := ColLine;
  Ctx.fillRect(X0, 6, 14, 3);
  Txt(Ctx, 'science %', X0 + 19, 12, FontSmall, ColText, 'left');
  Ctx.fillStyle := 'rgba(255,181,71,0.9)';
  Ctx.fillRect(X0 + 96, 6, 14, 3);
  Txt(Ctx, 'power %', X0 + 115, 12, FontSmall, ColText, 'left');
  Ctx.fillStyle := 'rgba(74,222,128,0.9)';
  Ctx.fillRect(X0 + 180, 6, 14, 3);
  Txt(Ctx, 'data sent home %', X0 + 199, 12, FontSmall, ColText, 'left');
  Txt(Ctx, 'weeks of science: ' + IntToStr(Length(S.HistScience)), X0 + Pw, H - 6, FontSmall, ColMuted, 'right');
end;

end.
