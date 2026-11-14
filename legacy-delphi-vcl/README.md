# The original Windows prototype

This folder holds the team's first version of the game: a Delphi 12 VCL
program (`Project1.dpr`, `Unit1.pas`) with one launch scene. A rocket lifts
off over a NASA sunset photograph, clouds drift past and the height is shown.

It is kept for the record. The game that is submitted is the browser version
in `/src`, which grew out of this idea: the launch scene, the NASA sky
photograph and the cloud cut-outs all carry over.

## Why the game moved to the browser

- A VCL program is a Windows `.exe`. Vercel hosts web pages, so it could not
  be deployed there, and judges would have had to download and run an
  unsigned program.
- The same Object Pascal language compiles to JavaScript with pas2js, so the
  game could stay in Pascal and still run from a link.

## What was wrong in this prototype (all fixed in the new version)

| Problem | Where | What happens |
| --- | --- | --- |
| `Unit2.pas` does not compile | `TShape = TObject` with no `type` keyword | The whole project fails to build |
| Height is not a height | `iheight := rSpeed` | The label shows speed, not altitude |
| Motion is rounded to whole numbers every tick | `rSpeed := rSpeed + Round(rA * dt1)` | At small accelerations the rocket never moves |
| No gravity | `rA := rForce / rMass` | A rocket lighter than its thrust still needs `F/m - g` to rise |
| Crashes on bad input | `StrToFloat(InputBox(...))` | Typing nothing, or a letter, raises an exception; a mass of 0 divides by zero |
| Clouds load from a file that is not shipped | `LoadFromFile('Cloud.jpeg')` | Fails unless the working folder happens to contain it; the embedded resources were not used |
| Staging never triggers properly | `thrust` is defined but never called | Boosters do not separate |
| Timers and images are created but never freed | `createcloud` | Memory grows each launch |
| Global variables for everything | top of `Unit1.pas` | Hard to extend to a full game |

## Files not in the repository

`Unit1.dfm`, `Project1.res`, `SceneAssets.res` and `assets/rocket_*.png` are
left out of git on purpose. They contain the rocket artwork, and nobody has
yet written down where that artwork came from. The Space Apps rules require
every image to be listed with its source, and forbid images the team has no
right to use.

If the team drew the rocket themselves, or can name its source and licence,
remove those four lines from `.gitignore` and add the credit to
`assets/credits.txt`. The new game does not need them: it draws its own
rockets in code.

The sky photograph and the cloud cut-outs are from NASA image KSC-08pd1628
and are credited in `assets/credits.txt`.
