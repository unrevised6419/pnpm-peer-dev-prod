#!/usr/bin/env bash
# Runs the same workspace twice: once with lib's peer duplicated as a
# devDependency, once with the peer alone. Restores lib/package.json on exit.
set -uo pipefail
cd "$(dirname "$0")"

manifest=packages/lib/package.json
cp "$manifest" "$manifest.orig"
trap 'mv "$manifest.orig" "$manifest"; rm -rf node_modules packages/*/node_modules pnpm-lock.yaml' EXIT

run_app() {
	(cd packages/app && node index.js 2>&1 | grep -m1 -E '^[0-9]+$|Error:')
}

scenario() {
	echo "### $1"
	rm -rf node_modules packages/*/node_modules pnpm-lock.yaml
	pnpm install --config.strict-peer-dependencies=true >/dev/null || echo "install failed"
	echo "full install:  $(run_app)"
	pnpm install --prod --config.strict-peer-dependencies=true --config.confirmModulesPurge=false >/dev/null \
		|| echo "prod install failed"
	echo "--prod:        $(run_app)"
	echo "lockfile entry for packages/lib:"
	sed -n '/^  packages\/lib:/,/^packages:/p' pnpm-lock.yaml | sed '$d'
	echo
}

pnpm --version
echo
scenario "peer + devDependency (lib/package.json as committed)"

node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
delete m.devDependencies;
fs.writeFileSync(process.argv[1], JSON.stringify(m, null, 2) + "\n");
' "$manifest"
scenario "peer only (devDependencies removed)"
