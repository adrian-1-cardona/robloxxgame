# Survive at Sea

Ocean survival lobby template (Dead Rails–style boarding dock).

## Run

```bash
rojo serve
```

In Roblox Studio: **Plugins → Rojo → Connect** to `localhost:34872`.

After connecting you should see **`Workspace.SurviveAtSeaLobby`** in Explorer (pier, portals, ocean) **even before pressing Play**.

Then Stop → Play. Walk forward along the neon arrows to the glowing portals.

## Lobby features

- Sea-themed boarding dock with voyage portals
- Create / join crews with friends (party codes)
- Up to **10** sailors per game state
- Public or private berths
- Cast-off countdown, then launch into the voyage
- **No session saves** — party state is ephemeral (no DataStore caching yet)
- UI tuned for phone, tablet, computer, console, and VR

## Project layout

```
src/
  map/      SurviveAtSeaLobby.model.json  (dock synced into Workspace)
  shared/   Config, remotes, party codes
  server/   Bootstrap + party/portal services
  client/   Cross-platform lobby UI
```

Set `GamePlaceId` in `src/shared/Config.luau` when you have a separate voyage place; until then, crews launch into the in-place staging deck.
