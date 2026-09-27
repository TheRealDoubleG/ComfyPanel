ComfyPanel = ComfyPanel or {}
local A = ComfyPanel

local controls = {}
local dropdowns = {}
local sliderIndex = 0

local function SetLabel(check, text)
    local label = check.Text or check.text
    if not label then
        label = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", check, "RIGHT", 3, 1)
        check.Text = label
    end
    label:SetText(text)
end

local function CreateCheck(parent, text, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    SetLabel(cb, text)
    cb._getter = getter
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        if A.RefreshFeature then A:RefreshFeature() end
        A:RefreshOptions()
    end)
    controls[#controls + 1] = cb
    return cb
end

local function CreateButton(parent, text, x, y, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter, formatter)
    sliderIndex = sliderIndex + 1
    local name = "ComfyPanelSlider" .. tostring(sliderIndex)
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", x, y)
    sl:SetWidth(250)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    if _G[name.."Low"] then _G[name.."Low"]:SetText(tostring(minV)) end
    if _G[name.."High"] then _G[name.."High"]:SetText(tostring(maxV)) end
    if _G[name.."Text"] then _G[name.."Text"]:SetText(label) end
    sl.valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sl.valueText:SetPoint("LEFT", sl, "RIGHT", 12, 0)
    sl._getter = getter
    sl._formatter = formatter
    sl:SetScript("OnValueChanged", function(self, value)
        if self._refreshing then return end
        setter(value)
        self.valueText:SetText(formatter and formatter(value) or tostring(value))
        if A.RefreshFeature then A:RefreshFeature() end
    end)
    controls[#controls + 1] = sl
    return sl
end

local function CreateDropdown(parent, x, y, width, itemsFn, currentFn, selectFn)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x, y)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width or 200) end
    UIDropDownMenu_Initialize(dd, function(_, level)
        local current = currentFn()
        for _, entry in ipairs(itemsFn() or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.value = entry.value
            info.checked = entry.value == current
            info.func = function()
                selectFn(entry.value)
                CloseDropDownMenus()
                if dd._refresh then dd._refresh() end
                A:RefreshOptions()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    dd._refresh = function()
        local current = currentFn()
        local label = tostring(current or "")
        for _, entry in ipairs(itemsFn() or {}) do
            if entry.value == current then label = entry.text break end
        end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, label) end
    end
    dropdowns[#dropdowns + 1] = dd
    return dd
end

local function CreateEdit(parent, x, y, w, h, multiline)
    local template = multiline and "BackdropTemplate" or "InputBoxTemplate"
    local e = CreateFrame("EditBox", nil, parent, template)
    e:SetPoint("TOPLEFT", x, y)
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    e:SetMultiLine(multiline and true or false)
    if multiline then
        e:SetFontObject("ChatFontNormal")
        e:SetTextInsets(8, 8, 8, 8)
        e:SetJustifyH("LEFT")
        e:SetJustifyV("TOP")
        e:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
        e:SetBackdropColor(0.02,0.02,0.02,0.8)
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local function SelectTab(index)
    local frame = A.optionsFrame
    if not frame then return end
    for i, tab in ipairs(frame.tabs) do
        tab:SetEnabled(true)
        tab:SetButtonState(i == index and "PUSHED" or "NORMAL", i == index)
        frame.pages[i]:SetShown(i == index)
    end
end

function A:RefreshOptions()
    if not self.optionsFrame or not self.db then return end
    for _, c in ipairs(controls) do
        if c._getter then
            local value = c._getter()
            if c:GetObjectType() == "CheckButton" then
                c:SetChecked(value and true or false)
            elseif c:GetObjectType() == "Slider" then
                c._refreshing = true
                c:SetValue(value)
                c._refreshing = false
                if c.valueText then
                    c.valueText:SetText(c._formatter and c._formatter(value) or tostring(value))
                end
            end
        end
    end
    for _, d in ipairs(dropdowns) do if d._refresh then d._refresh() end end
    if self.RefreshFeatureOptions then self:RefreshFeatureOptions() end
    if self.RefreshSharedSettingsPage then self:RefreshSharedSettingsPage() end
end

function A:RegisterBlizzardSettingsCategory()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

    local canvas = CreateFrame("Frame")
    local isDE = type(GetLocale) == "function" and GetLocale() == "deDE"

    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ComfyPanel")

    local desc = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(isDE
        and "Öffnet das vollständige ComfyPanel-Einstellungsfenster der Comfy Suite."
        or "Opens the full ComfyPanel settings window for the Comfy Suite.")

    CreateButton(canvas, isDE and "Einstellungen öffnen" or "Open settings", 16, -90, 220, function()
        A:ShowOptions()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "ComfyPanel")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

function A:InitializeOptions()
    if self.optionsFrame then return end

    local frame = CreateFrame("Frame", "ComfyPanelOptions", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 620)
    local pos = self.db and self.db.optionsWindow or {}
    local point = pos.point or "CENTER"
    local rp = pos.relativePoint or point
    frame:SetPoint(point, UIParent, rp, pos.x or 0, pos.y or 20)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(20)
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    frame.TitleText:SetText("ComfyPanel")
    frame:SetScript("OnMouseDown", function(self) self:Raise() end)
    frame:SetScript("OnDragStart", function(self)
        if A:IsOptionsWindowLocked() then return end
        self:Raise()
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, r, x, y = self:GetPoint(1)
        A.db.optionsWindow = A.db.optionsWindow or {}
        A.db.optionsWindow.point, A.db.optionsWindow.relativePoint = p, r or p
        A.db.optionsWindow.x, A.db.optionsWindow.y = x or 0, y or 0
    end)
    table.insert(UISpecialFrames, frame:GetName())
    self.optionsFrame = frame
    frame.tabs, frame.pages = {}, {}

    local names = {self:T("TAB_GENERAL"), self:GetSharedSettingsTabLabel(), self:T("TAB_INFO")}
    for i, label in ipairs(names) do
        local tab = CreateButton(frame, label, 18 + (i - 1) * 120, -35, 110, function() SelectTab(i) end)
        frame.tabs[i] = tab
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 12, -70)
        page:SetPoint("BOTTOMRIGHT", -12, 12)
        frame.pages[i] = page
    end

    local general = frame.pages[1]
    local title = general:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -10)
    title:SetText(self:T("TAB_GENERAL"))

    CreateCheck(general, self:T("ADDON_ENABLED"), 20, -50,
        function() return A.db.enabled end,
        function(v) A:SetEnabled(v) end)

    local ui = {
        CreateCheck=CreateCheck, CreateButton=CreateButton, CreateSlider=CreateSlider,
        CreateDropdown=CreateDropdown, CreateEdit=CreateEdit,
    }
    if self.BuildGeneralOptions then self:BuildGeneralOptions(general, ui) end

    self:BuildSharedSettingsPage(frame.pages[2])

    local info = frame.pages[3]
    local box = CreateFrame("Frame", nil, info, "BackdropTemplate")
    box:SetSize(680,455); box:SetPoint("TOPLEFT",20,-52)
    box:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    box:SetBackdropColor(0.03,0.03,0.03,0.92)
    box:SetBackdropBorderColor(0.55,0.45,0.2,1)

    local name = box:CreateFontString(nil,"ARTWORK","GameFontNormalHuge")
    name:SetPoint("TOPLEFT",24,-22); name:SetText("ComfyPanel")
    local badge = box:CreateFontString(nil,"ARTWORK","GameFontNormal")
    badge:SetPoint("TOPRIGHT",-24,-26); badge:SetText("Comfy Suite"); badge:SetTextColor(1,0.82,0)
    local tagline = box:CreateFontString(nil,"ARTWORK","GameFontHighlight")
    tagline:SetPoint("TOPLEFT",24,-58); tagline:SetWidth(610); tagline:SetJustifyH("LEFT"); tagline:SetText("Minimal modular information panel for WoW Forever.")

    local function Row(label,value,y)
        local l=box:CreateFontString(nil,"ARTWORK","GameFontNormal"); l:SetPoint("TOPLEFT",28,y); l:SetText(label)
        local v=box:CreateFontString(nil,"ARTWORK","GameFontHighlight"); v:SetPoint("TOPLEFT",185,y); v:SetWidth(455); v:SetJustifyH("LEFT"); v:SetText(value or "-")
        return v
    end
    local cv, cb, _, ci = self:GetClientBuildInfo()
    local compatible, compatText = self:GetCompatibilityStatus()
    Row(self:T("INFO_VERSION"),self.version,-100)
    Row(self:T("INFO_BUILD_DATE"),self.buildDate,-122)
    Row(self:T("INFO_STATUS"),self.status,-144)
    Row(self:T("INFO_CLIENT"),"WoW Forever "..tostring(cv).." / Build "..tostring(cb).." / Interface "..tostring(ci or "?"),-166)
    Row(self:T("INFO_TESTED_TARGET"),self.gameVersion.." / Build "..self.targetBuild.." / Interface "..tostring(self.interface),-188)
    local comp=Row(self:T("INFO_COMPAT_STATUS"),compatText,-210); comp:SetTextColor(compatible and 0.2 or 1, compatible and 1 or 0.35, compatible and 0.2 or 0.2)
    Row(self:T("INFO_AUTHOR"),self.author,-232)

    local dl=box:CreateFontString(nil,"ARTWORK","GameFontNormal"); dl:SetPoint("TOPLEFT",28,-257); dl:SetText(self:T("INFO_DISCORD"))
    local db=CreateFrame("EditBox",nil,box,"InputBoxTemplate"); db:SetSize(275,30); db:SetPoint("TOPLEFT",180,-248); db:SetAutoFocus(false); db:SetText(self.discord); db:SetScript("OnEditFocusGained",function(self) self:HighlightText() end); db:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local gl=box:CreateFontString(nil,"ARTWORK","GameFontNormal"); gl:SetPoint("TOPLEFT",28,-292); gl:SetText(self:T("INFO_GITHUB"))
    local gb=CreateFrame("EditBox",nil,box,"InputBoxTemplate"); gb:SetSize(395,30); gb:SetPoint("TOPLEFT",180,-283); gb:SetAutoFocus(false); gb:SetText(self.github); gb:SetScript("OnEditFocusGained",function(self) self:HighlightText() end); gb:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    Row(self:T("INFO_COMMANDS"),"/comfypanel  ·  /cpanel",-328)

    local notice=box:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); notice:SetPoint("TOPLEFT",28,-350); notice:SetWidth(620); notice:SetHeight(42); notice:SetJustifyH("LEFT"); notice:SetJustifyV("TOP"); notice:SetText(self:T("INFO_NOTICE"))
    local cr=box:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); cr:SetPoint("BOTTOMLEFT",28,48); cr:SetText("© 2026 TheRealDoubleG")
    local thanks=box:CreateFontString(nil,"ARTWORK","GameFontHighlight"); thanks:SetPoint("BOTTOMLEFT",28,16); thanks:SetWidth(620); thanks:SetText(self:T("INFO_THANKS"))

    frame:SetScript("OnShow", function()
        A:ApplySharedWindowSettings()
        A:RefreshOptions()
    end)
    self:ApplySharedWindowSettings()
    SelectTab(1)
    self:RefreshOptions()
    self:RegisterBlizzardSettingsCategory()
end

function A:ShowOptions()
    if not self.optionsFrame then self:InitializeOptions() end
    self.optionsFrame:Show()
    self.optionsFrame:Raise()
    self:RefreshOptions()
end
