ComfyPanel = ComfyPanel or {}
local A = ComfyPanel

local MODULE_ORDER = {"money","bags","playtime","kills","clock","fps","latency"}
local MODULE_GAP = 12
local IDLE_DISPLAY_AFTER = 5
local AUTO_AFK_SECONDS = 300
local AFK_LOGOUT_SECONDS = 1800

local function Now()
    if type(GetTimePreciseSec) == "function" then
        local ok, v = pcall(GetTimePreciseSec)
        if ok and tonumber(v) then return tonumber(v) end
    end
    if type(GetTime) == "function" then
        local ok, v = pcall(GetTime)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if days > 0 then return string.format("%dd %02dh", days, hours) end
    if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
    return string.format("%02d:%02d", minutes, secs)
end

local function FormatClock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
    return string.format("%02d:%02d", minutes, secs)
end

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    if type(GetMoneyString) == "function" then
        local ok, text = pcall(GetMoneyString, copper, true)
        if ok and text then return text end
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", gold, silver, c)
end

local function GetBagTotals()
    local free, total = 0, 0
    for bag = 0, 4 do
        local slots, freeSlots
        if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
            local ok, v = pcall(C_Container.GetContainerNumSlots, bag)
            if ok then slots = tonumber(v) end
        elseif type(GetContainerNumSlots) == "function" then
            local ok, v = pcall(GetContainerNumSlots, bag)
            if ok then slots = tonumber(v) end
        end

        if C_Container and type(C_Container.GetContainerNumFreeSlots) == "function" then
            local ok, v = pcall(C_Container.GetContainerNumFreeSlots, bag)
            if ok then freeSlots = tonumber(v) end
        elseif type(GetContainerNumFreeSlots) == "function" then
            local ok, v = pcall(GetContainerNumFreeSlots, bag)
            if ok then freeSlots = tonumber(v) end
        end

        total = total + (slots or 0)
        free = free + (freeSlots or 0)
    end
    return free, total
end

local function CharacterIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or ""
    name = name or "Unknown"
    realm = realm or ""
    return realm .. ":" .. name, name, realm
end

local function CurrentPvPKills()
    local session, lifetime = 0, 0
    if type(GetPVPSessionStats) == "function" then
        local ok, hk = pcall(GetPVPSessionStats)
        if ok then session = tonumber(hk) or 0 end
    end
    if type(GetPVPLifetimeStats) == "function" then
        local ok, hk = pcall(GetPVPLifetimeStats)
        if ok then lifetime = tonumber(hk) or 0 end
    end
    return session, lifetime
end

function A:EnsureStatsDB()
    if type(ComfyData) == "table" and type(ComfyData.GetDB) == "function" then
        self.statsDB = ComfyData:GetDB()
        self.usingComfyData = true
        return
    end
    self.usingComfyData = false
    if type(ComfyPanelStatsDB) ~= "table" then ComfyPanelStatsDB = {} end
    ComfyPanelStatsDB.version = 1
    ComfyPanelStatsDB.characters = ComfyPanelStatsDB.characters or {}
    self.statsDB = ComfyPanelStatsDB
end

function A:GetCharacterRecord()
    self:EnsureStatsDB()
    if self.usingComfyData and type(ComfyData.GetCurrentCharacter) == "function" then
        local record = ComfyData:GetCurrentCharacter()
        self.currentCharacterKey = type(ComfyData.GetCurrentKey) == "function" and ComfyData:GetCurrentKey() or CharacterIdentity()
        self.currentCharacter = record
        return record
    end
    local key, name, realm = CharacterIdentity()
    local record = self.statsDB.characters[key]
    if type(record) ~= "table" then
        record = {name = name, realm = realm}
        self.statsDB.characters[key] = record
    end
    record.name = name
    record.realm = realm
    record.level = type(UnitLevel) == "function" and (tonumber(UnitLevel("player")) or record.level or 0) or (record.level or 0)
    if type(UnitClass) == "function" then
        local localizedClass, classFile = UnitClass("player")
        record.class = localizedClass or record.class
        record.classFile = classFile or record.classFile
    end
    self.currentCharacterKey = key
    self.currentCharacter = record
    return record
