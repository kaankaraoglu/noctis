local _, ns = ...
local Noctis = ns

------------------------------------------------------------------------
-- Module Definition
------------------------------------------------------------------------

local EssentialCooldowns = {
    name = "EssentialCooldowns",
    displayName = "Essential Cooldowns",
    defaults = {
        enabled = true,
        fader = {
            enabled = true,
            alpha = 0.3,
        },
    },
}

-- Frame reference cache
local cooldownFrame = nil
-- Track whether hooks have been installed (HookScript can't be undone)
local hooksInstalled = false

------------------------------------------------------------------------
-- Frame Discovery
-- The Cooldown Manager was added in 11.1.5. The frame name must be
-- verified in-game with /framestack. We try known candidates.
------------------------------------------------------------------------

local FRAME_CANDIDATES = {
    "EssentialCooldownViewer",
}

local function FindCooldownFrame()
    for _, name in ipairs(FRAME_CANDIDATES) do
        local frame = _G[name]
        if frame and type(frame.SetAlpha) == "function" then
            return frame
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Fader Feature
------------------------------------------------------------------------

local FADE_DURATION = 0.2

local function ApplyFaderAlpha(db)
    if not cooldownFrame then return end
    if not db.fader.enabled then return end
    Noctis:SetSafeAlpha(cooldownFrame, db.fader.alpha)
end

local function InstallFaderHooks(db)
    if hooksInstalled then return end
    if not cooldownFrame then return end
    hooksInstalled = true

    cooldownFrame:HookScript("OnEnter", function()
        if not db.fader.enabled then return end
        if UIFrameFadeIn then
            UIFrameFadeIn(cooldownFrame, FADE_DURATION, cooldownFrame:GetAlpha(), 1.0)
        else
            Noctis:SetSafeAlpha(cooldownFrame, 1.0)
        end
    end)

    cooldownFrame:HookScript("OnLeave", function()
        if not db.fader.enabled then return end
        if UIFrameFadeOut then
            UIFrameFadeOut(cooldownFrame, FADE_DURATION, cooldownFrame:GetAlpha(), db.fader.alpha)
        else
            Noctis:SetSafeAlpha(cooldownFrame, db.fader.alpha)
        end
    end)
end

------------------------------------------------------------------------
-- Module Lifecycle
------------------------------------------------------------------------

local MAX_RETRIES = 10
local RETRY_INTERVAL = 2

function EssentialCooldowns:OnEnable(db) -- luacheck: ignore 212/self
    cooldownFrame = FindCooldownFrame()
    if cooldownFrame then
        InstallFaderHooks(db)
        ApplyFaderAlpha(db)
        return
    end

    -- Frame not found — Blizzard_CooldownViewer may load late. Retry periodically.
    local retries = 0
    local function RetryDiscovery()
        retries = retries + 1
        cooldownFrame = FindCooldownFrame()
        if cooldownFrame then
            InstallFaderHooks(db)
            ApplyFaderAlpha(db)
        elseif retries < MAX_RETRIES then
            C_Timer.After(RETRY_INTERVAL, RetryDiscovery)
        else
            print("|cFFFF6600Noctis:|r Essential Cooldowns frame not found after " .. MAX_RETRIES .. " attempts. The fader feature is disabled.")
        end
    end
    C_Timer.After(RETRY_INTERVAL, RetryDiscovery)
end

function EssentialCooldowns:OnDisable() -- luacheck: ignore 212/self
    -- Restore full opacity. Hooks will no-op because db.fader.enabled
    -- is checked inside them (controlled by the parent module toggle).
    if cooldownFrame then
        Noctis:SetSafeAlpha(cooldownFrame, 1.0)
    end
end

------------------------------------------------------------------------
-- Settings Registration
------------------------------------------------------------------------

function EssentialCooldowns:RegisterSettings(category, layout, db)
    -- Module master toggle
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "Enable Essential Cooldowns",
            "enabled",
            db,
            type(true),
            "Enable or disable all Essential Cooldowns customizations",
            self.defaults.enabled
        )
        setting:SetValueChangedCallback(function(_, value)
            if value then
                self:OnEnable(db)
            else
                self:OnDisable()
            end
        end)
        Settings.CreateCheckbox(category, setting, "Enable or disable all Essential Cooldowns customizations")
    end

    -- Fader sub-header
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Fader"))

    -- Fader enable toggle
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "Enable Fader",
            "enabled",
            db.fader,
            type(true),
            "Fade the Essential Cooldowns bar to a resting opacity",
            self.defaults.fader.enabled
        )
        setting:SetValueChangedCallback(function(_, value)
            if not cooldownFrame then return end
            if value then
                ApplyFaderAlpha(db)
            else
                Noctis:SetSafeAlpha(cooldownFrame, 1.0)
            end
        end)
        Settings.CreateCheckbox(category, setting, "Fade the Essential Cooldowns bar to a resting opacity")
    end

    -- Resting opacity slider
    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "Resting Opacity",
            "alpha",
            db.fader,
            type(0.0),
            "Opacity of the Essential Cooldowns bar when not hovered (0 = invisible, 1 = fully visible)",
            self.defaults.fader.alpha
        )
        setting:SetValueChangedCallback(function(_, value)
            if not cooldownFrame then return end
            if db.fader.enabled then
                Noctis:SetSafeAlpha(cooldownFrame, value)
            end
        end)

        local options = Settings.CreateSliderOptions(0, 1, 0.05)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%.0f%%", value * 100)
        end)
        Settings.CreateSlider(category, setting, options, "Opacity when not hovered")
    end
end

------------------------------------------------------------------------
-- Register with Noctis core
------------------------------------------------------------------------

Noctis:RegisterModule(EssentialCooldowns)
