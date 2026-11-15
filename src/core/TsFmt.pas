unit TsFmt;

{ Atomic Space - number formatting that does not depend on the computer's
  language settings, so it gives the same text in Delphi and in the browser.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

function FmtNum(X: Double; Dec: Integer): string;
function FmtAuto(X: Double): string;
function FmtMoney(M: Double): string;       // input in $ millions
function FmtMass(Kg: Double): string;
function FmtPower(W: Double): string;
function FmtPct(Fraction: Double): string;  // 0.25 -> 25 %
function FmtSignedPct(Fraction: Double): string;
function FmtYears(Y: Double): string;
function FmtRate(Mbps: Double): string;
function FmtData(Gbit: Double): string;
function FmtDv(Ms: Double): string;
function FmtDist(Km: Double): string;
function Plural(N: Integer; const One, Many: string): string;
{ Reads a number such as '5.67' the same way on every computer. }
function ParseFloat(const S: string): Double;
{ Days since 1 January 2000 for a date written as YYYY-MM-DD (0 if unreadable). }
function DayNumber(const IsoDate: string): Integer;
{ '2026-11-14' -> '14 Nov 2026' }
function NiceDate(const IsoDate: string): string;

implementation

uses
  SysUtils, TsTypes;

function FmtNum(X: Double; Dec: Integer): string;
var
  Neg: Boolean;
  Scale: Double;
  V, IntV, FracV, ScaleI: TBigInt;
  S, FracS: string;
  I, Cnt: Integer;
begin
  Neg := X < 0;
  if Neg then
    X := -X;
  Scale := 1;
  for I := 1 to Dec do
    Scale := Scale * 10;
  ScaleI := Trunc(Scale);
  V := Trunc(X * Scale + 0.5);
  IntV := V div ScaleI;
  FracV := V mod ScaleI;
  S := IntToStr(IntV);
  Result := '';
  Cnt := 0;
  for I := Length(S) downto 1 do
  begin
    Result := S[I] + Result;
    Inc(Cnt);
    if (Cnt mod 3 = 0) and (I > 1) then
      Result := ',' + Result;
  end;
  if Dec > 0 then
  begin
    FracS := IntToStr(FracV);
    while Length(FracS) < Dec do
      FracS := '0' + FracS;
    Result := Result + '.' + FracS;
  end;
  if Neg and (V <> 0) then
    Result := '-' + Result;
end;

function FmtAuto(X: Double): string;
var
  A: Double;
begin
  A := Abs(X);
  if A >= 100 then
    Result := FmtNum(X, 0)
  else if A >= 10 then
    Result := FmtNum(X, 1)
  else if A >= 1 then
    Result := FmtNum(X, 2)
  else
    Result := FmtNum(X, 3);
end;

function FmtMoney(M: Double): string;
var
  A: Double;
begin
  A := Abs(M);
  if A >= 1000 then
    Result := '$' + FmtNum(M / 1000, 2) + 'B'
  else if A >= 100 then
    Result := '$' + FmtNum(M, 0) + 'M'
  else
    Result := '$' + FmtNum(M, 1) + 'M';
end;

function FmtMass(Kg: Double): string;
var
  A: Double;
begin
  A := Abs(Kg);
  if A >= 10000 then
    Result := FmtNum(Kg / 1000, 1) + ' t'
  else if A >= 100 then
    Result := FmtNum(Kg, 0) + ' kg'
  else
    Result := FmtNum(Kg, 1) + ' kg';
end;

function FmtPower(W: Double): string;
var
  A: Double;
begin
  A := Abs(W);
  if A >= 10000 then
    Result := FmtNum(W / 1000, 1) + ' kW'
  else if A >= 100 then
    Result := FmtNum(W, 0) + ' W'
  else
    Result := FmtNum(W, 1) + ' W';
end;

function FmtPct(Fraction: Double): string;
begin
  Result := FmtNum(Fraction * 100, 0) + '%';
end;

function FmtSignedPct(Fraction: Double): string;
begin
  if Fraction >= 0 then
    Result := '+' + FmtNum(Fraction * 100, 0) + '%'
  else
    Result := FmtNum(Fraction * 100, 0) + '%';
end;

function FmtYears(Y: Double): string;
begin
  if Y < 0.095 then
    Result := FmtNum(Y * 365.25, 0) + ' days'
  else if Y < 1 then
    Result := FmtNum(Y * 12, 0) + ' months'
  else
    Result := FmtNum(Y, 1) + ' years';
end;

function FmtRate(Mbps: Double): string;
begin
  if Mbps >= 1000 then
    Result := FmtNum(Mbps / 1000, 1) + ' Gbps'
  else if Mbps >= 1 then
    Result := FmtAuto(Mbps) + ' Mbps'
  else if Mbps >= 0.001 then
    Result := FmtAuto(Mbps * 1000) + ' kbps'
  else
    Result := FmtNum(Mbps * 1000000, 0) + ' bps';
end;

function FmtData(Gbit: Double): string;
var
  GB: Double;
begin
  GB := Gbit / 8;
  if GB >= 1000 then
    Result := FmtAuto(GB / 1000) + ' TB'
  else if GB >= 1 then
    Result := FmtAuto(GB) + ' GB'
  else if GB >= 0.001 then
    Result := FmtAuto(GB * 1000) + ' MB'
  else
    Result := FmtNum(GB * 1000000, 0) + ' kB';
end;

function FmtDv(Ms: Double): string;
begin
  if Abs(Ms) >= 1000 then
    Result := FmtNum(Ms / 1000, 2) + ' km/s'
  else
    Result := FmtNum(Ms, 0) + ' m/s';
end;

function FmtDist(Km: Double): string;
begin
  if Km >= 1.0e9 then
    Result := FmtNum(Km / 1.0e9, 2) + ' billion km'
  else if Km >= 1.0e6 then
    Result := FmtNum(Km / 1.0e6, 1) + ' million km'
  else
    Result := FmtNum(Km, 0) + ' km';
end;

function Plural(N: Integer; const One, Many: string): string;
begin
  if N = 1 then
    Result := IntToStr(N) + ' ' + One
  else
    Result := IntToStr(N) + ' ' + Many;
end;

function ParseFloat(const S: string): Double;
var
  I: Integer;
  Scale: Double;
  Seen, Frac, Neg: Boolean;
begin
  Result := 0;
  Scale := 1;
  Seen := False;
  Frac := False;
  Neg := False;
  for I := 1 to Length(S) do
  begin
    if (S[I] >= '0') and (S[I] <= '9') then
    begin
      Seen := True;
      if Frac then
      begin
        Scale := Scale / 10;
        Result := Result + (Ord(S[I]) - Ord('0')) * Scale;
      end
      else
        Result := Result * 10 + (Ord(S[I]) - Ord('0'));
    end
    else if (S[I] = '.') and not Frac then
      Frac := True
    else if (S[I] = '-') and not Seen then
      Neg := True
    else if Seen then
      Break;
  end;
  if Neg then
    Result := -Result;
end;

function DayNumber(const IsoDate: string): Integer;
var
  Y, M, D, A, Yy, Mm: Integer;
begin
  Result := 0;
  if Length(IsoDate) < 10 then
    Exit;
  Y := StrToIntDef(Copy(IsoDate, 1, 4), 0);
  M := StrToIntDef(Copy(IsoDate, 6, 2), 0);
  D := StrToIntDef(Copy(IsoDate, 9, 2), 0);
  if (Y < 1900) or (M < 1) or (M > 12) or (D < 1) or (D > 31) then
    Exit;
  { Standard Julian day number formula, shifted so 2000-01-01 is day 0. }
  A := (14 - M) div 12;
  Yy := Y + 4800 - A;
  Mm := M + 12 * A - 3;
  Result := D + (153 * Mm + 2) div 5 + 365 * Yy + Yy div 4 - Yy div 100 + Yy div 400 - 32045 - 2451545;
end;

function NiceDate(const IsoDate: string): string;
const
  Mon: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  M, D: Integer;
begin
  Result := IsoDate;
  if Length(IsoDate) < 10 then
    Exit;
  M := StrToIntDef(Copy(IsoDate, 6, 2), 0);
  D := StrToIntDef(Copy(IsoDate, 9, 2), 0);
  if (M < 1) or (M > 12) or (D < 1) then
    Exit;
  Result := IntToStr(D) + ' ' + Mon[M] + ' ' + Copy(IsoDate, 1, 4);
end;

end.
