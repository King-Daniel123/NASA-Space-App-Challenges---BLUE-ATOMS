# Text for the Space Apps project page

Copy each block into the matching field on your team's Project tab.

**Read every sentence before you paste it.** It describes the project as it
stands in this repository. If something is not true for your team, change it.
The two places that need your own words are marked **YOUR WORDS**.

Deadline: **Sunday 15 November 2026, 11:59 p.m.** local time. Press
*Submit for Judging*, not only *Save Progress*.

---

## Project Name

```
TradeSpace
```

## High-Level Project Summary

```
TradeSpace is a browser game in which one to four players design, manage and fly a complete space mission. Players take a mission with a science goal, a cost cap and a deadline, then choose the orbit, instruments, spacecraft, power system, radio and rocket. Seven live gauges (cost, launch mass, power, data, science, schedule, odds) show how every choice changes the others, and a "ripple" line spells it out: add a radar and you gain science, but also mass, propellant, power demand, data volume and cost. A review board explains what will fail and why. Then the mission is built, launched and operated week by week, with decisions to make, and a final report explains the score and names the real mission the design most resembles.

NASA open data drives the play. Real natural events from EONET are the targets of the Earth mission and set its science priorities. Real solar storms from DONKI strike the spacecraft. The real 2029 Apophis flyby from NeoWs/JPL is the deadline of the asteroid mission.

It matters because the trade-offs of mission design usually stay abstract for students. TradeSpace lets anyone with a browser try a whole mission in ten minutes, fail safely, understand why, and try again.
```

## Link to Project Demo

```
https://tradespace-blue-atoms.vercel.app/slides/
```

Seven slides. Before you submit, put your team members' names on slide 1
(edit `public/slides/index.html`, then deploy again). If you would rather use
a video, it must be 30 seconds or less, and a video in another language needs
English subtitles.

## Link to Final Project

```
https://tradespace-blue-atoms.vercel.app
```

Source code: `https://github.com/King-Daniel123/NASA-Space-App-Challenges---BLUE-ATOMS`
(put this in the description or references so judges can find it).

## Detailed Project Description

```
WHAT IT DOES

TradeSpace walks a team through the life of a space mission, from concept to operations.

1. Briefing. Five missions modelled on real ones: Disaster Watch (Earth orbit), Ice Prospector (Moon), Follow the Water (Mars), Race to Apophis (asteroid), Ocean World (Europa). Each gives an objective, science priorities, a cost cap, a deadline and the facts that make the destination hard.

2. Design lab. Seven tabs: orbit, payload, spacecraft, power, communications and data, launch, and plan. Players choose from 15 instruments, 12 real launch vehicles and about 40 subsystem options (bus, propulsion, attitude control, thermal control, radiation shielding, antenna, radio band, transmitter, ground network, computer, risk class, schedule). Seven gauges update live, and a "ripple" line states what the last change did to everything else. A blueprint of the spacecraft and an animated view of the orbit are drawn from the design.

3. Review board. Lists what must be fixed and what is risky. Every finding says what is wrong, why it matters and what to try. It checks, among other things, that the spacecraft's mass and orbit match the chosen rocket, that power and battery cover the longest eclipse, that the data link keeps up with the instruments, that the design fits the cost cap and the deadline, and that the orbit can see the targets.

4. Flight. Development brings surprises (mass growth, late parts, budget cuts). The launch can fail at the rocket's real rate. In operations, solar panels fade, the data rate changes with distance, hardware fails at the rate the design earned, and the crew must decide how to respond to storms, failures and discoveries.

5. Report. A score out of 1,000 across science, survival, budget, engineering and value for money, with plain-language reasons, a week-by-week chart, and the real mission the design most resembles.

TEAM PLAY

Two to four players share one screen. Each has a role (Project Manager, Science Lead, Spacecraft Engineer, Comms and Ops Lead), owns some of the design tabs, and has a personal goal that conflicts with the others. Every role must call GO before launch, and in-flight decisions go to the role that owns the affected system. Share links let another team load the same design with the same luck and compare scores. A mission log ranks every flight.

HOW IT WORKS

The models are simple but real: the Tsiolkovsky rocket equation for propellant; launch capacity falling with launch energy; sunlight and radio signal falling with the square of distance; an energy balance over each orbit including shadow; a link budget calibrated against Mars Reconnaissance Orbiter; science that accumulates with diminishing returns. Automated tests check them against real missions (for example, a Juno-sized solar array gives about 500 W at Jupiter).

BENEFITS

It makes the links between subsystems visible, which is the hardest part of mission design to teach. It needs only a browser: no install, no account, no cost. It uses plain language, a 27-term glossary, example designs and three difficulty levels, so beginners can start and experienced players are still stretched. There is no single right answer: a 36 kg CubeSat and a nuclear-powered probe can both succeed.

WHAT WE HOPE TO ACHIEVE

That a class can run a mission in one lesson and come away understanding why engineers keep margins, why distance is the enemy of data, and why every instrument has to earn its place.

TOOLS

The whole game is written in Object Pascal (the Delphi language) and compiled to JavaScript with the open-source pas2js compiler. Graphics are drawn on HTML canvas by the game's own code. Node.js runs the tests and builds the NASA data snapshot. Hosted on Vercel; source on GitHub under the MIT licence.
```

