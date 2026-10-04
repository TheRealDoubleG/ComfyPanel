ComfyPanel = ComfyPanel or {}
local A = ComfyPanel

A.version = "0.7"
A.buildDate = "04.10.2026"

local EXTRA_ORDER = {"money", "bags", "xp", "durability", "playtime", "kills", "clock", "fps", "latency"}
local MODULE_GAP = 12

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

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    if type(GetMoneyString) == "function" then
        local ok, text = pcall(GetMoneyString, copper, true)
        if ok and text then return sign .. text end
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%s%dg %ds %dc", sign, gold, silver, c)
end

local function FormatNumber(v)
    v = tonumber(v) or 0
    if math.abs(v) >= 1000000 then return string.format("%.1fm", v / 1000000) end
    if math.abs(v) >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

local function FormatDuration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds >= 86400 then return string.format("%.1fd", seconds / 86400) end
    if seconds >= 3600 then return string.format("%.1fh", seconds / 3600) end
    if seconds >= 60 then return string.format("%.0fm", seconds / 60) end
    return string.format("%.0fs", seconds)
end

local function Hex(hex, fr, fg, fb)
    hex = tostring(hex or ""):gsub("#", ""):gsub("%s+", ""):upper()
    if not hex:match("^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then return fr, fg, fb end
    return (tonumber(hex:sub(1,2), 16) or 255) / 255,
           (tonumber(hex:sub(3,4), 16) or 255) / 255,
           (tonumber(hex:sub(5,6), 16) or 255) / 255
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function EnsureDefaults()
    if not A.db then return end
    A.db.panel = A.db.panel or {}
    local p = A.db.panel
    local defaults = {
        showXP = true,
        showDurability = true,
        showReagentBagCount = true,
        moneyShowSession = false,
        moneyShowPerHour = false,
        xpShowLevel = true,
        xpShowPercent = true,
        xpShowCurrent = false,
        xpShowRemaining = false,
        xpShowPerHour = false,
        xpShowETA = false,
        xpShowSession = false,
        textColor = "FFFFFF",
        dynamicPerformanceColors = false,
        showDatabaseNote = false,
    }
    for k, v in pairs(defaults) do if p[k] == nil then p[k] = v end end
end

local originalInitializeDB = A.InitializeDB
function A:InitializeDB(...)
    local r
    if originalInitializeDB then r = originalInitializeDB(self, ...) end
    EnsureDefaults()
    return r
end

local function GetXPState()
    local level = type(UnitLevel) == "function" and tonumber(UnitLevel("player")) or 0
    local current = type(UnitXP) == "function" and tonumber(UnitXP("player")) or 0
    local maxXP = type(UnitXPMax) == "function" and tonumber(UnitXPMax("player")) or 0
    local remaining = math.max(0, maxXP - current)
    local pct = maxXP > 0 and (current / maxXP) * 100 or 0
    local elapsed = math.max(1, Now() - (A.xpSessionStartAt or Now()))
    local session = tonumber(A.xpSessionGained) or 0
    local perHour = session * 3600 / elapsed
    local eta = perHour > 0 and remaining / perHour * 3600 or nil
    local rested = type(GetXPExhaustion) == "function" and tonumber(GetXPExhaustion()) or nil
    return level, current, maxXP, remaining, pct, session, perHour, eta, rested
end

local function GetBagInfo(bag)
    local slots, free
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, v = pcall(C_Container.GetContainerNumSlots, bag); if ok then slots = tonumber(v) end
    elseif type(GetContainerNumSlots) == "function" then
        local ok, v = pcall(GetContainerNumSlots, bag); if ok then slots = tonumber(v) end
    end
    if C_Container and type(C_Container.GetContainerNumFreeSlots) == "function" then
        local ok, v = pcall(C_Container.GetContainerNumFreeSlots, bag); if ok then free = tonumber(v) end
    elseif type(GetContainerNumFreeSlots) == "function" then
        local ok, v = pcall(GetContainerNumFreeSlots, bag); if ok then free = tonumber(v) end
    end
    return free or 0, slots or 0
end

local DURABILITY_SLOTS_DE = {
    [1]="Kopf", [3]="Schulter", [5]="Brust", [6]="Taille", [7]="Beine", [8]="Füße",
    [9]="Handgelenke", [10]="Hände", [16]="Waffenhand", [17]="Nebenhand", [18]="Fernkampf",
}
local DURABILITY_SLOTS_EN = {
    [1]="Head", [3]="Shoulder", [5]="Chest", [6]="Waist", [7]="Legs", [8]="Feet",
    [9]="Wrists", [10]="Hands", [16]="Main hand", [17]="Off hand", [18]="Ranged",
}

local function DurabilityColor(pct)
    if pct <= 0 then return 0.55, 0.55, 0.55 end
    if pct < 25 then return 0.55, 0.05, 0.05 end
    if pct < 50 then return 1.00, 0.20, 0.20 end
    if pct < 75 then return 1.00, 0.82, 0.00 end
    return 0.20, 1.00, 0.20
end

local function GetDurabilityRows()
    local rows, minPct, totalPct, count = {}, nil, 0, 0
    if type(GetInventoryItemDurability) ~= "function" then return rows, nil, nil end
    local names = type(GetLocale) == "function" and GetLocale() == "deDE" and DURABILITY_SLOTS_DE or DURABILITY_SLOTS_EN
    for slot = 1, 18 do
        local ok, cur, maxv = pcall(GetInventoryItemDurability, slot)
        cur, maxv = ok and tonumber(cur) or nil, ok and tonumber(maxv) or nil
        if cur and maxv and maxv > 0 then
            local pct = math.floor((cur / maxv) * 100 + 0.5)
            local itemName = type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", slot) or nil
            rows[#rows + 1] = {slot=slot, name=itemName or names[slot] or ("Slot " .. slot), pct=pct}
            minPct = minPct and math.min(minPct, pct) or pct
            totalPct = totalPct + pct
            count = count + 1
        end
    end
    return rows, minPct, count > 0 and totalPct / count or nil
end

local function SortedCharacters(db)
    local list = {}
    for key, record in pairs((db and db.characters) or {}) do list[#list + 1] = {key=key, record=record} end
    table.sort(list, function(a,b) return tostring(a.record.name or ""):lower() < tostring(b.record.name or ""):lower() end)
    return list
end

local function CharacterColor(record)
    local c = record and record.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[record.classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local originalCreatePanel = A.CreatePanel
function A:CreatePanel(...)
    if originalCreatePanel then originalCreatePanel(self, ...) end
    if not self.panelFrame or not self.modules then return end
    if not self.modules.xp then self:CreateModule("xp") end
    if not self.modules.durability then self:CreateModule("durability") end
end

local originalIsModuleEnabled = A.IsModuleEnabled
function A:IsModuleEnabled(id)
    EnsureDefaults()
    if id == "xp" then return self.db and self.db.panel and self.db.panel.showXP end
    if id == "durability" then return self.db and self.db.panel and self.db.panel.showDurability end
    return originalIsModuleEnabled and originalIsModuleEnabled(self, id) or false
end

local originalGetModuleText = A.GetModuleText
function A:GetModuleText(id)
    EnsureDefaults()
    local p = self.db.panel

    if id == "money" then
        local record = self:GetCharacterRecord()
        local text = self:T("MONEY_SHORT") .. ": " .. FormatMoney(record.money or 0)
        local current = type(GetMoney) == "function" and tonumber(GetMoney()) or tonumber(record.money) or 0
        local delta = current - (tonumber(self.sessionMoneyStart) or current)
        local hours = math.max(1 / 3600, (Now() - (self.moneySessionStartAt or Now())) / 3600)
        if p.moneyShowSession then text = text .. " | " .. (delta >= 0 and "+" or "") .. FormatMoney(delta) end
        if p.moneyShowPerHour then
            local rate = delta / hours
            text = text .. " | " .. (rate >= 0 and "+" or "") .. FormatMoney(rate) .. "/h"
        end
        return text
    elseif id == "bags" then
        local base = originalGetModuleText and originalGetModuleText(self, id) or ""
        if p.showReagentBagCount then
            local reagentBag = _G.REAGENTBAG_CONTAINER or 5
            local free, total = GetBagInfo(reagentBag)
            if total > 0 then base = base .. string.format(" | R %d/%d", free, total) end
        end
        return base
    elseif id == "xp" then
        local level, current, maxXP, remaining, pct, session, perHour, eta = GetXPState()
        local parts = {}
        if p.xpShowLevel then parts[#parts + 1] = "Lv " .. tostring(level) end
        if p.xpShowPercent then parts[#parts + 1] = string.format("%.1f%%", pct) end
        if p.xpShowCurrent then parts[#parts + 1] = FormatNumber(current) .. "/" .. FormatNumber(maxXP) end
        if p.xpShowRemaining then parts[#parts + 1] = "Rest " .. FormatNumber(remaining) end
        if p.xpShowPerHour then parts[#parts + 1] = FormatNumber(perHour) .. "/h" end
        if p.xpShowETA then parts[#parts + 1] = eta and ("ETA " .. FormatDuration(eta)) or "ETA —" end
        if p.xpShowSession then parts[#parts + 1] = "S " .. FormatNumber(session) end
        if #parts == 0 then parts[1] = string.format("Lv %d | %.1f%%", level, pct) end
        return table.concat(parts, " | ")
    elseif id == "durability" then
        local _, minPct = GetDurabilityRows()
        return minPct and string.format("Haltb. %d%%", minPct) or "Haltb. —"
    end

    return originalGetModuleText and originalGetModuleText(self, id) or ""
end

function A:LayoutModules()
    if not self.panelFrame or not self.db or not self.db.panel then return end
    local panel, p = self.panelFrame, self.db.panel
    local visible, totalWidth = {}, 0
    for _, id in ipairs(EXTRA_ORDER) do
        local m = self.modules and self.modules[id]
        if m and self:IsModuleEnabled(id) then
            local width = math.max(30, math.ceil((m.text:GetStringWidth() or 0) + 14))
            m:SetSize(width, tonumber(p.height) or 22)
            visible[#visible + 1] = m
            totalWidth = totalWidth + width
        end
    end
    if #visible > 1 then totalWidth = totalWidth + (#visible - 1) * MODULE_GAP end

    local panelWidth = panel:GetWidth() or UIParent:GetWidth() or 1024
    if p.alignment == "CUSTOM" then
        p.modulePositions = p.modulePositions or {}
        local fallback = 8
        for _, m in ipairs(visible) do
            local half = (m:GetWidth() or 20) / 2
            local x = tonumber(p.modulePositions[m.id])
            if not x then x = fallback + half; fallback = fallback + (m:GetWidth() or 20) + MODULE_GAP end
            x = Clamp(x, half, panelWidth - half)
            m:ClearAllPoints(); m:SetPoint("CENTER", panel, "LEFT", x, 0)
        end
        return
    end

    local x = 8
    if p.alignment == "CENTER" then x = math.max(8, (panelWidth - totalWidth) / 2)
    elseif p.alignment == "RIGHT" then x = math.max(8, panelWidth - totalWidth - 8) end
    for _, m in ipairs(visible) do
        m:ClearAllPoints(); m:SetPoint("LEFT", panel, "LEFT", x, 0)
        x = x + (m:GetWidth() or 20) + MODULE_GAP
    end
end

local function ResetPerfStats()
    A.perf = {
        count=0, fpsSum=0, fpsMin=nil, fpsMax=nil,
        homeSum=0, homeMin=nil, homeMax=nil,
        worldSum=0, worldMin=nil, worldMax=nil,
    }
end

local function SamplePerformance()
    A.perf = A.perf or {}; local s = A.perf
    local fps = type(GetFramerate) == "function" and tonumber(GetFramerate()) or nil
    local home, world
    if type(GetNetStats) == "function" then
        local ok, _, _, h, w = pcall(GetNetStats)
        if ok then home, world = tonumber(h), tonumber(w) end
    end
    if fps then
        s.count = (s.count or 0) + 1; s.fpsSum = (s.fpsSum or 0) + fps
        s.fpsMin = s.fpsMin and math.min(s.fpsMin, fps) or fps; s.fpsMax = s.fpsMax and math.max(s.fpsMax, fps) or fps
    end
    if home then s.homeSum=(s.homeSum or 0)+home; s.homeMin=s.homeMin and math.min(s.homeMin,home) or home; s.homeMax=s.homeMax and math.max(s.homeMax,home) or home end
    if world then s.worldSum=(s.worldSum or 0)+world; s.worldMin=s.worldMin and math.min(s.worldMin,world) or world; s.worldMax=s.worldMax and math.max(s.worldMax,world) or world end
end

local function AddAddonUsage(tooltip)
    local count = type(GetNumAddOns) == "function" and tonumber(GetNumAddOns()) or 0
    if count <= 0 then return end

    if type(UpdateAddOnCPUUsage) == "function" and type(GetAddOnCPUUsage) == "function" then
        pcall(UpdateAddOnCPUUsage)
        local rows = {}
        for i=1,count do
            local cpu = tonumber(GetAddOnCPUUsage(i))
            if cpu and cpu > 0 then
                local name = type(GetAddOnInfo)=="function" and select(1,GetAddOnInfo(i)) or tostring(i)
                rows[#rows+1]={name=name or tostring(i),value=cpu}
            end
        end
        table.sort(rows,function(a,b) return a.value>b.value end)
        if #rows > 0 then
            tooltip:AddLine(" "); tooltip:AddLine("Addon CPU-Zeit",1,0.82,0)
            for i=1,math.min(5,#rows) do tooltip:AddDoubleLine(rows[i].name,string.format("%.1f ms",rows[i].value),1,1,1,1,1,1) end
        end
    end

    if type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function" then
        pcall(UpdateAddOnMemoryUsage)
        local rows, total = {}, 0
        for i=1,count do
            local mem = tonumber(GetAddOnMemoryUsage(i)) or 0; total=total+mem
            if mem > 0 then
                local name = type(GetAddOnInfo)=="function" and select(1,GetAddOnInfo(i)) or tostring(i)
                rows[#rows+1]={name=name or tostring(i),value=mem}
            end
        end
        table.sort(rows,function(a,b) return a.value>b.value end)
        tooltip:AddLine(" "); tooltip:AddLine("Addon-Speicher",1,0.82,0)
        tooltip:AddDoubleLine("Gesamt",total>=1024 and string.format("%.2f MB",total/1024) or string.format("%.0f KB",total),1,1,1,1,1,1)
        for i=1,math.min(5,#rows) do
            local v=rows[i].value; tooltip:AddDoubleLine(rows[i].name,v>=1024 and string.format("%.2f MB",v/1024) or string.format("%.0f KB",v),1,1,1,1,1,1)
        end
    end
end

local originalShowModuleTooltip = A.ShowModuleTooltip
function A:ShowModuleTooltip(id, owner)
    EnsureDefaults()
    if not GameTooltip then return end

    if id == "money" then
        self:UpdateCharacterSnapshot(true)
        GameTooltip:SetOwner(owner,"ANCHOR_BOTTOM"); GameTooltip:ClearLines(); GameTooltip:AddLine("Gold auf bekannten Charakteren",1,0.82,0)
        local total=0
        for _, item in ipairs(SortedCharacters(self.statsDB)) do
            local r=item.record; local value=tonumber(r.money) or 0; total=total+value
            local rr,gg,bb=CharacterColor(r)
            local label=(r.name or "?") .. (r.class and (" ("..r.class..")") or "")
            if r.guild and r.guild~="" then label=label.."  <"..r.guild..">" end
            GameTooltip:AddDoubleLine(label,FormatMoney(value),rr,gg,bb,1,1,1)
        end
        GameTooltip:AddLine(" "); GameTooltip:AddDoubleLine("Alle bekannten Charaktere",FormatMoney(total),1,0.82,0,1,0.82,0)
        local current=type(GetMoney)=="function" and tonumber(GetMoney()) or 0
        local delta=current-(tonumber(self.sessionMoneyStart) or current)
        local hours=math.max(1/3600,(Now()-(self.moneySessionStartAt or Now()))/3600)
        GameTooltip:AddDoubleLine("Seit Login",(delta>=0 and "+" or "")..FormatMoney(delta),1,1,1,delta>=0 and 0.2 or 1,delta>=0 and 1 or 0.2,0.2)
        GameTooltip:AddDoubleLine("Pro Stunde",((delta/hours)>=0 and "+" or "")..FormatMoney(delta/hours).."/h",1,1,1,1,1,1)
        if self.db.panel.showDatabaseNote then GameTooltip:AddLine(" "); GameTooltip:AddLine(self:T("DB_LOGIN_NOTE"),0.65,0.65,0.65,true) end
        GameTooltip:Show(); return
    elseif id == "xp" then
        GameTooltip:SetOwner(owner,"ANCHOR_BOTTOM"); GameTooltip:ClearLines(); GameTooltip:AddLine("Erfahrung",1,0.82,0)
        local level,current,maxXP,remaining,pct,session,perHour,eta,rested=GetXPState()
        GameTooltip:AddDoubleLine("Level",tostring(level),1,1,1,1,1,1)
        GameTooltip:AddDoubleLine("Fortschritt",string.format("%.1f%%",pct),1,1,1,1,1,1)
        GameTooltip:AddDoubleLine("XP",FormatNumber(current).." / "..FormatNumber(maxXP),1,1,1,1,1,1)
        GameTooltip:AddDoubleLine("Rest-XP",FormatNumber(remaining),1,1,1,1,1,1)
        GameTooltip:AddDoubleLine("XP seit Login",FormatNumber(session),1,1,1,1,1,1)
        GameTooltip:AddDoubleLine("XP/Stunde",FormatNumber(perHour),1,1,1,1,0.82,0)
        GameTooltip:AddDoubleLine("Restzeit",eta and FormatDuration(eta) or "—",1,1,1,1,1,1)
        if rested then GameTooltip:AddDoubleLine("Erholungsbonus",FormatNumber(rested),1,1,1,0.4,0.7,1) end
        GameTooltip:Show(); return
    elseif id == "durability" then
        GameTooltip:SetOwner(owner,"ANCHOR_BOTTOM"); GameTooltip:ClearLines(); GameTooltip:AddLine("Haltbarkeit",1,0.82,0)
        local rows,minPct,avgPct=GetDurabilityRows()
        if avgPct then GameTooltip:AddDoubleLine("Durchschnitt",string.format("%.0f%%",avgPct),1,1,1,1,1,1) end
        if minPct then GameTooltip:AddDoubleLine("Niedrigster Wert",string.format("%d%%",minPct),1,1,1,1,1,1) end
        GameTooltip:AddLine(" ")
        for _,row in ipairs(rows) do local r,g,b=DurabilityColor(row.pct); GameTooltip:AddDoubleLine(row.name,string.format("%d%%",row.pct),1,1,1,r,g,b) end
        if type(GetRepairAllCost)=="function" then
            local ok,cost,canRepair=pcall(GetRepairAllCost)
            cost=ok and tonumber(cost) or nil
            if cost and cost>0 then GameTooltip:AddLine(" "); GameTooltip:AddDoubleLine("Reparaturkosten",FormatMoney(cost),1,0.82,0,1,1,1) end
        end
        GameTooltip:Show(); return
    elseif id == "fps" or id == "latency" then
        GameTooltip:SetOwner(owner,"ANCHOR_BOTTOM"); GameTooltip:ClearLines(); GameTooltip:AddLine("System / Leistung",1,0.82,0)
        local s=self.perf or {}; local count=math.max(1,tonumber(s.count) or 0)
        local currentFPS=type(GetFramerate)=="function" and tonumber(GetFramerate()) or 0
        GameTooltip:AddDoubleLine("FPS aktuell",string.format("%.0f",currentFPS),1,1,1,1,1,1)
        if s.fpsMin then GameTooltip:AddDoubleLine("FPS Minimum",string.format("%.0f",s.fpsMin),1,1,1,1,0.2,0.2) end
        if s.fpsSum and s.count and s.count>0 then GameTooltip:AddDoubleLine("FPS Durchschnitt",string.format("%.0f",s.fpsSum/count),1,1,1,1,0.82,0) end
        if s.fpsMax then GameTooltip:AddDoubleLine("FPS Maximum",string.format("%.0f",s.fpsMax),1,1,1,0.2,1,0.2) end
        if type(GetNetStats)=="function" then
            local _,_,home,world=GetNetStats(); GameTooltip:AddLine(" "); GameTooltip:AddLine("Latenz",1,0.82,0)
            GameTooltip:AddDoubleLine("Standort aktuell",tostring(math.floor(tonumber(home) or 0)).." ms",1,1,1,1,1,1)
            GameTooltip:AddDoubleLine("Welt aktuell",tostring(math.floor(tonumber(world) or 0)).." ms",1,1,1,1,1,1)
            if s.homeMin then GameTooltip:AddDoubleLine("Standort Min / Ø / Max",string.format("%.0f / %.0f / %.0f ms",s.homeMin,(s.homeSum or 0)/count,s.homeMax or 0),1,1,1,0.2,1,0.2) end
            if s.worldMin then GameTooltip:AddDoubleLine("Welt Min / Ø / Max",string.format("%.0f / %.0f / %.0f ms",s.worldMin,(s.worldSum or 0)/count,s.worldMax or 0),1,1,1,0.2,1,0.2) end
        end
        AddAddonUsage(GameTooltip)
        GameTooltip:AddLine(" "); GameTooltip:AddLine("Rechtsklick: Statistik zurücksetzen",0.65,0.65,0.65)
        GameTooltip:Show(); return
    elseif id == "clock" then
        GameTooltip:SetOwner(owner,"ANCHOR_BOTTOM"); GameTooltip:ClearLines(); GameTooltip:AddLine("Zeit",1,0.82,0)
        if date then GameTooltip:AddDoubleLine("Lokal",date("%H:%M:%S  %d.%m.%Y"),1,1,1,1,1,1) end
        if type(GetGameTime)=="function" then local h,m=GetGameTime(); GameTooltip:AddDoubleLine("Server",string.format("%02d:%02d",h or 0,m or 0),1,1,1,1,1,1) end
        if self.GetSessionPlayed then GameTooltip:AddDoubleLine("Sitzung",FormatDuration(self:GetSessionPlayed()),1,1,1,1,1,1) end
        if self.GetCurrentTotalPlayed then GameTooltip:AddDoubleLine("Charakter",FormatDuration(self:GetCurrentTotalPlayed()),1,1,1,1,1,1) end
        if self.GetAccountPlayedTotal then GameTooltip:AddDoubleLine("Alle Charaktere",FormatDuration(self:GetAccountPlayedTotal()),1,0.82,0,1,0.82,0) end
        GameTooltip:Show(); return
    end

    if originalShowModuleTooltip then return originalShowModuleTooltip(self,id,owner) end
end

local originalRefreshFeature = A.RefreshFeature
function A:RefreshFeature(...)
    if originalRefreshFeature then originalRefreshFeature(self, ...) end
    if not self.db or not self.panelFrame or not self.modules then return end
    EnsureDefaults()

    for _, id in ipairs({"xp","durability"}) do
        local m=self.modules[id]
        if m then local enabled=self:IsModuleEnabled(id); m:SetShown(enabled); if enabled then m.text:SetText(self:GetModuleText(id)) end end
    end

    local tr,tg,tb=Hex(self.db.panel.textColor,1,1,1)
    for id,m in pairs(self.modules) do
        if m.text then m.text:SetTextColor(tr,tg,tb) end
    end
    if self.db.panel.dynamicPerformanceColors then
        local fps=self.modules.fps; local f=type(GetFramerate)=="function" and tonumber(GetFramerate()) or 0
        if fps and fps.text then if f>=60 then fps.text:SetTextColor(0.2,1,0.2) elseif f>=30 then fps.text:SetTextColor(1,0.82,0) else fps.text:SetTextColor(1,0.2,0.2) end end
        local lat=self.modules.latency
        if lat and lat.text and type(GetNetStats)=="function" then local _,_,h,w=GetNetStats(); local ms=math.max(tonumber(h) or 0,tonumber(w) or 0); if ms<80 then lat.text:SetTextColor(0.2,1,0.2) elseif ms<150 then lat.text:SetTextColor(1,0.82,0) else lat.text:SetTextColor(1,0.2,0.2) end end
    end
    self:LayoutModules()
end

local function HookPerformanceReset()
    if A.modules and A.modules.fps and not A.modules.fps.__comfyResetHook then
        A.modules.fps.__comfyResetHook=true
        A.modules.fps:HookScript("OnMouseUp",function(_,button) if button=="RightButton" then ResetPerfStats(); A:RefreshFeature() end end)
    end
end

local function UpdateCurrentExtendedCharacter()
    local r=A.GetCharacterRecord and A:GetCharacterRecord() or nil
    if not r then return end
    if type(UnitClass)=="function" then local localized,classFile=UnitClass("player"); r.class=localized or r.class; r.classFile=classFile or r.classFile end
    if type(GetGuildInfo)=="function" then local guild=GetGuildInfo("player"); r.guild=guild or r.guild end
end

local function HandleXP()
    local cur=type(UnitXP)=="function" and tonumber(UnitXP("player")) or nil
    local maxXP=type(UnitXPMax)=="function" and tonumber(UnitXPMax("player")) or nil
    local level=type(UnitLevel)=="function" and tonumber(UnitLevel("player")) or nil
    if cur and A.lastXPValue then
        local delta
        if level and A.lastXPLevel and level>A.lastXPLevel and A.lastXPMax then delta=math.max(0,A.lastXPMax-A.lastXPValue)+cur
        else delta=cur-A.lastXPValue end
        if delta and delta>0 then A.xpSessionGained=(A.xpSessionGained or 0)+delta end
    end
    A.lastXPValue=cur; A.lastXPMax=maxXP; A.lastXPLevel=level
end

local originalInitializeFeature = A.InitializeFeature
function A:InitializeFeature(...)
    EnsureDefaults()
    ResetPerfStats()
    self.moneySessionStartAt=Now(); self.sessionMoneyStart=type(GetMoney)=="function" and tonumber(GetMoney()) or 0
    self.xpSessionStartAt=Now(); self.xpSessionGained=0
    self.lastXPValue=type(UnitXP)=="function" and tonumber(UnitXP("player")) or 0
    self.lastXPMax=type(UnitXPMax)=="function" and tonumber(UnitXPMax("player")) or 0
    self.lastXPLevel=type(UnitLevel)=="function" and tonumber(UnitLevel("player")) or 0

    if originalInitializeFeature then originalInitializeFeature(self, ...) end
    self:CreatePanel(); HookPerformanceReset(); UpdateCurrentExtendedCharacter()

    local e=CreateFrame("Frame")
    e:RegisterEvent("PLAYER_XP_UPDATE"); e:RegisterEvent("PLAYER_LEVEL_UP"); e:RegisterEvent("PLAYER_MONEY"); e:RegisterEvent("PLAYER_GUILD_UPDATE")
    e:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_XP_UPDATE" or event=="PLAYER_LEVEL_UP" then HandleXP() end
        UpdateCurrentExtendedCharacter(); A:RefreshFeature()
    end)
    e:SetScript("OnUpdate",function(self,elapsed)
        self.elapsed=(self.elapsed or 0)+(tonumber(elapsed) or 0)
        if self.elapsed>=1 then self.elapsed=0; SamplePerformance(); HookPerformanceReset() end
    end)
    self.enhancementEvents=e
end

local function CreateCheck(parent,text,x,y,get,set)
    local c=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate"); c:SetPoint("TOPLEFT",x,y)
    local t=c.Text or c.text; if t then t:SetText(text) end; c:SetChecked(get() and true or false)
    c:SetScript("OnClick",function(self) set(self:GetChecked() and true or false); A:RefreshFeature() end); return c
end

local function OpenEnhancementSettings()
    EnsureDefaults()
    if not A.enhancementOptions then
        local f=CreateFrame("Frame","ComfyPanelEnhancementOptions",UIParent,"BasicFrameTemplateWithInset")
        f:SetSize(720,560); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",function(self) self:StartMoving() end); f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        f.TitleText:SetText("ComfyPanel · Anzeige")
        local p=A.db.panel
        local title=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); title:SetPoint("TOPLEFT",24,-42); title:SetText("Module")
        CreateCheck(f,"XP anzeigen",24,-72,function() return p.showXP end,function(v) p.showXP=v end)
        CreateCheck(f,"Haltbarkeit anzeigen",200,-72,function() return p.showDurability end,function(v) p.showDurability=v end)
        CreateCheck(f,"Reagenztasche bei Taschen",410,-72,function() return p.showReagentBagCount end,function(v) p.showReagentBagCount=v end)
        local gold=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); gold:SetPoint("TOPLEFT",24,-125); gold:SetText("Gold")
        CreateCheck(f,"Seit Login",24,-155,function() return p.moneyShowSession end,function(v) p.moneyShowSession=v end)
        CreateCheck(f,"Gold/Stunde",200,-155,function() return p.moneyShowPerHour end,function(v) p.moneyShowPerHour=v end)
        CreateCheck(f,"Datenbank-Hinweis",410,-155,function() return p.showDatabaseNote end,function(v) p.showDatabaseNote=v end)
        local xp=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); xp:SetPoint("TOPLEFT",24,-210); xp:SetText("XP-Anzeige im Panel")
        local defs={{"Level", "xpShowLevel",24,-240},{"Prozent", "xpShowPercent",150,-240},{"XP/Max", "xpShowCurrent",280,-240},{"Rest-XP", "xpShowRemaining",410,-240},{"XP/Stunde", "xpShowPerHour",24,-275},{"Restzeit", "xpShowETA",200,-275},{"Session-XP", "xpShowSession",360,-275}}
        for _,d in ipairs(defs) do CreateCheck(f,d[1],d[3],d[4],function() return p[d[2]] end,function(v) p[d[2]]=v end) end
        local perf=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge"); perf:SetPoint("TOPLEFT",24,-335); perf:SetText("Darstellung")
        CreateCheck(f,"FPS/MS dynamisch einfärben",24,-365,function() return p.dynamicPerformanceColors end,function(v) p.dynamicPerformanceColors=v end)
        local colorBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); colorBtn:SetSize(190,24); colorBtn:SetPoint("TOPLEFT",24,-410); colorBtn:SetText("Panel-Textfarbe")
        colorBtn:SetScript("OnClick",function()
            if not ColorPickerFrame then return end
            local r,g,b=Hex(p.textColor,1,1,1)
            ColorPickerFrame:SetColorRGB(r,g,b)
            ColorPickerFrame.hasOpacity=false
            ColorPickerFrame.func=function()
                local nr,ng,nb=ColorPickerFrame:GetColorRGB(); p.textColor=string.format("%02X%02X%02X",math.floor(nr*255+0.5),math.floor(ng*255+0.5),math.floor(nb*255+0.5)); A:RefreshFeature()
            end
            ColorPickerFrame.cancelFunc=function(previous) if type(previous)=="table" then local pr,pg,pb=unpack(previous); p.textColor=string.format("%02X%02X%02X",math.floor(pr*255+0.5),math.floor(pg*255+0.5),math.floor(pb*255+0.5)); A:RefreshFeature() end end
            ColorPickerFrame.previousValues={r,g,b}; ColorPickerFrame:Show()
        end)
        A.enhancementOptions=f
    end
    A.enhancementOptions:Show(); A.enhancementOptions:Raise()
end

local originalBuildGeneralOptions=A.BuildGeneralOptions
function A:BuildGeneralOptions(page,ui)
    if originalBuildGeneralOptions then originalBuildGeneralOptions(self,page,ui) end
    if ui and ui.CreateButton then ui.CreateButton(page,"Erweiterte Anzeige",390,-400,190,OpenEnhancementSettings) end
end
