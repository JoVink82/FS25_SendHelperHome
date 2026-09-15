# FS25_SendHelperHome — technische notities (v0.4.0.0)

**Bevestigd in-game werkend (door Dennis getest):** de kernfunctie — helper
rijdt automatisch naar het opgeslagen thuis-punt zodra het veld echt klaar is
— draait zoals bedoeld. Dat bevestigt het hele AIJob/AIMessage/AIJobGoTo-
mechanisme hieronder.

## Wat deze mod doet

Zodra een ingehuurde AI-helper een veld **volledig** heeft afgewerkt, rijdt hij
automatisch naar een zelf ingesteld "thuis"-punt op je erf. Bij elke andere
stopreden (lege tank, geen brandstof, zelf gestopt, ...) verandert er niets aan
het standaardgedrag van het spel.

## Hoe het werkt (geverifieerd tegen basisspel-broncode)

`device_bash` (de shell op je pc) werkte tijdens deze sessie niet door een
bekend Windows-update-probleem (8 september), en `dataS.gar` is met 3,3 GB te
groot om in deze sessie te uploaden. In plaats van zelf te decompileren is de
exacte API dus geverifieerd via:

- De officiële GIANTS Developer Network scripting-documentatie
  (`gdn.giants-software.com/documentation_scripting_fs25.php`), en
- Een community-repo met de daadwerkelijke gedecompileerde FS25-scripts
  (`github.com/Dukefarming/FS25-lua-scripting`), waarin de volgende bestanden
  letterlijk zijn nagelezen: `ai/jobs/AIJob.lua`, `ai/jobs/AIJobFieldWork.lua`,
  `ai/jobs/AIJobGoTo.lua`, `ai/AISystem.lua`, `ai/AIJobTypeManager.lua`,
  `ai/tasks/AITaskFieldWork.lua`, `ai/tasks/AITaskDriveTo.lua`.

Kernmechanisme:

1. `AIJob:update(dt)` roept, zodra de laatste taak van een job klaar is en er
   geen volgende taak is, `g_currentMission.aiSystem:stopJob(self, AIMessageSuccessFinishedJob.new())`
   aan. Dat is de enige plek waar "job echt succesvol klaar" wordt gemeld —
   andere stopredenen gebruiken andere `AIMessage`-subklassen
   (`AIMessageErrorOutOfFuel`, `AIMessageErrorOutOfFill`,
   `AIMessageSuccessStoppedByUser`, ...).
2. `AISystem:stopJobInternal(job, aiMessage)` publiceert daarna altijd
   `g_messageCenter:publish(MessageType.AI_JOB_STOPPED, job, aiMessage)`.
   Onze mod abonneert zich hierop (`g_messageCenter:subscribe`) — dit vereist
   geen enkele functie te overschrijven, dus botst niet met andere mods.
3. In de listener wordt gecontroleerd of `job:isa(AIJobFieldWork)` en
   `aiMessage:isa(AIMessageSuccessFinishedJob)`. Zo niet, wordt niets gedaan.
4. Zo ja: er wordt een nieuwe `AIJobGoTo`-job aangemaakt via
   `g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)` — hetzelfde
   job-type dat het spel zelf gebruikt om voertuigen zelfstandig (via de
   navigatie/wegen) naar een positie te sturen — met als doel het opgeslagen
   thuis-punt, en gestart via `g_currentMission.aiSystem:startJob(job, farmId)`.

## Thuis-punt instellen (v0.3.0.0)

Twee gelijkwaardige manieren:

- **Toetsencombinatie** (aanbevolen): `Ctrl+L` slaat de huidige positie op
  (van het voertuig waarin je zit, anders je speler) als thuis-punt voor jouw
  boerderij, met een melding in beeld "Helper home punt ingesteld";
  `Alt+L` wist het weer ("Helper home punt gewist"). Beide zijn herbindbaar
  via Opties > Besturing, omdat ze als echte `<action>`/`<inputBinding>` in
  modDesc.xml staan (zelfde mechanisme als bv. de mod Tardis Teleport of
  AdditionalInputs gebruikt) en via `g_inputBinding:registerActionEvent(...)`
  in `SendHelperHome:registerActionEvents()` worden aangemeld.
- **Consolecommando's** (`~` toets): `shhSetHome` / `shhClearHome` — blijven
  bestaan, o.a. handig op een dedicated server, en geven een uitgebreidere
  tekst terug (incl. coördinaten) in de console zelf.

Wordt bewaard in `<savegame>/SendHelperHome.xml`, geschreven zodra het spel
opslaat (haakt in op `ItemSystem.save`, zelfde patroon als bv. de mod
FS25_ContractBoost gebruikt voor zijn eigen instellingen-XML).

### v0.2.0.0 (Ctrl+Home/Alt+Home) deed niks — twee vermoedelijke oorzaken, beide gefixt

1. **Toetsnaam**: `KEY_home` was nooit 1-op-1 bevestigd in echte broncode (zie
   git-geschiedenis van dit bestand). Nu vervangen door `KEY_l` (gewone letter,
   exact zoals bevestigd in meerdere actuele FS25-mods, o.a.
   `loki79uk/FS25_MapObjectsHider` dat letterlijk `KEY_h` gebruikt).
