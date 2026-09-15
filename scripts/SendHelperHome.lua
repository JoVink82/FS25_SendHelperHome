--[[
    SendHelperHome.lua

    Stuurt de AI-helper (ingehuurde arbeider) automatisch naar een zelf ingesteld
    "thuis"-punt zodra hij het veldwerk van een AIJobFieldWork volledig heeft afgerond.

    Werking (uitgezocht en gecontroleerd tegen de gedecompileerde FS25 basisspel-scripts,
    zie NOTES.md in dit mod-project voor de bronnen):

    - AIJob:update(dt) roept, wanneer de laatste taak van een job klaar is en er geen
      volgende taak meer is, g_currentMission.aiSystem:stopJob(self, AIMessageSuccessFinishedJob.new())
      aan. Dit is het EchTe signaal dat een job succesvol en volledig is afgerond
      (in tegenstelling tot bv. AIMessageErrorOutOfFuel, AIMessageErrorOutOfFill of
      AIMessageSuccessStoppedByUser, die allemaal ook de job stoppen maar niet betekenen
      dat het veld klaar is).
    - AISystem:stopJobInternal(job, aiMessage) publiceert daarna altijd
      g_messageCenter:publish(MessageType.AI_JOB_STOPPED, job, aiMessage).
      Dat is de veilige, ondersteunde plek om op te reageren: we hoeven geen bestaande
      functie te overschrijven, alleen te abonneren op dit bericht.
    - Als het gestopte job-type AIJobFieldWork is EN het aiMessage-type
      AIMessageSuccessFinishedJob is, starten we zelf een nieuwe AIJobGoTo-job voor
      hetzelfde voertuig, met als doel het opgeslagen thuis-punt van de boerderij.
      AIJobGoTo is het job-type dat het spel zelf ook gebruikt om voertuigen zelfstandig
      (via de weg/navigatie) naar een positie te laten rijden.

    Thuis-punt instellen kan op twee manieren:
    - Toetsencombinatie: Ctrl+L (SHH_SET_HOME) slaat de huidige positie op,
      Alt+L (SHH_CLEAR_HOME) wist hem weer. Beide zijn herbindbaar via
      Opties > Besturing (zie de <actions>/<inputBinding>/<l10n> secties in modDesc.xml).
      De acties hebben bewust GEEN category-attribuut (zoals FS25_AutoDrive en
      FS25_Tardis dat ook niet hebben voor hun globale acties), zodat ze in elke
      context actief zijn -- zowel lopend als in een voertuig. Een eerdere versie
      gebruikte category="ONFOOT VEHICLE", maar die combinatie komt in geen enkele
      geverifieerde, echt werkende FS25-mod voor; alle onderzochte voorbeelden
      gebruiken óf een losse category (bv. "ONFOOT") óf laten hem helemaal weg.
    - Consolecommando's shhSetHome / shhClearHome (blijven ook werken, o.a. handig
      op een dedicated server zonder los toetsenbord-invoer).

    BELANGRIJK (v0.7.0.0, uitgebreid getest door Dennis): registerActionEvent meldde
    altijd al 'success=true' bij het laden, en de acties waren gewoon zichtbaar/rebindbaar
    in Opties > Besturing -- maar de toetsen deden desondanks niets, ook niet met een
    simpele, niet-gecombineerde toets zonder enige conflicterende binding (dus geen
    combo-/categorie-/conflictprobleem). De exacte engine-oorzaak is niet met zekerheid
    vastgesteld, maar het actionEventId lijkt na verloop van tijd stil ongeldig te worden.
    Fix: SendHelperHome:update(dt) her-registreert de actie-events nu periodiek (elke 5s)
    geforceerd via registerActionEvents(true), ook als er al een (mogelijk verweesd)
    actionEventId bestaat. Dit is empirisch bevestigd als werkende oplossing.

    Bekende beperkingen van deze eerste versie:
    - Geen GUI/plaatsbaar object in de wereld: het thuis-punt is alleen data (x, z, hoek),
      er verschijnt geen markering op de kaart.
    - Werkt het beste in singleplayer of als je het zelf uitvoert op de host/server;
      in multiplayer als client is er nog geen netwerksynchronisatie voor het instellen
      van het thuis-punt.
]]

