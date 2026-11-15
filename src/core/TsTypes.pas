unit TsTypes;

{ Atomic Space - shared types for the mission engine.

  This unit is plain Object Pascal with no browser dependencies, so it can be
  compiled by Delphi, Free Pascal or pas2js.

  AI-assistance note: written with the help of Claude (Anthropic). }

{$IFDEF PAS2JS}{$mode delphi}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$ENDIF}

interface

const
  GameName = 'Atomic Space';
  GameTagline = 'Design it. Fly it. Find out why.';
  GameVersion = '1.0';

  { Physical constants used by the engine }
  G0 = 9.80665;                 // standard gravity, m/s^2 (rocket equation)
  SolarConstant = 1361.0;       // W/m^2 at 1 AU
  ArrayWattsPerM2 = 250.0;      // usable end-of-life output per m^2 at 1 AU
  ArrayKgPerM2 = 3.4;           // panel + substrate + deployment
  ArrayCostPerM2 = 0.32;        // $M per m^2
  BatteryWhPerKg = 130.0;       // pack-level specific energy
  BatteryCostPerWh = 0.0022;    // $M per Wh
  RtgWatts = 110.0;             // one MMRTG at start of life
  RtgKg = 45.0;
  RtgCostM = 95.0;
  RtgDecayPerYear = 0.03;
  LinkK = 0.0012;               // Mbps per (W * m^2) at 1 AU into a 34 m dish
  WrapFraction = 0.23;          // management, systems engineering, assembly and test
  HarnessFraction = 0.07;       // cabling and small parts, share of dry mass
  DvMargin = 0.10;              // extra propellant held back for surprises
  AuKm = 149597870.7;
  LightSecondsPerAu = 499.0;

