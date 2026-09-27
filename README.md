# ComfyPanel

**Version 0.4 – Beta**  
**Target: World of Warcraft: Forever 1.60.1 / Interface 16001**  
Author: **TheRealDoubleG**  
Discord: **the.real.double.g**

Minimal modular information panel for WoW Forever.

## Scope

A lightweight information strip for money, bag space, time, FPS and latency. It does not try to reproduce Titan Panel's plugin ecosystem.

ComfyPanel is developed specifically for **WoW: Forever**. Retail/Modern WoW, Midnight and WoW Classic are not compatibility targets.

## 0.4 Beta

- ComfyPanel now prefers the shared ComfyData service for account-wide character data.
- AFK/idle display moved to ComfyXP, where it belongs next to the XP/session information.
- Existing ComfyPanelStatsDB remains as a fallback for standalone installs without ComfyData.
- ComfyData stores character snapshots outside the AddOns folder through WoW SavedVariables, so addon-folder updates do not overwrite the database.

## 0.3 Beta

- Panel background opacity now supports a true 0%.
- Configurable distance from the screen edge so the panel does not have to overlap the minimap/zone strip.
- Unlock mode lets every panel module be dragged horizontally; dragging automatically switches to custom positioning.
- One-click left, center, right and custom module alignment.
- Bag display can show free slots only or free / maximum slots.
- Added account-wide ComfyPanelStatsDB for known characters.
- Money tooltip shows stored money for all known characters.
- Bag tooltip shows free / maximum bag slots for all known characters.
- Playtime module supports login-session, current-character total and all-known-characters total.
- Playtime tooltip lists each known character separately.
- PvP honorable-kill module shows current PvP-session and lifetime kills; tooltip lists lifetime kills for all known characters.
- Local idle display starts after 5 seconds, then shows estimated AFK and auto-logout timing. The actual UnitIsAFK state takes priority once WoW marks the character AFK.
- Character data is learned when each character is logged in with ComfyPanel at least once.

## 0.1 Beta

- Initial information panel with money, bag space, clock, FPS and latency.

## Design notes

Titan Panel demonstrates the value of small independent data modules, but ComfyPanel keeps a much smaller Forever-only scope and owns its own frame.

The referenced third-party addons were used only to study public feature ideas, long-term bug patterns and architecture lessons. ComfyPanel uses original Comfy Suite code and Blizzard UI assets; it does not copy their code or artwork.

## Commands

- /comfypanel
- /cpanel

## Comfy Suite

The addon follows Comfy Suite UI standard generation 2: Settings immediately before Info, per-character/account/custom saved profiles, movable/lockable settings window, opacity controls and the shared Info layout.