SendHelperHome = {}
SendHelperHome.MOD_NAME = g_currentModName or "FS25_SendHelperHome"
SendHelperHome.modDirectory = g_currentModDirectory or ""
SendHelperHome.homePositions = {}

-- ============================================================================
-- Mission lifecycle
-- ============================================================================

function SendHelperHome:loadMap(name)
    self.homePositions = {}

    if g_server ~= nil then
        self.xmlSchema = self:initXMLSchema()
        self:loadHomePositions()
    end

    g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, self.onAIJobStopped, self)

    addConsoleCommand(
        "shhSetHome",
        g_i18n:getText("shh_console_setHome_desc"),
        "consoleCommandSetHome",
        self
    )
    addConsoleCommand(
        "shhClearHome",
        g_i18n:getText("shh_console_clearHome_desc"),
        "consoleCommandClearHome",
        self
    )

    self:registerActionEvents()

    Logging.info("[SendHelperHome] geladen. Druk Ctrl+L om een thuis-punt in te stellen, Alt+L om te wissen (of gebruik 'shhSetHome'/'shhClearHome' in de console).")
end

function SendHelperHome:deleteMap()
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end

    removeConsoleCommand("shhSetHome")
    removeConsoleCommand("shhClearHome")

    self:removeActionEvents()
end

-- ============================================================================
-- Toetsencombinaties (Ctrl+L / Alt+L), zie <actions>/<inputBinding> in modDesc.xml
-- ============================================================================

function SendHelperHome:update(dt)
    -- Vangnet 1: als registreren in loadMap te vroeg was (g_inputBinding nog niet klaar),
    -- proberen we het hier opnieuw.
    if self.actionEventIds == nil or #self.actionEventIds == 0 then
        self:registerActionEvents()
        return
    end

    -- Vangnet 2: BEVESTIGD NODIG (15 sep, door Dennis getest). Zelfs als registerActionEvent
    -- bij het laden 'success=true' meldde en de actie prima zichtbaar/rebindbaar was in
    -- Opties > Besturing, bleek de toets in de praktijk (v0.2 t/m v0.6.1, ook met een simpele
    -- niet-gecombineerde toets zonder enige conflicterende binding) toch niet te reageren.
    -- De exacte engine-oorzaak is niet 100% duidelijk, maar periodiek geforceerd opnieuw
    -- registreren (zelfde actionEventId of niet, maakt niet uit) houdt 'm werkend blijkens
    -- test v0.6.2.0. Interval bewust niet te kort (i.v.m. log.txt-groei over lange sessies).
    self.reregisterTimer = (self.reregisterTimer or 0) + dt
    if self.reregisterTimer >= 5000 then
        self.reregisterTimer = 0
        self:registerActionEvents(true)
    end
end