type
  { What an instrument can measure }
  TMeasure = (mImaging, mSpectral, mThermal, mRadar, mTopo, mVolatiles,
    mAtmos, mFields, mService);
  TMeasureValues = array[TMeasure] of Double;

  TBusClass = (bcCube, bcSmall, bcMedium, bcLarge);
  TLvMode = (lvLEO, lvSSO, lvGTO, lvC3);
  TSeverity = (svGood, svInfo, svWarn, svBlock);
  TRole = (roPM, roScience, roSpacecraft, roOps);
  TDifficulty = (dfCadet, dfEngineer, dfChief);

  TPartKind = (pkBus, pkPropulsion, pkAdcs, pkThermal, pkComputer, pkShield,
    pkAntenna, pkBand, pkTx, pkGround, pkRisk, pkSchedule);

  { A wide integer that works in Delphi (64 bit) and in the browser (53 bit) }
  {$IFDEF PAS2JS}
  TBigInt = NativeInt;
  {$ELSE}
  TBigInt = Int64;
  {$ENDIF}

  TStringArray = array of string;
  TDoubleArray = array of Double;
  TIntArray = array of Integer;
  TBoolArray = array of Boolean;

  { A science instrument that can be flown }
  TInstrument = record
    Id, Name, Analog, Blurb: string;
    MassKg, PowerW, CostM: Double;
    DataMbps: Double;      // data produced while observing
    Duty: Double;          // share of the time it observes
    DevYears: Double;      // development time it adds
    Value: TMeasureValues; // how well it measures each thing (0..100)
    NeedsFinePointing, NeedsCooling, NeedsHGA: Boolean;
    MinBus: TBusClass;
  end;

  { One selectable option of a spacecraft subsystem or programme decision.
    A..G are kind-specific numbers, documented in TsCatalog. }
  TPart = record
    Kind: TPartKind;
    Id, Name, Analog, Blurb: string;
    MassKg, PowerW, CostM, DevYears: Double;
    A, B, C, D, E, F, G: Double;
    Tier: Integer;
    MinBus: TBusClass;
  end;
  TPartArray = array of TPart;

  TLauncher = record
    Id, Name, Agency, Blurb: string;
    LeoKg, SsoKg, GtoKg: Double;
    C3ZeroKg, C3K: Double;  // capacity to escape = C3ZeroKg * exp(-C3 / C3K)
    CostM, Reliability: Double;
    MaxBus: TBusClass;
    Rideshare: Boolean;
    Size: Integer;          // 0 small .. 3 super heavy, used by the launch scene
  end;

  TOrbit = record
    Id, Name, Blurb, Why: string;
    AltKm, ApoKm, IncDeg, PeriodHr: Double;
    EclipseFrac, MaxEclipseHr: Double;
    Coverage: Double;        // share of the primary targets this orbit can reach
    Factor: TMeasureValues;  // quality multiplier per measurement
    Base: TMeasureValues;    // Factor before live Earth-event data is applied
    EventsSeen, EventsTotal: Integer; // real NASA EONET events in view (Earth only)
    TauFactor: Double;       // <1 finishes the survey faster
    DataFactor: Double;      // share of the time there is anything to record (a flyby is brief)
    CommFactor: Double;      // multiplies ground contact time
    RangeKm: Double;         // distance to the ground station (near-Earth only)
    DvInsert, DvPerYear: Double;
    LvMode: TLvMode;
    C3: Double;              // launch energy when it sets its own (otherwise the transfer does)
    ExtraYears: Double;      // e.g. aerobraking
    InsertRisk: Double;
    RadLevel: Integer;       // 0 benign .. 3 extreme
    RadLifeYears: Double;    // electronics wear-out time at standard protection (0 = no limit)
    DragLifeYears: Double;   // orbit lifetime without propulsion (0 = no limit)
    NeedsDeorbit: Boolean;
    IsGeo: Boolean;
    GeoLon: Double;
  end;

  TTransfer = record
    Id, Name, Blurb: string;
    C3: Double;
    CruiseYears: Double;
    DvFactor: Double;        // multiplies the orbit insertion delta-v
    HotFlyby: Boolean;       // passes close to the Sun or Venus: needs active thermal control
  end;

  TGlossaryItem = record
    Term, Plain, Why: string;
  end;

  { A real natural event on Earth, from NASA EONET }
  TEarthEvent = record
    Title, Category, Date: string;
    Lat, Lon: Double;
  end;
  TEarthEventArray = array of TEarthEvent;

  { A real space-weather event, from NASA DONKI }
  TSpaceWeather = record
    Kind, Date, ClassType: string;  // Kind: FLR, GST or SEP
    Strength: Double;               // 0..1 game severity
  end;
  TSpaceWeatherArray = array of TSpaceWeather;

  { A real mission the player's design can be compared with }
  TAnalog = record
    Name, Agency, Year, Blurb, Url: string;
    MassKg, CostM: Double;
    Instruments: Integer;
  end;

  TScenario = record
    Id, Name, Tagline, Body, Brief, Objective: string;
    Level: Integer;          // 1 beginner .. 3 advanced
    CostCapM: Double;
    DeadlineYears: Double;   // launch (or arrive, see ArriveBy) no later than this
    WindowYears: Double;     // first launch window (0 = launch any time)
    WindowPeriod: Double;    // spacing of later windows
    ArriveBy: Boolean;       // deadline applies to arrival, not launch
    LateFactor: Double;      // science multiplier when the deadline is missed
    MinLife, MaxLife, DefaultLife: Double;
    SunAU, EarthMinAU, EarthMaxAU, SynodicDays: Double;
    NearEarth: Boolean;
    DataScale: Double;       // share of the time instruments record (far away you must be choosy)
    HeaterW: Double;         // survival heater power for a small bus
    ColdWorld: Boolean;      // needs active thermal control
    AllowRTG, AllowSEP: Boolean;
    SepDvFactor, SepExtraYears: Double;
    Weight: TMeasureValues;
    FullScience: Double;     // capability sum that counts as 100 %
    ThresholdPct: Double;    // minimum for mission success
    TauYears: Double;        // time constant for completing the survey
    Orbits: array of TOrbit;
    Transfers: array of TTransfer;
    Instruments: TStringArray;
    Analogs: array of TAnalog;
    Facts: TStringArray;
    UsesEonet, UsesApophis: Boolean;
  end;

  { Everything the player decides }
  TDesign = record
    Scenario: Integer;
    Difficulty: TDifficulty;
    Sandbox: Boolean;
    Orbit, Transfer: Integer;
    Part: array[TPartKind] of Integer;
    Launcher: Integer;
    Instr: TBoolArray;       // indexed like the global instrument list
    SolarM2: Double;
    RtgCount: Integer;
    BatteryWh: Double;
    LifeYears: Double;
    ReservePct: Double;
    Seed: Integer;
  end;

  TFinding = record
    Sev: TSeverity;
    Code, Title, Why, Fix: string;
    Owner: TRole;
  end;
  TFindingArray = array of TFinding;

  TLine = record
    Name: string;
    Value: Double;
  end;
  TLineArray = array of TLine;

  { The result of analysing a design }
  TAnalysis = record
    // mass
    PayloadKg, DryKg, PropKg, WetKg, LvCapKg, MassMargin: Double;
    MassLines: TLineArray;
    // power
    SolarW, RtgW, GenW, GenAvgW, LoadAvgW, LoadPeakW, PowerMargin: Double;
    BatteryNeedWh: Double;
    PowerLines: TLineArray;
    // delta-v
    DvNeed, DvInsert, DvKeep, DvDisposal: Double;
    PropFeasible: Boolean;
    // data and communications
    GenGbitDay, RateAvgMbps, RateMinMbps, ContactHr, DownGbitDay: Double;
    DataReturn, StorageGbit, StorageDays, LightDelayMin: Double;
    // money
    CostHardware, CostWraps, CostLaunch, CostOps, CostReserve, CostTotal: Double;
    CapM, CostMargin: Double;
    DevCostM, OpsPerYearM, SlipCostM: Double;
    CostLines: TLineArray;
    // time
    DevYears, LaunchYear, CruiseYears, ArriveYear, LifeYears, SlipYears: Double;
    MissedDeadline: Boolean;
    // science
    Capability: TMeasureValues;   // after orbit effects, 0..110
    InstrQuality: TDoubleArray;   // per global instrument index
    SciencePct, ScienceMaxPct: Double;
    TauYears, LifeLimitYears: Double;
    LifeLimitWhy: string;
    // risk
    PointingTier, RadExposure: Integer;
    LaunchSuccess, InsertSuccess, YearSurvival, SuccessProb: Double;
    AnomalyRate: Double;   // expected hardware faults per year
    FatalShare: Double;    // share of faults that end the mission
    InstrumentCount: Integer;
    Findings: TFindingArray;
    Blockers, Warnings: Integer;
  end;

const
  MeasureName: array[TMeasure] of string = ('Imaging', 'Composition',
    'Thermal', 'Radar', 'Topography & gravity', 'Volatiles & ice',
    'Atmosphere & weather', 'Fields & particles', 'Relay service');
  MeasureHint: array[TMeasure] of string = (
    'Pictures of the surface: shapes, craters, landforms, change over time.',
    'Splits light into colours to tell what a surface is made of.',
    'Measures heat: fires, lava, day-night temperatures, cold traps.',
    'Bounces radio waves off the ground. Sees through cloud, dark and even ice.',
    'Measures heights and gravity, which reveal the inside of a world.',
    'Sniffs out hydrogen, water and other easily-vapourised materials.',
    'Profiles temperature, moisture, gases and storms in an atmosphere.',
    'Senses magnetic fields, charged particles and dust around the spacecraft.',
    'Relays data for other missions. Not science itself, but valuable.');
  RoleName: array[TRole] of string = ('Project Manager', 'Science Lead',
    'Spacecraft Engineer', 'Comms & Ops Lead');
  RoleShort: array[TRole] of string = ('PM', 'SCI', 'ENG', 'OPS');
  DifficultyName: array[TDifficulty] of string = ('Cadet', 'Engineer', 'Chief Engineer');
  BusClassName: array[TBusClass] of string = ('CubeSat', 'SmallSat', 'Medium probe', 'Flagship');

function Clamp(X, Lo, Hi: Double): Double;
function MaxD(A, B: Double): Double;
function MinD(A, B: Double): Double;
procedure AddLine(var L: TLineArray; const AName: string; AValue: Double);
procedure AddStr(var L: TStringArray; const S: string);

implementation

function Clamp(X, Lo, Hi: Double): Double;
begin
  if X < Lo then
    Result := Lo
  else if X > Hi then
    Result := Hi
  else
    Result := X;
end;

function MaxD(A, B: Double): Double;
begin
  if A > B then Result := A else Result := B;
end;

function MinD(A, B: Double): Double;
begin
  if A < B then Result := A else Result := B;
end;

procedure AddLine(var L: TLineArray; const AName: string; AValue: Double);
var
  N: Integer;
begin
  N := Length(L);
  SetLength(L, N + 1);
  L[N].Name := AName;
  L[N].Value := AValue;
end;

procedure AddStr(var L: TStringArray; const S: string);
var
  N: Integer;
begin
  N := Length(L);
  SetLength(L, N + 1);
  L[N] := S;
end;

end.
