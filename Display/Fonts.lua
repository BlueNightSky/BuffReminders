---@class BR
local _, BR = ...

-- Fonts for the display layer: reminder icons, movers, secure overlays, and
-- the externals tracker. The options panel typeface is a separate system
-- (UI/Fonts.lua).
--
-- At login the client can report a successful SetFont without a real apply,
-- and can revert a verified apply when the async load of the font file
-- completes. Every apply is therefore verified with a GetFont read-back,
-- and the shared Font objects are re-verified for a while after login.

local LSM = LibStub("LibSharedMedia-3.0")
local abs = math.abs

-- The stock client font, captured at file load, before any addon can
-- reassign the STANDARD_TEXT_FONT global at login. The client preloads this
-- file for its own UI, so a fallback to it always applies.
local CLIENT_FONT = STANDARD_TEXT_FONT

-- Resolved from saved settings by Resolve().
local fontPath = STANDARD_TEXT_FONT

-- "NONE" in saved settings maps to "" at the WoW API level.
local outlineFlag = "OUTLINE"

-- All Font objects are built at this height. Per-fontstring sizes are text
-- scales (size / BASE_HEIGHT), so a size change never touches the font API.
local BASE_HEIGHT = 20

---One verified font apply on any FontInstance. The return value of SetFont
---is ignored: fontstrings can return `true` without a real apply, and Font
---objects return nothing. Only a GetFont read-back that matches the request
---counts as success. Outline flags are not compared - the client reformats
---the flags string.
---@param target FontInstance any Font object, fontstring, or edit box
---@param path string
---@param size number
---@param outline string
---@return boolean applied true when the face and size are on the target
local function TrySetFont(target, path, size, outline)
    if not pcall(target.SetFont, target, path, size, outline) then
        return false
    end
    local okRead, appliedPath, appliedSize = pcall(target.GetFont, target)
    return okRead and appliedPath == path and appliedSize ~= nil and abs(appliedSize - size) < 0.5
end

-- Shared Font objects, one per outline variant in use.
-- healthy = the configured face passed a verified apply on the object.
local fontObjects = {} ---@type table<string, Font>
local objectHealthy = {} ---@type table<string, boolean>
local objectCount = 0

local ScheduleReassert -- defined below

---Apply the configured face to one Font object, with fallbacks. The object
---must always carry a font: SetText on a fontstring linked to a font-less
---object raises an error.
---@param outline string
local function AssertObject(outline)
    local obj = fontObjects[outline]
    if TrySetFont(obj, fontPath, BASE_HEIGHT, outline) then
        objectHealthy[outline] = true
        return
    end
    objectHealthy[outline] = false
    -- Fallback chain: the live STANDARD_TEXT_FONT (another addon can swap
    -- it game-wide), then the stock client font.
    if fontPath == STANDARD_TEXT_FONT or not TrySetFont(obj, STANDARD_TEXT_FONT, BASE_HEIGHT, outline) then
        pcall(obj.SetFont, obj, CLIENT_FONT, BASE_HEIGHT, outline)
    end
    ScheduleReassert()
end

---Re-apply every object that the client reverted or never accepted.
local function ReassertObjects()
    for outline, obj in pairs(fontObjects) do
        local okRead, path, size = pcall(obj.GetFont, obj)
        local intact = okRead and path == fontPath and size ~= nil and abs(size - BASE_HEIGHT) < 0.5
        if not intact then
            AssertObject(outline)
        else
            objectHealthy[outline] = true
        end
    end
end

---@param outline string
---@return Font
local function GetObject(outline)
    local obj = fontObjects[outline]
    if not obj then
        objectCount = objectCount + 1
        obj = CreateFont("BuffRemindersDisplayFont" .. objectCount)
        fontObjects[outline] = obj
        AssertObject(outline)
    end
    return obj
end