end

function A:GetSessionPlayed()
    if self.usingComfyData and type(ComfyData.GetSessionSeconds) == "function" then
        return ComfyData:GetSessionSeconds()
    end
    return math.max(0, Now() - (self.sessionStart or Now()))
end

function A:GetCurrentTotalPlayed()
    if self.usingComfyData and type(ComfyData.GetCurrentTotalPlayed) == "function" then
        return ComfyData:GetCurrentTotalPlayed()
    end
    local sessionElapsed = self:GetSessionPlayed()
    if self.playedBase ~= nil then
        return math.max(0, self.playedBase + sessionElapsed - (self.playedBaseSessionElapsed or 0))
    end
    return math.max(0, (self.sessionStartStoredTotal or 0) + sessionElapsed)
end

function A:GetAccountPlayedTotal()
    self:EnsureStatsDB()
    if self.usingComfyData and type(ComfyData.GetAccountTotals) == "function" then
        local totals = ComfyData:GetAccountTotals()
        return tonumber(totals and totals.totalPlayed) or 0
    end
    local total = 0
    for key, record in pairs(self.statsDB.characters) do
        if key == self.currentCharacterKey then
            total = total + self:GetCurrentTotalPlayed()
        else
            total = total + (tonumber(record.totalPlayed) or 0)
        end
    end
    return total
end

function A:GetAccountLifetimeKills()
    self:EnsureStatsDB()
    if self.usingComfyData and type(ComfyData.GetAccountTotals) == "function" then
        local totals = ComfyData:GetAccountTotals()
        return tonumber(totals and totals.lifetimeKills) or 0
    end
    local total = 0
    for key, record in pairs(self.statsDB.characters) do
        if key == self.currentCharacterKey then
            local _, lifetime = CurrentPvPKills()
            total = total + lifetime
        else
            total = total + (tonumber(record.lifetimeKills) or 0)
        end
    end
    return total
end

function A:UpdateCharacterSnapshot(includeBags)
    self:EnsureStatsDB()
    if self.usingComfyData and type(ComfyData.RefreshCurrent) == "function" then
        ComfyData:RefreshCurrent(includeBags and true or false, false)
        self.statsDB = ComfyData:GetDB()
        self.currentCharacterKey = ComfyData:GetCurrentKey()
        self.currentCharacter = ComfyData:GetCurrentCharacter()
        return self.currentCharacter
    end
    local record = self:GetCharacterRecord()

    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        if ok then record.money = tonumber(money) or record.money or 0 end
    end

    if includeBags then
        local free, total = GetBagTotals()
        record.bagFree = free
        record.bagTotal = total
    end

    local sessionKills, lifetimeKills = CurrentPvPKills()
    record.sessionKills = sessionKills
    record.lifetimeKills = lifetimeKills
    record.totalPlayed = self:GetCurrentTotalPlayed()
    record.lastSeen = type(time) == "function" and time() or record.lastSeen
end

function A:ResetIdleTimer()
    self.lastActivity = Now()
    self.afkDetectedAt = nil
end

function A:GetIdleSeconds()
    return math.max(0, Now() - (self.lastActivity or Now()))
end

