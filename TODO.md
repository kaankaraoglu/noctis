# Noctis — Improvement Ideas

## Fader Module

- [ ] **Per-element opacity overrides** — Allow individual elements to have their own resting opacity instead of only the shared global slider
- [ ] **Combat auto-reveal** — Option to automatically show all faded elements at full opacity during combat and re-fade after combat ends
- [ ] **Fade speed setting** — Expose `FADE_DURATION` as a user-configurable slider (currently hardcoded at 0.2s)
- [ ] **Hover reveal radius** — Option to reveal faded elements when the mouse is near them (within N pixels) rather than only on direct hover
- [ ] **Mouseover propagation** — When hovering Player Frame, also reveal Target Frame (and vice versa) as a linked group
- [ ] **Fade delay** — Configurable delay before fading out after mouse leaves, so elements don't immediately disappear
- [ ] **Out-of-combat only mode** — Only apply fading outside of combat, full visibility during encounters regardless of hover
- [ ] **Per-element opacity** — Allow overriding the global opacity per element for finer control
- [ ] **Keyboard shortcut toggle** — Keybind to temporarily reveal all faded elements or toggle fading on/off

## New Modules

- [ ] **Action Bars** — Fade action bar frames (MainMenuBar, MultiBar*, StanceBar, PetActionBar)
- [ ] **Chat Frame** — Fade chat windows when not actively reading/typing
- [ ] **Buff/Debuff Frames** — Fade the buff/debuff icons near the minimap
- [ ] **Cast Bar** — Fade the player/target cast bars when not casting
- [ ] **Bags Bar** — Fade the bag buttons
- [ ] **Zone Text** — Fade or auto-hide zone/subzone text overlays
- [ ] **XP/Rep Bar** — Fade the status tracking bar

## Architecture

- [ ] **Profile system** — Support multiple SavedVariables profiles (e.g. "Raid", "Solo", "PvP") with quick switching
- [ ] **Per-character overrides** — Add `SavedVariablesPerCharacter` support so alts can have different settings
- [ ] **Module load-on-demand** — Split modules into separate TOC addons that load only when enabled, reducing memory footprint
- [ ] **Addon icon** — Create an actual icon texture for the minimap button and addon compartment (currently references a missing file)
- [ ] **Frame name auto-discovery** — Scan `_G` for common Blizzard frame patterns instead of hardcoding candidates, with a UI to browse and select frames to fade
- [ ] **Import/export settings** — Serialize NoctisDB to a string for sharing between accounts or players

## Quality of Life

- [ ] **Hover monitor optimization** — Replace per-element 50ms tickers with a single shared OnUpdate frame that checks all elements, reducing timer overhead
- [ ] **Dynamic child hooking** — For frames with dynamic children, hook the parent's layout/update methods to catch new children as they're created instead of relying solely on polling
- [ ] **Minimap button right-click menu** — Show quick toggles for each module on right-click
- [ ] **Slash command arguments** — Support `/noctis fade 0.5` to set opacity from chat, `/noctis toggle` to enable/disable
- [ ] **Clean up stale SavedVariables** — Remove `db.elements` entries for elements that are no longer registered (e.g. after removing a module)