2. **Ontbrekend `category`-attribuut**: onze `<action>`-elementen hadden geen
   `category`, terwijl een echte, actuele FS25-mod met een globaal (niet aan
   een voertuig gebonden) keybind-script —
   `loki79uk/FS25_MapObjectsHider/modDesc.xml` — altijd `category="ONFOOT"`
   (of `"ONFOOT VEHICLE"`) meegeeft. Zonder category lijkt de actie in de
   huidige FS25-schemaversie (descVersion 106) niet in een bruikbare context
   geregistreerd te worden. Nu toegevoegd: `category="ONFOOT VEHICLE"` op
   beide acties, zodat ze zowel lopend als in een voertuig werken.

Extra bevestiging van het algemene patroon: `loki79uk/FS25_LumberJack` is een
**globaal** modscript (net als SendHelperHome, geen voertuig-specialization)
dat op precies dezelfde manier werkt: `addModEventListener(LumberJack)` +
`LumberJack:loadMap()` + `g_inputBinding:registerActionEvent('LUMBERJACK_STRENGTH',
LumberJack, LumberJack.strengthKeyCallback, true, true, false, true)`. Dat is
structureel identiek aan `SendHelperHome:registerActionEvents()`.

Als Ctrl+L/Alt+L na deze fix nog steeds niks doet: check `log.txt` op een
waarschuwing over `SHH_SET_HOME`/`SHH_CLEAR_HOME` bij het laden van de mod, en
kijk in Opties > Besturing of de acties "Send Helper Home: ..." in de lijst
staan (dan zijn ze wel geregistreerd, maar niet per ongeluk overschreven door
een andere mod/toets — gewoon zelf een andere toets toewijzen). De
consolecommando's blijven in elk geval een werkende fallback.

### v0.3.0.0 (category-fix) werkte ook nog niet — ontbrekende `setActionEventActive`

Na de category-fix meldde Dennis dat de toetsen nog steeds niet reageerden,
zowel niet lopend als niet in een voertuig. Bij het opnieuw vergelijken met
een structureel identieke, echte, gepubliceerde globale mod —
`loki79uk/FS25_LumberJack` (ook geen voertuig-specialization, ook
`addModEventListener` + `g_inputBinding:registerActionEvent(...)` in
`loadMap`) — viel op dat die mod na het registreren altijd
`g_inputBinding:setActionEventActive(actionEventId, true)` aanroept. Die
aanroep ontbrak in `SendHelperHome:registerActionEvents()`: de actie werd wel
aangemeld bij het inputsysteem, maar nooit actief gezet, waardoor er geen
toetsaanslag werd doorgegeven — in beide standen (lopend/voertuig), wat
verklaart waarom hij in geen van beide werkte.

**Fix in v0.4.0.0:**

1. `setActionEventActive(id, true)` toegevoegd voor beide acties, direct na
   een succesvolle `registerActionEvent`.
2. Een idempotency-guard in `registerActionEvents()`: als
   `self.actionEventIds` al gevuld is, wordt niet opnieuw geregistreerd (voorkomt
   dubbele actie-events als de functie per ongeluk twee keer wordt aangeroepen).
3. Een nieuwe `SendHelperHome:update(dt)` als vangnet: zolang
   `self.actionEventIds` leeg is, wordt `registerActionEvents()` elke frame
   opnieuw geprobeerd. Dit dekt af of `g_inputBinding` tijdens `loadMap()`
   misschien nog niet volledig klaar was (zou anders alsnog stil falen).
4. `Logging.info(...)` toegevoegd die het `(success, id)`-resultaat van beide
   `registerActionEvent`-aanroepen naar `log.txt` schrijft, zodat bij een
   volgend probleem direct te zien is of registratie zelf al faalt (dan staat
   er `success=false`) of dat het probleem verderop zit.

**Nog niet in-game bevestigd door Dennis** — dit is de meest onderbouwde fix
tot nu toe (gebaseerd op een concreet verschil met een echte werkende mod),
maar moet nog getest worden, zowel lopend als in een voertuig.

## Bekende beperkingen / volgende stappen

- **Geen fysiek plaatsbaar object**: de gebruiker koos bewust voor een
  toetsencombinatie in plaats van een placeable/3D-marker (zou een eigen
  I3D-model vragen dat er nu niet is). Thuis-punt is alleen data (x, z, hoek),
  er verschijnt geen zichtbare markering op de kaart.
- **Multiplayer**: zowel de toetsen als de consolecommando's werken alleen
  betrouwbaar in singleplayer of wanneer uitgevoerd op de host/server. Er is
  nog geen netwerk-event dat een client-actie naar de server synchroniseert.
- **Toetsencombinatie nog niet in-game bevestigd**: de kern (AI-detectie +
  AIJobGoTo) is bevestigd werkend; Ctrl+L/Alt+L zelf is na v0.2 en v0.3 beide
  keren gemeld als niet-werkend. v0.4.0.0 voegt de ontbrekende
  `setActionEventActive`-aanroep toe (zie hierboven) plus een retry-vangnet en
  uitgebreidere logging, maar is nog niet door Dennis getest
  (device_bash op deze pc bleef de hele sessie onbereikbaar, dus geen eigen
  test mogelijk vanuit Claude). Als het nog steeds niet werkt: graag de
  regels uit `log.txt` met "SendHelperHome" erin doorgeven — die laten precies
  zien of `registerActionEvent` `success=true` teruggeeft of niet.
- Zodra `device_bash` weer werkt (of dataS.gar los geëxtraheerd kan worden),
  kan de exacte broncode nogmaals 1-op-1 gecontroleerd worden tegen de
  daadwerkelijke FS25 1.20-installatie op deze pc, in plaats van tegen de
  community-repo's.