function A:GetAFKText()
    local now = Now()
    local idle = self:GetIdleSeconds()
    local isAFK = type(UnitIsAFK) == "function" and UnitIsAFK("player") and true or false

    if isAFK then
        if not self.afkDetectedAt then
            self.afkDetectedAt = idle >= AUTO_AFK_SECONDS
                and ((self.lastActivity or now) + AUTO_AFK_SECONDS)
                or now
        end
        local afkFor = math.max(0, now - self.afkDetectedAt)
        local logoutIn = math.max(0, AFK_LOGOUT_SECONDS - afkFor)
        return string.format("AFK %s  |  Logout ~%s", FormatClock(afkFor), FormatClock(logoutIn))
    end

    self.afkDetectedAt = nil
    if idle < IDLE_DISPLAY_AFTER then return self:T("AFK_ACTIVE") end

    local untilAFK = math.max(0, AUTO_AFK_SECONDS - idle)
    local untilLogout = math.max(0, AUTO_AFK_SECONDS + AFK_LOGOUT_SECONDS - idle)
    if untilAFK > 0 then
        return string.format("Idle %s  |  AFK %s  |  Logout ~%s", FormatClock(idle), FormatClock(untilAFK), FormatClock(untilLogout))
    end
    return string.format("Idle %s  |  Logout ~%s", FormatClock(idle), FormatClock(untilLogout))
end

function A:IsModuleEnabled(id)
    local c = self.db and self.db.panel
    if not c then return false end
    if id == "money" then return c.showMoney end
    if id == "bags" then return c.showBags end
    if id == "playtime" then return c.showPlaytime end
    if id == "kills" then return c.showKills end
    if id == "clock" then return c.showTime end
    if id == "fps" then return c.showFPS end
    if id == "latency" then return c.showLatency end
    return false
end