function SendHelperHome:registerActionEvents(force)
    if g_inputBinding == nil then
        return
    end

    if not force and self.actionEventIds ~= nil and #self.actionEventIds > 0 then
        -- Al geregistreerd, niet dubbel doen (tenzij force=true, zie update(dt)).
        return
    end

    if force then
        self:removeActionEvents()
    end

    self.actionEventIds = {}

    local setSuccess, setEventId = g_inputBinding:registerActionEvent(
        "SHH_SET_HOME", self, SendHelperHome.actionEventSetHome, false, true, false, true
    )
    local clearSuccess, clearEventId = g_inputBinding:registerActionEvent(
        "SHH_CLEAR_HOME", self, SendHelperHome.actionEventClearHome, false, true, false, true
    )

    -- Alleen loggen bij de allereerste registratie of als iets misgaat -- anders spamt de
    -- periodieke her-registratie (Vangnet 2) log.txt vol over een lange speelsessie.
    if not self.hasLoggedRegistration or not setSuccess or not clearSuccess then
        Logging.info(
            "[SendHelperHome] registerActionEvent SHH_SET_HOME -> success=%s id=%s ; SHH_CLEAR_HOME -> success=%s id=%s",
            tostring(setSuccess), tostring(setEventId), tostring(clearSuccess), tostring(clearEventId)
        )
        self.hasLoggedRegistration = true
    end

    if setSuccess and setEventId ~= nil then
        table.insert(self.actionEventIds, setEventId)
        g_inputBinding:setActionEventActive(setEventId, true)
        g_inputBinding:setActionEventTextVisibility(setEventId, true)
        if GS_PRIO_LOW ~= nil then
            g_inputBinding:setActionEventTextPriority(setEventId, GS_PRIO_LOW)
        end
    end

    if clearSuccess and clearEventId ~= nil then
        table.insert(self.actionEventIds, clearEventId)
        g_inputBinding:setActionEventActive(clearEventId, true)
        g_inputBinding:setActionEventTextVisibility(clearEventId, true)
        if GS_PRIO_LOW ~= nil then
            g_inputBinding:setActionEventTextPriority(clearEventId, GS_PRIO_LOW)
        end
    end
end

function SendHelperHome:removeActionEvents()
    if g_inputBinding == nil or self.actionEventIds == nil then
        return
    end

    for _, eventId in ipairs(self.actionEventIds) do
        g_inputBinding:removeActionEvent(eventId)
    end

    self.actionEventIds = nil
end

function SendHelperHome:actionEventSetHome(actionName, inputValue, callbackState, isAnalog)
    Logging.info(
        "[SendHelperHome] KEY-CALLBACK actionEventSetHome gevuurd (actionName=%s inputValue=%s isAnalog=%s)",
        tostring(actionName), tostring(inputValue), tostring(isAnalog)
    )
    local ok, errorMessage = SendHelperHome:doSetHome()
    if ok then
        SendHelperHome:notify(g_i18n:getText("shh_notify_setHome"))
    else
        SendHelperHome:notify(errorMessage)
    end
end

function SendHelperHome:actionEventClearHome(actionName, inputValue, callbackState, isAnalog)
    Logging.info(
        "[SendHelperHome] KEY-CALLBACK actionEventClearHome gevuurd (actionName=%s inputValue=%s isAnalog=%s)",
        tostring(actionName), tostring(inputValue), tostring(isAnalog)
    )
    local ok, errorMessage = SendHelperHome:doClearHome()
    if ok then
        SendHelperHome:notify(g_i18n:getText("shh_notify_clearHome"))
    else
        SendHelperHome:notify(errorMessage)
    end
end

function SendHelperHome:notify(message)
    if message == nil then
        return
    end

    Logging.info("[SendHelperHome] %s", message)

    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, message)
    end
end

addModEventListener(SendHelperHome)

-- Sla het thuis-punt op elke keer dat het spel opgeslagen wordt (zelfde aanpak als
-- andere FS25-mods gebruiken om eigen data in de savegame-map te bewaren).
ItemSystem.save = Utils.prependedFunction(ItemSystem.save, function(...)
    if g_server ~= nil and SendHelperHome.homePositions ~= nil then
        SendHelperHome:saveHomePositions()
    end
end)

-- ============================================================================
-- AI job afhandeling
-- ============================================================================