## Use of AI (the form calls it "Super Intelligence")

This answer is for data collection and is not shown to judges, but it must be
accurate. The first paragraph below is true of this repository. The second is
for you to write.

```
Yes. We used Claude, a large language model made by Anthropic (through Claude Code), as a coding assistant. It helped plan the software, wrote most of the Object Pascal source code, the in-game text, the README and the demo slides, and wrote the code that draws the game's graphics. We acknowledge this in the header of each source file, in the page metadata, in the game's About panel and in the README.

No AI-generated images, audio or video are used. Every picture is drawn by the game from the numbers in the player's design, or is a NASA photograph or map. No NASA logos, flags or mission insignia appear.

YOUR WORDS: say what the team did. For example, who chose the challenge and the idea of a mission design game with a launch scene, who built the first Delphi prototype, who play-tested and adjusted the game, and who prepared the submission.
```

## NASA Data

```
NASA EONET (Earth Observatory Natural Event Tracker) v3 API, https://eonet.gsfc.nasa.gov/docs/v3 : real wildfires, severe storms, floods and sea-ice events from the last 30 days are loaded live. Their locations determine what each orbit can see, and their types set the science priorities of the Disaster Watch mission. They are plotted on the map and named in the mission log.

NASA CCMC DONKI (Space Weather Database Of Notifications, Knowledge, Information), https://ccmc.gsfc.nasa.gov/tools/DONKI/ : one year of real solar flares, solar energetic particle events and geomagnetic storms. They strike the spacecraft during every simulated mission on their real dates and are named in the log.

NASA NeoWs (Near Earth Object Web Service), https://api.nasa.gov/ , and JPL Small-Body Database close-approach data: the date, miss distance and speed of the 13 April 2029 flyby of asteroid 99942 Apophis. The date sets the deadline of the Race to Apophis mission, counted down on the real calendar.

NASA GIBS (Global Imagery Browse Services), layer BlueMarble_NextGeneration: the world map.

NASA image KSC-08pd1628: the sky and clouds of the launch scene.

NASA resources from the challenge page that shaped the design: Design and Develop Science Missions (the launch, space, ground and user segments), JPL Concept Maturity Levels, the Goddard Mission Design Lab, GMAT, NASA Mission Viz, CubeSat 101, and the Webb "Build It Yourself" game.

NASA mission pages and Planetary Fact Sheets were the source for the simplified masses, costs, data rates, distances and sunlight levels.
```

## Space Agency Partner Data and Other References

```
SPACE AGENCY PARTNERS
ISRO: PSLV and LVM3 launch vehicles; Chandrayaan-1, Mangalyaan and NISAR as reference missions.
ESA: Ariane 6 and Vega-C launch vehicles; SMART-1, JUICE, Trace Gas Orbiter and Ramses as reference missions.
JAXA: H3 launch vehicle; Hayabusa2 and Akatsuki as reference missions.
CSA: the laser altimeter on OSIRIS-REx and MOPITT on Terra, cited in the game; CSA Digital Games and Activities from the challenge resources.
Italian Space Agency: LICIACube.
KASA / KARI: Danuri lunar orbiter.
UAE Space Agency / MBRSC: Hope Mars mission.

NASA DATA AND IMAGES
NASA EONET v3 API. NASA CCMC DONKI web service. NASA NeoWs API and JPL Small-Body Database. NASA GIBS, Blue Marble Next Generation. NASA image KSC-08pd1628, "Gathering clouds filter the painted sky over the turn basin", Dimitri Gerondidakis, 2008.

NASA DOCUMENTS
Design and Develop Science Missions. Concept Maturity Levels (JPL). Mission Design Lab (GSFC). General Mission Analysis Tool. NASA Mission Viz. CubeSat 101. A Learning Game About Telescopes. NASA Systems Engineering Handbook. State-of-the-Art of Small Spacecraft Technology. NASA Planetary Fact Sheets. Mission pages on science.nasa.gov for LRO, Lunar Prospector, Lunar Trailblazer, CAPSTONE, MRO, MAVEN, Mars Odyssey, ESCAPADE, MarCO, DART, NEAR Shoemaker, OSIRIS-REx, OSIRIS-APEX, Europa Clipper, Juno, Galileo, New Horizons, Landsat 9, TROPICS, NISAR, CYGNSS and Terra.

SOFTWARE AND TOOLS
pas2js 3.2.0 (Free Pascal to JavaScript compiler) and its run-time library, https://getpas2js.freepascal.org/ . Node.js. Vercel. GitHub. Claude (Anthropic) as an AI coding assistant.

OTHER
Launch vehicle capacities, prices and success rates are simplified from the providers' published figures. All numbers in the game are rounded for teaching and are not engineering data.
```

---

## Before you press Submit

- [ ] Open the game link and the slides link in a private window. Both must load without logging in.
- [ ] Team name and member names are on slide 1.
- [ ] Every team member is on the Members tab and registered for the same local event.
- [ ] The AI answer says what really happened.
- [ ] Both boxes are ticked, and you pressed **Submit for Judging**.
