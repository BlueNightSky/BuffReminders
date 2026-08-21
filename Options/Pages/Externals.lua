local _, BR = ...

-- ============================================================================
-- EXTERNALS PAGE (selection)
-- ============================================================================
-- "Which received buffs do I want to see" - the mirror of the Reminders page, and
-- laid out the same way: two columns of grouped sections, one fixed-height row per
-- entry. Appearance lives on the Externals tab of the Categories page, matching
-- every other category.
--
-- The tracked set is curated in Data/Externals.lua rather than freeform, because
-- spell-ID filtering only works for helpful auras on the player and the useful set
-- of those is small.
--
-- The ticked set is the switch: no separate enable toggle, so a first tick starts
-- the display. One sound serves every tracked entry, and a row can override it, so
-- the glyph column answers one question at a glance: which buffs make a sound.

local L = BR.L
local Components = BR.Components

local COL_PADDING = BR.Options.Constants.COL_PADDING
local PAGE_TOP_PADDING = BR.Options.Constants.PAGE_TOP_PADDING
local ITEM_HEIGHT = BR.Options.Constants.ITEM_HEIGHT

local TEXCOORD_INSET = BR.TEXCOORD_INSET

local floor = math.floor
local max = math.max
local abs = math.abs
local format = string.format
local tinsert = table.insert

local GOLD = { 1, 0.8, 0 }

-- Section rhythm, matched to the Reminders page so the two read as one system.
-- That page clears a note between header and rows; there is none here, so this is
-- its header-to-note gap plus enough for the header's own descenders.
local HEADER_TO_ROWS_GAP = 22
local ROW_INDENT = 6
local INTER_SECTION_GAP = 10

local ICON_SIZE = 16
local FALLBACK_ICON = 134400

-- Trailing sound glyph, tinted to match the All Buffs row glyphs.
local GLYPH_IDLE = { 0.62, 0.70, 0.75 }
local GLYPH_HOVER = { 0.85, 0.92, 0.97 }
local GLYPH_UNSET = { 0.42, 0.42, 0.46 }
-- A silent row keeps a ghost of the glyph: it reads as absent across the column,
-- yet stays a target, so the drawer needs no second way in.
local GLYPH_ALPHA_SILENT = 0.16
local GLYPH_SIZE = 13
local GLYPH_GAP = 6
local SOUND_ATLAS = "chatframe-button-icon-voicechat"

-- Left column takes the longest section on its own; the right column stacks the
-- four shorter ones, which roughly balances the page at 16-18 rows a side.
local LEFT_SECTIONS = { "defensives" }
local RIGHT_SECTIONS = { "groupBuffs", "movement", "aggro", "augmentation" }

local Settings = BR.GetExternalSettings