function SendHelperHome:onAIJobStopped(job, aiMessage)
    if g_server == nil then
        -- Alleen de server (of singleplayer host) mag zelf een nieuwe AI-job starten.
        return
    end

    if job == nil or aiMessage == nil then
        return
    end

    if job.isa == nil or not job:isa(AIJobFieldWork) then
        return
    end

    if aiMessage.isa == nil or not aiMessage:isa(AIMessageSuccessFinishedJob) then
        -- Job is gestopt door een andere reden (leeg, brandstof, handmatig gestopt, ...):
        -- laat het standaardgedrag van het spel staan.
        return
    end

    local vehicle = job.vehicleParameter ~= nil and job.vehicleParameter:getVehicle() or nil
    if vehicle == nil then
        return
    end

    local farmId = vehicle:getOwnerFarmId()
    local home = self.homePositions[farmId]
    if home == nil then
        -- Geen thuis-punt ingesteld voor deze boerderij: niets doen.
        return
    end

    self:sendVehicleHome(vehicle, farmId, home)
end

function SendHelperHome:sendVehicleHome(vehicle, farmId, home)
    if g_currentMission == nil or g_currentMission.aiJobTypeManager == nil or g_currentMission.aiSystem == nil then
        return
    end

    if AIJobType == nil or AIJobType.GOTO == nil then
        Logging.warning("[SendHelperHome] AIJobType.GOTO niet gevonden, kan helper niet naar huis sturen.")
        return
    end

    local goToJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
    if goToJob == nil then
        Logging.warning("[SendHelperHome] Kon geen AIJobGoTo aanmaken.")
        return
    end

    goToJob.vehicleParameter:setVehicle(vehicle)
    goToJob.positionAngleParameter:setPosition(home.x, home.z)
    goToJob.positionAngleParameter:setAngle(home.angle or 0)
    goToJob:setValues()

    local isValid, errorMessage = goToJob:validate(farmId)
    if not isValid then
        Logging.warning("[SendHelperHome] Kan helper niet naar huis sturen (%s).", tostring(errorMessage))
        return
    end

    g_currentMission.aiSystem:startJob(goToJob, farmId)

    if g_localPlayer ~= nil and g_localPlayer.farmId == farmId and g_currentMission.addIngameNotification ~= nil then
        local vehicleName = vehicle.getName ~= nil and vehicle:getName() or g_i18n:getText("shh_fallback_vehicleName")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("shh_notify_vehicleHome"), vehicleName)
        )
    end
end

-- ============================================================================
-- Thuis-punt instellen / wissen (kernlogica, gedeeld door toetsen en console)
-- ============================================================================

