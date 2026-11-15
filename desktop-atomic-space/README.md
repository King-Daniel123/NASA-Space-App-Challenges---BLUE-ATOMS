# Atomic Space: desktop edition (Delphi VCL)

The Windows edition of team Blue Atoms' space mission design game for the
2026 NASA Space Apps Challenge. Download the built game from
https://cosatblueatoms.earth/desktop. Gameplay and the trade-offs
are described in the main [README](../README.md#desktop-edition-delphi).

## Build

Open `AtomicSpace_p.dproj` in Delphi 12 (Community Edition works) and press
**Shift+F9**. To build without opening the IDE window:

```powershell
& "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\bds.exe" -ns -b "AtomicSpace_p.dproj"
```

The program looks for `Assets\` next to the `.exe`, then in `Win32\Debug\`,
then two folders up, so it runs straight from `Win32\Debug` after a build.

## Running it from a download

- **Just play:** download the zip from https://cosatblueatoms.earth/desktop, unzip the whole folder and run `AtomicSpace.exe`. Keep the `Assets` folder next to it.
- **From the source code (GitHub "Download ZIP" or clone):** open `desktop-atomic-space/AtomicSpace_p.dproj` in Delphi 12 and press Run. The program finds `desktop-atomic-space/Assets` from `Win32\Debug` by itself, so nothing needs copying.
- The other pictures (backgrounds, logo, crane, president) are stored inside the `.dfm` form files, so the `Assets` folder only holds what the game loads while it runs.

## What changed for the hackathon

| Was | Now |
| --- | --- |
| No mission objective. The "President" offered R5 million, but even the cheapest rocket cost $73 million. | Three missions, each with a payload, a cost cap and the fuel it needs, based on CAPSTONE, LRO and CLPS. |
| The Nova (third) thruster was the cheapest and also the strongest, so there was nothing to trade. | Thruster prices rebalanced, and a choice of 2 or 4 boosters added. Every mission has 3 to 6 designs that pass review. |
| Launch with any design. | Live review board: thrust-to-weight, budget, payload, fuel margin. RED findings block launch. |
| One player. | Hot-seat team of 1-4 with four roles. Every role signs off, and a design change resets the sign-offs. |
| After booster separation the rocket fell back and its altitude went below zero, forever. | The core stage keeps climbing, and the "continue to the Moon" button appears. A rocket that falls back ends the flight as lost. |
| Running out of fuel had no effect. | The engines cut off and gravity takes over. |
| The Moon phase always started with 100% fuel. | It starts with the fuel the design's margin allows. |
| No result at the end. | Mission report: score out of 100 (design 60, flight 40), a grade, the reasons, and the real mission it resembles. |
| Images loaded with paths relative to the working folder, so the game failed when started from anywhere else. | `AssetFile()` resolves every path from the program's own folder. |
| `<` did not update the Moon-scene rocket; the Base/Thrusters buttons were hidden under the text box. | Fixed. |
| Built from source, LAUNCH and the Moon mission stopped with "Rocket image file not found": two screens only looked next to the `.exe`. | Every screen now uses the same `AssetFile()` search. |
| `if (height >= 5000)` compared the window height, not the altitude. | `iheight`. |
| Closing the planner left the program running in the background (the start screen is the hidden main form). | Closing the planner exits the game. |
| The launch window was titled "SKYWARD" and "Form1". | Titled "Atomic Space". |
| The "Mission Director" picture is a caricature of a real person. | Hidden (`imgPresident.Visible := False` in `Game.pas`). Space Apps rules and NASA likeness rules make it a risk. |

The new controls are created in code (in `Game.pas`, `BuildMissionPanel`),
so the large `.dfm` files are unchanged. Positions are scaled by the screen
DPI.

## Tested

Built with Delphi 12 Community Edition and driven end to end with Windows UI
Automation at 150% display scaling. The test went: start, choose a design
that is NO-GO, add boosters until it is GO, launch, booster separation,
continue to the Moon, exit, mission report. It was also started from another
folder, to check the asset paths.

Part of the code was written with the help of Claude (Anthropic), an AI coding
assistant. The source headers say which.