-- Retry timer for objects that failed a verified apply (for example, the
-- face file is not loadable yet). The cap stops the timer for a face that
-- never loads. Resolve resets the budget when the face changes.
local reassertScheduled = false
local reassertCount = 0
local MAX_REASSERTS = 10

ScheduleReassert = function()
    if reassertScheduled or reassertCount >= MAX_REASSERTS then
        return
    end
    reassertScheduled = true
    reassertCount = reassertCount + 1
    C_Timer.After(1.5, function()
        reassertScheduled = false
        ReassertObjects()
    end)
end

local fontProbe = UIParent:CreateFontString(nil, "BACKGROUND")
fontProbe:Hide()
local fontPathValidCache = {}

---Report whether the WoW client can load a font file path (the options font
---picker filters the LSM list through this). The cache keeps successes
---only: a failure can be a first-use transient, so the next call probes the
---path again.
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

---A loadability probe must not gate the result: a probe at login can fail
---for a face that loads a moment later.
local function Resolve()
    local defaults = BR.profile and BR.profile.defaults
    local fontName = defaults and defaults.fontFace
    local path = fontName and LSM:Fetch("font", fontName)
    path = path or STANDARD_TEXT_FONT

    local outline = defaults and defaults.textOutline
    if outline == "NONE" then
        outline = ""
    else
        outline = outline or "OUTLINE"
    end

    if path ~= fontPath then
        -- A new face gets a fresh retry budget.
        reassertCount = 0
    end
    fontPath = path
    outlineFlag = outline
    ReassertObjects()
end

---Link a fontstring to the shared font and set its pixel size as a text
---scale. Safe to call from render paths on every pass. Edit boxes have no
---SetTextScale, so they get a direct verified apply with fallback.
---@param fs FontString|EditBox any FontInstance
---@param size number pixel size
---@param outline? string overrides the shared outlineFlag (e.g. "" for edit boxes)
---@return boolean healthy true when the configured face is on the shared object
local function Apply(fs, size, outline)
    outline = outline or outlineFlag
    if fs.SetTextScale then
        local obj = GetObject(outline)
        if fs:GetFontObject() ~= obj then
            fs:SetFontObject(obj)
        end
        local scale = size / BASE_HEIGHT
        if abs(fs:GetTextScale() - scale) > 0.001 then
            fs:SetTextScale(scale)
        end
        return objectHealthy[outline] == true
    end
    if TrySetFont(fs, fontPath, size, outline) then
        return true
    end
    if fontPath ~= STANDARD_TEXT_FONT then
        TrySetFont(fs, STANDARD_TEXT_FONT, size, outline)
    end
    return false
end

BR.DisplayFonts = {
    Resolve = Resolve,
    GetFontPath = function()
        return fontPath
    end,
    GetOutline = function()
        return outlineFlag
    end,
    IsFontPathValid = IsFontPathValid,
    Apply = Apply,
    ---Measured size of a fontstring's current text. GetStringWidth/Height
    ---do not include the text scale, so it is multiplied back in here.
    ---@param fs FontString
    ---@return number width
    ---@return number height
    GetStringSize = function(fs)
        local scale = (fs.GetTextScale and fs:GetTextScale()) or 1
        return fs:GetStringWidth() * scale, fs:GetStringHeight() * scale
    end,
}

-- LSM can change what Fetch returns after login: a late registration of the
-- configured face, or a global override (LSM 12 SetGlobal makes every Fetch
-- return the override).
local function OnMediaChanged(_, mediatype)
    if mediatype == "font" then
        Resolve()
    end
end
LSM.RegisterCallback(BR.DisplayFonts, "LibSharedMedia_Registered", OnMediaChanged)
LSM.RegisterCallback(BR.DisplayFonts, "LibSharedMedia_SetGlobal", OnMediaChanged)

-- Zone-change loading screens pass neither flag and stay excluded.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi)
    if not (isInitialLogin or isReloadingUi) then
        return
    end
    C_Timer.NewTicker(5, ReassertObjects, 6)
end)
