# Survive at Sea

Ocean survival lobby template (Dead Rails–style boarding dock).

## Run

```bash
rojo serve
```

Connect Roblox Studio via the Rojo plugin to `localhost:34872`.

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
  shared/   Config, remotes, party codes
  server/   Lobby world, party service, portals
  client/   Cross-platform lobby UI
```

Set `GamePlaceId` in `src/shared/Config.luau` when you have a separate voyage place; until then, crews launch into the in-place staging deck.
