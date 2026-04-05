local _, ns = ...
local Noctis = ns

------------------------------------------------------------------------
-- Blizzard Settings Panel
------------------------------------------------------------------------

local function InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Noctis")
    Noctis.categoryID = category:GetID()

    -- Let each module register its own settings
    for name, module in pairs(Noctis.modules) do
        local db = Noctis.db.modules[name]
        if db and module.RegisterSettings then
            -- Add a header for the module
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(module.displayName))
            module:RegisterSettings(category, layout, db)
        end
    end

    Settings.RegisterAddOnCategory(category)
end

------------------------------------------------------------------------
-- Open settings panel helper
------------------------------------------------------------------------

local function OpenSettings()
    if Noctis.categoryID then
        Settings.OpenToCategory(Noctis.categoryID)
    end
end

------------------------------------------------------------------------
-- Minimap Button (LibDataBroker + LibDBIcon)
------------------------------------------------------------------------

local function InitializeMinimapButton()
    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not ldb or not icon then return end

    local dataObj = ldb:NewDataObject("Noctis", {
        type = "launcher",
        icon = "Interface\\AddOns\\Noctis\\icon",
        OnClick = function(_, button)
            if button == "LeftButton" then
                OpenSettings()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Noctis")
            tooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
        end,
    })

    icon:Register("Noctis", dataObj, Noctis.db.minimap)
end

------------------------------------------------------------------------
-- Addon Compartment (Blizzard built-in, 10.0.0+)
------------------------------------------------------------------------

function Noctis_OnAddonCompartmentClick(_, button)
    if button == "LeftButton" then
        OpenSettings()
    end
end

------------------------------------------------------------------------
-- Slash Command
------------------------------------------------------------------------

SLASH_NOCTIS1 = "/noctis"
SlashCmdList["NOCTIS"] = function()
    OpenSettings()
end

------------------------------------------------------------------------
-- Initialization — called from Core.lua after PLAYER_LOGIN
------------------------------------------------------------------------

function Noctis:InitializeConfig() -- luacheck: ignore 212
    InitializeSettings()
    InitializeMinimapButton()
end
