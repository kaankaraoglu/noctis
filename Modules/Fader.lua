local _, ns = ...
local Noctis = ns

------------------------------------------------------------------------
-- Module Definition
------------------------------------------------------------------------

local Fader = {
    name = "Fader",
    displayName = "Fader",
    defaults = {
        enabled = true,
        alpha = 0.3,
        elements = {},
    },
}

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local FADE_DURATION = 0.2
local LEAVE_CHECK_INTERVAL = 0.05
local MAX_RETRIES = 10
local RETRY_INTERVAL = 2

------------------------------------------------------------------------
-- Per-element runtime state (not saved)
------------------------------------------------------------------------

---@class FaderElementState
---@field descriptor FaderElementDescriptor
---@field frame table|nil
---@field hooksInstalled boolean
---@field isMouseOver boolean
---@field leaveCheckTicker table|nil

local elementStates = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

--- Check if a specific element is effectively enabled (master + per-element).
---@param db table
---@param key string
---@return boolean
local function IsElementEnabled(db, key)
    return db.enabled and db.elements[key] and db.elements[key].enabled
end

--- Check if the mouse is over a frame or any of its children.
---@param state FaderElementState
---@return boolean
--- Recursively check if the mouse is over a frame or any descendant.
---@param frame table
---@return boolean
local function IsMouseOverRecursive(frame)
    if frame:IsMouseOver() then return true end
    for _, child in ipairs({ frame:GetChildren() }) do
        if IsMouseOverRecursive(child) then return true end
    end
    return false
end

local function IsMouseOverElement(state)
    if not state.frame then return false end
    if state.descriptor.hookChildren then
        return IsMouseOverRecursive(state.frame)
    end
    return state.frame:IsMouseOver()
end

------------------------------------------------------------------------
-- Fade Animations
------------------------------------------------------------------------

local function FadeInElement(state, db)
    if not state.frame then return end
    if not IsElementEnabled(db, state.descriptor.key) then return end
    if UIFrameFadeIn then
        UIFrameFadeIn(state.frame, FADE_DURATION, state.frame:GetAlpha(), 1.0)
    else
        Noctis:SetSafeAlpha(state.frame, 1.0)
    end
end

local function FadeOutElement(state, db)
    if not state.frame then return end
    if not IsElementEnabled(db, state.descriptor.key) then return end
    if UIFrameFadeOut then
        UIFrameFadeOut(state.frame, FADE_DURATION, state.frame:GetAlpha(), db.alpha)
    else
        Noctis:SetSafeAlpha(state.frame, db.alpha)
    end
end

------------------------------------------------------------------------
-- Leave-Check Polling (per element)
------------------------------------------------------------------------

local function StopLeaveCheck(state)
    if state.leaveCheckTicker then
        state.leaveCheckTicker:Cancel()
        state.leaveCheckTicker = nil
    end
end

local function StartLeaveCheck(state, db)
    if state.leaveCheckTicker then return end
    state.leaveCheckTicker = C_Timer.NewTicker(LEAVE_CHECK_INTERVAL, function()
        if not IsMouseOverElement(state) then
            state.isMouseOver = false
            FadeOutElement(state, db)
            StopLeaveCheck(state)
        end
    end)
end

------------------------------------------------------------------------
-- Hook Installation
------------------------------------------------------------------------

local function HookFrame(frame, state, db)
    frame:HookScript("OnEnter", function()
        if not IsElementEnabled(db, state.descriptor.key) then return end
        if not state.isMouseOver then
            state.isMouseOver = true
            StopLeaveCheck(state)
            FadeInElement(state, db)
        end
    end)
    frame:HookScript("OnLeave", function()
        if not IsElementEnabled(db, state.descriptor.key) then return end
        StartLeaveCheck(state, db)
    end)
end

--- Recursively hook a frame and all its descendants.
local function HookFrameRecursive(frame, state, db)
    HookFrame(frame, state, db)
    for _, child in ipairs({ frame:GetChildren() }) do
        HookFrameRecursive(child, state, db)
    end
end

local function InstallHooks(state, db)
    if state.hooksInstalled then return end
    if not state.frame then return end
    state.hooksInstalled = true

    if state.descriptor.hookChildren then
        HookFrameRecursive(state.frame, state, db)
    else
        HookFrame(state.frame, state, db)
    end
end

------------------------------------------------------------------------
-- Frame Discovery
------------------------------------------------------------------------

local function FindFrame(candidates)
    for _, name in ipairs(candidates) do
        local frame = _G[name] -- luacheck: ignore 113
        if frame and type(frame.SetAlpha) == "function" then
            return frame
        end
    end
    return nil
end

