unit TsCatalog;

{ Atomic Space - the catalogue of things a mission can be built from:
  science instruments, spacecraft subsystems, launch vehicles and a glossary.

  Figures are simplified from publicly available NASA and partner-agency
  material (mission press kits, the NASA Small Spacecraft State-of-the-Art
  report, NASA Launch Services Program data, Planetary Fact Sheets). They are
  rounded for teaching and are not engineering data.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

uses
  TsTypes;

{ Meaning of the kind-specific numbers A..G in TPart:

  pkBus        MassKg=structure  PowerW=housekeeping
               A=max dry mass kg  B=max payload kg  C=max instruments
               D=max solar array m2  E=operations $M/yr
               F=chance of a year with no significant anomaly
               G=scale used to size the other subsystems
  pkPropulsion MassKg=engine dry mass at scale 1   Tier 0 none .. 4 electric
               A=specific impulse s  B=tank mass per kg of propellant
               C=electrical power needed while thrusting W
               D=reliability of the big orbit-insertion burn
               E=$M per kg of propellant
  pkAdcs       Tier=pointing class (0 coarse, 1 fine, 2 precise)
               A=1 when it only works in low Earth orbit   B=1 when redundant
  pkThermal    Tier 0 passive, 1 active, 2 active + cryocooler
               A=share of dry mass  B=heater power factor  E=fixed extra $M
  pkComputer   Tier=radiation tolerance 0..2   A=data storage in gigabits
  pkShield     Tier=radiation protection 0..2 (mass and cost scale with the bus)
  pkAntenna    A=effective dish diameter m
  pkBand       Tier 0 UHF, 1 S, 2 X, 3 Ka, 4 optical
               A=data-rate factor  B=hardware rate limit Mbps
               C=availability (weather)  D=pointing class required
  pkTx         A=radio output power W   PowerW=electrical power drawn
  pkGround     A=contact hours/day in deep space  B=hours/day near Earth
               C=ground antenna factor (1 = 34 m dish)   CostM=$M per year
  pkRisk       A=hardware cost multiplier  B=mass multiplier
               C=failure-rate multiplier  D=development years added
  pkSchedule   A=development time multiplier  B=cost multiplier
               C=failure-rate multiplier }

var
  Instruments: array of TInstrument;
  Parts: array[TPartKind] of TPartArray;
  Launchers: array of TLauncher;
  Glossary: array of TGlossaryItem;

const
  PartKindName: array[TPartKind] of string = ('Spacecraft bus', 'Propulsion',
    'Attitude control', 'Thermal control', 'Flight computer', 'Radiation shielding',
    'Antenna', 'Radio band', 'Transmitter', 'Ground network', 'Risk posture',
    'Schedule');
  PartKindOwner: array[TPartKind] of TRole = (roSpacecraft, roSpacecraft,
    roSpacecraft, roSpacecraft, roOps, roSpacecraft, roOps, roOps, roOps, roOps,
    roPM, roPM);

function MV(Im, Sp, Th, Ra, Tp, Vo, At, Fi, Se: Double): TMeasureValues;
function FindInstrument(const AId: string): Integer;
function FindPart(AKind: TPartKind; const AId: string): Integer;
function FindLauncher(const AId: string): Integer;
function BusClassOf(const P: TPart): TBusClass;

implementation

function MV(Im, Sp, Th, Ra, Tp, Vo, At, Fi, Se: Double): TMeasureValues;
begin
  Result[mImaging] := Im;
  Result[mSpectral] := Sp;
  Result[mThermal] := Th;
  Result[mRadar] := Ra;
  Result[mTopo] := Tp;
  Result[mVolatiles] := Vo;
  Result[mAtmos] := At;
  Result[mFields] := Fi;
  Result[mService] := Se;
end;

function FindInstrument(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Instruments) do
    if Instruments[I].Id = AId then
    begin
      Result := I;
      Exit;
    end;
end;

function FindPart(AKind: TPartKind; const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Parts[AKind]) do
    if Parts[AKind][I].Id = AId then
    begin
      Result := I;
      Exit;
    end;
end;

function FindLauncher(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Launchers) do
    if Launchers[I].Id = AId then
    begin
      Result := I;
      Exit;
    end;
end;

function BusClassOf(const P: TPart): TBusClass;
begin
  case P.Tier of
    0: Result := bcCube;
    1: Result := bcSmall;
    2: Result := bcMedium;
  else
    Result := bcLarge;
  end;
end;

procedure AddInstr(const AId, AName, AAnalog, ABlurb: string;
  AMass, APower, ACost, AData, ADuty, ADev: Double; const AValue: TMeasureValues;
  AFine, ACool, AHga: Boolean; AMinBus: TBusClass);
var
  N: Integer;
begin
  N := Length(Instruments);
  SetLength(Instruments, N + 1);
  Instruments[N].Id := AId;
  Instruments[N].Name := AName;
  Instruments[N].Analog := AAnalog;
  Instruments[N].Blurb := ABlurb;
  Instruments[N].MassKg := AMass;
  Instruments[N].PowerW := APower;
  Instruments[N].CostM := ACost;
  Instruments[N].DataMbps := AData;
  Instruments[N].Duty := ADuty;
  Instruments[N].DevYears := ADev;
  Instruments[N].Value := AValue;
  Instruments[N].NeedsFinePointing := AFine;
  Instruments[N].NeedsCooling := ACool;
  Instruments[N].NeedsHGA := AHga;
  Instruments[N].MinBus := AMinBus;
end;

procedure AddPart(AKind: TPartKind; const AId, AName, AAnalog, ABlurb: string;
  AMass, APower, ACost, ADev: Double; ATier: Integer; AMinBus: TBusClass;
  A, B, C, D, E, F, G: Double);
var
  N: Integer;
begin
  N := Length(Parts[AKind]);
  SetLength(Parts[AKind], N + 1);
  Parts[AKind][N].Kind := AKind;
  Parts[AKind][N].Id := AId;
  Parts[AKind][N].Name := AName;
  Parts[AKind][N].Analog := AAnalog;
  Parts[AKind][N].Blurb := ABlurb;
  Parts[AKind][N].MassKg := AMass;
  Parts[AKind][N].PowerW := APower;
  Parts[AKind][N].CostM := ACost;
  Parts[AKind][N].DevYears := ADev;
  Parts[AKind][N].Tier := ATier;
  Parts[AKind][N].MinBus := AMinBus;
  Parts[AKind][N].A := A;
  Parts[AKind][N].B := B;
  Parts[AKind][N].C := C;
  Parts[AKind][N].D := D;
  Parts[AKind][N].E := E;
  Parts[AKind][N].F := F;
  Parts[AKind][N].G := G;
end;

procedure AddLauncher(const AId, AName, AAgency, ABlurb: string;
  ALeo, ASso, AGto, AC3Zero, AC3K, ACost, ARel: Double; AMaxBus: TBusClass;
  ARideshare: Boolean; ASize: Integer);
var
  N: Integer;
begin
  N := Length(Launchers);
  SetLength(Launchers, N + 1);
  Launchers[N].Id := AId;
  Launchers[N].Name := AName;
  Launchers[N].Agency := AAgency;
  Launchers[N].Blurb := ABlurb;
  Launchers[N].LeoKg := ALeo;
  Launchers[N].SsoKg := ASso;
  Launchers[N].GtoKg := AGto;
  Launchers[N].C3ZeroKg := AC3Zero;
  Launchers[N].C3K := AC3K;
  Launchers[N].CostM := ACost;
  Launchers[N].Reliability := ARel;
  Launchers[N].MaxBus := AMaxBus;
  Launchers[N].Rideshare := ARideshare;
  Launchers[N].Size := ASize;
end;

procedure AddTerm(const ATerm, APlain, AWhy: string);
var
  N: Integer;
begin
  N := Length(Glossary);
  SetLength(Glossary, N + 1);
  Glossary[N].Term := ATerm;
  Glossary[N].Plain := APlain;
  Glossary[N].Why := AWhy;
end;

procedure BuildInstruments;
begin
  AddInstr('cam_ctx', 'Wide-angle context camera', 'Like CTX on Mars Reconnaissance Orbiter',
    'A small, sturdy camera that maps wide areas. Light and cheap, modest detail.',
    4, 7, 6, 3, 0.35, 0.15, MV(35, 0, 0, 0, 0, 0, 0, 0, 0), False, False, False, bcCube);
  AddInstr('cam_hires', 'High-resolution telescope camera', 'Like HiRISE on Mars Reconnaissance Orbiter',
    'A telescope with a camera on the end. Stunning detail, but heavy, data-hungry and it needs a very steady spacecraft.',
    48, 60, 40, 24, 0.15, 0.4, MV(85, 0, 0, 0, 15, 0, 0, 0, 0), True, False, False, bcSmall);
  AddInstr('spec_vnir', 'Imaging spectrometer', 'Like M3, which found water on the Moon from Chandrayaan-1',
    'Splits reflected sunlight into hundreds of colours to identify minerals and ices. Its detector must be kept very cold.',
    16, 38, 24, 8, 0.3, 0.3, MV(10, 75, 0, 0, 0, 25, 0, 0, 0), False, True, False, bcSmall);
  AddInstr('tir', 'Thermal infrared imager', 'Like Diviner on Lunar Reconnaissance Orbiter',
    'Maps temperature. Spots fires and lava on Earth, cold traps on the Moon and warm ice on Europa.',
    9, 20, 13, 1.2, 0.5, 0.2, MV(0, 0, 75, 0, 0, 10, 0, 0, 0), False, False, False, bcCube);
  AddInstr('sar', 'Imaging radar and sounder', 'Like Mini-RF on LRO, SHARAD on MRO and REASON on Europa Clipper',
    'Makes its own radio light, so it sees through cloud, darkness and ice. Very power-hungry and produces floods of data.',
    30, 150, 38, 30, 0.12, 0.4, MV(0, 0, 0, 85, 10, 20, 0, 0, 0), False, False, False, bcSmall);
  AddInstr('lidar', 'Laser altimeter', 'Like LOLA on LRO; OSIRIS-REx carried one from the Canadian Space Agency',
    'Fires laser pulses at the ground and times the echo to build a 3D map. Works best from a low orbit.',
    13, 34, 19, 0.05, 0.9, 0.25, MV(0, 0, 0, 0, 80, 0, 0, 0, 0), False, False, False, bcSmall);
  AddInstr('neutron', 'Neutron spectrometer', 'Like the one on Lunar Prospector that first hinted at polar ice',
    'Counts neutrons leaking from the ground. Fewer neutrons means hydrogen, and hydrogen usually means water ice. Only works close to the surface.',
    5, 8, 8, 0.002, 1.0, 0.15, MV(0, 0, 0, 0, 0, 75, 0, 0, 0), False, False, False, bcCube);
  AddInstr('mag', 'Magnetometer on a boom', 'Like the magnetometers on MAVEN, Juno and Europa Clipper',
    'Measures magnetic fields. At Europa, a wobbling field revealed a salty ocean hidden under the ice.',
    3, 4, 5, 0.004, 1.0, 0.1, MV(0, 0, 0, 0, 15, 0, 0, 50, 0), False, False, False, bcCube);
  AddInstr('plasma', 'Plasma and particle suite', 'Like the particle instruments on MAVEN and ESCAPADE',
    'Tastes the thin, electrically charged gas around the spacecraft and shows how a world loses its air.',
    11, 14, 15, 0.02, 1.0, 0.2, MV(0, 0, 0, 0, 0, 0, 20, 65, 0), False, False, False, bcSmall);
  AddInstr('massspec', 'Mass spectrometer', 'Like NGIMS on MAVEN and MASPEX on Europa Clipper',
    'Weighs individual molecules to say exactly which gases are present. It has to fly through the gas it studies.',
    14, 28, 27, 0.01, 0.3, 0.3, MV(0, 0, 0, 0, 0, 45, 55, 0, 0), False, False, False, bcSmall);
  AddInstr('radiometer', 'Microwave radiometer', 'Like the TROPICS storm-watching CubeSats and Mars Climate Sounder',
    'Reads temperature and moisture inside clouds and atmospheres. Small enough for a CubeSat.',
    6, 12, 10, 0.06, 1.0, 0.15, MV(0, 0, 10, 0, 0, 0, 75, 0, 0), False, False, False, bcCube);
  AddInstr('uvs', 'Ultraviolet spectrometer', 'Like LAMP on LRO, which peers into permanently dark craters',
    'Watches faint ultraviolet glow from thin gases, plumes and frost.',
    7, 9, 11, 0.3, 0.5, 0.2, MV(0, 25, 0, 0, 0, 20, 45, 0, 0), False, False, False, bcCube);
  AddInstr('dust', 'Dust analyser', 'Like LDEX on LADEE and SUDA on Europa Clipper',
    'Catches tiny grains knocked off the surface and reads their chemistry, sampling the ground without landing.',
    6, 8, 10, 0.01, 1.0, 0.2, MV(0, 10, 0, 0, 0, 35, 0, 30, 0), False, False, False, bcCube);
  AddInstr('radio', 'Radio science package', 'Gravity science as on GRAIL, Juno and MRO',
    'An ultra-stable clock for the radio. Tiny changes in the signal reveal the gravity, and so the inside, of a world. Needs a dish antenna.',
    2, 3, 3, 0, 1.0, 0.05, MV(0, 0, 0, 0, 45, 0, 0, 0, 0), False, False, True, bcCube);
  AddInstr('relay', 'UHF relay radio', 'Like Electra on MRO and MAVEN',
    'Passes messages between Earth and landers or rovers on the surface. No science of its own, but other missions depend on it.',
    5, 18, 8, 0, 0.2, 0.1, MV(0, 0, 0, 0, 0, 0, 0, 0, 80), False, False, False, bcSmall);
end;

procedure BuildParts;
begin
  { ---- Spacecraft bus ---- }
  AddPart(pkBus, 'cube', '12U CubeSat', 'Like CAPSTONE and the MarCO pair',
    'The size of a large shoebox. Cheap and fast to build, but there is room for only one or two small instruments.',
    5, 6, 2.5, 1.2, 0, bcCube, 36, 10, 2, 1.5, 1.2, 0.72, 0.15);
  AddPart(pkBus, 'small', 'SmallSat (ESPA class)', 'Like Lunar Trailblazer and ESCAPADE',
    'About the size of a washing machine. A good balance for focused missions on a budget.',
    48, 30, 16, 2.2, 1, bcSmall, 380, 90, 4, 10, 3.5, 0.80, 1.0);
  AddPart(pkBus, 'medium', 'Medium probe (Discovery class)', 'Like MAVEN and Lunar Reconnaissance Orbiter',
    'A car-sized spacecraft that can carry a full instrument suite and a big antenna.',
    240, 110, 105, 3.5, 2, bcMedium, 1900, 280, 7, 50, 13, 0.86, 3.2);
  AddPart(pkBus, 'large', 'Flagship bus', 'Like Europa Clipper and Cassini',
    'A bus-sized spacecraft. Carries everything, costs a fortune and takes most of a decade to build.',
    720, 280, 360, 5.5, 3, bcLarge, 5200, 850, 12, 130, 38, 0.90, 7.0);

  { ---- Propulsion ---- }
  AddPart(pkPropulsion, 'none', 'No propulsion', 'Many Earth-orbit CubeSats',
    'No engine at all. Nothing to leak or explode, but the spacecraft can never change its orbit.',
    0, 0, 0, 0, 0, bcCube, 0, 0, 0, 1, 0, 0, 0);
  AddPart(pkPropulsion, 'cold', 'Cold-gas thrusters', 'Used on small CubeSats',
    'Puffs of compressed gas. Simple and safe, but far too weak for big manoeuvres.',
    1.5, 0, 0.8, 0, 1, bcCube, 65, 0.25, 0, 0.995, 0.004, 0, 0);
  AddPart(pkPropulsion, 'mono', 'Monopropellant thrusters', 'Hydrazine, as on most spacecraft',
    'One liquid sprayed over a catalyst. Reliable workhorse for steering and small orbit changes.',
    6, 0, 3, 0, 2, bcCube, 225, 0.12, 0, 0.99, 0.012, 0, 0);
  AddPart(pkPropulsion, 'biprop', 'Bipropellant main engine', 'As on MRO, Juno and Europa Clipper',
    'Fuel plus oxidiser. About 40 % more push per kilogram, which matters enormously for braking into orbit.',
    28, 0, 12, 0, 3, bcSmall, 320, 0.10, 0, 0.985, 0.015, 0, 0);
  AddPart(pkPropulsion, 'sep', 'Solar electric propulsion', 'As on Dawn, Psyche, Hayabusa2 and SMART-1',
    'Ion engines sip xenon and are six times more efficient, but push as gently as a sheet of paper and need a lot of electricity. Trips take longer.',
    30, 0, 22, 0.5, 4, bcCube, 1800, 0.12, 900, 0.99, 0.02, 0, 0);

  { ---- Attitude determination and control ---- }
  AddPart(pkAdcs, 'mtq', 'Magnetorquers and sun sensors', 'Common on Earth-orbit CubeSats',
    'Electromagnets that push against Earth''s magnetic field. Coarse pointing, and useless anywhere without a strong magnetic field.',
    1.5, 2, 0.5, 0, 0, bcCube, 1, 0, 0, 0, 0, 0, 0);
  AddPart(pkAdcs, 'rw3', 'Reaction wheels and star tracker', 'Standard on most science spacecraft',
    'Three spinning wheels turn the spacecraft precisely. If one wheel fails, fine pointing is lost.',
    9, 16, 4.5, 0, 1, bcCube, 0, 0, 0, 0, 0, 0, 0);
  AddPart(pkAdcs, 'rw4', 'Four wheels, twin star trackers', 'As on Kepler, MRO and Europa Clipper',
    'A spare wheel and a second star tracker. Rock-steady pointing that survives a failure.',
    14, 24, 9, 0.1, 2, bcCube, 0, 1, 0, 0, 0, 0, 0);

  { ---- Thermal control ---- }
  AddPart(pkThermal, 'passive', 'Passive: blankets and heaters', 'Used on simple spacecraft',
    'Shiny insulation, paint and a few heaters. Light and cheap. Fine in gentle environments.',
    0, 0, 0.6, 0, 0, bcCube, 0.02, 1.0, 0, 0, 0, 0, 0);
  AddPart(pkThermal, 'active', 'Active: louvres, heat pipes, radiators', 'As on Juno and MRO',
    'Moves heat to where it is needed and dumps the rest. Needed for extreme cold or heat and for power-hungry equipment.',
    0, 0, 2.5, 0.1, 1, bcCube, 0.04, 0.6, 0, 0, 0, 0, 0);
  AddPart(pkThermal, 'cryo', 'Active plus cryocooler', 'As on infrared space telescopes',
    'Adds a mechanical fridge that keeps infrared detectors far below freezing. Extra mass, power and cost.',
    8, 45, 2.5, 0.3, 2, bcSmall, 0.045, 0.6, 0, 0, 12, 0, 0);

  { ---- Flight computer and data storage ---- }
  AddPart(pkComputer, 'cots', 'Commercial computer', 'Phone-class parts, used on CubeSats',
    'Fast and cheap, with 8 GB of storage. Not built for radiation: happy in low Earth orbit, fragile beyond it.',
    0.6, 5, 0.6, 0, 0, bcCube, 64, 0, 0, 0, 0, 0, 0);
  AddPart(pkComputer, 'radtol', 'Radiation-tolerant computer', 'As on many SmallSat missions',
    'Hardened against most radiation upsets, with 64 GB of storage. A sensible middle path.',
    2, 12, 4, 0, 1, bcCube, 512, 0, 0, 0, 0, 0, 0);
  AddPart(pkComputer, 'radhard', 'Radiation-hardened computer and recorder', 'RAD750 heritage: MRO, Juno, Perseverance',
    'Slow but nearly indestructible, with a 250 GB solid-state recorder. The choice for deep space.',
    9, 28, 15, 0.1, 2, bcSmall, 2000, 0, 0, 0, 0, 0, 0);

  { ---- Radiation shielding ---- }
  AddPart(pkShield, 'none', 'No extra shielding', 'Typical in low Earth orbit',
    'Relies on the parts themselves. Saves mass.',
    0, 0, 0, 0, 0, bcCube, 0, 0, 0, 0, 0, 0, 0);
  AddPart(pkShield, 'spot', 'Spot shielding', 'Metal covers on sensitive chips',
    'Small slabs of metal over the most delicate electronics.',
    3, 0, 1.5, 0, 1, bcCube, 0, 0, 0, 0, 0, 0, 0);
  AddPart(pkShield, 'vault', 'Radiation vault', 'Juno''s 200 kg titanium vault',
    'A thick-walled metal box around all the electronics. Heavy, but the only way to survive the worst radiation belts.',
    28, 0, 6, 0.2, 2, bcSmall, 0, 0, 0, 0, 0, 0, 0);

  { ---- Antenna ---- }
  AddPart(pkAntenna, 'patch', 'Patch antenna', 'A flat plate the size of a coaster',
    'Radiates in almost every direction, so it never needs pointing, but very little of the signal reaches Earth.',
    0.2, 0, 0.2, 0, 0, bcCube, 0.03, 0, 0, 0, 0, 0, 0);
  AddPart(pkAntenna, 'dish06', '0.6 m dish or reflectarray', 'MarCO''s fold-out panel',
    'A small dish focuses the signal into a beam. It must be pointed at Earth.',
    2.5, 0, 1.5, 0, 1, bcCube, 0.6, 0, 0, 0, 0, 0, 0);
  AddPart(pkAntenna, 'dish12', '1.2 m dish', 'Typical SmallSat high-gain antenna',
    'Four times the collecting area of the 0.6 m dish, so four times the data rate.',
    8, 0, 3.5, 0, 2, bcSmall, 1.2, 0, 0, 0, 0, 0, 0);
  AddPart(pkAntenna, 'dish20', '2 m dish', 'MAVEN and Juno class',
    'A serious deep-space antenna. Needs a medium-sized spacecraft to carry it.',
    19, 0, 7, 0, 3, bcMedium, 2.0, 0, 0, 0, 0, 0, 0);
  AddPart(pkAntenna, 'dish30', '3 m dish', 'Mars Reconnaissance Orbiter, Europa Clipper',
    'The big one. MRO''s 3 m dish has returned more data than every other planetary mission combined.',
    36, 0, 12, 0.1, 4, bcMedium, 3.0, 0, 0, 0, 0, 0, 0);

  { ---- Radio band ---- }
  AddPart(pkBand, 'uhf', 'UHF', 'Amateur-radio style, used by CubeSats near Earth',
    'Simple and cheap, a trickle of data. Cannot reach Earth from deep space.',
    0.4, 4, 0.3, 0, 0, bcCube, 0.003, 1, 1.0, 0, 0, 0, 0);
  AddPart(pkBand, 's', 'S-band', 'Classic telemetry and command band',
    'Reliable in any weather. Fine for commands and small amounts of data.',
    1.5, 5, 1.0, 0, 1, bcCube, 0.07, 5, 1.0, 0, 0, 0, 0);
  AddPart(pkBand, 'x', 'X-band', 'The standard for deep space',
    'A higher frequency packs the signal into a tighter beam: about 14 times the data of S-band from the same dish.',
    2.2, 8, 3.5, 0, 2, bcCube, 1.0, 150, 1.0, 0, 0, 0, 0);
  AddPart(pkBand, 'ka', 'Ka-band', 'Used by LRO, Kepler and JWST',
    'Tighter beam again, four times the data of X-band. Rain on Earth can block it and the dish must be pointed precisely.',
    5, 10, 7, 0.1, 3, bcSmall, 4.0, 800, 0.9, 1, 0, 0, 0);
  AddPart(pkBand, 'opt', 'Laser communications', 'Demonstrated by DSOC on Psyche and LCRD',
    'Sends data on a laser beam: tens of times faster than radio. Clouds block it and it demands extremely steady pointing.',
    28, 80, 42, 0.75, 4, bcSmall, 60, 2000, 0.65, 2, 0, 0, 0);

  { ---- Transmitter ---- }
  AddPart(pkTx, 'tx5', '5 W transmitter', 'Solid-state amplifier',
    'About the power of a bicycle lamp. Enough close to Earth.',
    0.6, 22, 0.5, 0, 0, bcCube, 5, 0, 0, 0, 0, 0, 0);
  AddPart(pkTx, 'tx20', '20 W transmitter', 'Solid-state amplifier',
    'Four times the signal, and four times the data, for 70 W of electricity.',
    2, 70, 1.8, 0, 1, bcCube, 20, 0, 0, 0, 0, 0, 0);
  AddPart(pkTx, 'tx100', '100 W travelling-wave tube', 'As on Mars Reconnaissance Orbiter',
    'The loudest voice available. Drinks over 200 W while transmitting.',
    6.5, 210, 6, 0, 2, bcSmall, 100, 0, 0, 0, 0, 0, 0);

  { ---- Ground network ---- }
  AddPart(pkGround, 'basic', 'Basic: one short contact a day', 'A shared 34 m dish',
    'The cheapest plan. Around 2 hours a day in deep space, or a couple of passes a day in low Earth orbit.',
    0, 0, 0.8, 0, 0, bcCube, 2, 0.3, 1.0, 0, 0, 0, 0);
  AddPart(pkGround, 'standard', 'Standard: daily 8-hour track', 'A normal Deep Space Network schedule',
    'One full shift of listening per day, or half a dozen passes a day near Earth.',
    0, 0, 3.5, 0, 1, bcCube, 8, 0.9, 1.0, 0, 0, 0, 0);
  AddPart(pkGround, 'premium', 'Premium: 70 m dishes, long tracks', 'Priority time on the biggest antennas',
    'Fourteen hours a day on the 70 m giants, which hear four times fainter signals. Near Earth, a station on every orbit.',
    0, 0, 11, 0, 2, bcCube, 14, 2.2, 4.2, 0, 0, 0, 0);

  { ---- Risk posture (NASA mission risk classes) ---- }
  AddPart(pkRisk, 'classd', 'Class D: lean and single-string', 'Lunar Trailblazer, most CubeSats',
    'Commercial parts, one of everything, light testing. About 20 % cheaper and faster, but failures are more than twice as likely.',
    0, 0, 0, -0.4, 0, bcCube, 0.80, 0.95, 2.2, -0.4, 0, 0, 0);
  AddPart(pkRisk, 'classc', 'Class C: selective backups', 'Many Discovery-class missions',
    'Spares for the things most likely to fail, and thorough testing.',
    0, 0, 0, 0, 1, bcCube, 1.0, 1.0, 1.0, 0, 0, 0, 0);
  AddPart(pkRisk, 'classb', 'Class B: fully redundant', 'Flagships such as Europa Clipper',
    'Two of everything important and exhaustive testing. A third more cost, more mass and time, but less than half the failures.',
    0, 0, 0, 0.8, 2, bcCube, 1.35, 1.15, 0.45, 0.8, 0, 0, 0);

  { ---- Schedule ---- }
  AddPart(pkSchedule, 'standard', 'Standard schedule', 'A normal development pace',
    'Enough time to design, build and test properly.',
    0, 0, 0, 0, 0, bcCube, 1.0, 1.0, 1.0, 0, 0, 0, 0);
  AddPart(pkSchedule, 'fast', 'Accelerated schedule', 'Around-the-clock shifts, parallel work',
    'A quarter less time for about 18 % more money. Less testing means more risk.',
    0, 0, 0, 0, 1, bcCube, 0.75, 1.18, 1.35, 0, 0, 0, 0);
end;

procedure BuildLaunchers;
begin
  AddLauncher('rideshare', 'Rideshare slot', 'Commercial rideshare',
    'A seat on someone else''s rocket. By far the cheapest way up, but you go where and when the main passenger goes.',
    0, 350, 0, 450, 100000, 1.2, 0.985, bcSmall, True, 1);
  AddLauncher('electron', 'Electron', 'Rocket Lab (USA / New Zealand)',
    'A small dedicated rocket. With its kick stage it sent the 25 kg CAPSTONE CubeSat to the Moon.',
    300, 200, 0, 55, 14, 8, 0.93, bcSmall, False, 0);
  AddLauncher('alpha', 'Firefly Alpha', 'Firefly Aerospace (USA)',
    'A one-tonne-class small launcher with a short flight record.',
    1030, 630, 0, 0, 1, 15.5, 0.86, bcSmall, False, 0);
  AddLauncher('pslv', 'PSLV-XL', 'ISRO (India)',
    'India''s workhorse. It launched Chandrayaan-1 to the Moon and Mangalyaan to Mars.',
    3800, 1750, 1425, 500, 18, 30, 0.95, bcMedium, False, 1);
  AddLauncher('vegac', 'Vega-C', 'ESA / Italy',
    'Europe''s light launcher, built for polar Earth-observation satellites.',
    3300, 2250, 0, 0, 1, 42, 0.90, bcMedium, False, 1);
  AddLauncher('lvm3', 'LVM3', 'ISRO (India)',
    'India''s heavy lifter. It sent Chandrayaan-3 on its way to the Moon.',
    8000, 6000, 4000, 2300, 30, 52, 0.97, bcLarge, False, 2);
  AddLauncher('h3', 'H3', 'JAXA (Japan)',
    'Japan''s new flagship rocket, chosen to launch the MMX mission to the moons of Mars.',
    6500, 4000, 6500, 3600, 42, 55, 0.93, bcLarge, False, 2);
  AddLauncher('falcon9', 'Falcon 9', 'SpaceX (USA)',
    'The most-flown rocket in the world, with a reusable first stage. Launched DART, TESS and IXPE for NASA.',
    17500, 11000, 5500, 3400, 38, 70, 0.99, bcLarge, False, 2);
  AddLauncher('ariane64', 'Ariane 64', 'ESA / ArianeGroup (Europe)',
    'Europe''s heavy launcher with four boosters.',
    21650, 15500, 11500, 7400, 46, 125, 0.96, bcLarge, False, 3);
  AddLauncher('vulcan', 'Vulcan Centaur', 'United Launch Alliance (USA)',
    'Successor to the Atlas V that launched MRO, MAVEN, LRO, Juno and OSIRIS-REx. Its Centaur upper stage excels at high-energy escapes.',
    24600, 20000, 11300, 8500, 52, 135, 0.96, bcLarge, False, 3);
  AddLauncher('falconheavy', 'Falcon Heavy (expendable)', 'SpaceX (USA)',
    'Three Falcon 9 cores strapped together. Launched Psyche and Europa Clipper.',
    63800, 45000, 26700, 15000, 45, 150, 0.985, bcLarge, False, 3);
  AddLauncher('sls', 'Space Launch System', 'NASA (USA)',
    'The Moon rocket. It can throw a spacecraft straight to Jupiter, at a price that swallows most budgets whole.',
    95000, 0, 40000, 26000, 48, 2200, 0.97, bcLarge, False, 3);
end;

procedure BuildGlossary;
begin
  AddTerm('Payload', 'The science instruments: the reason the mission exists.',
    'Everything else on the spacecraft is there to carry, power, point and talk for the payload.');
  AddTerm('Bus', 'The spacecraft body and all its support systems.',
    'A bigger bus carries more instruments, but needs more fuel and a bigger rocket.');
  AddTerm('Trade study', 'Comparing options by what each one costs and gains.',
    'There is rarely one right answer. Good teams compare several designs before choosing.');
  AddTerm('Mass margin', 'Spare lifting capacity between your spacecraft and what the rocket can carry.',
    'Spacecraft almost always gain weight while being built. NASA teams start with 25 to 30 % in hand.');
  AddTerm('Power margin', 'Spare electricity beyond what the spacecraft needs.',
    'Solar panels fade and instruments draw more than planned. Without margin, something has to be switched off.');
  AddTerm('Delta-v', 'The total change in speed a spacecraft can make with its engines.',
    'Every manoeuvre, from braking into orbit to staying there, spends delta-v. When it is gone, the mission is over.');
  AddTerm('Rocket equation', 'The rule that fuel needs fuel to carry it.',
    'Doubling the speed change needs far more than double the propellant. This is why spacecraft are mostly fuel tank.');
  AddTerm('Specific impulse', 'How much push an engine gets from each kilogram of propellant.',
    'Higher is better. Chemical engines reach about 320 seconds, ion engines about 1,800 or more.');
  AddTerm('Launch energy (C3)', 'How hard the rocket must throw the spacecraft to escape Earth.',
    'The higher the energy, the less mass a rocket can send. Far-off worlds need a bigger rocket or a slower route.');
  AddTerm('Launch window', 'The dates when the planets line up for the trip.',
    'For Mars it opens for a few weeks every 26 months. Miss it and you wait.');
  AddTerm('Gravity assist', 'Stealing speed from a planet by flying close past it.',
    'It saves launch energy, so a smaller rocket will do, but adds years to the journey.');
  AddTerm('Aerobraking', 'Dipping into the top of an atmosphere to slow down for free.',
    'It saves hundreds of kilograms of fuel but takes months of careful flying.');
  AddTerm('Inclination', 'How steeply an orbit is tilted from the equator.',
    'A spacecraft can only fly over latitudes up to its inclination. To see the poles you need a polar orbit.');
  AddTerm('Sun-synchronous orbit', 'A near-polar orbit that passes over each place at the same local time of day.',
    'The lighting is always the same, so pictures from different days can be compared.');
  AddTerm('Geostationary orbit', 'An orbit 35,786 km up where a satellite keeps pace with Earth''s rotation.',
    'It stares at the same third of the planet all the time, but from far away, so detail is poor.');
  AddTerm('Eclipse', 'The part of each orbit spent in the shadow of a planet or moon.',
    'Solar panels make nothing in shadow, so the battery has to carry the whole spacecraft.');
  AddTerm('RTG', 'A nuclear battery that turns the heat of decaying plutonium into electricity.',
    'It works anywhere, even far from the Sun, but is heavy, scarce and very expensive.');
  AddTerm('Data rate', 'How many bits per second the spacecraft can send home.',
    'It falls with the square of distance. Twice as far means a quarter of the data.');
  AddTerm('Deep Space Network', 'NASA''s giant dish antennas in California, Spain and Australia.',
    'Every deep-space mission shares them, so listening time is rationed and costs money.');
  AddTerm('Light-time delay', 'How long a radio signal takes to cross the distance.',
    'About 1.3 seconds to the Moon, up to 22 minutes to Mars, around 45 minutes to Jupiter. The spacecraft must look after itself.');
  AddTerm('Attitude control', 'How a spacecraft knows which way it faces and turns to point.',
    'Sharp cameras and narrow radio beams need steady pointing. Coarse pointing blurs both.');
  AddTerm('Radiation', 'High-energy particles from the Sun, deep space and planetary radiation belts.',
    'They scramble and slowly destroy electronics. Jupiter''s belts are the harshest in the solar system.');
  AddTerm('Safe mode', 'A protective state: instruments off, panels to the Sun, wait for help.',
    'It saves the spacecraft, but every day in safe mode is a day without science.');
  AddTerm('Risk class', 'NASA grades missions from A (must not fail) to D (cheap, higher risk accepted).',
    'More backups and testing cost money, mass and time. The right level depends on what you can afford to lose.');
  AddTerm('Reserves', 'Money set aside for problems nobody has thought of yet.',
    'Problems always appear. NASA expects about 25 % in reserve when a mission is confirmed.');
  AddTerm('Threshold and baseline science', 'The minimum result that still counts as success, and the full result you are aiming for.',
    'Knowing the minimum tells a team what can be cut when trouble comes.');
  AddTerm('Concept Maturity Level', 'NASA JPL''s scale for how well thought-out a mission idea is, from a sketch (1) to a full point design (4) and beyond.',
    'This game walks an idea up that ladder: objective, trade space, point design, review.');
end;

initialization
  BuildInstruments;
  BuildParts;
  BuildLaunchers;
  BuildGlossary;

end.
