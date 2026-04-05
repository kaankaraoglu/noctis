local _, ns = ...
local Noctis = ns

------------------------------------------------------------------------
-- Register frame for the shared fader system
------------------------------------------------------------------------

Noctis:RegisterFaderElement({
    key = "EssentialCooldowns",
    displayName = "Essential Cooldowns",
    frameCandidates = { "EssentialCooldownViewer" },
    hookChildren = true,
    defaultEnabled = true,
})

------------------------------------------------------------------------
-- Module skeleton for future non-fader features
------------------------------------------------------------------------

local EssentialCooldowns = {
    name = "EssentialCooldowns",
    displayName = "Essential Cooldowns",
    defaults = {
        enabled = true,
    },
}

function EssentialCooldowns:OnEnable() end   -- luacheck: ignore 212/self
function EssentialCooldowns:OnDisable() end  -- luacheck: ignore 212/self

Noctis:RegisterModule(EssentialCooldowns)
