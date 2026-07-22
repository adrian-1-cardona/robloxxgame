## always do this 

```bash
    rojo serve
```

Run that to make sure you are always have teh server running when editing code :D 

## Portal load-into-game test (must stay green on every PR)

`tests/PortalLoad.spec.luau` is the canonical **"the portals work"** regression
test. It reproduces the exact path a player takes to load into a game — walk a
pier portal → get seated on a raft → friends join by code — by running the real
`PartyService` logic headlessly with the [Lune](https://lune-org.github.io/docs)
Luau runtime.

This test runs automatically on **every commit and every pull request** via
`.github/workflows/portal-load-test.yml`. If it fails, players can no longer
reliably board a game from the portals, so **do not merge until it is green.**

Run it locally from the repo root:

```bash
    lune run tests/PortalLoad.spec.luau
```

Install Lune first if you don't have it (`rokit add lune-org/lune`, or grab a
release binary from the Lune repo).
