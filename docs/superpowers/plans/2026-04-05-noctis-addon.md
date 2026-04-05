# Noctis Addon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Noctis, a modular WoW 12.0.0 addon with its first feature — an opacity fader for the Essential Cooldowns bar.

**Architecture:** Module registry in Core.lua manages lifecycle and event routing. Config.lua integrates with Blizzard's modern Settings API + LibDBIcon minimap button. Each module is an independent file under Modules/ that registers itself and its settings. The addon namespace is shared via WoW's `(addonName, ns) = ...` pattern with no globals beyond `NoctisDB`.

**Tech Stack:** Lua, WoW Widget API (12.0.0), Settings API (11.0.2+), LibStub, LibDataBroker-1.1, LibDBIcon-1.0, CallbackHandler-1.0

**Testing note:** WoW addons cannot be unit-tested outside the game client. Each task includes a Lua syntax check (`luacheck` or `lua -p`) and in-game verification steps. Install `luacheck` for static analysis: `brew install luacheck`.

---

## File Map

| File | Responsibility | Task |
|------|---------------|------|
| `.gitignore` | Replace UE5 template with WoW addon ignores | 1 |
| `.gitattributes` | Replace UE5 template with WoW addon attributes | 1 |
| `Noctis.toc` | Addon manifest — version, saved vars, file list | 1 |
| `Core.lua` | Addon namespace, event frame, module registry, DeepMergeMissing, combat queue | 2 |
| `Libs/LibStub/LibStub.lua` | Library versioning (vendored) | 3 |
| `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` | Event callbacks (vendored) | 3 |
| `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` | Data objects for minimap (vendored) | 3 |
| `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` | Minimap button rendering (vendored) | 3 |
| `Config.lua` | Blizzard Settings panel, minimap button, addon compartment | 4 |
| `Modules/EssentialCooldowns.lua` | Essential Cooldowns module — fader feature with combat safety | 5 |
| `.luacheckrc` | Luacheck config for WoW globals | 1 |

---

### Task 1: Project Scaffolding — TOC, Git Config, Luacheck

**Files:**
- Replace: `.gitignore`
- Replace: `.gitattributes`
- Create: `Noctis.toc`
- Create: `.luacheckrc`

- [ ] **Step 1: Replace .gitignore with WoW addon ignores**

```gitignore
# macOS
.DS_Store

# Editor
*.swp
*~
.vs/
.idea/
*.sln
*.suo
*.user

# Superpowers brainstorming
.superpowers/

# Luacheck cache
.luacheckrc.cache
```

- [ ] **Step 2: Replace .gitattributes with WoW addon attributes**

```gitattributes
# Lua files
*.lua text eol=lf
*.toc text eol=lf
*.xml text eol=lf
*.md text eol=lf

# Images
*.tga binary
*.blp binary
*.png binary
```

- [ ] **Step 3: Create Noctis.toc**

```toc
## Interface: 120000
## Title: Noctis
## Notes: Modular UI customization
## Version: 1.0.0
## Author: kaank
## SavedVariables: NoctisDB
## LoadSavedVariablesFirst: 1
## IconTexture: Interface\AddOns\Noctis\icon
## AddonCompartmentFunc: Noctis_OnAddonCompartmentClick

Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
Libs\LibDataBroker-1.1\LibDataBroker-1.1.lua
Libs\LibDBIcon-1.0\LibDBIcon-1.0.lua

Core.lua
Config.lua
Modules\EssentialCooldowns.lua
```

- [ ] **Step 4: Create .luacheckrc for WoW Lua environment**

```lua
std = "lua51"
max_line_length = false
exclude_files = {
    "Libs/",
}
globals = {
    "NoctisDB",
    "Noctis_OnAddonCompartmentClick",
    "SLASH_NOCTIS1",
    "SlashCmdList",
}
read_globals = {
    -- WoW API
    "CreateFrame",
    "Settings",
    "UIFrameFadeIn",
    "UIFrameFadeOut",
    "InCombatLockdown",
    "print",
    "select",
    "type",
    "pairs",
    "ipairs",
    "tostring",
    "tonumber",
    "unpack",
    "math",
    "string",
    "table",
    "C_Timer",
    "GameTooltip",
    "LibStub",
    "ADDON_RESTRICTION_STATE_CHANGED",
    -- Varargs
    "...",
}
```

- [ ] **Step 5: Verify luacheck is available**

Run: `luacheck --version`
Expected: Version output (e.g., `Luacheck: 1.x.x`). If not installed, run `brew install luacheck`.

- [ ] **Step 6: Commit scaffolding**

```bash
git add .gitignore .gitattributes Noctis.toc .luacheckrc
git commit -m "scaffold: add TOC, git config, and luacheck for WoW 12.0.0 addon"
```

---

### Task 2: Core System — Namespace, Events, Module Registry

**Files:**
- Create: `Core.lua`

- [ ] **Step 1: Write Core.lua with namespace, DeepMergeMissing, event frame, and module registry**

```lua
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
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
```

