local _, ns = ...
local Noctis = ns

------------------------------------------------------------------------
-- Register frames for the shared fader system
------------------------------------------------------------------------

Noctis:RegisterFaderElement({
    key = "EssentialCooldowns",
    displayName = "Essential Cooldowns",
    frameCandidates = { "EssentialCooldownViewer" },
    hookChildren = true,
    defaultEnabled = true,
})

Noctis:RegisterFaderElement({
    key = "PlayerFrame",
    displayName = "Player Frame",
    frameCandidates = { "PlayerFrame" },
    hookChildren = true,
    defaultEnabled = true,
})

Noctis:RegisterFaderElement({
    key = "TargetFrame",
    displayName = "Target Frame",
    frameCandidates = { "TargetFrame" },
    hookChildren = true,
    defaultEnabled = true,
})

Noctis:RegisterFaderElement({
    key = "Minimap",
    displayName = "Minimap",
    frameCandidates = { "MinimapCluster" },
    hookChildren = true,
    defaultEnabled = true,
})

Noctis:RegisterFaderElement({
    key = "VehicleSeat",
    displayName = "Vehicle Seat",
    frameCandidates = { "VehicleSeatIndicator" },
    hookChildren = true,
    defaultEnabled = true,
})

Noctis:RegisterFaderElement({
    key = "MicroMenu",
    displayName = "Micro Menu",
    frameCandidates = { "MicroMenuContainer" },
    hookChildren = true,
    defaultEnabled = true,
})
