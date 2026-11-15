unit WebUtil;

{ Atomic Space - small helpers for building the page from Object Pascal.

  This unit talks to the browser (through pas2js's Web and JS units), so it is
  compiled only for the web game, not for the Delphi/Node core tests.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

interface

uses
  JS, Web, SysUtils;

function El(const Id: string): TJSHTMLElement;
function HasEl(const Id: string): Boolean;
function Esc(const S: string): string;
procedure SetHtml(const Id, Html: string);
procedure SetText(const Id, Txt: string);
function Icon(const Name: string): string;
function IconLg(const Name: string): string;
function Btn(const Cls, Act, A, Inner: string): string;
function BtnOff(const Cls, Inner: string): string;
function Chip(const Cls, Inner: string): string;
function Link(const Url, Inner: string): string;
function NowMs: Double;
function TodayIso: string;
procedure Toast(const Msg: string);
procedure ScrollTop;

implementation

var
  ToastTimer: NativeInt = 0;

function El(const Id: string): TJSHTMLElement;
begin
  Result := TJSHTMLElement(document.getElementById(Id));
end;

function HasEl(const Id: string): Boolean;
begin
  Result := document.getElementById(Id) <> nil;
end;

function Esc(const S: string): string;
begin
  { Player names and shared links are untrusted text: never put them in the page raw. }
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

procedure SetHtml(const Id, Html: string);
var
  E: TJSElement;
begin
  E := document.getElementById(Id);
  if E <> nil then
    E.innerHTML := Html;
end;

procedure SetText(const Id, Txt: string);
var
  E: TJSElement;
begin
  E := document.getElementById(Id);
  if E <> nil then
    E.textContent := Txt;
end;

function IconPath(const Name: string): string;
begin
  if Name = 'check' then Result := 'M5 13l4 4L19 7'
  else if Name = 'warn' then Result := 'M12 3l10 18H2L12 3z M12 10v5 M12 18v.5'
  else if Name = 'block' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M5 5l14 14'
  else if Name = 'info' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 11v6 M12 7v.5'
  else if Name = 'rocket' then Result := 'M12 2c3 2 5 6 5 10l-2 4H9l-2-4c0-4 2-8 5-10z M9 16l-3 4h3 M15 16l3 4h-3 M12 9v.5'
  else if Name = 'bolt' then Result := 'M13 2L4 14h7l-1 8 9-12h-7l1-8z'
  else if Name = 'mass' then Result := 'M6 8h12l2 13H4L6 8z M9 8a3 3 0 016 0'
  else if Name = 'coin' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M15 9c-.6-1-1.7-1.5-3-1.5-1.700 0-3 .9-3 2.2 0 3 6 1.500 6 4.300 0 1.300-1.300 2.200-3 2.200-1.400 0-2.500-.6-3-1.600 M12 5.500v2 M12 16.500v2'
  else if Name = 'data' then Result := 'M4 6c0-1.700 3.600-3 8-3s8 1.300 8 3-3.600 3-8 3-8-1.300-8-3z M4 6v6c0 1.700 3.600 3 8 3s8-1.300 8-3V6 M4 12v6c0 1.700 3.600 3 8 3s8-1.300 8-3v-6'
  else if Name = 'dish' then Result := 'M4 10a8 8 0 0010 10 M4 10l10 10 M9 15l5-5 M16 8a2 2 0 100-4 2 2 0 000 4z'
  else if Name = 'clock' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 6v6l4 2'
  else if Name = 'flask' then Result := 'M9 3h6 M10 3v6l-5 10a1 1 0 001 2h12a1 1 0 001-2l-5-10V3'
  else if Name = 'shield' then Result := 'M12 2l8 3v6c0 5-3.500 9-8 11-4.500-2-8-6-8-11V5l8-3z'
  else if Name = 'users' then Result := 'M8 11a3.500 3.500 0 100-7 3.500 3.500 0 000 7z M2 20c0-3.300 2.700-6 6-6s6 2.700 6 6 M17 11a3 3 0 100-6 M22 20c0-2.800-2-5-4.500-5.700'
  else if Name = 'book' then Result := 'M4 4h7a3 3 0 013 3v13a2 2 0 00-2-2H4V4z M20 4h-3a3 3 0 00-3 3'
  else if Name = 'play' then Result := 'M7 4l13 8-13 8V4z'
  else if Name = 'pause' then Result := 'M7 4h3v16H7z M14 4h3v16h-3z'
  else if Name = 'skip' then Result := 'M5 4l10 8-10 8V4z M18 4v16'
  else if Name = 'share' then Result := 'M4 12v7h16v-7 M12 3v12 M8 7l4-4 4 4'
  else if Name = 'back' then Result := 'M15 5l-7 7 7 7'
  else if Name = 'next' then Result := 'M9 5l7 7-7 7'
  else if Name = 'orbit' then Result := 'M12 9a3 3 0 100 6 3 3 0 000-6z M3 12c0-2.500 4-4.500 9-4.500s9 2 9 4.500-4 4.500-9 4.500-9-2-9-4.500z'
  else if Name = 'sun' then Result := 'M12 8a4 4 0 100 8 4 4 0 000-8z M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M19 5l-2 2 M7 17l-2 2'
  else if Name = 'cpu' then Result := 'M7 7h10v10H7z M10 2v5 M14 2v5 M10 17v5 M14 17v5 M2 10h5 M2 14h5 M17 10h5 M17 14h5'
  else if Name = 'target' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 7a5 5 0 100 10 5 5 0 000-10z M12 11.500v1'
  else if Name = 'star' then Result := 'M12 3l2.700 5.600 6.100.9-4.400 4.300 1 6.100L12 17l-5.400 2.900 1-6.100-4.400-4.300 6.100-.9L12 3z'
  else if Name = 'x' then Result := 'M6 6l12 12 M18 6L6 18'
  else if Name = 'flag' then Result := 'M5 21V4 M5 4h12l-2 4 2 4H5'
  else if Name = 'globe' then Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z M2 12h20 M12 2c3 3 3 17 0 20 M12 2c-3 3-3 17 0 20'
  else if Name = 'trophy' then Result := 'M7 4h10v5a5 5 0 01-10 0V4z M7 6H4c0 3 1.500 4.500 3.500 4.500 M17 6h3c0 3-1.500 4.500-3.500 4.500 M12 14v4 M8 21h8'
  else if Name = 'list' then Result := 'M8 6h13 M8 12h13 M8 18h13 M3 6h.5 M3 12h.5 M3 18h.5'
  else if Name = 'redo' then Result := 'M20 11a8 8 0 10-2.300 5.700 M20 4v7h-7'
  else if Name = 'wrench' then Result := 'M14 6a4 4 0 005 5l-9 9a2.100 2.100 0 01-3-3l9-9a4 4 0 00-2-2z'
  else Result := 'M12 2a10 10 0 100 20 10 10 0 000-20z';
end;

function IconSvg(const Name, Cls: string): string;
begin
  Result := '<svg class="' + Cls + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' +
    IconPath(Name) + '"/></svg>';
end;

function Icon(const Name: string): string;
begin
  Result := IconSvg(Name, 'ico');
end;

function IconLg(const Name: string): string;
begin
  Result := IconSvg(Name, 'ico ico-lg');
end;

function Btn(const Cls, Act, A, Inner: string): string;
begin
  Result := '<button type="button" class="' + Cls + '" data-act="' + Act + '"';
  if A <> '' then
    Result := Result + ' data-a="' + Esc(A) + '"';
  Result := Result + '>' + Inner + '</button>';
end;

function BtnOff(const Cls, Inner: string): string;
begin
  Result := '<button type="button" class="' + Cls + '" disabled>' + Inner + '</button>';
end;

function Chip(const Cls, Inner: string): string;
begin
  Result := '<span class="chip ' + Cls + '">' + Inner + '</span>';
end;

function Link(const Url, Inner: string): string;
begin
  Result := '<a href="' + Esc(Url) + '" target="_blank" rel="noopener noreferrer">' + Inner + '</a>';
end;

function NowMs: Double;
begin
  Result := TJSDate.now;
end;

function TodayIso: string;
begin
  Result := Copy(TJSDate.New.toISOString, 1, 10);
end;

procedure HideToast;
var
  T: TJSHTMLElement;
begin
  T := El('toast');
  if T <> nil then
    T.hidden := True;
end;

procedure Toast(const Msg: string);
var
  T: TJSHTMLElement;
begin
  T := El('toast');
  if T = nil then
    Exit;
  T.textContent := Msg;
  T.hidden := False;
  if ToastTimer <> 0 then
    window.clearTimeout(ToastTimer);
  ToastTimer := window.setTimeout(@HideToast, 2600);
end;

procedure ScrollTop;
begin
  window.scrollTo(0, 0);
end;

end.