- [ ] **Step 2: Run luacheck on Core.lua**

Run: `luacheck Core.lua --config .luacheckrc`
Expected: `0 warnings` (or only warnings about WoW globals we haven't added to `.luacheckrc` yet — add any missing ones).

- [ ] **Step 3: Update .luacheckrc if needed**

Add any missing WoW globals that luacheck flagged (e.g., `C_EventUtils`). The goal is zero warnings.

- [ ] **Step 4: Commit Core.lua**

```bash
git add Core.lua .luacheckrc
git commit -m "feat: add Core.lua — namespace, event handling, module registry, combat-safe alpha"
```

---

### Task 3: Vendor Libraries

**Files:**
- Create: `Libs/LibStub/LibStub.lua`
- Create: `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`
- Create: `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua`
- Create: `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`

These are standard WoW community libraries. They must be downloaded from their official sources and placed in the Libs directory.

- [ ] **Step 1: Download LibStub**

Run:
```bash
mkdir -p Libs/LibStub
curl -L "https://repos.wowace.com/wow/libstub/trunk/LibStub.lua" -o Libs/LibStub/LibStub.lua
```

Verify: File exists and starts with `-- LibStub` or similar header.

- [ ] **Step 2: Download CallbackHandler-1.0**

Run:
```bash
mkdir -p "Libs/CallbackHandler-1.0"
curl -L "https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0/CallbackHandler-1.0.lua" -o "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"
```

Verify: File exists and contains `CallbackHandler`.

- [ ] **Step 3: Download LibDataBroker-1.1**

Run:
```bash
mkdir -p "Libs/LibDataBroker-1.1"
curl -L "https://repos.wowace.com/wow/libdatabroker-1-1/trunk/LibDataBroker-1.1.lua" -o "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"
```

Verify: File exists and contains `LibDataBroker`.

- [ ] **Step 4: Download LibDBIcon-1.0**

Run:
```bash
mkdir -p "Libs/LibDBIcon-1.0"
curl -L "https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua" -o "Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"
```

Verify: File exists and contains `LibDBIcon`.

- [ ] **Step 5: Verify all library files exist**

Run: `find Libs -name "*.lua" | sort`

Expected output:
```
Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua
Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua
Libs/LibStub/LibStub.lua
```

- [ ] **Step 6: If any download failed, source from GitHub alternatives**

LibStub: `https://raw.githubusercontent.com/rxi/lite/master/data/core/init.lua` — no, use the WoW community standard. If wowace is down, try:
- LibStub: `https://raw.githubusercontent.com/tekkub/libstub/master/LibStub.lua`
- CallbackHandler: search GitHub for `CallbackHandler-1.0.lua wow`
- LibDataBroker: `https://raw.githubusercontent.com/tekkub/libdatabroker-1-1/master/LibDataBroker-1.1.lua`
- LibDBIcon: `https://raw.githubusercontent.com/tekkub/libdbicon-1-0/master/LibDBIcon-1.0/LibDBIcon-1.0.lua`

If all downloads fail, write stub files that register with LibStub and provide the minimum API surface, then replace with real libraries later.

- [ ] **Step 7: Commit vendored libraries**

```bash
git add Libs/
git commit -m "vendor: add LibStub, CallbackHandler, LibDataBroker, LibDBIcon"
```

---

### Task 4: Config System — Settings Panel, Minimap Button, Addon Compartment

**Files:**
- Create: `Config.lua`

- [ ] **Step 1: Write Config.lua**

```lua
local addonName, ns = ...
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

function Noctis:InitializeConfig()
    InitializeSettings()
    InitializeMinimapButton()
end
```

- [ ] **Step 2: Update Core.lua to call InitializeConfig on PLAYER_LOGIN**

In Core.lua, inside `OnPlayerLogin()`, add a call to `Noctis:InitializeConfig()` **before** enabling modules (so settings are registered before modules try to update them). The updated `OnPlayerLogin` function should be:

```lua
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
```

- [ ] **Step 3: Run luacheck on Config.lua**

Run: `luacheck Config.lua --config .luacheckrc`
Expected: `0 warnings`. Add any new WoW globals to `.luacheckrc` (e.g., `CreateSettingsListSectionHeaderInitializer`).

- [ ] **Step 4: Run luacheck on all project files**

Run: `luacheck Core.lua Config.lua --config .luacheckrc`
Expected: `0 warnings` across both files.

- [ ] **Step 5: Commit Config.lua and Core.lua update**

```bash
git add Config.lua Core.lua .luacheckrc
git commit -m "feat: add Config.lua — Settings panel, minimap button, addon compartment, slash command"
```

---

### Task 5: EssentialCooldowns Module — Fader Feature

**Files:**
- Create: `Modules/EssentialCooldowns.lua`

- [ ] **Step 1: Write Modules/EssentialCooldowns.lua**

```lua
local addonName, ns = ...
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
    "CooldownManagerFrame",
    "PlayerCooldownManager",
    "CooldownManagerContainer",
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

function EssentialCooldowns:OnEnable(db)
    cooldownFrame = FindCooldownFrame()
    if not cooldownFrame then
        -- Frame not found — may not be in the UI yet. Retry after a short delay.
        C_Timer.After(1, function()
            cooldownFrame = FindCooldownFrame()
            if cooldownFrame then
                InstallFaderHooks(db)
                ApplyFaderAlpha(db)
            else
                print("|cFFFF6600Noctis:|r Essential Cooldowns frame not found. The fader feature is disabled.")
            end
        end)
        return
    end
    InstallFaderHooks(db)
    ApplyFaderAlpha(db)
end

function EssentialCooldowns:OnDisable()
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
```

- [ ] **Step 2: Create Modules directory if needed**

Run: `mkdir -p Modules`

- [ ] **Step 3: Run luacheck on EssentialCooldowns.lua**

Run: `luacheck Modules/EssentialCooldowns.lua --config .luacheckrc`
Expected: `0 warnings`. Add any missing globals to `.luacheckrc` (e.g., `_G`, `MinimalSliderWithSteppersMixin`, `C_Timer`).

- [ ] **Step 4: Run luacheck on entire project**

Run: `luacheck Core.lua Config.lua Modules/EssentialCooldowns.lua --config .luacheckrc`
Expected: `0 warnings` across all files.

- [ ] **Step 5: Commit EssentialCooldowns module**

```bash
git add Modules/EssentialCooldowns.lua .luacheckrc
git commit -m "feat: add EssentialCooldowns module — fader with combat-safe alpha and Settings integration"
```

---

### Task 6: Final Integration and Cleanup

**Files:**
- Verify: all files listed in `Noctis.toc` exist
- Update: `.gitignore` if needed

- [ ] **Step 1: Verify TOC file list matches actual files**

Run:
```bash
echo "=== Files listed in TOC ===" && grep -v "^#" Noctis.toc | grep -v "^$" | while read f; do f=$(echo "$f" | tr '\\' '/'); if [ -f "$f" ]; then echo "OK: $f"; else echo "MISSING: $f"; fi; done
```

Expected: All files show `OK`. If any show `MISSING`, the library downloads in Task 3 failed and need to be resolved.

- [ ] **Step 2: Run full luacheck**

Run: `luacheck Core.lua Config.lua Modules/EssentialCooldowns.lua --config .luacheckrc`
Expected: `0 warnings`.

- [ ] **Step 3: Review for unused code or inconsistencies**

Manually review:
- `Noctis:RegisterModule()` in EssentialCooldowns.lua calls the function defined in Core.lua
- `Noctis:InitializeConfig()` in Config.lua is called by Core.lua's `OnPlayerLogin`
- `Noctis:SetSafeAlpha()` in Core.lua is used by EssentialCooldowns.lua
- `Noctis_OnAddonCompartmentClick` in Config.lua matches the TOC's `AddonCompartmentFunc`
- `NoctisDB` is the only global besides `Noctis_OnAddonCompartmentClick` and slash command globals

- [ ] **Step 4: Add .superpowers/ to .gitignore if missing**

Check if `.superpowers/` is in `.gitignore`. If not, add it.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final integration verification — all files present and lint-clean"
```

---

### Task 7: In-Game Testing Checklist (Manual)

This task is a manual checklist for the developer to verify in the WoW 12.0.0 client.

- [ ] **Step 1: Install the addon** — Copy the `Noctis/` folder to `World of Warcraft/_retail_/Interface/AddOns/Noctis/`
- [ ] **Step 2: Verify addon loads** — `/reload` in-game, check that Noctis appears in the AddOns list without errors
- [ ] **Step 3: Verify settings panel** — Open Settings > AddOns > Noctis. Confirm checkboxes and slider appear.
- [ ] **Step 4: Verify minimap button** — Confirm the Noctis minimap icon appears. Click it — should open Settings to Noctis.
- [ ] **Step 5: Verify addon compartment** — Click the addon compartment on the minimap. Noctis entry should appear. Click it — should open Settings.
- [ ] **Step 6: Verify slash command** — Type `/noctis` — should open Settings.
- [ ] **Step 7: Identify the correct frame name** — Use `/framestack` while hovering over the Essential Cooldowns bar. Note the frame name. If it doesn't match any candidate in `FRAME_CANDIDATES`, update the constant in `Modules/EssentialCooldowns.lua`.
- [ ] **Step 8: Verify fader works** — With the correct frame name, confirm the bar fades to the resting opacity.
- [ ] **Step 9: Verify hover reveal** — Hover over the faded bar. It should smoothly animate to full opacity.
- [ ] **Step 10: Verify slider live-preview** — Open Settings, adjust the Resting Opacity slider. The bar should update in real-time.
- [ ] **Step 11: Verify combat safety** — Enter combat and confirm no Lua errors. Verify the bar behaves correctly after combat ends.
- [ ] **Step 12: Verify persistence** — Change settings, `/reload`, confirm settings are preserved.
