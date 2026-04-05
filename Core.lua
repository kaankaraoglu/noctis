local addonName, ns = ...

---@class Noctis
---@field modules table<string, NoctisModule>
---@field pendingModules NoctisModule[]
---@field db NoctisDB
---@field categoryID number|nil
---@field pendingAlpha table<Frame, number>
local Noctis = ns
Noctis.modules = {}
Noctis.pendingModules = {}
Noctis.pendingAlpha = {}

-- Defaults for SavedVariables. Modules add their own defaults here at load time.
Noctis.defaults = {
    modules = {},
    minimap = { hide = false },
}

------------------------------------------------------------------------
-- Utility: merge missing keys from defaults into saved (recursive).
-- saved is updated in place. defaults is never modified.
-- Returns saved for convenience.
------------------------------------------------------------------------
local function DeepMergeMissing(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            if type(v) == "table" then
                saved[k] = {}
                DeepMergeMissing(saved[k], v)
            else
                saved[k] = v
            end
        elseif type(v) == "table" and type(saved[k]) == "table" then
            DeepMergeMissing(saved[k], v)
        end
    end
    return saved
end

Noctis.DeepMergeMissing = DeepMergeMissing

------------------------------------------------------------------------
-- Module Registry
------------------------------------------------------------------------

---@class NoctisModule
---@field name string
---@field displayName string
---@field defaults table
---@field OnEnable fun(self, db: table)
---@field OnDisable fun(self)
---@field RegisterSettings fun(self, category, layout, db: table)

--- Register a module. Called at file load time by each module.
--- The module is queued and initialized on ADDON_LOADED.
---@param module NoctisModule
function Noctis:RegisterModule(module)
    self.pendingModules[#self.pendingModules + 1] = module
end

------------------------------------------------------------------------
-- Safe Alpha Setter — respects combat lockdown and secret values
------------------------------------------------------------------------

--- Set alpha on a frame, deferring if in combat or restricted.
---@param frame Frame
---@param alpha number
function Noctis:SetSafeAlpha(frame, alpha)
    if InCombatLockdown() then
        self.pendingAlpha[frame] = alpha
        return false
    end
    if frame.HasSecretValues and frame:HasSecretValues() then
        self.pendingAlpha[frame] = alpha
        return false
    end
    frame:SetAlpha(alpha)
    return true
end

------------------------------------------------------------------------
-- Event Handling
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(loadedName)
    if loadedName ~= addonName then return end

    -- Initialize SavedVariables with defaults
    NoctisDB = NoctisDB or {}
    DeepMergeMissing(NoctisDB, Noctis.defaults)
    Noctis.db = NoctisDB

    -- Finalize module registration: merge each module's defaults
    for _, module in ipairs(Noctis.pendingModules) do
        Noctis.modules[module.name] = module
        if module.defaults then
            Noctis.defaults.modules[module.name] = module.defaults
            if not NoctisDB.modules[module.name] then
                NoctisDB.modules[module.name] = {}
            end
            DeepMergeMissing(NoctisDB.modules[module.name], module.defaults)
        end
    end
    Noctis.pendingModules = nil -- no longer needed

    eventFrame:UnregisterEvent("ADDON_LOADED")
end

local function OnPlayerLogin()
    -- Initialize settings panel and minimap button
    Noctis:InitializeConfig()

    -- Enable modules that are marked enabled in saved variables
    for name, module in pairs(Noctis.modules) do
        local db = NoctisDB.modules[name]
        if db and db.enabled then
            module:OnEnable(db)
        end
    end
    eventFrame:UnregisterEvent("PLAYER_LOGIN")
end

local function OnRegenEnabled()
    -- Flush pending alpha changes after combat ends
    for frame, alpha in pairs(Noctis.pendingAlpha) do
        if not (frame.HasSecretValues and frame:HasSecretValues()) then
            frame:SetAlpha(alpha)
            Noctis.pendingAlpha[frame] = nil
        end
    end
end

local function OnRestrictionStateChanged()
    -- Secret values may have been lifted — retry pending alpha
    for frame, alpha in pairs(Noctis.pendingAlpha) do
        if not (frame.HasSecretValues and frame:HasSecretValues()) then
            frame:SetAlpha(alpha)
            Noctis.pendingAlpha[frame] = nil
        end
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnRegenEnabled()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        OnRestrictionStateChanged()
    end
end)

-- Register for secret values event if it exists (12.0.0+)
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
    eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end
