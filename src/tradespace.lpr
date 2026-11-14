program tradespace;

{ TradeSpace - the space mission design game.

  Made for the 2026 NASA Space Apps Challenge, "Space Mission Design Game".

  The whole game is Object Pascal:
    src/core   the mission engine (catalogue, analysis, simulation, scoring).
               Plain Object Pascal with no browser code, so it also compiles
               in Delphi and Free Pascal.
    src/web    the browser front end (screens, canvas drawing, NASA data).

  pas2js turns it into public/js/tradespace.js, which index.html loads.
  Build with scripts\build.ps1.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$mode objfpc}

uses
  JS, Web, WebApp;

var
  Game: TGame;

begin
  Game := TGame.Create;
  Game.Start;
end.
