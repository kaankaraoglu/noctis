# Noctis — WoW Midnight (12.0.0) UI Customization Addon

## Overview

Noctis is a modular UI customization addon for World of Warcraft 12.0.0 (Midnight). Each feature is an independent module that can be toggled on or off. The first module targets the Essential Cooldowns bar with an opacity fader.

## Target Environment

- **WoW Version:** 12.0.0 Midnight (Interface: 120000)
- **Language:** Lua + WoW Widget API
- **Settings API:** Modern `Settings.RegisterVerticalLayoutCategory` / `Settings.RegisterAddOnSetting` (11.0.2+ signatures with `variableKey`/`variableTbl`)
- **Persistence:** `SavedVariables` (account-wide)

## File Structure

```
Noctis/
├── Noctis.toc                         -- Addon manifest
├── Core.lua                           -- Namespace, event handling, module registry
├── Config.lua                         -- Blizzard Settings panel + minimap button
├── Modules/
│   └── EssentialCooldowns.lua         -- Essential Cooldowns module (fader + future features)
└── Libs/
    ├── LibStub/
    ├── LibDataBroker-1.1/
    └── LibDBIcon-1.0/
```

## TOC File

```
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

Note: `CallbackHandler-1.0` is a dependency of LibDataBroker and LibDBIcon.

## SavedVariables Schema

```lua
---@class NoctisDB
---@field modules table<string, ModuleSettings>
---@field minimap MinimapSettings

---@class MinimapSettings
---@field hide boolean

---@class EssentialCooldownsSettings : ModuleSettings
---@field enabled boolean
---@field fader FaderSettings

---@class FaderSettings
---@field enabled boolean
---@field alpha number -- 0.0 to 1.0, resting opacity

NoctisDB = {
    modules = {
        EssentialCooldowns = {
            enabled = true,
            fader = {
                enabled = true,
                alpha = 0.3,
            },
        },
    },
    minimap = {
        hide = false,
    },
}
```

## Core System (Core.lua)

### Addon Namespace

A single global table `Noctis` serves as the addon namespace. All modules, utilities, and shared state live here. No pollution of the global namespace beyond `Noctis` and `NoctisDB`.

```lua
-- Standard addon namespace pattern: (addonName, ns) = ...
-- addonName is a string, ns is a private table shared across all files in this addon
local addonName, ns = ...