function A:GetModuleText(id)
    local c = self.db.panel
    local record = self:GetCharacterRecord()

    if id == "money" then
        return self:T("MONEY_SHORT") .. ": " .. FormatMoney(record.money or 0)
    elseif id == "bags" then
        local free, total = tonumber(record.bagFree) or 0, tonumber(record.bagTotal) or 0
        if c.bagShowMax then return string.format("%s: %d/%d", self:T("BAGS_SHORT"), free, total) end
        return string.format("%s: %d", self:T("BAGS_SHORT"), free)
    elseif id == "playtime" then
        local parts = {}
        if c.playtimeShowSession then parts[#parts + 1] = "S " .. FormatDuration(self:GetSessionPlayed()) end
        if c.playtimeShowCharacter then parts[#parts + 1] = "C " .. FormatDuration(self:GetCurrentTotalPlayed()) end
        if c.playtimeShowAccount then parts[#parts + 1] = "Σ " .. FormatDuration(self:GetAccountPlayedTotal()) end
        if #parts == 0 then parts[1] = "S " .. FormatDuration(self:GetSessionPlayed()) end
        return self:T("PLAY_SHORT") .. ": " .. table.concat(parts, " / ")
    elseif id == "kills" then
        local session, lifetime = CurrentPvPKills()
        return string.format("%s: %d / %d", self:T("KILLS_SHORT"), session, lifetime)
        elseif id == "clock" then
        return date and date("%H:%M") or "--:--"
    elseif id == "fps" then
        return type(GetFramerate) == "function" and string.format("FPS %.0f", tonumber(GetFramerate()) or 0) or "FPS —"
    elseif id == "latency" then
        if type(GetNetStats) == "function" then
            local ok, _, _, home, world = pcall(GetNetStats)
            if ok then return string.format("MS %d/%d", tonumber(home) or 0, tonumber(world) or 0) end
        end
        return "MS —"
    end
    return ""
end

local function SortedCharacters(db)
    local list = {}
    for key, record in pairs((db and db.characters) or {}) do
        list[#list + 1] = {key = key, record = record}
    end
    table.sort(list, function(a, b)
        local ar = tostring(a.record.realm or "")
        local br = tostring(b.record.realm or "")
        if ar ~= br then return ar:lower() < br:lower() end
        return tostring(a.record.name or ""):lower() < tostring(b.record.name or ""):lower()
    end)
    return list
end

function A:ShowModuleTooltip(id, owner)
    if not GameTooltip then return end
    self:UpdateCharacterSnapshot(true)

    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()

    if id == "money" then
        GameTooltip:AddLine(self:T("MONEY_TOOLTIP"), 1, 0.82, 0)
        local total = 0
        for _, item in ipairs(SortedCharacters(self.statsDB)) do
            local r = item.record
            local value = tonumber(r.money) or 0
            total = total + value
            GameTooltip:AddDoubleLine((r.name or "?") .. (r.realm and r.realm ~= "" and (" - " .. r.realm) or ""), FormatMoney(value), 1,1,1, 1,1,1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(self:T("ALL_CHARS"), FormatMoney(total), 1,0.82,0, 1,0.82,0)

    elseif id == "bags" then
        GameTooltip:AddLine(self:T("BAGS_TOOLTIP"), 1, 0.82, 0)
        for _, item in ipairs(SortedCharacters(self.statsDB)) do
            local r = item.record
            GameTooltip:AddDoubleLine((r.name or "?") .. (r.realm and r.realm ~= "" and (" - " .. r.realm) or ""), string.format("%d / %d", tonumber(r.bagFree) or 0, tonumber(r.bagTotal) or 0), 1,1,1, 1,1,1)
        end

    elseif id == "playtime" then
        GameTooltip:AddLine(self:T("PLAYTIME_TOOLTIP"), 1, 0.82, 0)
        GameTooltip:AddDoubleLine(self:T("SESSION_TIME"), FormatDuration(self:GetSessionPlayed()), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(self:T("CHARACTER_TIME"), FormatDuration(self:GetCurrentTotalPlayed()), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(self:T("ALL_CHARS"), FormatDuration(self:GetAccountPlayedTotal()), 1,0.82,0, 1,0.82,0)
        GameTooltip:AddLine(" ")
        for _, item in ipairs(SortedCharacters(self.statsDB)) do
            local r = item.record
            local value = item.key == self.currentCharacterKey and self:GetCurrentTotalPlayed() or (tonumber(r.totalPlayed) or 0)
            GameTooltip:AddDoubleLine((r.name or "?") .. (r.realm and r.realm ~= "" and (" - " .. r.realm) or ""), FormatDuration(value), 1,1,1, 1,1,1)
        end

    elseif id == "kills" then
        local session, lifetime = CurrentPvPKills()
        GameTooltip:AddLine(self:T("KILLS_TOOLTIP"), 1, 0.82, 0)
        GameTooltip:AddDoubleLine(self:T("SESSION_KILLS"), tostring(session), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(self:T("LIFETIME_KILLS"), tostring(lifetime), 1,1,1, 1,1,1)
        GameTooltip:AddDoubleLine(self:T("ALL_CHARS"), tostring(self:GetAccountLifetimeKills()), 1,0.82,0, 1,0.82,0)
        GameTooltip:AddLine(" ")
        for _, item in ipairs(SortedCharacters(self.statsDB)) do
            local r = item.record
            local value = item.key == self.currentCharacterKey and lifetime or (tonumber(r.lifetimeKills) or 0)
            GameTooltip:AddDoubleLine((r.name or "?") .. (r.realm and r.realm ~= "" and (" - " .. r.realm) or ""), tostring(value), 1,1,1, 1,1,1)
        end

    else
        return
    end

    if id == "money" or id == "bags" or id == "playtime" or id == "kills" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self:T("DB_LOGIN_NOTE"), 0.65, 0.65, 0.65, true)
    end
    GameTooltip:Show()
end

function A:CreateModule(id)
    local panel = self.panelFrame
    local frame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    frame:SetHeight(panel:GetHeight() or 22)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0)
    frame:SetBackdropBorderColor(1, 0.82, 0, 0)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.id = id

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("CENTER")

    frame:SetScript("OnEnter", function(self) A:ShowModuleTooltip(self.id, self) end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    frame:SetScript("OnDragStart", function(self)
        if not A.db or not A.db.panel or not A.db.panel.unlocked then return end
        A.db.panel.alignment = "CUSTOM"
        self._dragging = true
        self:SetScript("OnUpdate", function(module)
            local panelLeft = A.panelFrame and A.panelFrame:GetLeft()
            local panelWidth = A.panelFrame and A.panelFrame:GetWidth()
            if not panelLeft or not panelWidth or type(GetCursorPosition) ~= "function" then return end
            local cursorX = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            cursorX = cursorX / scale
            local half = (module:GetWidth() or 20) / 2
            local x = Clamp(cursorX - panelLeft, half, panelWidth - half)
            module:ClearAllPoints()
            module:SetPoint("CENTER", A.panelFrame, "LEFT", x, 0)
            module._customX = x
        end)
    end)

    frame:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        A.db.panel.modulePositions = A.db.panel.modulePositions or {}
        if self._customX then A.db.panel.modulePositions[self.id] = self._customX end
        if A.RefreshOptions then A:RefreshOptions() end
    end)

    self.modules[id] = frame
    return frame
end

function A:CreatePanel()
    if self.panelFrame then return end

    local f = CreateFrame("Frame", "ComfyPanelBar", UIParent, "BackdropTemplate")
    f:SetFrameStrata("LOW")
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
    f:SetClampedToScreen(true)
    self.panelFrame = f
    self.modules = {}

    for _, id in ipairs(MODULE_ORDER) do self:CreateModule(id) end
end

function A:LayoutModules()
    local panel = self.panelFrame
    local c = self.db.panel
    if not panel or not c then return end

    local visible = {}
    local totalWidth = 0
    for _, id in ipairs(MODULE_ORDER) do
        local module = self.modules[id]
        if self:IsModuleEnabled(id) then
            local width = math.max(30, math.ceil((module.text:GetStringWidth() or 0) + 14))
            module:SetSize(width, tonumber(c.height) or 22)
            visible[#visible + 1] = module
            totalWidth = totalWidth + width
        end
    end
    if #visible > 1 then totalWidth = totalWidth + (#visible - 1) * MODULE_GAP end

    local panelWidth = panel:GetWidth() or UIParent:GetWidth() or 1024
    local alignment = c.alignment or "LEFT"

    if alignment == "CUSTOM" then
        local positions = c.modulePositions or {}
        local fallbackX = 8
        for _, module in ipairs(visible) do
            local half = (module:GetWidth() or 20) / 2
            local x = tonumber(positions[module.id])
            if not x then
                x = fallbackX + half
                fallbackX = fallbackX + (module:GetWidth() or 20) + MODULE_GAP
            end
            x = Clamp(x, half, panelWidth - half)
            module:ClearAllPoints()
            module:SetPoint("CENTER", panel, "LEFT", x, 0)
        end
        return
    end

    local startX = 8
    if alignment == "CENTER" then
        startX = math.max(8, (panelWidth - totalWidth) / 2)
    elseif alignment == "RIGHT" then
        startX = math.max(8, panelWidth - totalWidth - 8)
    end

    local x = startX
    for _, module in ipairs(visible) do
        module:ClearAllPoints()
        module:SetPoint("LEFT", panel, "LEFT", x, 0)
        x = x + (module:GetWidth() or 20) + MODULE_GAP
    end
end

function A:RefreshModuleAppearance()
    local unlocked = self.db and self.db.panel and self.db.panel.unlocked
    for _, module in pairs(self.modules or {}) do
        module:SetBackdropColor(0.05, 0.05, 0.05, unlocked and 0.55 or 0)
        module:SetBackdropBorderColor(1, 0.82, 0, unlocked and 0.8 or 0)
    end
end

function A:RefreshFeature()
    self:CreatePanel()
    if not self.db or not self.db.panel or not self.db.enabled then
        self.panelFrame:Hide()
        return
    end

    self:UpdateCharacterSnapshot(false)

    local c = self.db.panel
    local panel = self.panelFrame
    local edge = c.position == "BOTTOM" and "BOTTOM" or "TOP"
    local offset = math.max(0, tonumber(c.offset) or 0)

    panel:ClearAllPoints()
    panel:SetPoint(edge, UIParent, edge, 0, edge == "TOP" and -offset or offset)
    panel:SetWidth(UIParent:GetWidth() or 1024)
    panel:SetHeight(tonumber(c.height) or 22)
    panel:SetBackdropColor(0.025, 0.025, 0.03, math.max(0, math.min(100, tonumber(c.opacity) or 0)) / 100)

    for _, id in ipairs(MODULE_ORDER) do
        local module = self.modules[id]
        local enabled = self:IsModuleEnabled(id)
        module:SetShown(enabled)
        if enabled then module.text:SetText(self:GetModuleText(id)) end
    end

    self:RefreshModuleAppearance()
    self:LayoutModules()
    panel:Show()
end

function A:RequestPlayedTimeOnce()
    if self.usingComfyData then return end
    if self.playedRequested or type(RequestTimePlayed) ~= "function" then return end
    self.playedRequested = true
    pcall(RequestTimePlayed)
end

function A:HandleTimePlayed(totalTimePlayed)
    if self.usingComfyData then return end
    totalTimePlayed = tonumber(totalTimePlayed)
    if not totalTimePlayed then return end

    local sessionElapsed = self:GetSessionPlayed()
    self.playedBase = totalTimePlayed
    self.playedBaseSessionElapsed = sessionElapsed

    local record = self:GetCharacterRecord()
    record.totalPlayed = totalTimePlayed
    self:RefreshFeature()
end

function A:InitializeFeature()
    self:EnsureStatsDB()
    local record = self:GetCharacterRecord()

    self.sessionStart = Now()
    self.sessionStartStoredTotal = tonumber(record.totalPlayed) or 0
    self.playedRequested = false
    self._playedRequestAt = Now() + 3

    self:CreatePanel()
    self:UpdateCharacterSnapshot(true)

    local e = CreateFrame("Frame")
    self.panelEvents = e
    local events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_MONEY",
        "BAG_UPDATE_DELAYED",
        "PLAYER_LEVEL_UP",
        "TIME_PLAYED_MSG",
        "PLAYER_PVP_KILLS_CHANGED",
        "PLAYER_LOGOUT",
    }
    for _, event in ipairs(events) do pcall(e.RegisterEvent, e, event) end

    e:SetScript("OnEvent", function(_, event, ...)
        if event == "TIME_PLAYED_MSG" then
            A:HandleTimePlayed(...)
            return
        end

        if event == "PLAYER_ENTERING_WORLD" then
            A:GetCharacterRecord()
            A:UpdateCharacterSnapshot(true)
        elseif event == "PLAYER_MONEY" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_PVP_KILLS_CHANGED" then
            A:UpdateCharacterSnapshot(event == "BAG_UPDATE_DELAYED")
        elseif event == "PLAYER_LOGOUT" then
            A:UpdateCharacterSnapshot(true)
        end

        A:RefreshFeature()
    end)

    e:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + (tonumber(elapsed) or 0)
        if not A.playedRequested and A._playedRequestAt and Now() >= A._playedRequestAt then
            A:RequestPlayedTimeOnce()
        end

        if self.elapsed >= 1 then
            self.elapsed = 0
            A:UpdateCharacterSnapshot(false)
            A:RefreshFeature()
        end
    end)

    self:RefreshFeature()
end

function A:ResetModulePositions()
    if not self.db or not self.db.panel then return end
    self.db.panel.modulePositions = {}
    self.db.panel.alignment = "CENTER"
    self:RefreshFeature()
    if self.RefreshOptions then self:RefreshOptions() end
end

function A:BuildGeneralOptions(page, ui)
    ui.CreateCheck(page, self:T("UNLOCK_MODULES"), 20, -90,
        function() return A.db.panel.unlocked end,
        function(v) A.db.panel.unlocked = v end)

    ui.CreateCheck(page, self:T("SHOW_MONEY"), 20, -125,
        function() return A.db.panel.showMoney end,
        function(v) A.db.panel.showMoney = v end)

    ui.CreateCheck(page, self:T("SHOW_BAGS"), 20, -160,
        function() return A.db.panel.showBags end,
        function(v) A.db.panel.showBags = v end)

    ui.CreateCheck(page, self:T("SHOW_BAG_MAX"), 45, -195,
        function() return A.db.panel.bagShowMax end,
        function(v) A.db.panel.bagShowMax = v end)

    ui.CreateCheck(page, self:T("SHOW_PLAYTIME"), 20, -230,
        function() return A.db.panel.showPlaytime end,
        function(v) A.db.panel.showPlaytime = v end)

    ui.CreateCheck(page, self:T("PLAYTIME_SESSION"), 45, -265,
        function() return A.db.panel.playtimeShowSession end,
        function(v) A.db.panel.playtimeShowSession = v end)

    ui.CreateCheck(page, self:T("PLAYTIME_CHARACTER"), 45, -300,
        function() return A.db.panel.playtimeShowCharacter end,
        function(v) A.db.panel.playtimeShowCharacter = v end)

    ui.CreateCheck(page, self:T("PLAYTIME_ACCOUNT"), 45, -335,
        function() return A.db.panel.playtimeShowAccount end,
        function(v) A.db.panel.playtimeShowAccount = v end)

    ui.CreateCheck(page, self:T("SHOW_KILLS"), 20, -370,
        function() return A.db.panel.showKills end,
        function(v) A.db.panel.showKills = v end)

    ui.CreateCheck(page, self:T("SHOW_TIME"), 390, -90,
        function() return A.db.panel.showTime end,
        function(v) A.db.panel.showTime = v end)

    ui.CreateCheck(page, self:T("SHOW_FPS"), 390, -125,
        function() return A.db.panel.showFPS end,
        function(v) A.db.panel.showFPS = v end)

    ui.CreateCheck(page, self:T("SHOW_LATENCY"), 390, -160,
        function() return A.db.panel.showLatency end,
        function(v) A.db.panel.showLatency = v end)

    local alignLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    alignLabel:SetPoint("TOPLEFT", 390, -210)
    alignLabel:SetText(self:T("ALIGNMENT"))

    ui.CreateDropdown(page, 375, -222, 190,
        function()
            return {
                {value = "LEFT", text = A:T("ALIGN_LEFT")},
                {value = "CENTER", text = A:T("ALIGN_CENTER")},
                {value = "RIGHT", text = A:T("ALIGN_RIGHT")},
                {value = "CUSTOM", text = A:T("ALIGN_CUSTOM")},
            }
        end,
        function() return A.db.panel.alignment end,
        function(v) A.db.panel.alignment = v end)

    local posLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    posLabel:SetPoint("TOPLEFT", 390, -280)
    posLabel:SetText(self:T("PANEL_POSITION"))

    ui.CreateDropdown(page, 375, -292, 190,
        function()
            return {
                {value = "TOP", text = A:T("TOP")},
                {value = "BOTTOM", text = A:T("BOTTOM")},
            }
        end,
        function() return A.db.panel.position end,
        function(v) A.db.panel.position = v end)

    ui.CreateButton(page, self:T("RESET_MODULE_POSITIONS"), 390, -350, 190, function()
        A:ResetModulePositions()
    end)

    ui.CreateSlider(page, self:T("HEIGHT"), 16, 36, 1, 35, -455,
        function() return A.db.panel.height end,
        function(v) A.db.panel.height = math.floor(v + 0.5) end,
        function(v) return math.floor(v + 0.5) .. " px" end)

    ui.CreateSlider(page, self:T("OPACITY"), 0, 100, 5, 365, -455,
        function() return A.db.panel.opacity end,
        function(v) A.db.panel.opacity = math.floor(v + 0.5) end,
        function(v) return math.floor(v + 0.5) .. "%" end)

    ui.CreateSlider(page, self:T("PANEL_OFFSET"), 0, 80, 1, 35, -515,
        function() return A.db.panel.offset end,
        function(v) A.db.panel.offset = math.floor(v + 0.5) end,
        function(v) return math.floor(v + 0.5) .. " px" end)
end
