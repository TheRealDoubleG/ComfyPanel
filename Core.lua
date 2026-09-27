local ADDON_NAME = ...

ComfyPanel = ComfyPanel or {}
local A = ComfyPanel
A.name = ADDON_NAME or "ComfyPanel"
A.version = "0.5"
A.buildDate = "27.09.2026"
A.status = "Beta"
A.gameVersion = "WoW Forever 1.60.1"
A.targetBuild = "70009"
A.interface = 16001
A.author = "TheRealDoubleG"
A.discord = "the.real.double.g"
A.github = "https://github.com/TheRealDoubleG/ComfyPanel"

local defaults = {
    enabled = true,
    panel = {
        position = "TOP",
        offset = 24,
        height = 22,
        opacity = 0,
        unlocked = false,
        alignment = "LEFT",
        modulePositions = {},
        showMoney = true,
        showBags = true,
        bagShowMax = true,
        showPlaytime = true,
        playtimeShowSession = true,
        playtimeShowCharacter = false,
        playtimeShowAccount = false,
        showKills = true,
        showTime = true,
        showFPS = true,
        showLatency = true,
    },
    optionsWindow = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 20,
    },
    ui = {
        windowLocked = false,
        windowOpacity = 100,
        showWindowBorder = true,
        backgroundAlpha = 92,
    },
}

local function CopyTable(src) if type(src)~="table" then return src end local d={} for k,v in pairs(src) do d[k]=CopyTable(v) end return d end
local function ApplyDefaults(dst,src) if type(dst)~="table" or type(src)~="table" then return end for k,v in pairs(src) do if type(v)=="table" then if type(dst[k])~="table" then dst[k]={} end ApplyDefaults(dst[k],v) elseif dst[k]==nil then dst[k]=v end end end
function A:Print(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd200ComfyPanel:|r "..tostring(msg)) end end
function A:GetClientBuildInfo() if type(GetBuildInfo)~="function" then return "?","?","?",nil end local v,b,d,i=GetBuildInfo(); return tostring(v or "?"),tostring(b or "?"),tostring(d or "?"),tonumber(i) end
function A:GetCompatibilityStatus() local _,_,_,i=self:GetClientBuildInfo(); if i and tonumber(i)==tonumber(self.interface) then return true,self:T("COMPAT_MATCH") end return false,self:T("COMPAT_UPDATE_REQUIRED") end
function A:InitializeDB() if self.InitializeProfileStorage then self:InitializeProfileStorage(defaults,"ComfyPanelDB") else if type(_G["ComfyPanelDB"])~="table" then _G["ComfyPanelDB"]=CopyTable(defaults) else ApplyDefaults(_G["ComfyPanelDB"],defaults) end self.db=_G["ComfyPanelDB"] end end
function A:SetEnabled(v) if not self.db then return false end self.db.enabled=v and true or false if self.RefreshFeature then self:RefreshFeature() end if self.RefreshOptions then self:RefreshOptions() end return true end
function A:GetComfyProfileProvider() return self end
function A:OpenOptions() if self.ShowOptions then self:ShowOptions() end end
SLASH_COMFYPANEL1="/comfypanel"
SLASH_COMFYPANEL2="/cpanel"
SlashCmdList.COMFYPANEL=function(msg) msg=tostring(msg or ""):lower():match("^%s*(.-)%s*$"); if A.HandleSlash and A:HandleSlash(msg) then return end A:OpenOptions() end
local e=CreateFrame("Frame"); e:RegisterEvent("ADDON_LOADED"); e:RegisterEvent("PLAYER_LOGIN")
e:SetScript("OnEvent",function(_,ev,arg1) if ev=="ADDON_LOADED" and arg1==A.name then A:InitializeDB(); if A.InitializeFeature then A:InitializeFeature() end; if A.InitializeOptions then A:InitializeOptions() end elseif ev=="PLAYER_LOGIN" and A.RefreshFeature then A:RefreshFeature() end end)