---@class Noctis
---@field modules table<string, NoctisModule>
---@field db NoctisDB
local Noctis = ns
Noctis.modules = {}
```

All `.lua` files in the TOC share the same `ns` table via `select(2, ...)`, so modules access the core via `local Noctis = select(2, ...)` without any globals beyond `NoctisDB`.

### Event Handling

A single event frame registered for:
- `ADDON_LOADED` — initialize SavedVariables, merge defaults, register modules
- `PLAYER_LOGIN` — enable active modules (UI frames are available at this point)
- `PLAYER_LOGOUT` — any final state writes
- `PLAYER_REGEN_ENABLED` — flush queued frame modifications after combat ends

### Module Registry

Modules register via `Noctis:RegisterModule(module)`. Each module is a table conforming to:

```lua
---@class NoctisModule
---@field name string           -- unique identifier
---@field displayName string    -- shown in settings UI
---@field OnEnable fun(self, db: table)   -- called when module is enabled
---@field OnDisable fun(self)             -- called when module is disabled
---@field RegisterSettings fun(self, category, layout, db: table)  -- adds settings to the panel
```

Registration flow:
1. Module calls `Noctis:RegisterModule(self)` at file load time
2. On `ADDON_LOADED`, Core merges module defaults into `NoctisDB.modules[name]`
3. On `PLAYER_LOGIN`, Core calls `OnEnable(db)` for each module where `db.enabled == true`

Default merging uses a `DeepMergeMissing(saved, defaults)` function that walks the defaults table and inserts any missing keys into the saved table without overwriting existing user values. The defaults table is never modified; saved is updated in place with new keys only.

## Config System (Config.lua)

### Blizzard Settings Panel

Uses `Settings.RegisterVerticalLayoutCategory("Noctis")` to create the main category.

Each module adds its own settings via `module:RegisterSettings(category, layout, db)`:
- Module-level enable/disable checkbox
- Feature-specific controls nested under the module heading

For the EssentialCooldowns module:
- **Enable Essential Cooldowns** — checkbox, maps to `NoctisDB.modules.EssentialCooldowns.enabled`
- **Enable Fader** — checkbox, maps to `...fader.enabled`
- **Resting Opacity** — slider (0.0–1.0, step 0.05), maps to `...fader.alpha`

Settings use `Settings.RegisterAddOnSetting()` with `variableKey` and `variableTbl` for direct SavedVariables binding (11.0.2+ API).

### Minimap Button

LibDataBroker + LibDBIcon provides a minimap button. On click, it opens the Blizzard Settings panel directly to the Noctis category via `Settings.OpenToCategory(categoryID)`.

### Addon Compartment

The `AddonCompartmentFunc` TOC directive registers a global `Noctis_OnAddonCompartmentClick` function that also calls `Settings.OpenToCategory(categoryID)`.

## EssentialCooldowns Module (Modules/EssentialCooldowns.lua)

### Frame Discovery

The Essential Cooldowns bar is part of the Cooldown Manager (added in Patch 11.1.5). The exact frame name must be confirmed via `/framestack` in-game. The module stores the frame name as a constant and fails gracefully if the frame is not found (prints a warning to chat, disables the feature).

Candidate frame names to verify in-game:
- `CooldownManagerFrame`
- `PlayerCooldownManager`
- `EditModeManagerFrame` children

The module will attempt discovery on `PLAYER_LOGIN` and cache the reference.

### Fader Feature

**Enable flow:**
1. Find the cooldown bar frame by global name
2. Set frame alpha to `db.fader.alpha`
3. `HookScript("OnEnter")` — fade to 1.0
4. `HookScript("OnLeave")` — fade to `db.fader.alpha`

**Fade animation:**
Uses `UIFrameFadeIn()` / `UIFrameFadeOut()` for smooth transitions (0.2s duration). Falls back to instant `SetAlpha()` if the fade API is unavailable.

**Disable flow:**
Since `HookScript` cannot be unhooked, the hooked functions check `db.fader.enabled` and early-return when disabled. On disable, alpha is restored to 1.0.

**Combat safety:**
- All `SetAlpha()` calls are guarded by `InCombatLockdown()` check
- If in combat, the desired alpha is stored in a pending queue
- On `PLAYER_REGEN_ENABLED` (combat end), pending alpha changes are applied
- If the frame reports `HasSecretValues()` (12.0.0 Secret Aspects), alpha modification is skipped entirely during that state and queued for when restrictions lift (listen for `ADDON_RESTRICTION_STATE_CHANGED`)

**Settings callback:**
When the slider value changes in the settings panel, the new alpha is applied immediately to the frame (live preview), respecting combat guards.

## 12.0.0 API Compliance

### Secret Values System
- The Essential Cooldowns bar may have Secret Aspects applied during encounters
- The "Alpha Aspect" can make `SetAlpha()`/`GetAlpha()` return opaque values
- We check `HasSecretValues()` before modifying alpha and defer if restricted
- Listen for `ADDON_RESTRICTION_STATE_CHANGED` to know when restrictions lift

### Frame Interaction Rules
- **Always `HookScript()`**, never `SetScript()` on Blizzard frames
- **Always check `InCombatLockdown()`** before frame modifications
- No anchoring to protected frames (avoids taint propagation)
- No `SetAttribute()` calls on Blizzard frames

### Modern API Usage
- Settings API: 11.0.2+ signatures (`variableKey`/`variableTbl`)
- No deprecated `InterfaceOptionsFrame` usage
- No deprecated global function calls (use `C_*` namespaces where applicable)
- Interface version 120000 in TOC

## Libraries

| Library | Version | Purpose |
|---------|---------|---------|
| LibStub | 1.0 | Library versioning/loading |
| CallbackHandler-1.0 | 1.0 | Event callbacks for LDB |
| LibDataBroker-1.1 | 1.1 | Data object for minimap button |
| LibDBIcon-1.0 | 1.0 | Minimap button rendering |

All libraries are embedded (not external dependencies) to ensure the addon is self-contained.

## Future Extensibility

New modules follow the same pattern:
1. Create `Modules/NewModule.lua`
2. Define the module table with `name`, `displayName`, lifecycle hooks, and `RegisterSettings`
3. Call `Noctis:RegisterModule(module)`
4. Add the file to the TOC
5. Add defaults to the SavedVariables schema

New features within the EssentialCooldowns module:
1. Add a new settings sub-table (e.g., `scale = { enabled = false, value = 1.0 }`)
2. Add defaults in the module's defaults table
3. Register settings in `RegisterSettings()`
4. Implement the feature logic with the same combat-safety patterns
