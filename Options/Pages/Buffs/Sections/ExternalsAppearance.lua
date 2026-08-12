local _, BR = ...

-- ============================================================================
-- BUFF PAGE SECTION: Externals Appearance
-- ============================================================================
-- The whole body of the Externals tab on the Categories page. Externals are not a
-- real category (no categorySettings entry, no State entries), so they get this
-- standalone section instead of the _Template composition - none of the shared
-- sections apply: visibility is Blizzard's call, click-to-cast is impossible on a
-- forbidden button, and growth is container-level flow-layout state with LEFT/RIGHT
-- only (the flow layout has no centered growth).
--
-- Like CustomAppearance, this section is terminal: it owns the tab frame's height.

local L = BR.L
local Components = BR.Components

local LayoutSectionHeader = BR.Options.Helpers.LayoutSectionHeader
local LayoutSectionNote = BR.Options.Helpers.LayoutSectionNote

local COMPONENT_GAP = BR.Options.Constants.COMPONENT_GAP
local DROPDOWN_EXTRA = BR.Options.Constants.DROPDOWN_EXTRA

local abs = math.abs

BR.Options.BuffSections = BR.Options.BuffSections or {}

local SLIDERS = {
    { key = "iconZoom", labelKey = "Appearance.Zoom", min = 0, max = 40, suffix = "%", default = 0 },
    { key = "borderSize", labelKey = "Appearance.Border", min = 0, max = 8, suffix = "px", default = 2 },
    { key = "spacing", labelKey = "Appearance.Spacing", min = 0, max = 32, suffix = "px", default = 4 },
    { key = "durationSize", labelKey = "Externals.DurationSize", min = 8, max = 32, suffix = "px", default = 16 },
}

local Settings = BR.GetExternalSettings
local IsEnabled = BR.AreExternalsEnabled

---Width [link] Height on one row, with AppearanceGrid's coupling semantics:
---linked = iconWidth nil (square, one value), unlinked = explicit iconWidth.
local function BuildSizeRow(parent, labelWidth)
    local function isLinked()
        return Settings().iconWidth == nil
    end

    local row = CreateFrame("Frame", nil, parent)
    local widthHolder, heightHolder

    widthHolder = Components.Slider(row, {
        label = L["Appearance.Width"],
        labelWidth = labelWidth,
        min = 16,
        max = 128,
        step = 1,
        suffix = "px",
        enabled = IsEnabled,
        disabledReason = L["Externals.EnableElsewhere"],
        get = function()
            local settings = Settings()
            return settings.iconWidth or settings.iconSize or 40
        end,
        onChange = function(value)
            BR.Config.Set(isLinked() and "externals.iconSize" or "externals.iconWidth", value)
            if heightHolder then
                heightHolder:Refresh()
            end
        end,
    })
    widthHolder:SetPoint("TOPLEFT")

    local linkBtn = Components.DimensionLink(row, {
        isLinked = isLinked,
        enabled = IsEnabled,
        onLink = function()
            BR.Config.Set("externals.iconWidth", nil)
            Components.RefreshAll()
        end,
        onUnlink = function()
            BR.Config.Set("externals.iconWidth", Settings().iconSize or 40)
            Components.RefreshAll()
        end,
    })
    linkBtn:SetPoint("LEFT", widthHolder, "RIGHT", 6, 0)

    heightHolder = Components.Slider(row, {
        label = L["Appearance.Height"],
        min = 16,
        max = 128,
        step = 1,
        suffix = "px",
        enabled = IsEnabled,
        disabledReason = L["Externals.EnableElsewhere"],
        get = function()
            return Settings().iconSize or 40
        end,
        onChange = function(value)
            BR.Config.Set("externals.iconSize", value)
            if widthHolder then
                widthHolder:Refresh()
            end
        end,
    })
    heightHolder:SetPoint("LEFT", linkBtn, "RIGHT", 8, 0)

    row:SetSize(widthHolder:GetWidth() + 6 + linkBtn:GetWidth() + 8 + heightHolder:GetWidth(), 20)
    return row
end

local function Build(ctx, layout)
    local parent = ctx.content

    LayoutSectionHeader(layout, parent, L["Externals.Appearance"])
    LayoutSectionNote(layout, parent, L["Externals.AppearanceNote"])

    -- One shared label column so the tracks line up: "Countdown size" is far wider
    -- than "Zoom", and each slider would otherwise size its own label to fit.
    local labels = { L["Appearance.Width"] }
    for _, spec in ipairs(SLIDERS) do
        labels[#labels + 1] = L[spec.labelKey]
    end
    local labelWidth = Components.MeasureSharedLabelWidth(labels)

    layout:Add(BuildSizeRow(parent, labelWidth), nil, COMPONENT_GAP)

    for _, spec in ipairs(SLIDERS) do
        local key, default = spec.key, spec.default
        local slider = Components.Slider(parent, {
            label = L[spec.labelKey],
            labelWidth = labelWidth,
            min = spec.min,
            max = spec.max,
            step = 1,
            suffix = spec.suffix,
            enabled = IsEnabled,
            disabledReason = L["Externals.EnableElsewhere"],
            get = function()
                return Settings()[key] or default
            end,
            onChange = function(value)
                BR.Config.Set("externals." .. key, value)
            end,
        })
        layout:Add(slider, nil, COMPONENT_GAP)
    end

    local dirHolder = Components.Dropdown(parent, {
        label = L["Direction.Label"],
        labelWidth = labelWidth,
        options = {
            { label = L["Direction.Right"], value = "RIGHT" },
            { label = L["Direction.Left"], value = "LEFT" },
        },
        enabled = IsEnabled,
        disabledReason = L["Externals.EnableElsewhere"],
        get = function()
            return Settings().growDirection or "RIGHT"
        end,
        onChange = function(dir)
            BR.Config.Set("externals.growDirection", dir)
        end,
    })
    layout:Add(dirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

    LayoutSectionNote(layout, parent, L["Externals.MasqueNote"])

    parent:SetHeight(abs(layout:GetY()) + (ctx.appearancePadding or 30))
    if ctx.onAppearanceResize then
        ctx.onAppearanceResize()
    end
end

BR.Options.BuffSections.ExternalsAppearance = Build
