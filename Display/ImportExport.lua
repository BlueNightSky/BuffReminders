local _, BR = ...

-- ============================================================================
-- IMPORT/EXPORT FUNCTIONS
-- ============================================================================

local EXPORT_PREFIX = "!BR_"

-- Deep copy a table
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Serialize a Lua table to a base64-encoded CBOR string
local function SerializeTable(tbl)
    local success, cbor = pcall(C_EncodingUtil.SerializeCBOR, tbl)
    if not success then
        return nil
    end
    return C_EncodingUtil.EncodeBase64(cbor)
end

-- Deserialize a base64-encoded CBOR string back to a Lua table
local function DeserializeTable(str)
    if not str or str:trim() == "" then
        return nil, "Empty input"
    end

    local success, decoded = pcall(C_EncodingUtil.DecodeBase64, str)
    if not success or not decoded then
        return nil, "Invalid format: not valid base64"
    end

    local ok, data = pcall(C_EncodingUtil.DeserializeCBOR, decoded)
    if not ok or type(data) ~= "table" then
        return nil, "Invalid data: failed to deserialize"
    end

    return data
end

-- Export current settings to a serialized string (only includes valid settings from defaults + customBuffs)
local function ExportSettings()
    local defaults = BR.Display.defaults
    local export = {}

    -- Only export fields that exist in defaults
    for key in pairs(defaults) do
        if BR.profile[key] ~= nil then
            export[key] = DeepCopy(BR.profile[key])
        end
    end

    -- Also include custom buffs
    if BR.profile.customBuffs then
        export.customBuffs = DeepCopy(BR.profile.customBuffs)
    end

    local result = SerializeTable(export)
    if not result then
        return nil, "Failed to serialize settings"
    end
    return result
end

-- Import settings from a serialized string (full replacement of exported keys)
local function ImportSettings(str)
    local defaults = BR.Display.defaults
    local data, err = DeserializeTable(str)
    if not data then
        return false, err
    end

    -- Wipe all exportable keys first so import is a full replacement, not a merge.
    -- This ensures keys present in the current profile but absent from the import
    -- string are cleared (e.g. old customBuffs, disabled enabledBuffs entries).
    for key in pairs(defaults) do
        if key ~= "minimap" then
            BR.profile[key] = nil
        end
    end
    BR.profile.customBuffs = nil

    -- Apply imported data
    for k, v in pairs(data) do
        BR.profile[k] = DeepCopy(v)
    end

    -- Ensure defaults sub-table exists and has the metatable (DeepCopy produces
    -- a plain table, and old export strings may not include a defaults key at all).
    if not BR.profile.defaults then
        BR.profile.defaults = {}
    end
    setmetatable(BR.profile.defaults, { __index = defaults.defaults })

    return true
end

-- ============================================================================
-- PUBLIC API (for external addon integration)
-- ============================================================================

--- PUBLIC API — used by Wago UI and other external addons. Do not remove or rename.
--- Export settings to a prefixed string that can be imported by other addons
--- @param profileKey string|nil Optional profile name (ignored - exports the active profile)
--- @return string|nil Encoded settings string with !BR_ prefix, or nil on error
--- @return string|nil Error message if export failed
function BuffReminders:Export(profileKey)
    local exportString, err = ExportSettings()
    if not exportString then
        return nil, err
    end
    return EXPORT_PREFIX .. exportString
end

--- PUBLIC API — used by Wago UI and other external addons. Do not remove or rename.
--- Import settings from a prefixed string
--- @param importString string The encoded settings string (must start with !BR_)
--- @param profileKey string|nil Optional profile name (ignored - imports into the active profile)
--- @return boolean success Whether the import succeeded
--- @return string|nil error Error message if import failed
function BuffReminders:Import(importString, profileKey)
    if not importString or type(importString) ~= "string" then
        return false, "Invalid import string"
    end

    -- Validate prefix
    if importString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid import string (missing prefix)"
    end

    -- Strip prefix and import
    local dataString = importString:sub(#EXPORT_PREFIX + 1)
    return ImportSettings(dataString)
end

-- Export module
BR.ImportExport = {
    DeepCopy = DeepCopy,
    Export = ExportSettings,
    Import = ImportSettings,
}
