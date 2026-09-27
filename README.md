# ComfyPanel

**Version 0.1 – Beta**  
**Target: World of Warcraft: Forever 1.60.1 / Interface 16001**  
Author: **TheRealDoubleG**  
Discord: **the.real.double.g**

Minimal modular information panel for WoW Forever.

## Scope

A lightweight information strip for money, bag space, time, FPS and latency. It does not try to reproduce Titan Panel's plugin ecosystem.

ComfyPanel is developed specifically for **WoW: Forever**. Retail/Modern WoW, Midnight and WoW Classic are not compatibility targets.

## 0.1 Beta

- Added an independent top/bottom information panel.
- Added money, free bag slots, clock, FPS and home/world latency modules.
- Avoids repositioning Blizzard UI frames.

## Design notes

Titan Panel demonstrates the value of small independent data modules, but ComfyPanel keeps a much smaller Forever-only scope and owns its own frame.

The referenced third-party addons were used only to study public feature ideas, long-term bug patterns and architecture lessons. ComfyPanel uses original Comfy Suite code and Blizzard UI assets; it does not copy their code or artwork.

## Commands

- /comfypanel
- /cpanel

## Comfy Suite

The addon follows Comfy Suite UI standard generation 2: Settings immediately before Info, per-character/account/custom saved profiles, movable/lockable settings window, opacity controls and the shared Info layout.