local function DiscoverElement(state, db)
    state.frame = FindFrame(state.descriptor.frameCandidates)
    if state.frame then
        InstallHooks(state, db)
        if IsElementEnabled(db, state.descriptor.key) then
            Noctis:SetSafeAlpha(state.frame, db.alpha)
        end
        return true
    end
    return false
end

local function DiscoverElementWithRetry(state, db)
    if DiscoverElement(state, db) then return end

    local retries = 0
    local function Retry()
        retries = retries + 1
        if DiscoverElement(state, db) then return end
        if retries < MAX_RETRIES then
            C_Timer.After(RETRY_INTERVAL, Retry)
        end
    end
    C_Timer.After(RETRY_INTERVAL, Retry)
end

------------------------------------------------------------------------
-- Apply / Restore Alpha on All Elements
------------------------------------------------------------------------

local function ApplyAlphaToAll(db)
    for key, state in pairs(elementStates) do
        if state.frame then
            if IsElementEnabled(db, key) then
                Noctis:SetSafeAlpha(state.frame, db.alpha)
            end
        end
    end
end

local function RestoreAlphaToAll()
    for _, state in pairs(elementStates) do
        if state.frame then
            Noctis:SetSafeAlpha(state.frame, 1.0)
        end
    end
end

------------------------------------------------------------------------
-- Module Lifecycle
------------------------------------------------------------------------

function Fader:OnEnable(db) -- luacheck: ignore 212/self
    -- Build default element entries from registered descriptors
    for _, descriptor in ipairs(Noctis.faderElements) do
        if not db.elements[descriptor.key] then
            db.elements[descriptor.key] = { enabled = descriptor.defaultEnabled }
        end

        elementStates[descriptor.key] = {
            descriptor = descriptor,
            frame = nil,
            hooksInstalled = false,
            isMouseOver = false,
            leaveCheckTicker = nil,
        }

        DiscoverElementWithRetry(elementStates[descriptor.key], db)
    end

    -- Migration: pull old EssentialCooldowns fader settings
    local oldEC = NoctisDB.modules and NoctisDB.modules.EssentialCooldowns
    if oldEC and oldEC.fader then
        if oldEC.fader.alpha then
            db.alpha = oldEC.fader.alpha
        end
        if oldEC.fader.enabled ~= nil and db.elements.EssentialCooldowns then
            db.elements.EssentialCooldowns.enabled = oldEC.fader.enabled
        end
        oldEC.fader = nil
    end
end

function Fader:OnDisable() -- luacheck: ignore 212/self
    for _, state in pairs(elementStates) do
        StopLeaveCheck(state)
        if state.frame then
            Noctis:SetSafeAlpha(state.frame, 1.0)
        end
    end
end

------------------------------------------------------------------------
-- Settings Registration
------------------------------------------------------------------------

function Fader:RegisterSettings(category, layout, db) -- luacheck: ignore 212/self 212/layout
    -- Master toggle
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "Enable",
            "enabled",
            db,
            type(true),
            "Enable",
            Fader.defaults.enabled
        )
        setting:SetValueChangedCallback(function(_, value)
            if value then
                ApplyAlphaToAll(db)
            else
                RestoreAlphaToAll()
            end
        end)
        Settings.CreateCheckbox(category, setting, "Enable")
    end

    -- Shared opacity slider
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "Opacity",
            "alpha",
            db,
            type(0.0),
            "Resting Opacity",
            Fader.defaults.alpha
        )
        setting:SetValueChangedCallback(function(_, value) -- luacheck: ignore 212
            ApplyAlphaToAll(db)
        end)

        local options = Settings.CreateSliderOptions(0, 1, 0.05)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%.0f%%", value * 100)
        end)
        Settings.CreateSlider(category, setting, options, "Resting opacity for all faded elements (0 = invisible, 1 = fully visible)")
    end

    -- Per-element toggles
    for _, descriptor in ipairs(Noctis.faderElements) do
        local elemDB = db.elements[descriptor.key]
        if elemDB then
            local setting = Settings.RegisterAddOnSetting(
                category,
                descriptor.displayName,
                "enabled",
                elemDB,
                type(true),
                descriptor.displayName,
                descriptor.defaultEnabled
            )
            setting:SetValueChangedCallback(function(_, value)
                local state = elementStates[descriptor.key]
                if not state or not state.frame then return end
                if value and db.enabled then
                    Noctis:SetSafeAlpha(state.frame, db.alpha)
                else
                    Noctis:SetSafeAlpha(state.frame, 1.0)
                end
            end)
            Settings.CreateCheckbox(category, setting, descriptor.displayName)
        end
    end
end

------------------------------------------------------------------------
-- Register with Noctis core
------------------------------------------------------------------------

Noctis:RegisterModule(Fader)