---@type table<string, table[]> entries bucketed by section key, built once
local entriesBySection = {}
for _, entry in ipairs(BR.EXTERNALS) do
    local bucket = entriesBySection[entry.section]
    if not bucket then
        bucket = {}
        entriesBySection[entry.section] = bucket
    end
    bucket[#bucket + 1] = entry
end

local SECTION_BY_KEY = {}
for _, section in ipairs(BR.EXTERNAL_SECTIONS) do
    SECTION_BY_KEY[section.key] = section
end

---Trailing sound glyph: opens the sound drawer, and reports whether the entry
---carries a sound. Exposes Update() so the row can repaint it.
---@param row table
---@param entry table
local function CreateSoundGlyph(row, entry)
    local key = entry.key

    local path = "externals.sounds." .. key

    local model = {
        get = function()
            local sounds = Settings().sounds
            return sounds and sounds[key]
        end,
        set = function(value)
            -- The sentinel is stored on purpose: at entry level nil already means
            -- "inherit", so silence needs a value of its own.
            BR.Config.Set(path, value)
        end,
        override = {
            desc = L["Externals.Sound.Override.Desc"],
            isOn = function()
                return BR.IsExternalSoundOverridden(key)
            end,
            setOn = function(on)
                if not on then
                    BR.Config.Set(path, nil)
                    return
                end
                -- Snapshot what the row plays today, so turning the override on
                -- changes nothing until the player picks another sound.
                BR.Config.Set(path, BR.GetExternalEntrySound(entry) or BR.Sounds.NO_SOUND)
            end,
            effective = function()
                if entry.defaultSound == false then
                    return nil
                end
                return Settings().sound
            end,
        },
    }

    -- A sound only means something for a buff the player tracks, so the row's own
    -- checkbox gates the glyph.
    local function IsTracked()
        local enabled = Settings().entries
        return enabled ~= nil and enabled[key] == true
    end

    ---The name this row plays, or nil when it stays silent.
    local function PlayingLabel()
        return BR.Sounds.Label(BR.GetExternalEntrySound(entry))
    end

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetAtlas(SOUND_ATLAS)

    local function Tint(color, alpha)
        tex:SetVertexColor(color[1], color[2], color[3])
        tex:SetAlpha(alpha)
    end

    function btn.Update()
        if IsTracked() and PlayingLabel() then
            Tint(GLYPH_IDLE, 1)
        else
            Tint(GLYPH_UNSET, GLYPH_ALPHA_SILENT)
        end
    end

    ---Why this row sounds the way it does, and what to do about it.
    local function Describe()
        if not IsTracked() then
            return L["Externals.Sound.NeedsEntry"]
        end
        local playing = PlayingLabel()
        if playing then
            return format(L["Externals.Sound.Plays"], playing) .. "|n" .. L["Externals.Sound.Change"]
        end
        if BR.IsExternalSoundOverridden(key) then
            return L["Externals.Sound.Silenced"]
        end
        if entry.defaultSound == false then
            return L["Externals.Sound.SilentByDefault"]
        end
        return L["Externals.Sound.NoAlert"]
    end

    btn:SetScript("OnEnter", function(self)
        if IsTracked() then
            Tint(GLYPH_HOVER, 1)
        end
        BR.ShowTooltip(self, L["Externals.Sound"], Describe(), "ANCHOR_RIGHT")
    end)

    btn:SetScript("OnLeave", function()
        btn.Update()
        BR.HideTooltip()
    end)

    btn:SetScript("OnClick", function(self)
        if not IsTracked() then
            return
        end
        BR.Options.Dialogs.BuffPanel.ShowSound({
            title = BR.GetExternalLabel(entry),
            icon = C_Spell.GetSpellTexture(entry.spellIDs[1]),
            model = model,
        }, self)
    end)

    btn.Update()
    return btn
end

---One row: enable checkbox, spell icon, name, sound glyph.
local function RenderRow(parent, x, y, entry, rowWidth, updaters)
    local key = entry.key
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", x, y)
    row:SetSize(rowWidth, ITEM_HEIGHT)

    local soundGlyph = CreateSoundGlyph(row, entry)
    soundGlyph:SetPoint("RIGHT", 0, 0)
    updaters[#updaters + 1] = soundGlyph.Update

    -- holderWidth 18: the label is drawn separately, so the checkbox holder only
    -- needs to cover the box itself or it would push the icon far to the right.
    local checkbox = Components.Checkbox(row, {
        label = "",
        holderWidth = 18,
        get = function()
            local enabled = Settings().entries
            return enabled ~= nil and enabled[key] == true
        end,
        onChange = function(checked)
            local settings = Settings()
            settings.entries = settings.entries or {}
            -- nil rather than false: keeps SavedVariables free of dead keys.
            settings.entries[key] = checked or nil
            soundGlyph.Update()
            BR.CallbackRegistry:TriggerEvent("ExternalsRefresh")
        end,
    })
    checkbox:SetPoint("LEFT", 0, 0)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    icon:SetTexture(C_Spell.GetSpellTexture(entry.spellIDs[1]) or FALLBACK_ICON)
    icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    label:SetPoint("RIGHT", soundGlyph, "LEFT", -GLYPH_GAP, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(BR.GetExternalLabel(entry))

    return y - ITEM_HEIGHT
end

local function RenderColumn(parent, x, y, sectionKeys, colWidth, updaters)
    local rowsX = x + ROW_INDENT
    local rowWidth = colWidth - ROW_INDENT

    for i, sectionKey in ipairs(sectionKeys) do
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", x, y)
        header:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        header:SetText(L[SECTION_BY_KEY[sectionKey].titleKey])

        y = y - HEADER_TO_ROWS_GAP

        for _, entry in ipairs(entriesBySection[sectionKey] or {}) do
            y = RenderRow(parent, rowsX, y, entry, rowWidth, updaters)
        end

        if i < #sectionKeys then
            y = y - INTER_SECTION_GAP
        end
    end

    return y
end

local function Build(content, scrollFrame)
    local contentWidth = scrollFrame:GetContentWidth()
    local layout = Components.VerticalLayout(content, { x = COL_PADDING, y = PAGE_TOP_PADDING })

    BR.Options.Helpers.LayoutSectionNote(layout, content, L["Externals.PageNote"])

    local soundRow = CreateFrame("Frame", nil, content)
    soundRow:SetSize(contentWidth - COL_PADDING * 2, 26)

    local soundDrop = Components.Dropdown(soundRow, {
        label = L["Externals.Sound"],
        width = 200,
        maxItems = 15,
        options = BR.Sounds.BuildOptions(),
        tooltip = { title = L["Externals.Sound"], desc = L["Externals.Sound.Tooltip"] },
        get = function()
            return Settings().sound or BR.Sounds.NO_SOUND
        end,
        onChange = function(val)
            BR.Config.Set("externals.sound", val ~= BR.Sounds.NO_SOUND and val or nil)
            Components.RefreshAll()
        end,
    })
    soundDrop:SetPoint("LEFT", 0, 0)

    local preview = BR.Options.Helpers.SoundPreviewButton(soundRow, function()
        return Settings().sound
    end)
    preview:SetPoint("LEFT", soundDrop, "RIGHT", 8, 0)
    layout:Add(soundRow, 26, 16)

    local updaters = {}

    local colWidth = floor((contentWidth - COL_PADDING * 3) / 2)
    local startY = layout:GetY()
    local leftEndY = RenderColumn(content, COL_PADDING, startY, LEFT_SECTIONS, colWidth, updaters)
    local rightX = COL_PADDING + colWidth + COL_PADDING
    local rightEndY = RenderColumn(content, rightX, startY, RIGHT_SECTIONS, colWidth, updaters)

    content:SetHeight(max(abs(leftEndY), abs(rightEndY)) + 16)

    -- Persistent hook rather than per-widget `enabled`: a glyph is a plain button,
    -- not a component holder, so RefreshAll would never reach it. This repaints the
    -- column after the shared sound changes and on every page activation.
    tinsert(BR.RefreshableComponents, {
        Refresh = function()
            for _, Update in ipairs(updaters) do
                Update()
            end
        end,
    })
end

BR.Options.Pages.externals = {
    title = L["Externals.Title"],
    Build = Build,
}

-- The whole page is new, so it lights a notification dot on its sidebar button and
-- bubbles up to the Buffs group header until the panel is closed. Static Register
-- (not a provider) because there is nothing here that finishes populating later.
BR.Options.WhatsNew.Register({ cohort = "6.4.0", pageId = "externals" })
