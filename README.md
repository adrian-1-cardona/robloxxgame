# Survive at Sea

Ocean survival lobby template (Dead Rails–style boarding dock).

## Quick start (recommended)

Open the built place so Workspace already has the dock:

1. In a terminal: `rojo build -o SurviveAtSea.rbxlx`
2. In Studio: **File → Open from File…** → choose `SurviveAtSea.rbxlx`
3. Press Play — you should spawn on the wooden pier facing neon portals

Or keep using live sync on an existing place (`dnd`): the **client now builds the dock itself** when `Workspace.SurviveAtSeaLobby` is missing. Stop → Play after Rojo connects.

## Live sync

```bash
rojo serve
```

Studio → Plugins → Rojo → Connect → `localhost:34872`

After Play, Explorer should show `Workspace.SurviveAtSeaLobby` (client or server created it).

## Features

- Sea-themed boarding dock with voyage portals
- Create / join crews with codes (max **10** per game state)
- Public / private berths, cast-off countdown
- **No session saves** (ephemeral)
- Phone / tablet / PC / console / VR friendly UI
