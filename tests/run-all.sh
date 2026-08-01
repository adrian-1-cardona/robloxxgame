#!/usr/bin/env bash
# Runs every headless suite, from the repo root:
#
#   ./tests/run-all.sh
#
# Roblox Studio is not required. Lune compiles and runs the Luau directly, and the island
# suites measure the real generated geometry rather than eyeballing it in Studio.
set -euo pipefail

cd "$(dirname "$0")/.."

run() {
	echo
	echo "=== $1"
	lune run "$1"
}

run tests/Syntax.spec.luau        # every Luau file still compiles
run tests/PortalLoad.spec.luau    # players can still board a game
run tests/IslandWorld.spec.luau   # world rules, incl. the ban on circular island bodies
run tests/IslandShape.spec.luau   # measured geometry of all catalog islands
run tests/IslandPreview.luau      # top-down PNGs into build/island-preview/

echo
echo "All suites passed. Island previews are in build/island-preview/."
