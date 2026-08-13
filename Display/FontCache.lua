---@class BR
local _, BR = ...

-- Shared font handling for the display layer: reminder icons, movers, secure
-- overlays, and the externals tracker (the options panel typeface is a
-- separate system, see UI/Fonts.lua). The module resolves the configured LSM
-- face when the setting changes and memoizes per fontstring.

local LSM = LibStub("LibSharedMedia-3.0")

-- Cached font path - resolved once on load and updated when the setting changes (via VisualsRefresh).
-- All SetFont calls read this local directly instead of calling LSM:Fetch() every time.
local fontPath = STANDARD_TEXT_FONT

-- LSM can register fonts whose file assets can't be loaded (e.g. another addon points to
-- a missing TTF). We probe each path with a hidden FontString + pcall so we never hand a
-- broken path to SetFont, which would hard-error and break the display / options panel.
local fontProbe = UIParent:CreateFontString(nil, "BACKGROUND")
fontProbe:Hide()
local fontPathValidCache = {}

---Check whether a font file path is loadable by the WoW client (the options
---font picker filters the LSM list through this)
---@param path string? LSM-resolved font file path
---@return boolean valid true if path is non-nil and SetFont succeeds
local function IsFontPathValid(path)
    if not path then
        return false
    end
    local cached = fontPathValidCache[path]
    if cached ~= nil then
        return cached
    end
    local ok = pcall(fontProbe.SetFont, fontProbe, path, 12, "")
    fontPathValidCache[path] = ok
    return ok
end

-- Cached outline flag - resolved on load and updated when the setting changes (via VisualsRefresh).
-- "NONE" in saved settings is translated to "" at the WoW API level.
local outlineFlag = "OUTLINE"

---Resolve the font path and outline flag from saved settings and update the caches
local function Resolve()
    local fontName = BR.profile and BR.profile.defaults and BR.profile.defaults.fontFace
    if fontName then
        local path = LSM:Fetch("font", fontName)
        if IsFontPathValid(path) then
            fontPath = path
        else
            fontPath = STANDARD_TEXT_FONT
        end
    else
        fontPath = STANDARD_TEXT_FONT
    end

    local value = BR.profile and BR.profile.defaults and BR.profile.defaults.textOutline
    if value == "NONE" then
        outlineFlag = ""
    elseif value == nil then
        outlineFlag = "OUTLINE"
    else
        outlineFlag = value
    end
end

---@class BRFontString: FontString
---@field _br_font_size number?   -- last font size applied via SetFontCached
---@field _br_font_path string?   -- last font path applied via SetFontCached
---@field _br_font_outline string? -- last outline flag applied via SetFontCached

---Apply the shared font (fontPath/outlineFlag) to a fontstring only when
---something actually changed. SetFont forces a full fontstring re-layout, and
---render paths re-apply fonts up to twice per second with unchanged values.
---@param fs BRFontString|FontString|EditBox any FontInstance (edit boxes included)
---@param size number
---@param outline? string overrides the shared outlineFlag (e.g. "" for edit boxes)
local function SetFontCached(fs, size, outline)
    outline = outline or outlineFlag
    if fs._br_font_size == size and fs._br_font_path == fontPath and fs._br_font_outline == outline then
        return
    end
    fs._br_font_size = size
    fs._br_font_path = fontPath
    fs._br_font_outline = outline
    fs:SetFont(fontPath, size, outline)
end

BR.FontCache = {
    Resolve = Resolve,
    GetFontPath = function()
        return fontPath
    end,
    GetOutline = function()
        return outlineFlag
    end,
    IsFontPathValid = IsFontPathValid,
    SetFontCached = SetFontCached,
}
