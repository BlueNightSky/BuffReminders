local _, BR = ...

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================
-- Simplified 3-tab layout: Buffs, Display/Behavior, Settings

-- Lua stdlib locals
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local tinsert, tsort, tremove = table.insert, table.sort, table.remove

-- WoW API locals
local PlaySoundFile = PlaySoundFile

-- Aliases from BR namespace
local Components = BR.Components
local CreateButton = BR.CreateButton
local CreatePanel = BR.CreatePanel
local CreateSectionHeader = BR.CreateSectionHeader

-- Shared constants
local TEXCOORD_INSET = BR.TEXCOORD_INSET
local OPTIONS_BASE_SCALE = BR.OPTIONS_BASE_SCALE

-- Buff tables
local BUFF_TABLES = BR.BUFF_TABLES
local BuffGroups = BR.BuffGroups

-- Local aliases for buff arrays
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local PetBuffs = BUFF_TABLES.pet
local Consumables = BUFF_TABLES.consumable

-- Localization
local L = BR.L

-- Export references from BuffReminders.lua
local defaults = BR.defaults
local LSM = BR.LSM

-- Helper function aliases
local GetCategorySettings = BR.Helpers.GetCategorySettings
local IsCategorySplit = BR.Helpers.IsCategorySplit
local IsIconDetached = BR.Helpers.IsIconDetached
local DetachIcon = BR.Helpers.DetachIcon
local ReattachIcon = BR.Helpers.ReattachIcon
local GetBuffTexture = BR.Helpers.GetBuffTexture
local SetBuffSound = BR.Helpers.SetBuffSound

-- Display function aliases
local UpdateDisplay = BR.Display.Update
local ToggleTestMode = BR.Display.ToggleTestMode
local UpdateVisuals = BR.Display.UpdateVisuals
local ResetCategoryFramePosition = BR.Display.ResetCategoryFramePosition
local ReparentBuffFrames = BR.CallbackRegistry.TriggerEvent
        and function()
            BR.CallbackRegistry:TriggerEvent("FramesReparent")
        end
    or function() end

-- Masque state
local IsMasqueActive = BR.Masque and BR.Masque.IsActive or function()
    return false
end

-- Module-level variables
local optionsPanel = nil

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 540
local COL_PADDING = 20
local SECTION_SPACING = 12
local ITEM_HEIGHT = 22
local SCROLLBAR_WIDTH = 24

-- Vertical layout spacing constants
local COMPONENT_GAP = 4 -- Standard gap between components
local SECTION_GAP = 8 -- Gap before/after section boundaries
local DROPDOWN_EXTRA = 8 -- Extra clearance after dropdowns (menu overlay space)

local CATEGORY_ORDER = { "raid", "presence", "targeted", "self", "pet", "consumable", "custom" }
local CATEGORY_LABELS = {
    raid = L["Category.RaidBuffs"],
    presence = L["Category.PresenceBuffs"],
    targeted = L["Category.TargetedBuffs"],
    self = L["Category.SelfBuffs"],
    pet = L["Category.PetReminders"],
    consumable = L["Category.Consumables"],
    custom = L["Category.CustomBuffs"],
}

