local _, BR = ...

-- ============================================================================
-- EXTERNALS: SOUND ALERTS
-- ============================================================================
-- Plays a sound when a tracked external lands on the player. These auras are
-- secret, so no Lua code can see one arrive: the trigger has to live in the
-- engine. AddAuraSound registers a spell ID plus a file, and the client plays it.
--
-- AddAuraSound is refused while an addon restriction is active, so a denied
-- registration waits for the lift. RemoveAuraSound carries no such restriction,
-- so removals always run and only additions defer.
--
-- A resolved sound is a file path OR a file ID, and the two go in different struct
-- fields. The wrong field is rejected silently, with no sound and no error.

local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local type = type

local Resolve = BR.Sounds.Resolve

local AddAuraSound = C_UnitAuras.AddAuraSound
local RemoveAuraSound = C_UnitAuras.RemoveAuraSound
local IsAddOnRestrictionActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive

local RESTRICTION = Enum.AddOnRestrictionType
local TRIGGER_ADDED = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
-- Same channel the addon plays its reminder sounds on (Display.lua).
local CHANNEL = "Master"

local Settings = BR.GetExternalSettings
local EntrySound = BR.GetExternalEntrySound

-- Live registrations per entry key: { sound = <path or file ID>, ids = { handle, ... } }.
local active = {}
-- Set when a registration was refused, so the lift watcher retries.
local pending = false

---True while a registration is refused. An encounter blocks it outright; a
---keystone run blocks it once combat starts.
---@return boolean
local function IsRestricted()
    if not (IsAddOnRestrictionActive and RESTRICTION) then
        return false
    end
    if IsAddOnRestrictionActive(RESTRICTION.Encounter) then
        return true
    end
    return IsAddOnRestrictionActive(RESTRICTION.ChallengeMode) and IsAddOnRestrictionActive(RESTRICTION.Combat) == true
end

---@param key string
local function Remove(key)
    local registration = active[key]
    if not registration then
        return
    end
    local ids = registration.ids
    for i = #ids, 1, -1 do
        RemoveAuraSound(ids[i])
    end
    active[key] = nil
end

---One handle per spell ID. A partial registration would read as complete on the
---next reconcile, so whatever landed is dropped and the whole entry waits.
---@param key string
---@param spellIDs number[]
---@param sound string|number A file path or a file ID
local function Register(key, spellIDs, sound)
    local ids = {}
    -- One table for the whole loop: AddAuraSound reads it synchronously.
    local info = {
        unitToken = "player",
        soundFileName = type(sound) == "string" and sound or nil,
        soundFileID = type(sound) == "number" and sound or nil,
        outputChannel = CHANNEL,
    }

    for _, spellID in ipairs(spellIDs) do
        info.spellID = spellID
        local ok, handle = pcall(AddAuraSound, TRIGGER_ADDED, info)
        if not ok or not handle then
            for i = #ids, 1, -1 do
                RemoveAuraSound(ids[i])
            end
            pending = true
            return
        end
        ids[#ids + 1] = handle
    end

    active[key] = { sound = sound, ids = ids }
end

---Sound per entry key, for the entries that must play one.
---@return table<string, string|number>
local function BuildDesired()
    local desired = {}
    local enabled = Settings().entries
    -- A sound belongs to an external the player tracks, so the entry's own
    -- checkbox is the gate.
    if not enabled then
        return desired
    end

    for _, entry in ipairs(BR.EXTERNALS) do
        if enabled[entry.key] then
            local sound = Resolve(EntrySound(entry))
            if sound then
                desired[entry.key] = sound
            end
        end
    end

    return desired
end

---Bring the engine registrations in line with the settings.
local function Reconcile()
    if not AddAuraSound then
        return
    end

    local desired = BuildDesired()

    -- Clearing the current key during traversal is legal in Lua 5.1.
    for key, registration in pairs(active) do
        if desired[key] ~= registration.sound then
            Remove(key)
        end
    end

    pending = false
    local restricted = IsRestricted()

    for _, entry in ipairs(BR.EXTERNALS) do
        local sound = desired[entry.key]
        if sound and not active[entry.key] then
            if restricted then
                pending = true
            else
                Register(entry.key, entry.spellIDs, sound)
            end
        end
    end
end

local watcher = CreateFrame("Frame")
-- Registrations do not survive a reload, so login rebuilds them all.
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
watcher:SetScript("OnEvent", function(_, event, _, state)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- state 0 = Enum.AddOnRestrictionState.Inactive. Only a lift lets a
        -- refused registration through.
        if state ~= 0 or not pending then
            return
        end
    end
    Reconcile()
end)

BR.CallbackRegistry:RegisterCallback("ExternalsRefresh", Reconcile)

BR.AuraSounds = {
    Reconcile = Reconcile,
}
