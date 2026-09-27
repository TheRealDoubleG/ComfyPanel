ComfyPanel = ComfyPanel or {}
local CC = ComfyPanel

local de = GetLocale and GetLocale() == "deDE"

local function L(german, english)
    return de and german or english
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

local function ApplyDefaults(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Trim(value)
    value = tostring(value or "")
    return value:match("^%s*(.-)%s*$") or ""
end

local function SetShownSafe(region, shown)
    if region and type(region.SetShown) == "function" then
        region:SetShown(shown and true or false)
    end
end

function CC:GetCharacterStorageKey()
    local name, realm
    if type(UnitFullName) == "function" then
        local ok, n, r = pcall(UnitFullName, "player")
        if ok then name, realm = n, r end
    end
    if (not name or name == "") and type(UnitName) == "function" then
        local ok, n = pcall(UnitName, "player")
        if ok then name = n end
    end
    if (not realm or realm == "") and type(GetRealmName) == "function" then
        local ok, r = pcall(GetRealmName)
        if ok then realm = r end
    end
    name = name or "Unknown"
    realm = realm or "Realm"
    return tostring(name) .. " - " .. tostring(realm)
end

function CC:GetCharacterProfileKey()
    return "character:" .. self:GetCharacterStorageKey()
end

function CC:InitializeProfileStorage(defaults, savedVariableName)
    self._profileDefaults = DeepCopy(defaults or {})
    self._savedVariableName = savedVariableName

    local existing = _G[savedVariableName]
    local root

    if type(existing) == "table" and existing.__comfyProfileSchema == 1 and type(existing.profiles) == "table" then
        root = existing
    else
        local legacy = type(existing) == "table" and DeepCopy(existing) or DeepCopy(defaults or {})
        root = {
            __comfyProfileSchema = 1,
            profiles = {},
            labels = {},
            kinds = {},
            characters = {},
            activeByCharacter = {},
            nextCustomId = 1,
        }

        root.profiles.account = DeepCopy(legacy)
        root.labels.account = L("Account", "Account")
        root.kinds.account = "account"

        local character = self:GetCharacterStorageKey()
        local characterKey = "character:" .. character
        root.profiles[characterKey] = DeepCopy(legacy)
        root.labels[characterKey] = character
        root.kinds[characterKey] = "character"
        root.characters[character] = characterKey
        root.activeByCharacter[character] = characterKey
        _G[savedVariableName] = root
    end

    root.profiles = type(root.profiles) == "table" and root.profiles or {}
    root.labels = type(root.labels) == "table" and root.labels or {}
    root.kinds = type(root.kinds) == "table" and root.kinds or {}
    root.characters = type(root.characters) == "table" and root.characters or {}
    root.activeByCharacter = type(root.activeByCharacter) == "table" and root.activeByCharacter or {}
    root.nextCustomId = tonumber(root.nextCustomId) or 1

    if type(root.profiles.account) ~= "table" then root.profiles.account = DeepCopy(defaults or {}) end
    ApplyDefaults(root.profiles.account, defaults or {})
    root.labels.account = root.labels.account or L("Account", "Account")
    root.kinds.account = "account"

    local character = self:GetCharacterStorageKey()
    local characterKey = "character:" .. character
    if type(root.profiles[characterKey]) ~= "table" then
        root.profiles[characterKey] = DeepCopy(defaults or {})
    end
    ApplyDefaults(root.profiles[characterKey], defaults or {})
    root.labels[characterKey] = character
    root.kinds[characterKey] = "character"
    root.characters[character] = characterKey

    local activeKey = root.activeByCharacter[character] or characterKey
    if type(root.profiles[activeKey]) ~= "table" then activeKey = characterKey end
    root.activeByCharacter[character] = activeKey

    self.profileRoot = root
    self.db = root.profiles[activeKey]
    ApplyDefaults(self.db, defaults or {})
    self:EnsureSharedUISettings()
end

function CC:EnsureSharedUISettings()
    if not self.db then return end
    if type(self.db.ui) ~= "table" then self.db.ui = {} end
    local ui = self.db.ui
    if ui.windowLocked == nil then ui.windowLocked = false end
    if ui.windowOpacity == nil then ui.windowOpacity = 100 end
    if ui.showWindowBorder == nil then ui.showWindowBorder = true end
    if ui.backgroundAlpha == nil then ui.backgroundAlpha = 92 end
end

function CC:GetActiveStorageProfileKey()
    if not self.profileRoot then return nil end
    local character = self:GetCharacterStorageKey()
    return self.profileRoot.activeByCharacter[character] or self:GetCharacterProfileKey()
end

function CC:GetStorageProfileLabel(key)
    if not self.profileRoot then return tostring(key or "") end
    return self.profileRoot.labels[key] or tostring(key or "")
end

function CC:GetSelectableStorageProfiles()
    if not self.profileRoot then return {} end
    local root = self.profileRoot
    local currentCharacterKey = self:GetCharacterProfileKey()
    local list = {
        {value = currentCharacterKey, text = L("Charakter: ", "Character: ") .. self:GetStorageProfileLabel(currentCharacterKey)},
        {value = "account", text = L("Account-Profil", "Account profile")},
    }

    local custom = {}
    for key, kind in pairs(root.kinds) do
        if kind == "custom" and root.profiles[key] then
            custom[#custom + 1] = {value = key, text = root.labels[key] or key}
        end
    end
    table.sort(custom, function(a, b) return tostring(a.text):lower() < tostring(b.text):lower() end)
    for _, entry in ipairs(custom) do list[#list + 1] = entry end
    return list
end

function CC:GetCopySourceStorageProfiles()
    if not self.profileRoot then return {} end
    local root = self.profileRoot
    local list = {}

    list[#list + 1] = {value = "account", text = L("Account-Profil", "Account profile")}

    local characters = {}
    for character, key in pairs(root.characters) do
        if root.profiles[key] then
            characters[#characters + 1] = {value = key, text = L("Charakter: ", "Character: ") .. character}
        end
    end
    table.sort(characters, function(a, b) return tostring(a.text):lower() < tostring(b.text):lower() end)
    for _, entry in ipairs(characters) do list[#list + 1] = entry end

    local custom = {}
    for key, kind in pairs(root.kinds) do
        if kind == "custom" and root.profiles[key] then
            custom[#custom + 1] = {value = key, text = L("Eigenes Profil: ", "Custom profile: ") .. (root.labels[key] or key)}
        end
    end
    table.sort(custom, function(a, b) return tostring(a.text):lower() < tostring(b.text):lower() end)
    for _, entry in ipairs(custom) do list[#list + 1] = entry end
    return list
end

function CC:ApplyStoredOptionsWindowPosition()
    if not self.optionsFrame or not self.db then return end
    local saved = self.db.optionsWindow
    if type(saved) ~= "table" then return end
    local point = saved.point or "CENTER"
    local relativePoint = saved.relativePoint or point
    self.optionsFrame:ClearAllPoints()
    self.optionsFrame:SetPoint(point, UIParent, relativePoint, saved.x or 0, saved.y or 0)
end

function CC:NotifyStorageProfileChanged()
    self:EnsureSharedUISettings()
    if self.ApplyStoredOptionsWindowPosition then self:ApplyStoredOptionsWindowPosition() end
    if self.ApplySharedWindowSettings then self:ApplySharedWindowSettings() end
    if self.UpdateMinimapPosition then self:UpdateMinimapPosition() end
    if self.UpdateMinimapAppearance then self:UpdateMinimapAppearance() end
    if self.RefreshBars then self:RefreshBars() end
    if self.RefreshAllCooldowns then self:RefreshAllCooldowns() end
    if self.RefreshFeature then self:RefreshFeature() end
    if self.UpdatePreview then self:UpdatePreview() end
    if self.RefreshOptions then self:RefreshOptions() end
    if self.RefreshSharedSettingsPage then self:RefreshSharedSettingsPage() end
end

function CC:SetActiveStorageProfile(key)
    if not self.profileRoot or type(self.profileRoot.profiles[key]) ~= "table" then return false end
    local kind = self.profileRoot.kinds[key]
    local currentCharacterKey = self:GetCharacterProfileKey()
    if key ~= "account" and key ~= currentCharacterKey and kind ~= "custom" then return false end

    local character = self:GetCharacterStorageKey()
    self.profileRoot.activeByCharacter[character] = key
    self.db = self.profileRoot.profiles[key]
    ApplyDefaults(self.db, self._profileDefaults or {})
    self:NotifyStorageProfileChanged()
    return true
end

function CC:CopyStorageProfileToCharacter(sourceKey)
    if not self.profileRoot or type(self.profileRoot.profiles[sourceKey]) ~= "table" then return false end
    local targetKey = self:GetCharacterProfileKey()
    self.profileRoot.profiles[targetKey] = DeepCopy(self.profileRoot.profiles[sourceKey])
    ApplyDefaults(self.profileRoot.profiles[targetKey], self._profileDefaults or {})
    local character = self:GetCharacterStorageKey()
    self.profileRoot.activeByCharacter[character] = targetKey
    self.db = self.profileRoot.profiles[targetKey]
    self:NotifyStorageProfileChanged()
    return true
end

function CC:CreateStorageProfile(name)
    if not self.profileRoot then return false end
    name = Trim(name)
    if name == "" then return false end
    if #name > 40 then name = name:sub(1, 40) end

    local id = self.profileRoot.nextCustomId or 1
    local key
    repeat
        key = "custom:" .. tostring(id)
        id = id + 1
    until not self.profileRoot.profiles[key]
    self.profileRoot.nextCustomId = id

    self.profileRoot.profiles[key] = DeepCopy(self.db or self._profileDefaults or {})
    self.profileRoot.labels[key] = name
    self.profileRoot.kinds[key] = "custom"

    local character = self:GetCharacterStorageKey()
    self.profileRoot.activeByCharacter[character] = key
    self.db = self.profileRoot.profiles[key]
    self:NotifyStorageProfileChanged()
    return key
end

function CC:DeleteActiveStorageProfile()
    if not self.profileRoot then return false end
    local key = self:GetActiveStorageProfileKey()
    if self.profileRoot.kinds[key] ~= "custom" then return false end

    self.profileRoot.profiles[key] = nil
    self.profileRoot.labels[key] = nil
    self.profileRoot.kinds[key] = nil

    local character = self:GetCharacterStorageKey()
    local targetKey = self:GetCharacterProfileKey()
    self.profileRoot.activeByCharacter[character] = targetKey
    self.db = self.profileRoot.profiles[targetKey]
    ApplyDefaults(self.db, self._profileDefaults or {})
    self:NotifyStorageProfileChanged()
    return true
end

function CC:ResetActiveStorageProfile()
    if not self.profileRoot then return false end
    local key = self:GetActiveStorageProfileKey()
    if not key then return false end
    self.profileRoot.profiles[key] = DeepCopy(self._profileDefaults or {})
    self.db = self.profileRoot.profiles[key]
    self:NotifyStorageProfileChanged()
    return true
end

function CC:IsOptionsWindowLocked()
    self:EnsureSharedUISettings()
    return self.db and self.db.ui and self.db.ui.windowLocked and true or false
end

function CC:ApplySharedWindowSettings()
    local frame = self.optionsFrame
    if not frame or not self.db then return end
    self:EnsureSharedUISettings()
    local ui = self.db.ui

    local opacity = math.max(10, math.min(100, tonumber(ui.windowOpacity) or 100))
    frame:SetAlpha(opacity / 100)

    if not frame.__comfyMinimalBackground then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -24)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        bg:SetColorTexture(0.025, 0.025, 0.03, 1)
        frame.__comfyMinimalBackground = bg
    end

    local showBorder = ui.showWindowBorder ~= false
    local backgroundAlpha = math.max(0, math.min(100, tonumber(ui.backgroundAlpha) or 92)) / 100

    -- The Blizzard frame background is hidden permanently and replaced by one
    -- dedicated Comfy background texture. This keeps border visibility and
    -- background opacity independent from each other.
    SetShownSafe(frame.NineSlice, showBorder)
    SetShownSafe(frame.TitleBg, showBorder)
    SetShownSafe(frame.TopTileStreaks, showBorder)
    SetShownSafe(frame.Inset, showBorder)

    if frame.Bg and frame.Bg.Hide then frame.Bg:Hide() end
    if frame.Inset and frame.Inset.Bg and frame.Inset.Bg.Hide then frame.Inset.Bg:Hide() end

    frame.__comfyMinimalBackground:SetShown(backgroundAlpha > 0)
    frame.__comfyMinimalBackground:SetAlpha(backgroundAlpha)
end

function CC:ResetOptionsWindowPosition()
    if not self.optionsFrame or not self.db then return end
    local defaults = self._profileDefaults and self._profileDefaults.optionsWindow or nil
    local point = defaults and defaults.point or "CENTER"
    local relativePoint = defaults and defaults.relativePoint or point
    local x = defaults and defaults.x or 0
    local y = defaults and defaults.y or 0

    self.db.optionsWindow = self.db.optionsWindow or {}
    self.db.optionsWindow.point = point
    self.db.optionsWindow.relativePoint = relativePoint
    self.db.optionsWindow.x = x
    self.db.optionsWindow.y = y

    self.optionsFrame:ClearAllPoints()
    self.optionsFrame:SetPoint(point, UIParent, relativePoint, x, y)
end

function CC:GetSharedSettingsTabLabel()
    return L("Einstellungen", "Settings")
end

local function DropdownSetText(dropdown, value)
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, value or "") end
end

function CC:BuildSharedSettingsPage(page)
    if not page or page.__comfyBuilt then return end
    page.__comfyBuilt = true
    self.sharedSettingsPage = page
    self.sharedSettingsControls = {}

    local function AddText(text, x, y, font, width)
        local fs = page:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
        fs:SetPoint("TOPLEFT", x, y)
        if width then fs:SetWidth(width) fs:SetJustifyH("LEFT") end
        fs:SetText(text)
        return fs
    end

    local function AddButton(text, x, y, width, fn)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(width or 130, 24)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end

    local function AddCheck(text, x, y, getter, setter)
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, y)
        local label = cb.Text or cb.text
        if not label then
            label = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetPoint("LEFT", cb, "RIGHT", 3, 1)
            cb.Text = label
        end
        label:SetText(text)
        cb._getter = getter
        cb:SetScript("OnClick", function(self)
            setter(self:GetChecked() and true or false)
            CC:ApplySharedWindowSettings()
            CC:RefreshSharedSettingsPage()
        end)
        self.sharedSettingsControls[#self.sharedSettingsControls + 1] = cb
        return cb
    end

    local function AddSlider(label, minValue, maxValue, step, x, y, getter, setter)
        self._sharedSliderIndex = (self._sharedSliderIndex or 0) + 1
        local safeName = tostring(self.name or "ComfyPanel"):gsub("[^%w]", "")
        local name = safeName .. "SharedSlider" .. tostring(self._sharedSliderIndex)
        local slider = CreateFrame("Slider", name, page, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", x, y)
        slider:SetWidth(250)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        if _G[name .. "Low"] then _G[name .. "Low"]:SetText(tostring(minValue)) end
        if _G[name .. "High"] then _G[name .. "High"]:SetText(tostring(maxValue)) end
        if _G[name .. "Text"] then _G[name .. "Text"]:SetText(label) end

        slider.valueText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        slider.valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)
        slider._getter = getter
        slider:SetScript("OnValueChanged", function(self, value)
            if self._refreshing then return end
            value = math.floor(value + 0.5)
            setter(value)
            self.valueText:SetText(string.format("%d%%", value))
            CC:ApplySharedWindowSettings()
        end)
        self.sharedSettingsControls[#self.sharedSettingsControls + 1] = slider
        return slider
    end

    local function AddDropdown(x, y, width, itemsFn, currentFn, selectFn)
        local dd = CreateFrame("Frame", nil, page, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", x, y)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width or 220) end
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
                    CC:RefreshSharedSettingsPage()
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
            DropdownSetText(dd, label)
        end
        return dd
    end

    AddText(self:GetSharedSettingsTabLabel(), 20, -10, "GameFontNormalLarge")

    AddText(L("Profile", "Profiles"), 20, -48, "GameFontNormal")
    AddText(L("Aktives Profil", "Active profile"), 20, -78, "GameFontHighlightSmall")
    self.sharedActiveProfileDropdown = AddDropdown(5, -90, 250,
        function() return CC:GetSelectableStorageProfiles() end,
        function() return CC:GetActiveStorageProfileKey() end,
        function(value) CC:SetActiveStorageProfile(value) end)

    AddText(L("Profil kopieren von", "Copy profile from"), 340, -78, "GameFontHighlightSmall")
    self.sharedCopySourceKey = self:GetCharacterProfileKey()
    self.sharedCopyDropdown = AddDropdown(325, -90, 220,
        function() return CC:GetCopySourceStorageProfiles() end,
        function() return CC.sharedCopySourceKey end,
        function(value) CC.sharedCopySourceKey = value end)
    AddButton(L("Laden / Kopieren", "Load / copy"), 590, -88, 120, function()
        CC:CopyStorageProfileToCharacter(CC.sharedCopySourceKey)
    end)

    AddText(L("Eigenes Profil", "Custom profile"), 20, -145, "GameFontHighlightSmall")
    self.sharedProfileNameEdit = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    self.sharedProfileNameEdit:SetPoint("TOPLEFT", 20, -164)
    self.sharedProfileNameEdit:SetSize(220, 28)
    self.sharedProfileNameEdit:SetAutoFocus(false)
    self.sharedProfileNameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    AddButton(L("Erstellen", "Create"), 250, -162, 120, function()
        local name = CC.sharedProfileNameEdit:GetText()
        if CC:CreateStorageProfile(name) then
            CC.sharedProfileNameEdit:SetText("")
        end
    end)
    AddButton(L("Eigenes löschen", "Delete custom"), 380, -162, 140, function()
        CC:DeleteActiveStorageProfile()
    end)
    AddButton(L("Profil zurücksetzen", "Reset profile"), 530, -162, 150, function()
        CC:ResetActiveStorageProfile()
    end)

    AddText(
        L("Jeder Charakter erhält automatisch ein eigenes Profil. Andere Charaktere können als Vorlage kopiert werden; ComfyProfiles ist dafür nicht erforderlich.",
          "Every character automatically gets its own profile. Other characters can be copied as a template; ComfyProfiles is not required."),
        20, -205, "GameFontHighlightSmall", 690)

    AddText(L("Fenster", "Window"), 20, -255, "GameFontNormal")
    AddCheck(L("Fensterposition sperren", "Lock window position"), 20, -282,
        function() CC:EnsureSharedUISettings() return CC.db.ui.windowLocked end,
        function(v) CC.db.ui.windowLocked = v end)
    AddCheck(L("Blizzard-Rahmen anzeigen", "Show Blizzard border"), 20, -315,
        function() CC:EnsureSharedUISettings() return CC.db.ui.showWindowBorder end,
        function(v) CC.db.ui.showWindowBorder = v end)

    AddSlider(L("Fenster-Deckkraft", "Window opacity"), 10, 100, 1, 35, -370,
        function() CC:EnsureSharedUISettings() return CC.db.ui.windowOpacity or 100 end,
        function(v) CC.db.ui.windowOpacity = v end)

    AddSlider(L("Hintergrund-Deckkraft", "Background opacity"), 0, 100, 1, 35, -440,
        function() CC:EnsureSharedUISettings() return CC.db.ui.backgroundAlpha or 92 end,
        function(v) CC.db.ui.backgroundAlpha = v end)

    AddButton(L("Fensterposition zurücksetzen", "Reset window position"), 20, -505, 210, function()
        CC:ResetOptionsWindowPosition()
    end)

    if self.db and self.db.minimap then
        AddText(L("Minimap", "Minimap"), 420, -255, "GameFontNormal")
        AddCheck(L("Minimap-Icon anzeigen", "Show minimap icon"), 420, -282,
            function() return CC.db.minimap.show end,
            function(v)
                CC.db.minimap.show = v
                if CC.UpdateMinimapPosition then CC:UpdateMinimapPosition() end
            end)
        AddCheck(L("Minimap-Icon sperren", "Lock minimap icon"), 420, -315,
            function() return CC.db.minimap.locked end,
            function(v) CC.db.minimap.locked = v end)

        if type(self.SetMinimapBundling) == "function" then
            AddCheck(L("Comfy-Suite-Icons bündeln", "Bundle Comfy Suite icons"), 420, -348,
                function() return CC.db.minimap.bundleSuiteIcons ~= false end,
                function(v) CC:SetMinimapBundling(v) end)
        end
    end

    self:RefreshSharedSettingsPage()
end

function CC:RefreshSharedSettingsPage()
    if not self.sharedSettingsPage then return end
    self:EnsureSharedUISettings()

    for _, control in ipairs(self.sharedSettingsControls or {}) do
        if control._getter then
            local value = control._getter()
            if control:GetObjectType() == "CheckButton" then
                control:SetChecked(value and true or false)
            elseif control:GetObjectType() == "Slider" then
                control._refreshing = true
                control:SetValue(tonumber(value) or 0)
                control._refreshing = false
                if control.valueText then
                    control.valueText:SetText(string.format("%d%%", math.floor((tonumber(value) or 0) + 0.5)))
                end
            end
        end
    end

    if self.sharedActiveProfileDropdown and self.sharedActiveProfileDropdown._refresh then self.sharedActiveProfileDropdown._refresh() end
    if self.sharedCopyDropdown and self.sharedCopyDropdown._refresh then self.sharedCopyDropdown._refresh() end
end