-- Layout-aware section header (uses VerticalLayout instead of manual Y tracking)
local function LayoutSectionHeader(layout, parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffffcc00" .. text .. "|r")
    layout:AddText(header, 14, COMPONENT_GAP)
    return header
end

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================

local function CreateOptionsPanel()
    local panel = CreatePanel("BuffRemindersOptions", PANEL_WIDTH, 640, { escClose = true })
    panel:Hide()

    -- Forward declarations for banner system
    local UpdateBannerLayout
    local masqueBanner

    -- Track all EditBoxes so we can clear focus when panel hides
    local panelEditBoxes = {}
    Components.SetEditBoxesRef(panelEditBoxes)
    panel:SetScript("OnHide", function()
        for _, editBox in ipairs(panelEditBoxes) do
            editBox:ClearFocus()
        end
    end)

    -- Refresh all component values from DB when panel opens (OnShow pattern)
    panel:SetScript("OnShow", function()
        Components.RefreshAll()
        UpdateBannerLayout()
    end)

    -- Title (inline with tab row)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", COL_PADDING, -10)
    title:SetText("|cffffffffBuff|r|cffffcc00Reminders|r")

    -- Version (next to title, smaller font)
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, 0)
    local addonVersion = C_AddOns.GetAddOnMetadata("BuffReminders", "Version") or ""
    version:SetText(addonVersion)

    -- Discord link (next to version)
    local discordSep = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    discordSep:SetPoint("LEFT", version, "RIGHT", 6, 0)
    discordSep:SetText("|cff555555·|r")

    local discordLink = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    discordLink:SetPoint("LEFT", discordSep, "RIGHT", 6, 0)
    discordLink:SetText("|cff7289da" .. L["Options.JoinDiscord"] .. "|r")

    local discordHit = CreateFrame("Button", nil, panel)
    discordHit:SetAllPoints(discordLink)
    discordHit:SetScript("OnClick", function()
        StaticPopup_Show("BUFFREMINDERS_DISCORD_URL")
    end)
    discordHit:SetScript("OnEnter", function()
        discordLink:SetText("|cff99aaff" .. L["Options.JoinDiscord"] .. "|r")
        BR.ShowTooltip(discordHit, L["Options.JoinDiscord.Title"], L["Options.JoinDiscord.Desc"], "ANCHOR_BOTTOM")
    end)
    discordHit:SetScript("OnLeave", function()
        discordLink:SetText("|cff7289da" .. L["Options.JoinDiscord"] .. "|r")
        BR.HideTooltip()
    end)

    -- Scale controls (top right area) - text link style: < 100% >
    local BASE_SCALE = OPTIONS_BASE_SCALE
    local MIN_PCT, MAX_PCT = 80, 150

    local currentScale = BR.profile.optionsPanelScale or BASE_SCALE
    local currentPct = floor(currentScale / BASE_SCALE * 100 + 0.5)

    -- Close button
    local closeBtn = CreateButton(panel, "x", function()
        panel:Hide()
    end)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local scaleHolder = CreateFrame("Frame", nil, panel)
    scaleHolder:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    scaleHolder:SetSize(60, 16)

    local scaleDown = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleDown:SetPoint("LEFT", 0, 0)
    scaleDown:SetText("<")

    local scaleValue = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", scaleDown, "RIGHT", 4, 0)
    scaleValue:SetText(currentPct .. "%")

    local scaleUp = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText(">")

    local function UpdateScaleText()
        local pct = floor((BR.profile.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        scaleValue:SetText(pct .. "%")
        scaleDown:SetTextColor(pct > MIN_PCT and 1 or 0.4, pct > MIN_PCT and 1 or 0.4, pct > MIN_PCT and 1 or 0.4)
        scaleUp:SetTextColor(pct < MAX_PCT and 1 or 0.4, pct < MAX_PCT and 1 or 0.4, pct < MAX_PCT and 1 or 0.4)
    end

    local function UpdateScale(delta)
        local oldPct = floor((BR.profile.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        local newPct = max(MIN_PCT, min(MAX_PCT, oldPct + delta))
        local newScale = newPct / 100 * BASE_SCALE
        BR.profile.optionsPanelScale = newScale
        panel:SetScale(newScale)
        UpdateScaleText()
    end

    -- Clickable regions for < and >
    local downBtn = CreateFrame("Button", nil, scaleHolder)
    downBtn:SetAllPoints(scaleDown)
    downBtn:SetScript("OnClick", function()
        UpdateScale(-10)
    end)
    downBtn:SetScript("OnEnter", function()
        if currentPct > MIN_PCT then
            scaleDown:SetTextColor(1, 0.82, 0)
        end
    end)
    downBtn:SetScript("OnLeave", function()
        UpdateScaleText()
    end)

    local upBtn = CreateFrame("Button", nil, scaleHolder)
    upBtn:SetAllPoints(scaleUp)
    upBtn:SetScript("OnClick", function()
        UpdateScale(10)
    end)
    upBtn:SetScript("OnEnter", function()
        local pct = floor((BR.profile.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        if pct < MAX_PCT then
            scaleUp:SetTextColor(1, 0.82, 0)
        end
    end)
    upBtn:SetScript("OnLeave", function()
        UpdateScaleText()
    end)

    UpdateScaleText()

    if BR.profile.optionsPanelScale then
        panel:SetScale(BR.profile.optionsPanelScale)
    end

    -- ========== TABS ==========
    local tabButtons = {}
    local contentContainers = {}
    local TAB_HEIGHT = 22
    local activeTabName = "buffs"

    local function SetActiveTab(tabName)
        activeTabName = tabName
        for name, tab in pairs(tabButtons) do
            tab:SetActive(name == tabName)
        end
        for name, container in pairs(contentContainers) do
            if name == tabName then
                container:Show()
            else
                container:Hide()
            end
        end
        if masqueBanner then
            masqueBanner:Refresh()
            UpdateBannerLayout()
        end
    end

    -- Create 5 tabs: Buffs, Display & Behavior, Sounds, Settings, Profiles
    tabButtons.buffs = Components.Tab(panel, { name = "buffs", label = L["Tab.Buffs"], width = 50 })
    tabButtons.displayBehavior =
        Components.Tab(panel, { name = "displayBehavior", label = L["Tab.DisplayBehavior"], width = 110 })
    tabButtons.sounds = Components.Tab(panel, { name = "sounds", label = L["Tab.Sounds"], width = 60 })
    tabButtons.settings = Components.Tab(panel, { name = "settings", label = L["Tab.Settings"], width = 65 })
    tabButtons.profiles = Components.Tab(panel, { name = "profiles", label = L["Tab.Profiles"], width = 65 })

    -- Position tabs below title
    tabButtons.buffs:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, -30)
    tabButtons.displayBehavior:SetPoint("LEFT", tabButtons.buffs, "RIGHT", 2, 0)
    tabButtons.sounds:SetPoint("LEFT", tabButtons.displayBehavior, "RIGHT", 2, 0)
    tabButtons.settings:SetPoint("LEFT", tabButtons.sounds, "RIGHT", 2, 0)
    tabButtons.profiles:SetPoint("LEFT", tabButtons.settings, "RIGHT", 2, 0)

    for name, tab in pairs(tabButtons) do
        tab:SetScript("OnClick", function()
            SetActiveTab(name)
        end)
    end

    -- Separator line below tabs
    local tabSeparator = panel:CreateTexture(nil, "ARTWORK")
    tabSeparator:SetHeight(1)
    tabSeparator:SetPoint("TOPLEFT", COL_PADDING, -30 - TAB_HEIGHT)
    tabSeparator:SetPoint("TOPRIGHT", -COL_PADDING, -30 - TAB_HEIGHT)
    tabSeparator:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- ========== CONTENT CONTAINERS ==========
    local CONTENT_TOP = -30 - TAB_HEIGHT - 10

    -- Helper to create a scrollable content container using Components
    local function CreateScrollableContent(name)
        local scrollFrame, content = Components.ScrollableContainer(panel, {
            contentHeight = 600,
            scrollbarWidth = SCROLLBAR_WIDTH,
        })
        scrollFrame:SetPoint("TOPLEFT", 0, CONTENT_TOP)
        scrollFrame:SetPoint("BOTTOMRIGHT", 0, 46)
        scrollFrame:Hide()

        contentContainers[name] = scrollFrame
        return content, scrollFrame
    end

    -- ========== BANNERS ==========
    local BANNER_HEIGHT = 28
    local BANNER_TOP_GAP = 6
    local BANNER_BOTTOM_GAP = 0

    masqueBanner = Components.Banner(panel, {
        text = L["Options.MasqueNote"],
        icon = "QuestNormal",
        color = "orange",
        visible = function()
            return IsMasqueActive() and activeTabName == "displayBehavior"
        end,
    })

    UpdateBannerLayout = function()
        local bannerY = -30 - TAB_HEIGHT - BANNER_TOP_GAP
        local bannerOffset = 0

        if masqueBanner:IsShown() then
            masqueBanner:ClearAllPoints()
            masqueBanner:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, bannerY)
            masqueBanner:SetPoint("RIGHT", panel, "RIGHT", -COL_PADDING, 0)
            bannerOffset = bannerOffset + BANNER_HEIGHT + BANNER_BOTTOM_GAP
        end

        local newTop = CONTENT_TOP - bannerOffset
        for _, container in pairs(contentContainers) do
            container:ClearAllPoints()
            container:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, newTop)
            if container.GetContentFrame then
                container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 46)
            end
        end
    end

    -- Store buff checkboxes for refresh
    panel.buffCheckboxes = {}

    -- ========== HELPER FUNCTIONS ==========

    -- Resolve icon textures from displayIcon texture IDs or spell IDs
    local function ResolveBuffIcons(displayIcon, spellIDs)
        if displayIcon then
            -- Use override textures directly
            if type(displayIcon) == "table" then
                return displayIcon
            else
                return { displayIcon }
            end
        elseif spellIDs then
            -- Look up textures from spell IDs (deduplicated)
            local icons = {}
            local seenTextures = {}
            local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
            for _, spellID in ipairs(spellList) do
                local texture = GetBuffTexture(spellID)
                if texture and not seenTextures[texture] then
                    seenTextures[texture] = true
                    tinsert(icons, texture)
                end
            end
            return #icons > 0 and icons or nil
        end
        return nil
    end

    -- Buff-specific settings: key → { tooltip, note, onClick }
    -- Gear icon shown in a fixed column (right of detach pin) for consistent alignment
    local buffSettingsActions = {
        healthstone = {
            tooltip = L["Options.HealthstoneSettings"],
            note = L["Options.HealthstoneSettings.Note"],
            onClick = function()
                BR.Options.Modals.Healthstone.Show()
            end,
        },
        soulstone = {
            tooltip = L["Options.SoulstoneSettings"],
            note = L["Options.SoulstoneSettings.Note"],
            onClick = function()
                BR.Options.Modals.Soulstone.Show()
            end,
        },
        dkRunes = {
            tooltip = L["Options.RuneforgePreferences"],
            note = L["Options.RuneforgeNote"],
            onClick = function()
                BR.Options.Modals.Runeforge.Show()
            end,
        },
        roguePoisons = {
            tooltip = L["Options.RoguePoisonPreferences"],
            note = L["Options.RoguePoisonNote"],
            onClick = function()
                BR.Options.Modals.RoguePoison.Show()
            end,
        },
        petPassive = {
            tooltip = L["Options.PetPassiveSettings"],
            note = L["Options.PetPassiveSettings.Note"],
            onClick = function()
                BR.Options.Modals.PetPassive.Show()
            end,
        },
        pets = {
            tooltip = L["Options.PetSummonSettings"],
            note = L["Options.PetSummonSettings.Note"],
            onClick = function()
                BR.Options.Modals.PetSummon.Show()
            end,
        },
        delveFood = {
            tooltip = L["Options.DelveFoodSettings"],
            note = L["Options.DelveFoodSettings.Note"],
            onClick = function()
                BR.Options.Modals.DelveFood.Show()
            end,
        },
        bronze = {
            tooltip = L["Options.BronzeSettings"],
            note = L["Options.BronzeSettings.Note"],
            onClick = function()
                BR.Options.Modals.Bronze.Show()
            end,
        },
    }

    -- Create buff checkbox using Components.Checkbox
    local function CreateBuffCheckbox(
        parent,
        x,
        y,
        spellIDs,
        key,
        displayName,
        infoTooltip,
        displayIcon,
        readyCheckOnly,
        freeConsumable
    )
        local holder = Components.Checkbox(parent, {
            label = displayName,
            icons = ResolveBuffIcons(displayIcon, spellIDs),
            infoTooltip = not readyCheckOnly and infoTooltip or nil,
            get = function()
                return BR.profile.enabledBuffs[key] ~= false
            end,
            onChange = function(checked)
                BR.profile.enabledBuffs[key] = checked
                UpdateDisplay()
                if readyCheckOnly then
                    Components.RefreshAll()
                end
            end,
        })
        holder:SetPoint("TOPLEFT", x, y)
        panel.buffCheckboxes[key] = holder

        -- Inline toggle: "Ready check only" / "Always show" (replaces info tooltip icon)
        -- Skip for free consumables (controlled by dropdown) and soulstone (controlled by gear icon modal)
        if readyCheckOnly and not freeConsumable and key ~= "soulstone" then
            local function GetReadyCheckOnlyState()
                local overrides = BR.profile.readyCheckOnlyOverrides
                return not overrides or overrides[key] ~= false
            end

            local function ToggleLabel(checked)
                return checked and L["Options.ReadyCheck"] or L["Options.Always"]
            end

            local toggle
            toggle = Components.Toggle(holder, {
                label = ToggleLabel(GetReadyCheckOnlyState()),
                get = GetReadyCheckOnlyState,
                enabled = function()
                    return BR.profile.enabledBuffs[key] ~= false
                end,
                onChange = function(checked)
                    if checked then
                        -- Ready check only (default): remove override
                        BR.Config.Set("readyCheckOnlyOverrides." .. key, nil)
                    else
                        -- Always show: store explicit false
                        BR.Config.Set("readyCheckOnlyOverrides." .. key, false)
                    end
                    toggle.label:SetText(ToggleLabel(checked))
                end,
            })
            -- Also update label text on Refresh (wrap original Refresh)
            local origRefresh = toggle.Refresh
            function toggle:Refresh()
                origRefresh(self)
                self.label:SetText(ToggleLabel(GetReadyCheckOnlyState()))
            end
            toggle:SetPoint("LEFT", holder.label, "RIGHT", 6, 0)
        end

        -- Settings gear icon (fixed column, first icon right of checkbox)
        local settings = buffSettingsActions[key]
        if settings then
            local gearBtn = CreateFrame("Button", nil, holder)
            gearBtn:SetSize(14, 14)
            gearBtn:SetPoint("LEFT", holder, "RIGHT", 4, 0)
            gearBtn:SetFrameLevel(holder:GetFrameLevel() + 5)
            local gearTex = gearBtn:CreateTexture(nil, "ARTWORK")
            gearTex:SetAllPoints()
            gearTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
            gearTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            gearBtn:SetScript("OnEnter", function(self)
                gearTex:SetVertexColor(1, 1, 1, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(settings.tooltip, 1, 1, 1)
                GameTooltip:AddLine(settings.note, 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            gearBtn:SetScript("OnLeave", function()
                gearTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
                GameTooltip:Hide()
            end)
            gearBtn:SetScript("OnClick", settings.onClick)
        end

        -- Detach button: small pin icon to toggle detached positioning
        -- Fixed offset from holder right edge (leaves gap for gear icon slot)
        local detachBtn = CreateFrame("Button", nil, holder)
        detachBtn:SetSize(14, 14)
        detachBtn:SetPoint("LEFT", holder, "RIGHT", 22, 0)

        local detachIcon = detachBtn:CreateTexture(nil, "ARTWORK")
        detachIcon:SetAllPoints()
        detachIcon:SetAtlas("Waypoint-MapPin-ChatIcon")

        local function UpdateDetachVisual()
            if IsIconDetached(key) then
                detachIcon:SetVertexColor(1, 0.85, 0.3, 1) -- Gold when detached
                detachIcon:SetDesaturated(false)
            else
                detachIcon:SetVertexColor(0.5, 0.5, 0.5, 0.6) -- Dim when attached
                detachIcon:SetDesaturated(true)
            end
        end
        UpdateDetachVisual()

        detachBtn:SetScript("OnClick", function()
            if IsIconDetached(key) then
                ReattachIcon(key)
            else
                DetachIcon(key)
            end
            UpdateDetachVisual()
            UpdateDisplay()
        end)
        detachBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Options.DetachIcon"], 1, 1, 1)
            GameTooltip:AddLine(L["Options.DetachIcon.Desc"], 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        detachBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return y - ITEM_HEIGHT
    end

    -- ========== BUFFS TAB (Two-Column Layout) ==========
    local buffsContent, _ = CreateScrollableContent("buffs")

    -- Render checkboxes for a buff array (single column within each side)
    local function RenderBuffCheckboxes(parent, x, y, buffArray)
        local groupSpells = {}
        local groupDisplaySpells = {}
        local groupIconOverrides = {}
        local groupReadyCheckOnly = {}
        local groupFreeConsumable = {}

        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                groupSpells[buff.groupId] = groupSpells[buff.groupId] or {}
                groupDisplaySpells[buff.groupId] = groupDisplaySpells[buff.groupId] or {}
                if buff.spellID then
                    local spellList = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
                    for _, id in ipairs(spellList) do
                        tinsert(groupSpells[buff.groupId], id)
                    end
                end
                if buff.displaySpells then
                    local displayList = type(buff.displaySpells) == "table" and buff.displaySpells
                        or { buff.displaySpells }
                    for _, id in ipairs(displayList) do
                        tinsert(groupDisplaySpells[buff.groupId], id)
                    end
                end
                -- Resolve display icon(s) per entry: displayIcon > displaySpells > primary spellID
                -- Deduplicate icons within the same group (e.g., MH + OH weapon buffs share icons)
                if not groupIconOverrides[buff.groupId] then
                    groupIconOverrides[buff.groupId] = {}
                    groupIconOverrides[buff.groupId]._seen = {}
                end
                local seen = groupIconOverrides[buff.groupId]._seen
                if buff.displayIcon then
                    local overrides = type(buff.displayIcon) == "table" and buff.displayIcon or { buff.displayIcon }
                    for _, icon in ipairs(overrides) do
                        if not seen[icon] then
                            seen[icon] = true
                            tinsert(groupIconOverrides[buff.groupId], icon)
                        end
                    end
                elseif buff.displaySpells then
                    local displayList = type(buff.displaySpells) == "table" and buff.displaySpells
                        or { buff.displaySpells }
                    for _, id in ipairs(displayList) do
                        local texture = GetBuffTexture(id)
                        if texture and not seen[texture] then
                            seen[texture] = true
                            tinsert(groupIconOverrides[buff.groupId], texture)
                        end
                    end
                elseif buff.spellID then
                    local primarySpell = type(buff.spellID) == "table" and buff.spellID[1] or buff.spellID
                    if primarySpell and primarySpell > 0 then
                        local texture = GetBuffTexture(primarySpell)
                        if texture and not seen[texture] then
                            seen[texture] = true
                            tinsert(groupIconOverrides[buff.groupId], texture)
                        end
                    end
                end
                if buff.readyCheckOnly then
                    groupReadyCheckOnly[buff.groupId] = true
                end
                if buff.freeConsumable then
                    groupFreeConsumable[buff.groupId] = true
                end
            end
        end

        local seenGroups = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                if not seenGroups[buff.groupId] then
                    seenGroups[buff.groupId] = true
                    local groupInfo = BuffGroups[buff.groupId]
                    local displayIcon = groupIconOverrides[buff.groupId]
                    if displayIcon and #displayIcon == 0 then
                        displayIcon = nil
                    end
                    local displaySpells = groupDisplaySpells[buff.groupId]
                    local spells = (#displaySpells > 0) and displaySpells or groupSpells[buff.groupId]
                    if #spells == 0 then
                        spells = nil
                    end
                    y = CreateBuffCheckbox(
                        parent,
                        x,
                        y,
                        spells,
                        buff.groupId,
                        groupInfo and groupInfo.displayName or buff.name,
                        buff.infoTooltip,
                        displayIcon,
                        groupReadyCheckOnly[buff.groupId],
                        groupFreeConsumable[buff.groupId]
                    )
                end
            else
                local displaySpells = buff.displaySpells or buff.spellID
                y = CreateBuffCheckbox(
                    parent,
                    x,
                    y,
                    displaySpells,
                    buff.key,
                    buff.name,
                    buff.infoTooltip,
                    buff.displayIcon,
                    buff.readyCheckOnly,
                    buff.freeConsumable
                )
            end
        end

        return y
    end

    -- Column layout constants
    local COL_WIDTH = (PANEL_WIDTH - COL_PADDING * 3) / 2
    local buffsLeftX = COL_PADDING
    local buffsRightX = COL_PADDING + COL_WIDTH + COL_PADDING
    local buffsLeftY = -6
    local buffsRightY = -6

    -- Detach column headers (text label above pin buttons)
    local function CreateDetachColumnHeader(parent, x, y)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(L["Options.DetachIcon"])
    end

    CreateDetachColumnHeader(buffsContent, buffsLeftX + 211, -8)
    CreateDetachColumnHeader(buffsContent, buffsRightX + 211, -8)

    -- LEFT COLUMN: Group-wide buffs
    -- Raid Buffs
    _, buffsLeftY = CreateSectionHeader(buffsContent, L["Category.RaidBuffs"], buffsLeftX, buffsLeftY)
    local raidNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    raidNote:SetText(L["Category.RaidNote"])
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, RaidBuffs)
    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Targeted Buffs
    _, buffsLeftY = CreateSectionHeader(buffsContent, L["Category.TargetedBuffs"], buffsLeftX, buffsLeftY)
    local targetedNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetedNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    targetedNote:SetText(L["Category.TargetedNote"])
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, TargetedBuffs)
    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Consumables
    _, buffsLeftY = CreateSectionHeader(buffsContent, L["Category.Consumables"], buffsLeftX, buffsLeftY)
    local consumablesNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    consumablesNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    consumablesNote:SetText(L["Category.ConsumableNote"])
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, Consumables)

    -- RIGHT COLUMN: Individual buffs
    -- Presence Buffs
    _, buffsRightY = CreateSectionHeader(buffsContent, L["Category.PresenceBuffs"], buffsRightX, buffsRightY)
    local presenceNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    presenceNote:SetText(L["Category.PresenceNote"])
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, PresenceBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Self Buffs
    _, buffsRightY = CreateSectionHeader(buffsContent, L["Category.SelfBuffs"], buffsRightX, buffsRightY)
    local selfNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    selfNote:SetText(L["Category.SelfNote"])
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, SelfBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Pet Reminders
    _, buffsRightY = CreateSectionHeader(buffsContent, L["Category.PetReminders"], buffsRightX, buffsRightY)
    local petNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    petNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    petNote:SetText(L["Category.PetNote"])
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, PetBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Custom Buffs (right column)
    _, buffsRightY = CreateSectionHeader(buffsContent, L["Category.CustomBuffs"], buffsRightX, buffsRightY)
    panel.customBuffRows = {}

    local customNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    customNote:SetText(L["Category.CustomNote"])
    buffsRightY = buffsRightY - 14

    local customSectionStartY = buffsRightY
    local customBuffsContainer = CreateFrame("Frame", nil, buffsContent)
    customBuffsContainer:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    customBuffsContainer:SetSize(COL_WIDTH, 200)

    local ADD_BTN_GAP = 4
    local ADD_BTN_HEIGHT = 22
    local CUSTOM_CONTAINER_PAD = ADD_BTN_GAP + ADD_BTN_HEIGHT + 2

    local function RenderCustomBuffRows()
        for _, row in ipairs(panel.customBuffRows) do
            row:Hide()
            row:SetParent(nil)
        end
        panel.customBuffRows = {}

        local db = BR.profile
        local rowY = 0

        local sortedKeys = {}
        if db.customBuffs then
            for key in pairs(db.customBuffs) do
                tinsert(sortedKeys, key)
            end
        end
        tsort(sortedKeys)

        for _, key in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[key]

            -- Use Components.Checkbox for consistent styling
            local holder = Components.Checkbox(customBuffsContainer, {
                label = customBuff.name or (L["CustomBuff.Action.Spell"] .. " " .. tostring(customBuff.spellID)),
                icons = ResolveBuffIcons(nil, customBuff.spellID),
                get = function()
                    return BR.profile.enabledBuffs[key] ~= false
                end,
                onChange = function(checked)
                    BR.profile.enabledBuffs[key] = checked
                    UpdateDisplay()
                end,
                onRightClick = function()
                    BR.Options.Modals.CustomBuff.Show(key, RenderCustomBuffRows)
                end,
                tooltip = { title = L["CustomBuff.Tooltip.Title"], desc = L["CustomBuff.Tooltip.Desc"] },
            })
            holder:SetPoint("TOPLEFT", 0, rowY)
            panel.buffCheckboxes[key] = holder

            -- Detach button for custom buffs
            local detachBtn = CreateFrame("Button", nil, holder)
            detachBtn:SetSize(14, 14)
            detachBtn:SetPoint("LEFT", holder, "RIGHT", 4, 0)
            local detachTex = detachBtn:CreateTexture(nil, "ARTWORK")
            detachTex:SetAllPoints()
            detachTex:SetAtlas("Waypoint-MapPin-ChatIcon")
            local function UpdateDetachVis()
                if IsIconDetached(key) then
                    detachTex:SetVertexColor(1, 0.85, 0.3, 1)
                    detachTex:SetDesaturated(false)
                else
                    detachTex:SetVertexColor(0.5, 0.5, 0.5, 0.6)
                    detachTex:SetDesaturated(true)
                end
            end
            UpdateDetachVis()
            detachBtn:SetScript("OnClick", function()
                if IsIconDetached(key) then
                    ReattachIcon(key)
                else
                    DetachIcon(key)
                end
                UpdateDetachVis()
                UpdateDisplay()
            end)
            detachBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Options.DetachIcon"], 1, 1, 1)
                GameTooltip:AddLine(L["Options.DetachIcon.Desc"], 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            detachBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            tinsert(panel.customBuffRows, holder)
            rowY = rowY - ITEM_HEIGHT
        end

        local addBtn = CreateButton(customBuffsContainer, L["CustomBuff.AddButton"], function()
            BR.Options.Modals.CustomBuff.Show(nil, RenderCustomBuffRows)
        end)
        addBtn:SetPoint("TOPLEFT", 0, rowY - ADD_BTN_GAP)
        tinsert(panel.customBuffRows, addBtn)

        customBuffsContainer:SetHeight(abs(rowY) + CUSTOM_CONTAINER_PAD)

        -- Recalculate content height when custom buffs change
        local effectiveRightY = customSectionStartY + rowY - CUSTOM_CONTAINER_PAD
        buffsContent:SetHeight(max(abs(buffsLeftY), abs(effectiveRightY)) + 4)

        return rowY
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    RenderCustomBuffRows()

    -- ========== DISPLAY/BEHAVIOR TAB ==========
    local displayBehaviorContent, _ = CreateScrollableContent("displayBehavior")
    local displayBehaviorX = COL_PADDING
    local displayBehaviorLayout = Components.VerticalLayout(displayBehaviorContent, { x = displayBehaviorX, y = -10 })

    -- Global Defaults section
    LayoutSectionHeader(displayBehaviorLayout, displayBehaviorContent, L["Options.GlobalDefaults"])

    local defNote = displayBehaviorContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    displayBehaviorLayout:AddText(defNote, 12, COMPONENT_GAP)
    defNote:SetText(L["Options.GlobalDefaults.Note"])

    local function isDefDimensionsLinked()
        local db = BR.profile.defaults
        return not db or db.iconWidth == nil
    end

    local defGrid = Components.AppearanceGrid(displayBehaviorContent, {
        get = function(key, default)
            local d = BR.profile.defaults
            return d and d[key] or default
        end,
        set = function(key, value)
            BR.Config.Set("defaults." .. key, value)
        end,
        setMulti = function(changes)
            local prefixed = {}
            for k, v in pairs(changes) do
                prefixed["defaults." .. k] = v
            end
            BR.Config.SetMulti(prefixed)
        end,
        isLinked = isDefDimensionsLinked,
        onLink = function()
            BR.Config.Set("defaults.iconWidth", nil)
            Components.RefreshAll()
        end,
        onUnlink = function()
            local db = BR.profile.defaults
            BR.Config.Set("defaults.iconWidth", db and db.iconSize or 64)
            Components.RefreshAll()
        end,
        masqueCheck = IsMasqueActive,
    })
    displayBehaviorLayout:Add(defGrid.frame, defGrid.height, COMPONENT_GAP)

    -- Font dropdown (global setting, uses LibSharedMedia)
    local function BuildFontOptions()
        local fontList = LSM:List("font")
        local opts = { { label = L["Options.Default"], value = nil } }
        for _, name in ipairs(fontList) do
            tinsert(opts, { label = name, value = name })
        end
        return opts
    end

    local defFontHolder = Components.Dropdown(displayBehaviorContent, {
        label = L["Options.Font"],
        labelWidth = 50,
        options = BuildFontOptions(),
        width = 200,
        maxItems = 15,
        itemInit = function(_, itemLabel, opt)
            if opt.value then
                local path = LSM:Fetch("font", opt.value)
                if path then
                    itemLabel:SetFont(path, 12, "")
                end
            end
        end,
        get = function()
            return BR.profile.defaults and BR.profile.defaults.fontFace or nil
        end,
        onChange = function(val)
            BR.Config.Set("defaults.fontFace", val)
        end,
    })
    displayBehaviorLayout:Add(defFontHolder, nil, COMPONENT_GAP)

    local defOutlineHolder = Components.Dropdown(displayBehaviorContent, {
        label = L["Options.TextOutline"],
        labelWidth = 50,
        options = {
            { label = L["Options.TextOutline.None"], value = "NONE" },
            { label = L["Options.TextOutline.Outline"], value = "OUTLINE" },
            { label = L["Options.TextOutline.Thick"], value = "THICKOUTLINE" },
            { label = L["Options.TextOutline.Monochrome"], value = "MONOCHROME" },
            { label = L["Options.TextOutline.OutlineMono"], value = "OUTLINE, MONOCHROME" },
            { label = L["Options.TextOutline.ThickMono"], value = "THICKOUTLINE, MONOCHROME" },
        },
        width = 200,
        get = function()
            return (BR.profile.defaults and BR.profile.defaults.textOutline) or "OUTLINE"
        end,
        onChange = function(val)
            BR.Config.Set("defaults.textOutline", val)
        end,
    })
    displayBehaviorLayout:Add(defOutlineHolder, nil, COMPONENT_GAP)

    local defDirHolder = Components.DirectionButtons(displayBehaviorContent, {
        labelWidth = 50,
        get = function()
            return BR.profile.defaults and BR.profile.defaults.growDirection or "CENTER"
        end,
        onChange = function(dir)
            BR.Config.Set("defaults.growDirection", dir)
        end,
    })
    displayBehaviorLayout:Add(defDirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

    local defGlowHolder = Components.Checkbox(displayBehaviorContent, {
        label = L["Options.GlowReminderIcons"],
        tooltip = {
            title = L["Options.GlowReminderIcons.Title"],
            desc = L["Options.GlowReminderIcons.Desc"],
        },
        get = function()
            local d = BR.profile.defaults
            return d and (d.showExpirationGlow ~= false or d.showMissingGlow ~= false)
        end,
        onChange = function(checked)
            BR.Config.Set("defaults.showExpirationGlow", checked)
            BR.Config.Set("defaults.showMissingGlow", checked)
            Components.RefreshAll()
        end,
    })

    local glowSettingsBtn = CreateButton(displayBehaviorContent, L["Options.Customize"], function()
        BR.Options.Modals.Glow.Show()
    end)
    glowSettingsBtn:SetPoint("LEFT", defGlowHolder.label, "RIGHT", 8, 0)
    glowSettingsBtn:SetFrameLevel(defGlowHolder:GetFrameLevel() + 5)

    displayBehaviorLayout:Add(defGlowHolder, nil, COMPONENT_GAP)

    -- Expiration Reminder section
    displayBehaviorLayout:Space(8)
    LayoutSectionHeader(displayBehaviorLayout, displayBehaviorContent, L["Options.ExpirationReminder"])
    displayBehaviorLayout:Space(COMPONENT_GAP)

    local defThresholdHolder = Components.Slider(displayBehaviorContent, {
        label = L["Options.Threshold"],
        min = 0,
        max = 45,
        step = 5,
        get = function()
            return BR.profile.defaults and BR.profile.defaults.expirationThreshold or 15
        end,
        formatValue = function(val)
            return val == 0 and L["Options.Off"] or (val .. " " .. L["Options.Min"])
        end,
        onChange = function(val)
            BR.Config.Set("defaults.expirationThreshold", val)
        end,
    })
    displayBehaviorLayout:Add(defThresholdHolder, nil, COMPONENT_GAP)

    local preKeyThresholdHolder = Components.Slider(displayBehaviorContent, {
        label = L["Options.PreKeyThreshold"],
        tooltip = { title = L["Options.PreKeyThreshold"], desc = L["Options.PreKeyThreshold.Desc"] },
        min = 0,
        max = 60,
        step = 5,
        get = function()
            return BR.profile.defaults and BR.profile.defaults.preKeyThreshold or 0
        end,
        formatValue = function(val)
            return val == 0 and L["Options.Off"] or (val .. " " .. L["Options.Min"])
        end,
        onChange = function(val)
            BR.Config.Set("defaults.preKeyThreshold", val)
        end,
    })
    displayBehaviorLayout:Add(preKeyThresholdHolder, nil, COMPONENT_GAP)

    -- Per-Category Customization section
    displayBehaviorLayout:Space(8)
    LayoutSectionHeader(displayBehaviorLayout, displayBehaviorContent, L["Options.PerCategoryCustomization"])
    displayBehaviorLayout:Space(COMPONENT_GAP)

    -- Create collapsible sections that chain-anchor to each other
    local categorySections = {}
    local previousSection = nil

    local function UpdateAppearanceContentHeight()
        -- Calculate total height: fixed header area + all collapsible sections
        local totalHeight = abs(displayBehaviorLayout:GetY())
        for _, sec in ipairs(categorySections) do
            totalHeight = totalHeight + sec:GetHeight() + 4
        end
        displayBehaviorContent:SetHeight(totalHeight)
    end

    local SECTION_SCROLLBAR_OFFSET = COL_PADDING
    for _, category in ipairs(CATEGORY_ORDER) do
        local section = Components.CollapsibleSection(displayBehaviorContent, {
            title = CATEGORY_LABELS[category],
            defaultCollapsed = true,
            scrollbarOffset = SECTION_SCROLLBAR_OFFSET,
            onToggle = function()
                -- Defer layout update to next frame
                C_Timer.After(0, UpdateAppearanceContentHeight)
            end,
        })

        if previousSection then
            section:SetPoint("TOPLEFT", previousSection, "BOTTOMLEFT", 0, -4)
        else
            section:SetPoint("TOPLEFT", displayBehaviorX, displayBehaviorLayout:GetY())
        end

        local catContent = section:GetContentFrame()
        local catLayout = Components.VerticalLayout(catContent, { x = 0, y = 0 })

        local db = BR.profile

        -- W/S/D/R content visibility + ready check (not for custom — custom uses per-buff loadConditions)
        if category ~= "custom" then
            local function OnCategoryVisibilityChange()
                UpdateDisplay()
            end

            local visToggles = Components.VisibilityToggles(catContent, {
                category = category,
                onChange = function()
                    OnCategoryVisibilityChange()
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(visToggles, nil, SECTION_GAP)

            local hideInPvPMatchHolder = Components.Checkbox(catContent, {
                label = L["Options.HidePvPMatchStart"],
                get = function()
                    local vis = db.categoryVisibility and db.categoryVisibility[category]
                    return vis and vis.hideInPvPMatch or false
                end,
                enabled = function()
                    local vis = db.categoryVisibility and db.categoryVisibility[category]
                    return not vis or vis.pvp ~= false
                end,
                tooltip = {
                    title = L["Options.HidePvPMatchStart.Title"],
                    desc = L["Options.HidePvPMatchStart.Desc"],
                },
                onChange = function(checked)
                    if not db.categoryVisibility then
                        db.categoryVisibility = {}
                    end
                    if not db.categoryVisibility[category] then
                        db.categoryVisibility[category] = {
                            openWorld = true,
                            scenario = true,
                            dungeon = true,
                            raid = true,
                            housing = false,
                            pvp = true,
                            hideInPvPMatch = true,
                        }
                    end
                    db.categoryVisibility[category].hideInPvPMatch = checked
                    OnCategoryVisibilityChange()
                end,
            })
            catLayout:Add(hideInPvPMatchHolder, nil, COMPONENT_GAP)

            local readyCheckHolder = Components.Checkbox(catContent, {
                label = L["Options.ReadyCheckOnly"],
                get = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return cs and cs.showOnlyOnReadyCheck == true
                end,
                tooltip = {
                    title = L["Options.ReadyCheckOnly"],
                    desc = L["Options.ReadyCheckOnly.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showOnlyOnReadyCheck", checked)
                end,
            })
            catLayout:Add(readyCheckHolder, nil, COMPONENT_GAP)

            -- Free consumables sub-section (consumable category only)
            if category == "consumable" then
                local function EnsureFreeVisibility()
                    if not db.defaults then
                        db.defaults = {}
                    end
                    if not db.defaults.freeConsumableVisibility then
                        db.defaults.freeConsumableVisibility = {
                            openWorld = false,
                            scenario = true,
                            dungeon = true,
                            raid = true,
                            housing = false,
                            pvp = true,
                        }
                    end
                    return db.defaults.freeConsumableVisibility
                end
                catLayout:Space(SECTION_GAP)
                local freeHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                freeHeader:SetText("|cffffcc00" .. L["Options.FreeConsumables"] .. "|r")
                catLayout:AddText(freeHeader, 12, COMPONENT_GAP)
                local freeNote = catContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                freeNote:SetText(L["Options.FreeConsumables.Note"])
                catLayout:AddText(freeNote, 10, COMPONENT_GAP)

                local function IsFreeOverride()
                    return BR.Config.Get("defaults.freeConsumableMode", "override") == "override"
                end

                local freeOverrideHolder = Components.Checkbox(catContent, {
                    label = L["Options.FreeConsumables.Override"],
                    get = function()
                        return IsFreeOverride()
                    end,
                    tooltip = {
                        title = L["Options.FreeConsumables.Override"],
                        desc = L["Options.FreeConsumables.Override.Desc"],
                    },
                    onChange = function(checked)
                        BR.Config.Set("defaults.freeConsumableMode", checked and "override" or "follow")
                        Components.RefreshAll()
                    end,
                })
                catLayout:Add(freeOverrideHolder, nil, COMPONENT_GAP)

                -- Override controls (indented under checkbox)
                local INDENT = 12
                catLayout:SetX(catLayout:GetX() + INDENT)

                local freeVisToggles = Components.VisibilityToggles(catContent, {
                    store = {
                        getContent = function(key)
                            local vis = db.defaults and db.defaults.freeConsumableVisibility
                            return not vis or vis[key] ~= false
                        end,
                        setContent = function(key)
                            local vis = EnsureFreeVisibility()
                            vis[key] = not vis[key]
                        end,
                        getDiffTable = function(dbKey)
                            local vis = db.defaults and db.defaults.freeConsumableVisibility
                            return vis and vis[dbKey]
                        end,
                        ensureDiffTable = function(dbKey)
                            local vis = EnsureFreeVisibility()
                            if not vis[dbKey] then
                                vis[dbKey] = {} ---@diagnostic disable-line: assign-type-mismatch
                            end
                            return vis[dbKey]
                        end,
                    },
                    noAutoRefresh = true,
                    onChange = function()
                        UpdateDisplay()
                    end,
                })
                local origVisRefresh = freeVisToggles.Refresh
                function freeVisToggles:Refresh()
                    origVisRefresh(self)
                    local enabled = IsFreeOverride()
                    self:SetAlpha(enabled and 1 or 0.4)
                    for _, btn in ipairs(self.allToggleButtons) do
                        btn:EnableMouse(enabled)
                    end
                end
                tinsert(BR.RefreshableComponents, freeVisToggles)
                catLayout:Add(freeVisToggles, nil, COMPONENT_GAP)

                catLayout:SetX(catLayout:GetX() - INDENT)
                catLayout:Space(SECTION_GAP)
            end
        else
            local banner = Components.Banner(catContent, {
                text = L["CustomBuff.SettingsMovedNote"],
                color = "orange",
                icon = "services-icon-warning",
            })
            catLayout:Add(banner, nil, SECTION_GAP)
            banner:SetPoint("RIGHT", catContent, "RIGHT", 0, 0)
        end

        -- Icons sub-header (all categories except custom)
        if category ~= "custom" then
            local iconsHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            iconsHeader:SetText("|cffffcc00" .. L["Options.Icons"] .. "|r")
            catLayout:AddText(iconsHeader, 12, COMPONENT_GAP)
        end

        -- Show text on icons (not for custom — custom buffs have per-buff missing text)
        if category ~= "custom" then
            local showTextHolder = Components.Checkbox(catContent, {
                label = L["Options.ShowText"],
                get = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return not cs or cs.showText ~= false
                end,
                tooltip = {
                    title = L["Options.ShowText"],
                    desc = L["Options.ShowText.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showText", checked)
                end,
            })
            catLayout:Add(showTextHolder, nil, COMPONENT_GAP)
        end

        -- Missing count only (raid only)
        if category == "raid" then
            local missingCountHolder = Components.Checkbox(catContent, {
                label = L["Options.ShowMissingCountOnly"],
                get = function()
                    return db.showMissingCountOnly == true
                end,
                tooltip = {
                    title = L["Options.ShowMissingCountOnly"],
                    desc = L["Options.ShowMissingCountOnly.Desc"],
                },
                enabled = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return not cs or cs.showText ~= false
                end,
                onChange = function(checked)
                    BR.Config.Set("showMissingCountOnly", checked)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(missingCountHolder, nil, COMPONENT_GAP)
        end

        -- "BUFF!" text (raid only, grouped under Icons)
        if category == "raid" then
            local reminderHolder = Components.Checkbox(catContent, {
                label = L["Options.ShowBuffReminderText"],
                get = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return not cs or cs.showBuffReminder ~= false
                end,
                onChange = function(checked)
                    BR.Config.Set("categorySettings.raid.showBuffReminder", checked)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(reminderHolder, nil, COMPONENT_GAP)

            local buffTextSizeHolder = Components.NumericStepper(reminderHolder, {
                label = L["Options.Size"],
                labelWidth = 28,
                min = 6,
                max = 40,
                get = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    if cs and cs.buffTextSize then
                        return cs.buffTextSize
                    end
                    local textSize = (cs and cs.textSize) or defaults.defaults.textSize
                    return max(6, floor(textSize * 0.8))
                end,
                enabled = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return not cs or cs.showBuffReminder ~= false
                end,
                onChange = function(val)
                    BR.Config.Set("categorySettings.raid.buffTextSize", val)
                end,
            })
            buffTextSizeHolder:SetPoint("LEFT", reminderHolder, "LEFT", 210, 0)

            local buffTextOffsetXHolder = Components.Slider(catContent, {
                label = L["Options.BuffTextOffsetX"],
                labelWidth = 60,
                min = -40,
                max = 40,
                get = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return (cs and cs.buffTextOffsetX) or 0
                end,
                enabled = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return not cs or cs.showBuffReminder ~= false
                end,
                onChange = function(val)
                    BR.Config.Set("categorySettings.raid.buffTextOffsetX", val)
                end,
            })

            local buffTextOffsetYHolder = Components.Slider(catContent, {
                label = L["Options.BuffTextOffsetY"],
                labelWidth = 60,
                min = -40,
                max = 40,
                get = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return (cs and cs.buffTextOffsetY) or 0
                end,
                enabled = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return not cs or cs.showBuffReminder ~= false
                end,
                onChange = function(val)
                    BR.Config.Set("categorySettings.raid.buffTextOffsetY", val)
                end,
            })

            buffTextOffsetYHolder:SetPoint("LEFT", buffTextOffsetXHolder, "LEFT", 210, 0)
            catLayout:Add(buffTextOffsetXHolder, nil, COMPONENT_GAP)
        end

        -- Click to cast checkbox
        if category ~= "custom" then
            local clickableHolder = Components.Checkbox(catContent, {
                label = L["Options.ClickToCast"],
                get = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return cs and cs.clickable == true
                end,
                tooltip = {
                    title = L["Options.ClickToCast"],
                    desc = L["Options.ClickToCast.DescFull"],
                },
                onChange = function(checked)
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings[category] then
                        db.categorySettings[category] = {}
                    end
                    db.categorySettings[category].clickable = checked
                    BR.Display.UpdateActionButtons(category)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(clickableHolder, nil, 2)

            catLayout:SetX(20)
            local highlightHolder = Components.Checkbox(catContent, {
                label = L["Options.HoverHighlight"],
                get = function()
                    local hcs = db.categorySettings and db.categorySettings[category]
                    return hcs and hcs.clickableHighlight ~= false
                end,
                enabled = function()
                    local hcs = db.categorySettings and db.categorySettings[category]
                    return hcs and hcs.clickable == true
                end,
                tooltip = {
                    title = L["Options.HoverHighlight"],
                    desc = L["Options.HoverHighlight.Desc"],
                },
                onChange = function(checked)
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings[category] then
                        db.categorySettings[category] = {}
                    end
                    db.categorySettings[category].clickableHighlight = checked
                    BR.Display.UpdateActionButtons(category)
                end,
            })
            catLayout:Add(highlightHolder, nil, COMPONENT_GAP)

            if category == "pet" then
                local specIconHolder = Components.Checkbox(catContent, {
                    label = L["Options.PetSpecIcon"],
                    get = function()
                        return BR.Config.Get("defaults.petSpecIconOnHover", true)
                    end,
                    enabled = function()
                        local hcs = db.categorySettings and db.categorySettings[category]
                        return hcs and hcs.clickable == true
                    end,
                    tooltip = {
                        title = L["Options.PetSpecIcon.Title"],
                        desc = L["Options.PetSpecIcon.Desc"],
                    },
                    onChange = function(checked)
                        BR.Config.Set("defaults.petSpecIconOnHover", checked)
                    end,
                })
                catLayout:Add(specIconHolder, nil, COMPONENT_GAP)
            end

            if category == "consumable" then
                local showTooltipsHolder = Components.Checkbox(catContent, {
                    label = L["Options.ShowItemTooltips"],
                    get = function()
                        return BR.Config.Get("defaults.showConsumableTooltips", false) ~= false
                    end,
                    enabled = function()
                        local hcs = db.categorySettings and db.categorySettings[category]
                        return hcs and hcs.clickable == true
                    end,
                    tooltip = {
                        title = L["Options.ShowItemTooltips"],
                        desc = L["Options.ShowItemTooltips.Desc"],
                    },
                    onChange = function(checked)
                        BR.Config.Set("defaults.showConsumableTooltips", checked)
                    end,
                })
                catLayout:Add(showTooltipsHolder, nil, COMPONENT_GAP)
            end

            catLayout:SetX(0)
        end

        -- Pet display settings (pet only)
        if category == "pet" then
            catLayout:Space(SECTION_GAP)

            local updatePetDisplayModePreview -- forward declaration for preview update
            local petDisplayModeHolder = Components.Dropdown(catContent, {
                label = L["Options.PetDisplay"],
                width = 120,
                get = function()
                    return BR.Config.Get("defaults.petDisplayMode", "generic")
                end,
                options = {
                    {
                        value = "generic",
                        label = L["Options.PetDisplay.Generic"],
                        desc = L["Options.PetDisplay.GenericDesc"],
                    },
                    {
                        value = "expanded",
                        label = L["Options.PetDisplay.Summon"],
                        desc = L["Options.PetDisplay.SummonDesc"],
                    },
                },
                tooltip = {
                    title = L["Options.PetDisplay.Mode"],
                    desc = L["Options.PetDisplay.Mode.Desc"],
                },
                onChange = function(val)
                    BR.Config.Set("defaults.petDisplayMode", val)
                    if updatePetDisplayModePreview then
                        updatePetDisplayModePreview(val)
                    end
                end,
            })
            catLayout:Add(petDisplayModeHolder, nil, COMPONENT_GAP)

            -- Pet display mode preview (anchored to the right of the dropdown)
            local PP_ICON = 24
            local PP_BORDER = 2
            local PP_GAP = 3
            local PP_STEP = PP_ICON + PP_GAP + PP_BORDER * 2

            local TEX_PET_GENERIC = 136082 -- Summon Demon flyout icon
            local TEX_PETS = { 136218, 136221, 136217 } -- Imp, Voidwalker, Felhunter

            local petPreviewHeight = PP_ICON + PP_BORDER * 2
            local PET_MODE_ICON_COUNT = { generic = 1, expanded = 3 }

            local petPreviewHolder = CreateFrame("Frame", nil, catContent)
            petPreviewHolder:SetSize(PP_STEP, petPreviewHeight)
            petPreviewHolder:SetPoint("TOPLEFT", petDisplayModeHolder, "TOPRIGHT", 12, 0)

            local petPreviewContainer = CreateFrame("Frame", nil, petPreviewHolder)
            petPreviewContainer:SetPoint("TOPLEFT", 0, 0)
            petPreviewContainer:SetSize(3 * PP_STEP, petPreviewHeight)
            petPreviewContainer:SetAlpha(0.7)

            local function CreatePetPreviewIcon(parent, texture, size)
                local f = CreateFrame("Frame", nil, parent)
                f:SetSize(size, size)
                f.icon = f:CreateTexture(nil, "ARTWORK")
                f.icon:SetAllPoints()
                f.icon:SetTexture(texture)
                local z = TEXCOORD_INSET
                f.icon:SetTexCoord(z, 1 - z, z, 1 - z)
                f.border = f:CreateTexture(nil, "BACKGROUND")
                f.border:SetColorTexture(0, 0, 0, 1)
                f.border:SetPoint("TOPLEFT", -PP_BORDER, PP_BORDER)
                f.border:SetPoint("BOTTOMRIGHT", PP_BORDER, -PP_BORDER)
                return f
            end

            local allPetPreviewFrames = {}

            -- Generic: single icon
            local genericFrame = CreatePetPreviewIcon(petPreviewContainer, TEX_PET_GENERIC, PP_ICON)
            genericFrame:SetPoint("TOPLEFT", petPreviewContainer, "TOPLEFT", 0, 0)
            genericFrame:Hide()
            allPetPreviewFrames[#allPetPreviewFrames + 1] = genericFrame

            -- Expanded: individual summon spell icons
            local expandedPetFrames = {}
            for i = 1, 3 do
                local f = CreatePetPreviewIcon(petPreviewContainer, TEX_PETS[i], PP_ICON)
                f:SetPoint("TOPLEFT", petPreviewContainer, "TOPLEFT", (i - 1) * PP_STEP, 0)
                f:Hide()
                expandedPetFrames[i] = f
                allPetPreviewFrames[#allPetPreviewFrames + 1] = f
            end

            local PET_MODE_FRAMES = {
                generic = { genericFrame },
                expanded = expandedPetFrames,
            }
            updatePetDisplayModePreview = function(mode)
                for _, f in ipairs(allPetPreviewFrames) do
                    f:Hide()
                end
                local shown = PET_MODE_FRAMES[mode]
                if shown then
                    for _, f in ipairs(shown) do
                        f:Show()
                    end
                end
                petPreviewHolder:SetWidth((PET_MODE_ICON_COUNT[mode] or 1) * PP_STEP)
            end

            -- Initial state
            updatePetDisplayModePreview(BR.Config.Get("defaults.petDisplayMode", "generic"))

            -- Register for refresh so reopening the panel re-reads the value
            function petPreviewHolder:Refresh()
                updatePetDisplayModePreview(BR.Config.Get("defaults.petDisplayMode", "generic"))
            end
            tinsert(BR.RefreshableComponents, petPreviewHolder)

            local petLabelsHolder = Components.Checkbox(catContent, {
                label = L["Options.PetLabels"],
                get = function()
                    return BR.Config.Get("defaults.petLabels", true)
                end,
                tooltip = {
                    title = L["Options.PetLabels"],
                    desc = L["Options.PetLabels.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("defaults.petLabels", checked)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(petLabelsHolder, nil, COMPONENT_GAP)

            local petLabelScaleHolder = Components.NumericStepper(petLabelsHolder, {
                label = L["Options.PetLabels.SizePct"],
                labelWidth = 36,
                min = 50,
                max = 200,
                step = 10,
                get = function()
                    return BR.Config.Get("defaults.petLabelScale", 100)
                end,
                enabled = function()
                    return BR.Config.Get("defaults.petLabels", true)
                end,
                onChange = function(val)
                    BR.Config.Set("defaults.petLabelScale", val)
                end,
            })
            petLabelScaleHolder:SetPoint("LEFT", petLabelsHolder, "LEFT", 90, 0)

            -- Pet class label toggles (H/W/D/M) — anchored to the right of the scale stepper
            local function classColor(cls)
                local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                if c then
                    return { c.r, c.g, c.b }
                end
                return { 0.5, 0.5, 0.5 }
            end

            local petClassBar, petClassButtons = Components.CreateSegmentedBar(petLabelsHolder, {
                toggleDefs = {
                    {
                        key = "HUNTER",
                        label = "H",
                        tooltip = { title = L["Class.Hunter"] },
                        color = classColor("HUNTER"),
                    },
                    {
                        key = "WARLOCK",
                        label = "W",
                        tooltip = { title = L["Class.Warlock"] },
                        color = classColor("WARLOCK"),
                    },
                    {
                        key = "DEATHKNIGHT",
                        label = "D",
                        tooltip = { title = L["Class.DeathKnight"] },
                        color = classColor("DEATHKNIGHT"),
                    },
                    { key = "MAGE", label = "M", tooltip = { title = L["Class.Mage"] }, color = classColor("MAGE") },
                },
                getState = function(key)
                    local vis = BR.profile.defaults.petLabelClasses
                    return not vis or vis[key] ~= false
                end,
                setState = function(key)
                    if not BR.profile.defaults.petLabelClasses then
                        BR.profile.defaults.petLabelClasses = {
                            HUNTER = true,
                            WARLOCK = true,
                            DEATHKNIGHT = true,
                            MAGE = true,
                        }
                    end
                    BR.profile.defaults.petLabelClasses[key] = not BR.profile.defaults.petLabelClasses[key]
                end,
                onChange = function()
                    UpdateDisplay()
                end,
            })
            petClassBar:SetPoint("LEFT", petLabelScaleHolder, "RIGHT", 8, 0)

            local function isPetLabelsEnabled()
                return BR.Config.Get("defaults.petLabels", true)
            end
            petClassBar:SetBarDisabled(not isPetLabelsEnabled())

            local petClassBarRefreshHolder = CreateFrame("Frame", nil, petLabelsHolder)
            petClassBarRefreshHolder:SetSize(1, 1)
            function petClassBarRefreshHolder:Refresh()
                petClassBar:SetBarDisabled(not isPetLabelsEnabled())
                for _, btn in ipairs(petClassButtons) do
                    btn.UpdateVisual()
                end
            end
            tinsert(BR.RefreshableComponents, petClassBarRefreshHolder)
        end

        -- Item display mode (consumable only, grouped with icon options)
        if category == "consumable" then
            -- Consumable text scale (count + quality labels as % of icon size)
            local consumableTextScaleHolder = Components.Slider(catContent, {
                label = L["Options.ConsumableTextScale"],
                min = 5,
                max = 80,
                step = 1,
                suffix = "%",
                get = function()
                    return BR.Config.Get("defaults.consumableTextScale", 25)
                end,
                tooltip = {
                    title = L["Options.ConsumableTextScale.Title"],
                    desc = L["Options.ConsumableTextScale.Desc"],
                },
                onChange = function(val)
                    BR.Config.Set("defaults.consumableTextScale", val)
                end,
            })
            catLayout:Add(consumableTextScaleHolder, nil, COMPONENT_GAP)

            local updateDisplayModePreview -- forward declaration for preview update
            local updateSubIconSideVisibility -- forward declaration for sub-icon side visibility
            local displayModeHolder = Components.Dropdown(catContent, {
                label = L["Options.ItemDisplay"],
                get = function()
                    return BR.Config.Get("defaults.consumableDisplayMode", "sub_icons")
                end,
                options = {
                    {
                        value = "icon_only",
                        label = L["Options.ItemDisplay.IconOnly"],
                        desc = L["Options.ItemDisplay.IconOnlyDesc"],
                    },
                    {
                        value = "sub_icons",
                        label = L["Options.ItemDisplay.SubIcons"],
                        desc = L["Options.ItemDisplay.SubIconsDesc"],
                    },
                    {
                        value = "expanded",
                        label = L["Options.ItemDisplay.Expanded"],
                        desc = L["Options.ItemDisplay.ExpandedDesc"],
                    },
                },
                tooltip = {
                    title = L["Options.ItemDisplay.Mode"],
                    desc = L["Options.ItemDisplay.Mode.Desc"],
                },
                onChange = function(val)
                    BR.Config.Set("defaults.consumableDisplayMode", val)
                    if updateDisplayModePreview then
                        updateDisplayModePreview(val)
                    end
                    if updateSubIconSideVisibility then
                        updateSubIconSideVisibility(val)
                    end
                end,
            })
            catLayout:Add(displayModeHolder, nil, COMPONENT_GAP)

            -- Display mode preview (anchored to the right of the dropdown)
            local P_ICON = 24
            local P_SUB = 12
            local P_BORDER = 2
            local P_GAP = 3
            local P_STEP = P_ICON + P_GAP + P_BORDER * 2
            local P_SUB_STEP = P_SUB + P_BORDER * 2 -- sub-icons touch borders
            -- Distinct textures for flask/food/oil and their variants (Midnight icons)
            local TEX_FLASK = { 7548898, 7548899, 7548900 } -- Haranir flasks: blue, green, orange
            local TEX_FOOD = { 4672193, 1045939 } -- Royal Roast, Twilight Angler's Medley
            local TEX_OIL = 7548987 -- Thalassian Phoenix Oil

            local previewHeight = P_ICON + P_SUB + P_GAP + P_BORDER * 2
            local MODE_ICON_COUNT = { icon_only = 3, sub_icons = 3, expanded = 6 }

            local previewHolder = CreateFrame("Frame", nil, catContent)
            previewHolder:SetSize(3 * P_STEP, previewHeight)
            previewHolder:SetPoint("TOPLEFT", displayModeHolder, "TOPRIGHT", 12, 0)

            local previewContainer = CreateFrame("Frame", nil, previewHolder)
            previewContainer:SetPoint("TOPLEFT", 0, 0)
            previewContainer:SetSize(6 * P_STEP, previewHeight)
            previewContainer:SetAlpha(0.7)

            local function CreatePreviewIcon(parent, texture, size)
                local f = CreateFrame("Frame", nil, parent)
                f:SetSize(size, size)
                f.icon = f:CreateTexture(nil, "ARTWORK")
                f.icon:SetAllPoints()
                f.icon:SetTexture(texture)
                local z = TEXCOORD_INSET
                f.icon:SetTexCoord(z, 1 - z, z, 1 - z)
                f.border = f:CreateTexture(nil, "BACKGROUND")
                f.border:SetColorTexture(0, 0, 0, 1)
                f.border:SetPoint("TOPLEFT", -P_BORDER, P_BORDER)
                f.border:SetPoint("BOTTOMRIGHT", P_BORDER, -P_BORDER)
                return f
            end

            local allPreviewFrames = {}

            -- Icon-only: [Flask] [Food] [Oil]
            local iconOnlyFrames = {}
            local iconOnlyTextures = { TEX_FLASK[1], TEX_FOOD[1], TEX_OIL }
            for i = 1, 3 do
                local f = CreatePreviewIcon(previewContainer, iconOnlyTextures[i], P_ICON)
                f:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                f:Hide()
                iconOnlyFrames[i] = f
                allPreviewFrames[#allPreviewFrames + 1] = f
            end

            -- Sub-icons: [Flask] [Food] [Oil] with variant sub-icons below
            local subIconsFrames = { mains = {}, subs = {} }
            local subVariants = { TEX_FLASK, TEX_FOOD, {} } -- oil has no variants
            for i, variants in ipairs(subVariants) do
                local mainTex = (#variants > 0) and variants[1] or TEX_OIL
                local main = CreatePreviewIcon(previewContainer, mainTex, P_ICON)
                main:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                main:Hide()
                subIconsFrames.mains[i] = main
                allPreviewFrames[#allPreviewFrames + 1] = main
                if #variants > 1 then
                    local subCount = #variants - 1
                    local subRowWidth = (subCount - 1) * P_SUB_STEP + P_SUB
                    local subOffsetX = (P_ICON - subRowWidth) / 2
                    for j = 2, #variants do
                        local sub = CreatePreviewIcon(previewContainer, variants[j], P_SUB)
                        sub:SetPoint("TOPLEFT", main, "BOTTOMLEFT", subOffsetX + (j - 2) * P_SUB_STEP, -P_GAP)
                        sub:Hide()
                        subIconsFrames.subs[#subIconsFrames.subs + 1] = sub
                        allPreviewFrames[#allPreviewFrames + 1] = sub
                    end
                end
            end

            -- Expanded: [F1][F2][F3][Fd1][Fd2][Oil] — each variant at full size
            local expandedFrames = {}
            local expandedTextures = {
                TEX_FLASK[1],
                TEX_FLASK[2],
                TEX_FLASK[3],
                TEX_FOOD[1],
                TEX_FOOD[2],
                TEX_OIL,
            }
            for i = 1, 6 do
                local f = CreatePreviewIcon(previewContainer, expandedTextures[i], P_ICON)
                f:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                f:Hide()
                expandedFrames[i] = f
                allPreviewFrames[#allPreviewFrames + 1] = f
            end

            -- Combine sub-icons mains + subs into one flat list
            local subIconsAll = {}
            for _, f in ipairs(subIconsFrames.mains) do
                subIconsAll[#subIconsAll + 1] = f
            end
            for _, f in ipairs(subIconsFrames.subs) do
                subIconsAll[#subIconsAll + 1] = f
            end

            local MODE_FRAMES = {
                icon_only = iconOnlyFrames,
                sub_icons = subIconsAll,
                expanded = expandedFrames,
            }
            updateDisplayModePreview = function(mode)
                for _, f in ipairs(allPreviewFrames) do
                    f:Hide()
                end
                local shown = MODE_FRAMES[mode]
                if shown then
                    for _, f in ipairs(shown) do
                        f:Show()
                    end
                end
                previewHolder:SetWidth((MODE_ICON_COUNT[mode] or 3) * P_STEP)
            end

            -- Initial state
            updateDisplayModePreview(BR.Config.Get("defaults.consumableDisplayMode", "sub_icons"))

            -- Register for refresh so reopening the panel re-reads the value
            function previewHolder:Refresh()
                updateDisplayModePreview(BR.Config.Get("defaults.consumableDisplayMode", "sub_icons"))
            end
            tinsert(BR.RefreshableComponents, previewHolder)

            -- Sub-icon placement side (anchored below preview, visible only in sub_icons mode)
            local subIconSideHolder = Components.Dropdown(catContent, {
                label = L["Options.SubIconSide"],
                labelWidth = 30,
                width = 85,
                get = function()
                    local catSettings = db.categorySettings and db.categorySettings[category]
                    return catSettings and catSettings.subIconSide or "BOTTOM"
                end,
                options = {
                    { value = "BOTTOM", label = L["Options.SubIconSide.Bottom"] },
                    { value = "TOP", label = L["Options.SubIconSide.Top"] },
                    { value = "LEFT", label = L["Options.SubIconSide.Left"] },
                    { value = "RIGHT", label = L["Options.SubIconSide.Right"] },
                },
                onChange = function(val)
                    BR.Config.Set("categorySettings." .. category .. ".subIconSide", val)
                end,
            })
            subIconSideHolder:SetPoint("TOPLEFT", previewHolder, "TOPRIGHT", 12, 0)

            updateSubIconSideVisibility = function(mode)
                subIconSideHolder:SetShown(mode == "sub_icons")
            end
            updateSubIconSideVisibility(BR.Config.Get("defaults.consumableDisplayMode", "sub_icons"))

            -- Sub-header for behavior options
            catLayout:Space(SECTION_GAP)
            local behaviorHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            behaviorHeader:SetText("|cffffcc00" .. L["Options.Behavior"] .. "|r")
            catLayout:AddText(behaviorHeader, 12, COMPONENT_GAP)

            local showWithoutItemsHolder = Components.Checkbox(catContent, {
                label = L["Options.ShowWithoutItems"],
                get = function()
                    return BR.Config.Get("defaults.showConsumablesWithoutItems", false) == true
                end,
                tooltip = {
                    title = L["Options.ShowWithoutItems.Title"],
                    desc = L["Options.ShowWithoutItems.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("defaults.showConsumablesWithoutItems", checked)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(showWithoutItemsHolder, nil, COMPONENT_GAP)

            local SHOW_WITHOUT_INDENT = 12
            catLayout:SetX(catLayout:GetX() + SHOW_WITHOUT_INDENT)
            local readyCheckOnlyHolder = Components.Checkbox(catContent, {
                label = L["Options.ShowWithoutItemsReadyCheckOnly"],
                get = function()
                    return BR.Config.Get("defaults.showWithoutItemsOnlyOnReadyCheck", false) == true
                end,
                enabled = function()
                    return BR.Config.Get("defaults.showConsumablesWithoutItems", false) == true
                end,
                tooltip = {
                    title = L["Options.ShowWithoutItemsReadyCheckOnly.Title"],
                    desc = L["Options.ShowWithoutItemsReadyCheckOnly.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("defaults.showWithoutItemsOnlyOnReadyCheck", checked)
                end,
            })
            catLayout:Add(readyCheckOnlyHolder, nil, COMPONENT_GAP)
            catLayout:SetX(catLayout:GetX() - SHOW_WITHOUT_INDENT)

            local delveFoodOnlyHolder = Components.Checkbox(catContent, {
                label = L["Options.DelveFoodOnly"],
                get = function()
                    return BR.Config.Get("defaults.delveFoodOnly", false) == true
                end,
                tooltip = {
                    title = L["Options.DelveFoodOnly"],
                    desc = L["Options.DelveFoodOnly.Desc"],
                },
                onChange = function(checked)
                    BR.Config.Set("defaults.delveFoodOnly", checked)
                end,
            })
            catLayout:Add(delveFoodOnlyHolder, nil, COMPONENT_GAP)
        end

        -- Layout sub-header
        catLayout:Space(SECTION_GAP)
        local layoutHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        layoutHeader:SetText("|cffffcc00" .. L["Options.Layout"] .. "|r")
        catLayout:AddText(layoutHeader, 12, COMPONENT_GAP)

        -- Priority slider (only relevant when not split)
        local priorityHolder = Components.Slider(catContent, {
            label = L["Options.Priority"],
            min = 1,
            max = 7,
            step = 1,
            get = function()
                local cs = db.categorySettings and db.categorySettings[category]
                return cs and cs.priority or defaults.categorySettings[category].priority
            end,
            enabled = function()
                return not IsCategorySplit(category)
            end,
            tooltip = {
                title = L["Options.DisplayPriority"],
                desc = L["Options.Priority.Desc"],
            },
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".priority", val)
            end,
        })
        catLayout:Add(priorityHolder, nil, COMPONENT_GAP)

        -- Split frame checkbox
        local splitHolder = Components.Checkbox(catContent, {
            label = L["Options.SplitFrame"],
            get = function()
                return IsCategorySplit(category)
            end,
            tooltip = {
                title = L["Options.SplitFrame"],
                desc = L["Options.SplitFrame.Desc"],
            },
            onChange = function(checked)
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings[category] then
                    db.categorySettings[category] = {}
                end
                db.categorySettings[category].split = checked
                ReparentBuffFrames()
                UpdateVisuals()
            end,
        })
        catLayout:Add(splitHolder, nil, COMPONENT_GAP)

        -- Reset position button (only relevant when split)
        local resetBtn = CreateButton(catContent, L["Options.ResetPosition"], function()
            local catDefaults = defaults.categorySettings[category]
            if catDefaults and catDefaults.position then
                ResetCategoryFramePosition(category, catDefaults.position.x, catDefaults.position.y)
            end
        end)
        resetBtn:SetPoint("LEFT", splitHolder, "RIGHT", 10, 0)
        resetBtn:SetEnabled(IsCategorySplit(category))

        local origSplitClick = splitHolder.checkbox:GetScript("OnClick")
        splitHolder.checkbox:SetScript("OnClick", function(self)
            if origSplitClick then
                origSplitClick(self)
            end
            resetBtn:SetEnabled(IsCategorySplit(category))
            Components.RefreshAll()
        end)

        -- Shared enabled predicates for this category
        local function isCustomAppearanceEnabled()
            return db.categorySettings
                and db.categorySettings[category]
                and db.categorySettings[category].useCustomAppearance == true
        end

        local function isCustomGlowEnabled()
            return isCustomAppearanceEnabled() and db.categorySettings[category].useCustomGlow == true
        end

        -- Snapshot current effective glow values from defaults into a category
        local function SnapshotGlowDefaults()
            local cs = db.categorySettings[category]
            local glowDefaults = db.defaults or {}
            local glowSnapshotKeys = {
                -- Expiring glow keys
                "glowType",
                "glowSize",
                "glowPixelLines",
                "glowPixelFrequency",
                "glowPixelLength",
                "glowAutocastParticles",
                "glowAutocastFrequency",
                "glowAutocastScale",
                "glowBorderFrequency",
                "glowProcDuration",
                "glowProcStartAnim",
                "glowProcUseCustomColor",
                "glowXOffset",
                "glowYOffset",
                -- Missing glow keys
                "missingGlowType",
                "missingGlowSize",
                "missingGlowPixelLines",
                "missingGlowPixelFrequency",
                "missingGlowPixelLength",
                "missingGlowAutocastParticles",
                "missingGlowAutocastFrequency",
                "missingGlowAutocastScale",
                "missingGlowBorderFrequency",
                "missingGlowProcDuration",
                "missingGlowProcStartAnim",
                "missingGlowProcUseCustomColor",
                "missingGlowXOffset",
                "missingGlowYOffset",
            }
            for _, key in ipairs(glowSnapshotKeys) do
                if cs[key] == nil and glowDefaults[key] ~= nil then
                    cs[key] = glowDefaults[key]
                end
            end
            -- Color: deep copy (table values)
            for _, colorKey in ipairs({ "glowColor", "missingGlowColor" }) do
                if cs[colorKey] == nil and glowDefaults[colorKey] then
                    local gc = glowDefaults[colorKey]
                    cs[colorKey] = { gc[1], gc[2], gc[3], gc[4] }
                end
            end
        end

        -- Use custom appearance checkbox
        catLayout:SetX(0)
        local useCustomAppHolder = Components.Checkbox(catContent, {
            label = L["Options.CustomAppearance"],
            get = function()
                return db.categorySettings
                    and db.categorySettings[category]
                    and db.categorySettings[category].useCustomAppearance == true
            end,
            tooltip = {
                title = L["Options.CustomAppearance"],
                desc = L["Options.CustomAppearance.Desc"],
            },
            onChange = function(checked)
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings[category] then
                    db.categorySettings[category] = {}
                end
                -- When enabling custom appearance, snapshot current effective values
                -- so the category starts independent from future Global Defaults changes
                if checked then
                    local effective = GetCategorySettings(category)
                    local cs = db.categorySettings[category]
                    local appearanceKeys = {
                        "iconSize",
                        "iconWidth",
                        "textSize",
                        "spacing",
                        "iconZoom",
                        "borderSize",
                        "iconAlpha",
                        "textAlpha",
                        "growDirection",
                    }
                    for _, key in ipairs(appearanceKeys) do
                        if cs[key] == nil and effective[key] ~= nil then
                            cs[key] = effective[key]
                        end
                    end
                    -- textColor: deep copy (table value)
                    if cs.textColor == nil and effective.textColor then
                        local tc = effective.textColor
                        cs.textColor = { tc[1], tc[2], tc[3] }
                    end
                end
                BR.Config.Set("categorySettings." .. category .. ".useCustomAppearance", checked)
                Components.RefreshAll()
            end,
        })
        catLayout:Add(useCustomAppHolder, nil, COMPONENT_GAP)

        local baseContentY = catLayout:GetY()

        -- Direction buttons (part of custom appearance)
        catLayout:SetX(10)
        local dirHolder = Components.DirectionButtons(catContent, {
            get = function()
                local catSettings = db.categorySettings and db.categorySettings[category]
                local val = catSettings and catSettings.growDirection
                if val ~= nil then
                    return val
                end
                return db.defaults and db.defaults.growDirection or "CENTER"
            end,
            enabled = function()
                return isCustomAppearanceEnabled() and IsCategorySplit(category)
            end,
            onChange = function(dir)
                BR.Config.Set("categorySettings." .. category .. ".growDirection", dir)
            end,
        })
        catLayout:Add(dirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

        -- Read the category's own saved value, falling back to defaults only if no value was saved.
        -- This avoids showing inherited defaults when useCustomAppearance is off, so toggling
        -- custom appearance off/on preserves the user's previously configured values.
        local function getCatOwnValue(key, default)
            local catSettings = db.categorySettings and db.categorySettings[category]
            local val = catSettings and catSettings[key]
            if val ~= nil then
                return val
            end
            return db.defaults and db.defaults[key] or default
        end

        local function isCatDimensionsLinked()
            local cs = db.categorySettings and db.categorySettings[category]
            return not cs or cs.iconWidth == nil
        end

        -- Appearance controls (2-col declarative grid)
        catLayout:SetX(10)
        local appFrame = CreateFrame("Frame", nil, catContent)
        appFrame:SetSize(480, 50)
        catLayout:Add(appFrame, 0)

        local catGrid = Components.AppearanceGrid(appFrame, {
            get = getCatOwnValue,
            set = function(key, value)
                BR.Config.Set("categorySettings." .. category .. "." .. key, value)
            end,
            setMulti = function(changes)
                local prefixed = {}
                for k, v in pairs(changes) do
                    prefixed["categorySettings." .. category .. "." .. k] = v
                end
                BR.Config.SetMulti(prefixed)
            end,
            isLinked = isCatDimensionsLinked,
            onLink = function()
                BR.Config.Set("categorySettings." .. category .. ".iconWidth", nil)
                Components.RefreshAll()
            end,
            onUnlink = function()
                local size = getCatOwnValue("iconSize", 64)
                BR.Config.Set("categorySettings." .. category .. ".iconWidth", size)
                Components.RefreshAll()
            end,
            enabled = isCustomAppearanceEnabled,
            masqueCheck = IsMasqueActive,
        })

        -- Glow settings (positioned after appearance grid)
        local glowRowY = -catGrid.height
        local gridHeight
        if category == "pet" then
            -- Pets don't expire — single glow on/off checkbox (uses showMissingGlow)
            local catPetGlowHolder = Components.Checkbox(appFrame, {
                label = L["Options.GlowMissingPets"],
                get = function()
                    return getCatOwnValue("showMissingGlow", true) ~= false
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showMissingGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catPetGlowHolder:SetPoint("TOPLEFT", 0, glowRowY)

            -- Per-category custom glow style (pet)
            local catPetCustomGlowHolder = Components.Checkbox(appFrame, {
                label = L["Options.CustomGlowStyle"],
                get = function()
                    return isCustomGlowEnabled()
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    if checked then
                        SnapshotGlowDefaults()
                    end
                    BR.Config.Set("categorySettings." .. category .. ".useCustomGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catPetCustomGlowHolder:SetPoint("TOPLEFT", 0, glowRowY - 24)

            local catPetGlowSettingsBtn = CreateButton(appFrame, L["Options.Customize"], function()
                BR.Options.Modals.Glow.Show(category, "missing")
            end)
            catPetGlowSettingsBtn:SetPoint("LEFT", catPetCustomGlowHolder.label, "RIGHT", 8, 0)
            catPetGlowSettingsBtn:SetFrameLevel(catPetCustomGlowHolder:GetFrameLevel() + 5)

            local function updatePetGlowBtnEnabled()
                local enabled = isCustomGlowEnabled()
                if enabled then
                    catPetGlowSettingsBtn:Enable()
                    catPetGlowSettingsBtn:SetAlpha(1)
                else
                    catPetGlowSettingsBtn:Disable()
                    catPetGlowSettingsBtn:SetAlpha(0.4)
                end
            end
            updatePetGlowBtnEnabled()
            tinsert(BR.RefreshableComponents, { Refresh = updatePetGlowBtnEnabled })

            gridHeight = catGrid.height + 48
        elseif category == "custom" then
            -- Custom buffs: expiration is per-buff (in each buff's edit menu), only missing glow here
            local catCustomMissGlowHolder = Components.Checkbox(appFrame, {
                label = L["Options.Glow"],
                get = function()
                    return getCatOwnValue("showMissingGlow", true) ~= false
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showMissingGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catCustomMissGlowHolder:SetPoint("TOPLEFT", 0, glowRowY)

            -- Per-category custom glow style
            local catCustomGlowStyleHolder = Components.Checkbox(appFrame, {
                label = L["Options.CustomGlowStyle"],
                get = function()
                    return isCustomGlowEnabled()
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    if checked then
                        SnapshotGlowDefaults()
                    end
                    BR.Config.Set("categorySettings." .. category .. ".useCustomGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catCustomGlowStyleHolder:SetPoint("TOPLEFT", 0, glowRowY - 24)

            local catCustomGlowBtn = CreateButton(appFrame, L["Options.Customize"], function()
                BR.Options.Modals.Glow.Show(category)
            end)
            catCustomGlowBtn:SetPoint("LEFT", catCustomGlowStyleHolder.label, "RIGHT", 8, 0)
            catCustomGlowBtn:SetFrameLevel(catCustomGlowStyleHolder:GetFrameLevel() + 5)

            local function updateCustomGlowBtnEnabled()
                local enabled = isCustomGlowEnabled()
                if enabled then
                    catCustomGlowBtn:Enable()
                    catCustomGlowBtn:SetAlpha(1)
                else
                    catCustomGlowBtn:Disable()
                    catCustomGlowBtn:SetAlpha(0.4)
                end
            end
            updateCustomGlowBtnEnabled()
            tinsert(BR.RefreshableComponents, { Refresh = updateCustomGlowBtnEnabled })

            gridHeight = catGrid.height + 48
        else
            local catThresholdHolder = Components.Slider(appFrame, {
                label = L["Options.Expiration"],
                labelWidth = 56,
                min = 0,
                max = 45,
                step = 5,
                formatValue = function(val)
                    return val == 0 and L["Options.Off"] or (val .. " " .. L["Options.Min"])
                end,
                get = function()
                    return getCatOwnValue("expirationThreshold", 15)
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(val)
                    BR.Config.Set("categorySettings." .. category .. ".expirationThreshold", val)
                end,
            })
            catThresholdHolder:SetPoint("TOPLEFT", 0, glowRowY)

            local catGlowCheckHolder = Components.Checkbox(appFrame, {
                label = L["Options.Glow"],
                get = function()
                    local ex = getCatOwnValue("showExpirationGlow", true) ~= false
                    local miss = getCatOwnValue("showMissingGlow", true) ~= false
                    return ex or miss
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showExpirationGlow", checked)
                    BR.Config.Set("categorySettings." .. category .. ".showMissingGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catGlowCheckHolder:SetPoint("TOPLEFT", 0, glowRowY - 24)

            -- Per-category custom glow style
            local catCustomGlowHolder = Components.Checkbox(appFrame, {
                label = L["Options.CustomGlowStyle"],
                get = function()
                    return isCustomGlowEnabled()
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    if checked then
                        SnapshotGlowDefaults()
                    end
                    BR.Config.Set("categorySettings." .. category .. ".useCustomGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catCustomGlowHolder:SetPoint("TOPLEFT", 0, glowRowY - 48)

            local catGlowSettingsBtn = CreateButton(appFrame, L["Options.Customize"], function()
                BR.Options.Modals.Glow.Show(category)
            end)
            catGlowSettingsBtn:SetPoint("LEFT", catCustomGlowHolder.label, "RIGHT", 8, 0)
            catGlowSettingsBtn:SetFrameLevel(catCustomGlowHolder:GetFrameLevel() + 5)

            -- Register enabled state for the customize button
            local function updateGlowBtnEnabled()
                local enabled = isCustomGlowEnabled()
                if enabled then
                    catGlowSettingsBtn:Enable()
                    catGlowSettingsBtn:SetAlpha(1)
                else
                    catGlowSettingsBtn:Disable()
                    catGlowSettingsBtn:SetAlpha(0.4)
                end
            end
            updateGlowBtnEnabled()
            tinsert(BR.RefreshableComponents, { Refresh = updateGlowBtnEnabled })

            gridHeight = catGrid.height + 72
        end

        -- Advance past the appFrame grid and finalize section height
        catLayout:Space(gridHeight)
        catLayout:SetX(0)

        local fullContentHeight = abs(catLayout:GetY()) + 10
        local baseContentHeight = abs(baseContentY) + 10

        local UpdateCustomAppearanceVisibility = function()
            local show = isCustomAppearanceEnabled()
            if show then
                dirHolder:Show()
                appFrame:Show()
                section:SetContentHeight(fullContentHeight)
            else
                dirHolder:Hide()
                appFrame:Hide()
                section:SetContentHeight(baseContentHeight)
            end
            C_Timer.After(0, UpdateAppearanceContentHeight)
        end

        -- Register so panel OnShow syncs visibility state
        tinsert(BR.RefreshableComponents, { Refresh = UpdateCustomAppearanceVisibility })

        -- Set initial state (inline to avoid deferred timer during loop)
        if isCustomAppearanceEnabled() then
            section:SetContentHeight(fullContentHeight)
        else
            dirHolder:Hide()
            appFrame:Hide()
            section:SetContentHeight(baseContentHeight)
        end
        tinsert(categorySections, section)
        previousSection = section
    end

    UpdateAppearanceContentHeight()

    -- ========== SETTINGS TAB ==========
    -- Simple frame (not scrollable) - content fits without scrolling
    local settingsContent = CreateFrame("Frame", nil, panel)
    settingsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    settingsContent:SetSize(PANEL_WIDTH, 500)
    settingsContent:Hide()
    contentContainers.settings = settingsContent

    local setX = COL_PADDING
    local setLayout = Components.VerticalLayout(settingsContent, { x = setX, y = -10 })

    local loginMsgHolder = Components.Checkbox(settingsContent, {
        label = L["Options.ShowLoginMessages"],
        get = function()
            return BR.profile.showLoginMessages ~= false
        end,
        onChange = function(checked)
            BR.profile.showLoginMessages = checked
        end,
    })
    setLayout:Add(loginMsgHolder, nil, COMPONENT_GAP)

    local minimapHolder = Components.Checkbox(settingsContent, {
        label = L["Options.ShowMinimapButton"],
        get = function()
            return not BR.aceDB.global.minimap.hide
        end,
        onChange = function(checked)
            BR.aceDB.global.minimap.hide = not checked
            if BR.MinimapButton then
                if checked then
                    BR.MinimapButton.Icon:Show("BuffReminders")
                else
                    BR.MinimapButton.Icon:Hide("BuffReminders")
                end
            end
        end,
    })
    setLayout:Add(minimapHolder, nil, COMPONENT_GAP)

    LayoutSectionHeader(setLayout, settingsContent, L["Options.ChatRequests"])

    local requestBuffHolder = Components.Checkbox(settingsContent, {
        label = L["Options.RequestBuffInChat"],
        get = function()
            return BR.profile.requestBuffInChat == true
        end,
        tooltip = {
            title = L["Options.RequestBuffInChat"],
            desc = L["Options.RequestBuffInChat.Desc"],
        },
        onChange = function(checked)
            BR.profile.requestBuffInChat = checked
            BR.Display.UpdateActionButtons("raid")
            BR.Display.UpdateActionButtons("presence")
            Components.RefreshAll()
        end,
    })

    local customizeMsgsBtn = CreateButton(settingsContent, L["Options.CustomizeChatMessages"], function()
        BR.Options.Modals.ChatRequest.Show()
    end)
    customizeMsgsBtn:SetPoint("LEFT", requestBuffHolder.label, "RIGHT", 8, 0)
    customizeMsgsBtn:SetFrameLevel(requestBuffHolder:GetFrameLevel() + 5)

    setLayout:Add(requestBuffHolder, nil, COMPONENT_GAP)

    -- General Settings section
    LayoutSectionHeader(setLayout, settingsContent, L["Options.Visibility"])

    local groupHolder = Components.Checkbox(settingsContent, {
        label = L["Options.ShowOnlyInGroup"],
        get = function()
            return BR.profile.showOnlyInGroup ~= false
        end,
        onChange = function(checked)
            BR.Config.Set("showOnlyInGroup", checked)
        end,
    })
    setLayout:Add(groupHolder, nil, COMPONENT_GAP)

    -- "Hide when:" sub-label with indented checkboxes
    local hideWhenLabel = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideWhenLabel:SetText(L["Options.HideWhen"])
    setLayout:AddText(hideWhenLabel, 12, COMPONENT_GAP)

    local HIDE_INDENT = 16
    setLayout:SetX(setX + HIDE_INDENT)

    local combatHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Combat"],
        get = function()
            return BR.profile.hideInCombat == true
        end,
        onChange = function(checked)
            BR.Config.Set("hideInCombat", checked)
            Components.RefreshAll()
        end,
    })
    setLayout:Add(combatHolder, nil, COMPONENT_GAP)

    local combatExpiringHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Expiring"],
        tooltip = {
            title = L["Options.HideWhen.Expiring.Title"],
            desc = L["Options.HideWhen.Expiring.Desc"],
        },
        get = function()
            return BR.profile.hideExpiringInCombat ~= false
        end,
        enabled = function()
            return BR.profile.hideInCombat ~= true
        end,
        onChange = function(checked)
            BR.Config.Set("hideExpiringInCombat", checked)
        end,
    })
    setLayout:Add(combatExpiringHolder, nil, COMPONENT_GAP)

    local mountedHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Mounted"],
        tooltip = {
            title = L["Options.HideWhen.Mounted.Title"],
            desc = L["Options.HideWhen.Mounted.Desc"],
        },
        get = function()
            return BR.profile.hideWhileMounted == true
        end,
        onChange = function(checked)
            BR.Config.Set("hideWhileMounted", checked)
        end,
    })
    setLayout:Add(mountedHolder, nil, COMPONENT_GAP)

    local vehicleHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Vehicle"],
        tooltip = {
            title = L["Options.HideWhen.Vehicle.Title"],
            desc = L["Options.HideWhen.Vehicle.Desc"],
        },
        get = function()
            return BR.profile.hideAllInVehicle == true
        end,
        onChange = function(checked)
            BR.Config.Set("hideAllInVehicle", checked)
        end,
    })
    setLayout:Add(vehicleHolder, nil, COMPONENT_GAP)

    local restingHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Resting"],
        get = function()
            return BR.profile.hideWhileResting == true
        end,
        tooltip = { title = L["Options.HideWhen.Resting.Title"], desc = L["Options.HideWhen.Resting.Desc"] },
        onChange = function(checked)
            BR.Config.Set("hideWhileResting", checked)
        end,
    })
    setLayout:Add(restingHolder, nil, COMPONENT_GAP)

    local legacyHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Legacy"],
        tooltip = {
            title = L["Options.HideWhen.Legacy.Title"],
            desc = L["Options.HideWhen.Legacy.Desc"],
        },
        get = function()
            return BR.profile.hideInLegacyInstances == true
        end,
        onChange = function(checked)
            BR.Config.Set("hideInLegacyInstances", checked)
        end,
    })
    setLayout:Add(legacyHolder, nil, COMPONENT_GAP)

    local levelingHolder = Components.Checkbox(settingsContent, {
        label = L["Options.HideWhen.Leveling"],
        tooltip = {
            title = L["Options.HideWhen.Leveling.Title"],
            desc = L["Options.HideWhen.Leveling.Desc"],
        },
        get = function()
            return BR.profile.hideWhileLeveling == true
        end,
        onChange = function(checked)
            BR.Config.Set("hideWhileLeveling", checked)
        end,
    })
    setLayout:Add(levelingHolder, nil, COMPONENT_GAP)

    setLayout:SetX(setX)

    local trackingModeHolder = Components.Dropdown(settingsContent, {
        label = L["Options.BuffTracking"],
        width = 200,
        options = {
            {
                value = "all",
                label = L["Options.BuffTracking.All"],
                desc = L["Options.BuffTracking.All.Desc"],
            },
            {
                value = "my_buffs",
                label = L["Options.BuffTracking.MyBuffs"],
                desc = L["Options.BuffTracking.MyBuffs.Desc"],
            },
            {
                value = "personal",
                label = L["Options.BuffTracking.OnlyMine"],
                desc = L["Options.BuffTracking.OnlyMine.Desc"],
            },
            {
                value = "smart",
                label = L["Options.BuffTracking.Smart"],
                desc = L["Options.BuffTracking.Smart.Desc"],
            },
        },
        get = function()
            return BR.Config.Get("buffTrackingMode", "all")
        end,
        tooltip = {
            title = L["Options.BuffTracking.Mode"],
            desc = L["Options.BuffTracking.Mode.Desc"],
        },
        onChange = function(val)
            BR.Config.Set("buffTrackingMode", val)
            UpdateDisplay()
        end,
    })
    setLayout:Add(trackingModeHolder, nil, COMPONENT_GAP)

    -- Custom Anchor Frames section
    LayoutSectionHeader(setLayout, settingsContent, L["Options.CustomAnchorFrames"])

    local customAnchorDesc = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customAnchorDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    customAnchorDesc:SetJustifyH("LEFT")
    customAnchorDesc:SetText(L["Options.CustomAnchorFrames.Desc"])
    setLayout:AddText(customAnchorDesc, 22, COMPONENT_GAP)

    -- Input row: text input + add button (at top)
    local addAnchorRow = CreateFrame("Frame", nil, settingsContent)
    addAnchorRow:SetSize(PANEL_WIDTH - COL_PADDING * 2, 22)

    local addAnchorInput = Components.TextInput(addAnchorRow, {
        label = "",
        value = "",
        width = 180,
        labelWidth = 0,
    })
    addAnchorInput:SetPoint("LEFT", 0, 0)
    local addAnchorBox = addAnchorInput.editBox

    local addAnchorBtn -- forward declare for editbox callback

    local customAnchorList = CreateFrame("Frame", nil, settingsContent)
    customAnchorList:SetSize(PANEL_WIDTH - COL_PADDING * 2, 1)

    local customAnchorEntries = {} -- holder frames for removal

    local function RebuildCustomAnchorList()
        for _, entry in ipairs(customAnchorEntries) do
            entry:Hide()
            entry:SetParent(nil)
        end
        wipe(customAnchorEntries)

        local db = BR.profile
        local list = db.customAnchorFrames or {}
        local entryY = 0

        for i, name in ipairs(list) do
            local row = CreateFrame("Frame", nil, customAnchorList)
            row:SetSize(PANEL_WIDTH - COL_PADDING * 2, 20)
            row:SetPoint("TOPLEFT", 0, -entryY)

            local bullet = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            bullet:SetPoint("LEFT", 4, 0)
            bullet:SetText("-")

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", bullet, "RIGHT", 4, 0)
            text:SetText(name)

            local removeBtn = CreateFrame("Button", nil, row)
            removeBtn:SetSize(16, 16)
            removeBtn:SetPoint("LEFT", text, "RIGHT", 6, 0)
            removeBtn:SetNormalFontObject("GameFontRedSmall")
            removeBtn:SetText("x")
            removeBtn:SetScript("OnClick", function()
                tremove(list, i)
                if #list == 0 then
                    db.customAnchorFrames = nil
                end
                RebuildCustomAnchorList()
            end)

            tinsert(customAnchorEntries, row)
            entryY = entryY + 22
        end

        customAnchorList:SetHeight(math.max(1, entryY))
    end

    addAnchorBtn = CreateButton(addAnchorRow, L["Options.Add"], function()
        local name = strtrim(addAnchorBox:GetText())
        if name == "" then
            return
        end
        local db = BR.profile
        if not db.customAnchorFrames then
            db.customAnchorFrames = {}
        end
        -- Avoid duplicates
        for _, existing in ipairs(db.customAnchorFrames) do
            if existing == name then
                addAnchorBox:SetText("")
                return
            end
        end
        tinsert(db.customAnchorFrames, name)
        addAnchorBox:SetText("")
        RebuildCustomAnchorList()
    end)
    addAnchorBtn:SetSize(50, 22)
    addAnchorBtn:SetPoint("LEFT", addAnchorInput, "RIGHT", 6, 0)

    addAnchorBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        addAnchorBtn:Click()
    end)

    setLayout:Add(addAnchorRow, nil, COMPONENT_GAP)

    RebuildCustomAnchorList()
    setLayout:Add(customAnchorList, nil, COMPONENT_GAP)

    -- ========== SOUNDS TAB ==========
    local soundsContent = CreateFrame("Frame", nil, panel)
    soundsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    soundsContent:SetSize(PANEL_WIDTH, 500)
    soundsContent:Hide()
    contentContainers.sounds = soundsContent

    local SOUND_ROW_HEIGHT = 24
    local SOUND_ICON_SIZE = 20
    local soundRowPool = {} -- Reusable row frames to avoid frame leaks
    local soundRowCount = 0 -- Number of active rows in current render

    -- Build a lookup of all known buff keys to display names and icons.
    -- Static buff info is cached; custom buffs are merged on each call.
    local cachedStaticBuffInfo = nil
    local function GetAllBuffInfo()
        if not cachedStaticBuffInfo then
            cachedStaticBuffInfo = {}
            local seenGroups = {}
            local allBuffArrays = { RaidBuffs, PresenceBuffs, TargetedBuffs, SelfBuffs, PetBuffs, Consumables }
            for _, buffArray in ipairs(allBuffArrays) do
                for _, buff in ipairs(buffArray) do
                    if buff.groupId then
                        if not seenGroups[buff.groupId] then
                            seenGroups[buff.groupId] = true
                            local groupInfo = BuffGroups[buff.groupId]
                            local name = groupInfo and groupInfo.displayName or buff.name
                            cachedStaticBuffInfo[buff.groupId] = {
                                name = name,
                                spellID = buff.displaySpells or buff.spellID,
                            }
                        end
                    else
                        cachedStaticBuffInfo[buff.key] = {
                            name = buff.name,
                            spellID = buff.displaySpells or buff.spellID,
                        }
                    end
                end
            end
        end
        -- Merge custom buffs (may change between calls)
        local info = {}
        for k, v in pairs(cachedStaticBuffInfo) do
            info[k] = v
        end
        local db = BR.profile
        if db.customBuffs then
            for key, customBuff in pairs(db.customBuffs) do
                info[key] = {
                    name = customBuff.name or (L["CustomBuff.Action.Spell"] .. " " .. tostring(customBuff.spellID)),
                    spellID = customBuff.spellID,
                }
            end
        end
        return info
    end

    -- Get or create a pooled row frame
    local function AcquireSoundRow(index)
        local row = soundRowPool[index]
        if not row then
            row = CreateFrame("Frame", nil, soundsContent)
            row:SetSize(PANEL_WIDTH - COL_PADDING * 2, SOUND_ROW_HEIGHT)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(SOUND_ICON_SIZE, SOUND_ICON_SIZE)
            row.icon:SetPoint("LEFT", 0, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.soundText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.soundText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)
            -- Preview button
            row.previewBtn = CreateFrame("Button", nil, row)
            row.previewBtn:SetSize(14, 14)
            row.previewBtn:SetPoint("RIGHT", row, "RIGHT", -48, 0)
            row.previewTex = row.previewBtn:CreateTexture(nil, "ARTWORK")
            row.previewTex:SetAllPoints()
            row.previewTex:SetAtlas("chatframe-button-icon-voicechat")
            row.previewBtn:SetScript("OnEnter", function()
                row.previewTex:SetVertexColor(1, 1, 1, 1)
            end)
            row.previewBtn:SetScript("OnLeave", function()
                row.previewTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            end)
            -- Edit button
            row.editBtn = CreateFrame("Button", nil, row)
            row.editBtn:SetSize(14, 14)
            row.editBtn:SetPoint("RIGHT", row, "RIGHT", -24, 0)
            row.editTex = row.editBtn:CreateTexture(nil, "ARTWORK")
            row.editTex:SetAllPoints()
            row.editTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
            row.editBtn:SetScript("OnEnter", function()
                row.editTex:SetVertexColor(1, 1, 1, 1)
            end)
            row.editBtn:SetScript("OnLeave", function()
                row.editTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            end)
            -- Remove button
            row.removeBtn = CreateFrame("Button", nil, row)
            row.removeBtn:SetSize(14, 14)
            row.removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.removeTex = row.removeBtn:CreateTexture(nil, "ARTWORK")
            row.removeTex:SetAllPoints()
            row.removeTex:SetAtlas("common-icon-redx")
            row.removeBtn:SetScript("OnEnter", function()
                row.removeTex:SetVertexColor(1, 0.3, 0.3, 1)
            end)
            row.removeBtn:SetScript("OnLeave", function()
                row.removeTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            end)
            soundRowPool[index] = row
        end
        row.previewTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
        row.editTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
        row.removeTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
        row:Show()
        return row
    end

    local function RenderSoundAlertRows()
        -- Hide all previously active rows
        for i = 1, soundRowCount do
            soundRowPool[i]:Hide()
        end
        soundRowCount = 0

        local db = BR.profile
        local buffSounds = db.buffSounds
        local allBuffInfo = GetAllBuffInfo()
        local y = -10

        if not buffSounds or not next(buffSounds) then
            -- Empty state
            if not soundsContent.emptyText then
                soundsContent.emptyText = soundsContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                soundsContent.emptyText:SetPoint("TOPLEFT", COL_PADDING, -10)
                soundsContent.emptyText:SetJustifyH("LEFT")
            end
            soundsContent.emptyText:SetText(L["Options.Sound.NoAlerts"])
            soundsContent.emptyText:Show()
            y = y - SOUND_ROW_HEIGHT
        else
            if soundsContent.emptyText then
                soundsContent.emptyText:Hide()
            end

            -- Sort keys alphabetically by buff name
            local sortedKeys = {}
            for key in pairs(buffSounds) do
                tinsert(sortedKeys, key)
            end
            tsort(sortedKeys, function(a, b)
                local infoA = allBuffInfo[a]
                local infoB = allBuffInfo[b]
                local nameA = infoA and infoA.name or a
                local nameB = infoB and infoB.name or b
                return nameA < nameB
            end)

            for _, key in ipairs(sortedKeys) do
                local soundName = buffSounds[key]
                local buffInfo = allBuffInfo[key]
                local displayName = buffInfo and buffInfo.name or key

                soundRowCount = soundRowCount + 1
                local row = AcquireSoundRow(soundRowCount)
                row:SetPoint("TOPLEFT", COL_PADDING, y)

                -- Update icon
                if buffInfo and buffInfo.spellID then
                    local texture = GetBuffTexture(buffInfo.spellID)
                    if texture then
                        row.icon:SetTexture(texture)
                        row.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
                    else
                        row.icon:SetTexture(134400)
                        row.icon:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    row.icon:SetTexture(134400)
                    row.icon:SetTexCoord(0, 1, 0, 1)
                end

                row.nameText:SetText(displayName)
                row.soundText:SetText("|cff888888" .. soundName .. "|r")

                row.previewBtn:SetScript("OnClick", function()
                    local soundFile = LSM:Fetch("sound", soundName)
                    if soundFile then
                        PlaySoundFile(soundFile, "Master")
                    end
                end)
                row.editBtn:SetScript("OnClick", function()
                    BR.Options.Modals.SoundAlert.Show(RenderSoundAlertRows, key, soundName, displayName)
                end)
                row.removeBtn:SetScript("OnClick", function()
                    SetBuffSound(key, nil)
                    RenderSoundAlertRows()
                end)

                y = y - SOUND_ROW_HEIGHT
            end
        end

        -- Add button (always at bottom)
        if not soundsContent.addBtn then
            soundsContent.addBtn = CreateButton(soundsContent, L["Options.Sound.AddAlert"], function()
                BR.Options.Modals.SoundAlert.Show(RenderSoundAlertRows)
            end)
            soundsContent.addBtn:SetSize(160, 22)
        end
        soundsContent.addBtn:SetPoint("TOPLEFT", COL_PADDING, y - 10)
    end

    -- Render initial state and refresh on tab show
    soundsContent:SetScript("OnShow", function()
        RenderSoundAlertRows()
    end)

    -- ========== PROFILES TAB ==========
    -- Use simple frame (not scrollable) to avoid nested scroll frame issues with edit boxes
    local profilesContent = CreateFrame("Frame", nil, panel)
    profilesContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    profilesContent:SetSize(PANEL_WIDTH, 600)
    profilesContent:Hide()
    contentContainers.profiles = profilesContent

    local profX = COL_PADDING
    local profLayout = Components.VerticalLayout(profilesContent, { x = profX, y = -10 })
    local RefreshProfileDropdown -- forward declaration for closures

    -- Profile management section
    LayoutSectionHeader(profLayout, profilesContent, L["Options.ActiveProfile"])

    local profileDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profileDesc:SetText(L["Options.ActiveProfile.Desc"])
    profLayout:AddText(profileDesc, 12, COMPONENT_GAP)

    local function GetProfileOptions()
        local names = BR.Profiles.ListProfiles()
        local options = {}
        for _, name in ipairs(names) do
            options[#options + 1] = { value = name, label = name }
        end
        return options
    end

    local function GetOtherProfileOptions()
        local names = BR.Profiles.ListProfiles()
        local active = BR.Profiles.GetActiveProfileName()
        local options = { { value = "", label = L["Options.SelectProfile"] } }
        for _, name in ipairs(names) do
            if name ~= active then
                options[#options + 1] = { value = name, label = name }
            end
        end
        return options
    end

    local PROF_LABEL_WIDTH = 70
    local PROF_DROPDOWN_WIDTH = 150

    -- Active profile row: dropdown + New / Reset buttons
    local profileRow = CreateFrame("Frame", nil, profilesContent)
    profileRow:SetSize(PANEL_WIDTH - COL_PADDING * 2, 26)

    local profileDropdown = Components.Dropdown(profileRow, {
        label = L["Options.Profile"],
        labelWidth = PROF_LABEL_WIDTH,
        width = PROF_DROPDOWN_WIDTH,
        options = GetProfileOptions(),
        get = function()
            return BR.Profiles.GetActiveProfileName()
        end,
        onChange = function(value)
            BR.Profiles.SwitchProfile(value)
            RefreshProfileDropdown()
            Components.RefreshAll()
        end,
    })
    profileDropdown:SetPoint("LEFT", 0, 0)

    local btnX = PROF_LABEL_WIDTH + PROF_DROPDOWN_WIDTH + 10

    local newProfileBtn = CreateButton(profileRow, L["Options.New"], function()
        StaticPopup_Show("BUFFREMINDERS_NEW_PROFILE")
    end)
    newProfileBtn:SetSize(50, 22)
    newProfileBtn:SetPoint("LEFT", btnX, 0)

    local resetProfileBtn = CreateButton(profileRow, L["Dialog.Reset"], function()
        StaticPopup_Show("BUFFREMINDERS_RESET_DEFAULTS")
    end)
    resetProfileBtn:SetSize(50, 22)
    resetProfileBtn:SetPoint("LEFT", btnX + 54, 0)

    profLayout:Add(profileRow, 26, COMPONENT_GAP)

    -- Copy From dropdown
    local copyDropdown = Components.Dropdown(profilesContent, {
        label = L["Options.CopyFrom"],
        labelWidth = PROF_LABEL_WIDTH,
        width = PROF_DROPDOWN_WIDTH,
        options = GetOtherProfileOptions(),
        get = function()
            return ""
        end,
        onChange = function(value)
            if value == "" then
                return
            end
            BR.Profiles.CopyProfile(value)
            Components.RefreshAll()
        end,
    })
    profLayout:Add(copyDropdown, 26, COMPONENT_GAP)

    -- Delete dropdown
    local deleteDropdown = Components.Dropdown(profilesContent, {
        label = L["Options.Delete"],
        labelWidth = PROF_LABEL_WIDTH,
        width = PROF_DROPDOWN_WIDTH,
        options = GetOtherProfileOptions(),
        get = function()
            return ""
        end,
        onChange = function(value)
            if value == "" then
                return
            end
            BR.Profiles.DeleteProfile(value)
            -- RefreshProfileDropdown called below (forward ref via closure)
            RefreshProfileDropdown()
        end,
    })
    profLayout:Add(deleteDropdown, 26, SECTION_GAP)

    -- Rebuild all profile dropdowns after CRUD (defined after all dropdowns exist)
    RefreshProfileDropdown = function()
        local opts = GetProfileOptions()
        local otherOpts = GetOtherProfileOptions()
        profileDropdown.dropdown:SetOptions(opts)
        profileDropdown:SetValue(BR.Profiles.GetActiveProfileName())
        copyDropdown.dropdown:SetOptions(otherOpts)
        copyDropdown:SetValue("")
        deleteDropdown.dropdown:SetOptions(otherOpts)
        deleteDropdown:SetValue("")
    end

    -- Per-spec profiles section (LibDualSpec)
    LayoutSectionHeader(profLayout, profilesContent, L["Options.PerSpecProfiles"])

    local specDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    specDesc:SetText(L["Options.PerSpecProfiles.Desc"])
    profLayout:AddText(specDesc, 12, COMPONENT_GAP)

    local specEnabled = Components.Checkbox(profilesContent, {
        label = L["Options.PerSpecProfiles.Enable"],
        get = function()
            return BR.Profiles.IsPerSpecEnabled()
        end,
        onChange = function(checked)
            BR.Profiles.SetPerSpecEnabled(checked)
            Components.RefreshAll()
        end,
    })
    profLayout:Add(specEnabled, 20, COMPONENT_GAP)

    -- Per-spec dropdowns
    local numSpecs = GetNumSpecializations() or 0
    local specDropdowns = {}
    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfo(i)
        if specName then
            local specDropdown = Components.Dropdown(profilesContent, {
                label = specName,
                labelWidth = 100,
                width = 150,
                options = GetProfileOptions(),
                get = function()
                    return BR.Profiles.GetSpecProfile(i)
                end,
                enabled = function()
                    return BR.Profiles.IsPerSpecEnabled()
                end,
                onChange = function(value)
                    BR.Profiles.SetSpecProfile(i, value)
                end,
            })
            profLayout:Add(specDropdown, 26, COMPONENT_GAP)
            specDropdowns[i] = specDropdown
        end
    end

    -- Extend RefreshProfileDropdown to also update spec dropdowns
    local baseRefreshProfileDropdown = RefreshProfileDropdown
    RefreshProfileDropdown = function()
        baseRefreshProfileDropdown()
        local opts = GetProfileOptions()
        for _, sd in pairs(specDropdowns) do
            sd.dropdown:SetOptions(opts)
        end
    end

    -- Export so popup dialogs can call it
    BR.Options.RefreshProfileDropdown = function()
        RefreshProfileDropdown()
    end

    -- Export section
    LayoutSectionHeader(profLayout, profilesContent, L["Options.ExportSettings"])

    local exportDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    exportDesc:SetText(L["Options.ExportSettings.Desc"])
    profLayout:AddText(exportDesc, 12, COMPONENT_GAP)

    local exportTextArea = Components.TextArea(profilesContent, {
        width = PANEL_WIDTH - COL_PADDING * 2,
        height = 50,
    })
    profLayout:Add(exportTextArea, 50, COMPONENT_GAP)

    local exportButton = CreateButton(profilesContent, L["Options.Export"], function()
        local exportString, err = BuffReminders:Export()
        if exportString then
            exportTextArea:SetText(exportString)
            exportTextArea:HighlightText()
            exportTextArea:SetFocus()
        else
            exportTextArea:SetText(L["CustomBuff.Error"] .. " " .. (err or L["Options.FailedExport"]))
        end
    end)
    profLayout:Add(exportButton, 22, SECTION_GAP)

    -- Import section
    LayoutSectionHeader(profLayout, profilesContent, L["Options.ImportSettings"])

    local importDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    importDesc:SetText(
        L["Options.ImportSettings.DescPlain"] .. " |cffff6600" .. L["Options.ImportSettings.Overwrite"] .. "|r"
    )
    profLayout:AddText(importDesc, 12, COMPONENT_GAP)

    local importTextArea = Components.TextArea(profilesContent, {
        width = PANEL_WIDTH - COL_PADDING * 2,
        height = 50,
    })
    profLayout:Add(importTextArea, 50, COMPONENT_GAP)

    local importStatus = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatus:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 120)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetText("")

    local importButton = CreateButton(profilesContent, L["Options.Import"], function()
        local importString = importTextArea:GetText()
        local success, err = BuffReminders:Import(importString)
        if success then
            importStatus:SetText("|cff00ff00" .. L["Options.ImportSuccess"] .. "|r")
            StaticPopup_Show("BUFFREMINDERS_RELOAD_UI")
        else
            importStatus:SetText(
                "|cffff0000" .. L["CustomBuff.Error"] .. " " .. (err or L["Options.UnknownError"]) .. "|r"
            )
        end
    end)
    profLayout:Add(importButton, 22)
    importStatus:SetPoint("LEFT", importButton, "RIGHT", 10, 0)

    profilesContent:SetHeight(abs(profLayout:GetY()) + 50)

    -- ========== BOTTOM BUTTONS ==========
    local bottomFrame = CreateFrame("Frame", nil, panel)
    bottomFrame:SetPoint("BOTTOMLEFT", 0, 0)
    bottomFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    bottomFrame:SetHeight(45)
    bottomFrame:SetFrameLevel(panel:GetFrameLevel() + 10)

    local separator = bottomFrame:CreateTexture(nil, "ARTWORK")
    separator:SetSize(PANEL_WIDTH - 40, 1)
    separator:SetPoint("TOP", 0, -5)
    separator:SetColorTexture(0.3, 0.3, 0.3, 1)

    local btnHolder = CreateFrame("Frame", nil, bottomFrame)
    btnHolder:SetPoint("TOP", separator, "BOTTOM", 0, -8)
    btnHolder:SetSize(1, 22)

    local BTN_WIDTH = 80

    local lockBtn = CreateButton(btnHolder, L["Options.Unlock"], function()
        BR.Display.ToggleLock()
        Components.RefreshAll()
    end, { title = L["Options.LockUnlock"], desc = L["Options.LockUnlock.Desc"] }, {
        border = { 0.7, 0.58, 0, 1 },
        borderHover = { 1, 0.82, 0, 1 },
        text = { 1, 0.82, 0, 1 },
    })
    lockBtn:SetSize(BTN_WIDTH, 22)
    lockBtn:SetPoint("RIGHT", btnHolder, "CENTER", -4, 0)

    function lockBtn:Refresh()
        self.text:SetText(BR.profile.locked and L["Options.Unlock"] or L["Options.Lock"])
    end
    lockBtn:Refresh()
    tinsert(BR.RefreshableComponents, lockBtn)

    local unlockBanner = Components.Banner(panel, {
        text = L["Options.AnchorHint"],
        color = "orange",
        icon = "services-icon-warning",
        bgAlpha = 0.95,
        visible = function()
            return not BR.profile.locked
        end,
    })
    unlockBanner:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, 0)
    unlockBanner:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local testBtn = CreateButton(btnHolder, L["Options.StopTest"], function(self)
        local isOn = ToggleTestMode()
        self.text:SetText(isOn and L["Options.StopTest"] or L["Options.Test"])
    end, {
        title = L["Options.TestAppearance"],
        desc = L["Options.TestAppearance.Desc"],
    })
    testBtn:SetText(L["Options.Test"])
    testBtn:SetSize(BTN_WIDTH, 22)
    testBtn:SetPoint("LEFT", btnHolder, "CENTER", 4, 0)
    panel.testBtn = testBtn

    -- Set initial active tab
    SetActiveTab("buffs")

    return panel
end

local function ShowOptions()
    if not optionsPanel then
        optionsPanel = CreateOptionsPanel()
    end
    if not optionsPanel:IsShown() then
        if optionsPanel.RenderCustomBuffRows then
            optionsPanel.RenderCustomBuffRows()
        end
        if BR.Display.IsTestMode() then
            optionsPanel.testBtn.text:SetText(L["Options.StopTest"])
        else
            optionsPanel.testBtn.text:SetText(L["Options.Test"])
        end
        optionsPanel:Show()
    end
end

local function HideOptions()
    if optionsPanel and optionsPanel:IsShown() then
        optionsPanel:Hide()
    end
end

local function ToggleOptions()
    if optionsPanel and optionsPanel:IsShown() then
        HideOptions()
    else
        ShowOptions()
    end
end

StaticPopupDialogs["BUFFREMINDERS_RESET_DEFAULTS"] = {
    text = L["Dialog.ResetProfile"],
    button1 = L["Dialog.Reset"],
    button2 = L["Dialog.Cancel"],
    OnAccept = function()
        BR.Profiles.ResetProfile()
        ReloadUI()
    end,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["BUFFREMINDERS_RELOAD_UI"] = {
    text = L["Dialog.ReloadPrompt"],
    button1 = L["Dialog.Reload"],
    button2 = L["Dialog.Cancel"],
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateNewProfile(name)
    if name == "" then
        return
    end
    local copyFrom = BR.Profiles.GetActiveProfileName()
    BR.Profiles.BatchOperation(function()
        BR.aceDB:SetProfile(name)
        BR.aceDB:CopyProfile(copyFrom)
    end)
    if BR.Options.RefreshProfileDropdown then
        BR.Options.RefreshProfileDropdown()
    end
end

StaticPopupDialogs["BUFFREMINDERS_NEW_PROFILE"] = {
    text = L["Dialog.NewProfilePrompt"],
    button1 = L["Dialog.Create"],
    button2 = L["Dialog.Cancel"],
    hasEditBox = true,
    editBoxWidth = 200,
    OnAccept = function(self)
        CreateNewProfile(self.EditBox:GetText():trim())
    end,
    EditBoxOnEnterPressed = function(self)
        CreateNewProfile(self:GetText():trim())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["BUFFREMINDERS_DISCORD_URL"] = {
    text = L["Dialog.DiscordPrompt"],
    button1 = L["Dialog.Close"],
    hasEditBox = true,
    editBoxWidth = 250,
    OnShow = function(self)
        self.EditBox:SetText("https://discord.gg/qezQ2hXJJ7")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================================
-- PUBLIC API
-- ============================================================================

BR.Options.Toggle = ToggleOptions
BR.Options.Show = ShowOptions
BR.Options.Hide = HideOptions
