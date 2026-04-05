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
