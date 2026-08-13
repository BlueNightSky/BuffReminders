---@class BR
local _, BR = ...

-- Shared font handling for the display layer: reminder icons, movers, secure
-- overlays, and the externals tracker (the options panel typeface is a
-- separate system, see UI/Fonts.lua). The module resolves the configured LSM
-- face when the setting changes, applies it with fallback, and memoizes per
-- fontstring.

local LSM = LibStub("LibSharedMedia-3.0")

-- Cached font path - resolved once on load and updated when the setting changes (via VisualsRefresh).
-- All SetFont calls read this local directly instead of calling LSM:Fetch() every time.
local fontPath = STANDARD_TEXT_FONT

-- Cached outline flag - resolved on load and updated when the setting changes (via VisualsRefresh).
-- "NONE" in saved settings is translated to "" at the WoW API level.
local outlineFlag = "OUTLINE"

---One guarded SetFont attempt. The pcall catches paths that raise a hard
---error (for example, a missing TTF that another addon registered in LSM).
---The boolean return catches faces that the client cannot load yet. SetFont
---reports those with `false` instead of an error. The client loads addon
---font files on first use, so the first SetFont of a session can fail while
---a later call succeeds.
---@param fs FontString|EditBox any FontInstance
---@param path string
---@param size number
---@param outline string
---@return boolean applied true when the face is now on the font instance
local function TrySetFont(fs, path, size, outline)
    local ok, valid = pcall(fs.SetFont, fs, path, size, outline)
    return ok and valid == true
end

local fontProbe = UIParent:CreateFontString(nil, "BACKGROUND")
fontProbe:Hide()
local fontPathValidCache = {}

---Report whether the WoW client can load a font file path (the options font
---picker filters the LSM list through this).
---The cache keeps successes only. A failure can be the first-use transient,
---so the next call probes the path again.
---@param path string? LSM-resolved font file path
---@return boolean valid true if path is non-nil and SetFont succeeds
local function IsFontPathValid(path)
    if not path then
        return false
    end
    if fontPathValidCache[path] then
        return true
    end
    local valid = TrySetFont(fontProbe, path, 12, "")
    if valid then
        fontPathValidCache[path] = true
    end
    return valid
end

---Resolve the font path and outline flag from saved settings and update the
---caches. This function does not probe the path. ApplyFont handles unloadable
---faces at apply time. A probe at login can fail for a face that loads a
---moment later, and the fallback then stays until the next resolve.
local function Resolve()
    local defaults = BR.profile and BR.profile.defaults
    local fontName = defaults and defaults.fontFace
    local path = fontName and LSM:Fetch("font", fontName)
    fontPath = path or STANDARD_TEXT_FONT

    local outline = defaults and defaults.textOutline
    if outline == "NONE" then
        outlineFlag = ""
    else
        outlineFlag = outline or "OUTLINE"
    end
end

---@class BRFontString: FontString
---@field _br_font_size number?   -- last font size applied via SetFontCached
---@field _br_font_path string?   -- the path that SetFontCached applied (fallback, or nil on failure)
---@field _br_font_outline string? -- last outline flag applied via SetFontCached

---Apply the shared font face at the given size, with fallback. If the face
---fails to load, the client font keeps the text at the correct size. Callers
---that memoize must record the applied path and retry while it differs from
---fontPath. Then a load failure at login corrects itself on a later pass.
---@param fs FontString|EditBox any FontInstance
---@param size number
---@param outline? string overrides the shared outlineFlag
---@return string? appliedPath the path now on the font instance, nil if no call landed
local function ApplyFont(fs, size, outline)
    outline = outline or outlineFlag
    if TrySetFont(fs, fontPath, size, outline) then
        return fontPath
    end
    if fontPath ~= STANDARD_TEXT_FONT and TrySetFont(fs, STANDARD_TEXT_FONT, size, outline) then
        return STANDARD_TEXT_FONT
    end
    return nil
end

---Apply the shared font (fontPath/outlineFlag) to a fontstring only when
---something changed. SetFont forces a full fontstring re-layout, and render
---paths re-apply fonts up to twice per second with unchanged values. The
---memo stores the applied path. After a fallback or a failed call, each
---later call retries the desired face until it lands.
---@param fs BRFontString|FontString|EditBox any FontInstance (edit boxes included)
---@param size number
---@param outline? string overrides the shared outlineFlag (e.g. "" for edit boxes)
---@return boolean applied true when the desired face is on the fontstring
local function SetFontCached(fs, size, outline)
    outline = outline or outlineFlag
    if fs._br_font_size == size and fs._br_font_path == fontPath and fs._br_font_outline == outline then
        return true
    end
    local applied
    if TrySetFont(fs, fontPath, size, outline) then
        applied = fontPath
    elseif fs._br_font_size == size and fs._br_font_path == STANDARD_TEXT_FONT and fs._br_font_outline == outline then
        -- The fontstring already has the fallback at this size, so skip the re-layout.
        applied = STANDARD_TEXT_FONT
    elseif fontPath ~= STANDARD_TEXT_FONT and TrySetFont(fs, STANDARD_TEXT_FONT, size, outline) then
        applied = STANDARD_TEXT_FONT
    end
    fs._br_font_size = size
    fs._br_font_path = applied
    fs._br_font_outline = outline
    return applied == fontPath
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
    ApplyFont = ApplyFont,
    SetFontCached = SetFontCached,
}