--- Slaat de huidige positie op als thuis-punt voor de boerderij van de lokale speler.
-- @return boolean ok, number|string farmIdOfError, number|nil x, number|nil z
function SendHelperHome:doSetHome()
    if g_currentMission == nil or g_localPlayer == nil then
        return false, g_i18n:getText("shh_error_noSavegame")
    end

    local farmId = g_localPlayer.farmId
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return false, g_i18n:getText("shh_error_noFarm")
    end

    local x, y, z, angle
    local vehicle = g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil

    if vehicle ~= nil and vehicle.rootNode ~= nil then
        x, y, z = getWorldTranslation(vehicle.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
        angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
    elseif g_localPlayer.rootNode ~= nil then
        x, y, z = getWorldTranslation(g_localPlayer.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(g_localPlayer.rootNode, 0, 0, 1)
        angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
    else
        return false, g_i18n:getText("shh_error_noPosition")
    end

    self.homePositions[farmId] = { x = x, z = z, angle = angle }

    if g_server ~= nil then
        self:saveHomePositions()
    end

    Logging.info("[SendHelperHome] thuis-punt opgeslagen voor boerderij %d op (%.1f, %.1f)", farmId, x, z)

    return true, farmId, x, z
end

--- Wist het opgeslagen thuis-punt van de boerderij van de lokale speler.
-- @return boolean ok, number|string farmIdOfError
function SendHelperHome:doClearHome()
    if g_currentMission == nil or g_localPlayer == nil then
        return false, g_i18n:getText("shh_error_noSavegame")
    end

    local farmId = g_localPlayer.farmId
    self.homePositions[farmId] = nil

    if g_server ~= nil then
        self:saveHomePositions()
    end

    Logging.info("[SendHelperHome] thuis-punt gewist voor boerderij %s", tostring(farmId))

    return true, farmId
end

-- ============================================================================
-- Consolecommando's om het thuis-punt in te stellen
-- ============================================================================

function SendHelperHome:consoleCommandSetHome()
    Logging.info("[SendHelperHome] CONSOLE-CALLBACK shhSetHome aangeroepen")
    local ok, farmIdOrError, x, z = self:doSetHome()
    if not ok then
        return farmIdOrError
    end

    return string.format(
        g_i18n:getText("shh_console_setHome_result"),
        farmIdOrError, x, z
    )
end

function SendHelperHome:consoleCommandClearHome()
    Logging.info("[SendHelperHome] CONSOLE-CALLBACK shhClearHome aangeroepen")
    local ok, farmIdOrError = self:doClearHome()
    if not ok then
        return farmIdOrError
    end

    return string.format(g_i18n:getText("shh_console_clearHome_result"), farmIdOrError)
end

-- ============================================================================
-- Opslaan / laden in de savegame-map (zelfde patroon als andere FS25-mods, bv.
-- hoe FS25_ContractBoost zijn instellingen bewaart)
-- ============================================================================

function SendHelperHome:initXMLSchema()
    local schema = XMLSchema.new("sendHelperHome")
    schema:register(XMLValueType.INT, "sendHelperHome.farm(?)#farmId", "Farm id")
    schema:register(XMLValueType.FLOAT, "sendHelperHome.farm(?)#x", "Thuis-punt X positie")
    schema:register(XMLValueType.FLOAT, "sendHelperHome.farm(?)#z", "Thuis-punt Z positie")
    schema:register(XMLValueType.FLOAT, "sendHelperHome.farm(?)#angle", "Thuis-punt rotatiehoek (radialen)")
    return schema
end

function SendHelperHome:getSavegameFilePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        -- Kan nil zijn bij een nieuwe, nog niet eerder opgeslagen save game.
        return nil
    end

    return string.format("%s/SendHelperHome.xml", savegameDirectory)
end

function SendHelperHome:loadHomePositions()
    local filePath = self:getSavegameFilePath()
    if filePath == nil or not fileExists(filePath) then
        return
    end

    local xmlFile = XMLFile.load("shhXml", filePath, self.xmlSchema)
    if xmlFile == nil then
        return
    end

    xmlFile:iterate("sendHelperHome.farm", function(_, key)
        local farmId = xmlFile:getValue(key .. "#farmId")
        local x = xmlFile:getValue(key .. "#x")
        local z = xmlFile:getValue(key .. "#z")
        local angle = xmlFile:getValue(key .. "#angle", 0)

        if farmId ~= nil and x ~= nil and z ~= nil then
            self.homePositions[farmId] = { x = x, z = z, angle = angle }
        end
    end)

    xmlFile:delete()

    Logging.info("[SendHelperHome] thuis-punten geladen uit %s", filePath)
end

function SendHelperHome:saveHomePositions()
    local filePath = self:getSavegameFilePath()
    if filePath == nil then
        return
    end

    local xmlFileId = createXMLFile("SendHelperHomeXml", filePath, "sendHelperHome")
    if xmlFileId == nil or xmlFileId == 0 then
        Logging.warning("[SendHelperHome] Kon %s niet aanmaken.", filePath)
        return
    end

    local index = 0
    for farmId, pos in pairs(self.homePositions) do
        local key = string.format("sendHelperHome.farm(%d)", index)
        setXMLInt(xmlFileId, key .. "#farmId", farmId)
        setXMLFloat(xmlFileId, key .. "#x", pos.x)
        setXMLFloat(xmlFileId, key .. "#z", pos.z)
        setXMLFloat(xmlFileId, key .. "#angle", pos.angle or 0)
        index = index + 1
    end

    saveXMLFile(xmlFileId)
end
