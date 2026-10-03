# pnpm: a workspace package's peer that is also its devDependency is gone after `--prod`

Minimal reproduction for [pnpm/pnpm#7499](https://github.com/pnpm/pnpm/issues/7499),
on pnpm 12.8.1 (also reproduced on 11.26.0).

## Layout

```
packages/
  app/   dependencies: { "lib": "workspace:*" }      requires lib
  lib/   peerDependencies: { "ms": "^2.1.0" }        requires ms
         devDependencies:  { "ms": "^2.1.3" }
```

`lib` is a **production** dependency of `app`. `lib` needs `ms` at runtime, and
declares it as a peer, plus a devDependency so it can be developed and tested on
its own. That pairing is the usual way to declare a peer.
`autoInstallPeers` is on (the default).

## Run

```sh
./repro.sh
```

## Result

| `lib/package.json` | full install | `pnpm install --prod` | lockfile records `ms` for `lib` under |
|---|---|---|---|
| peer + devDependency | works | `Error: Cannot find module 'ms'` | `devDependencies` |
| peer only | works | works | `dependencies` |

Both scenarios run with `strictPeerDependencies: true`, and neither install
prints a warning or fails.

## Why this looks wrong

1. **The prod graph has an unmet peer that nothing reports.** `app` → `lib` →
   peer `ms` is entirely production edges. After `--prod` nothing provides `ms`,
   yet the install succeeds silently, even under `strictPeerDependencies`. The
   failure only shows at runtime.
2. **A devDependency changes what production gets.** Adding a devDependency to
   `lib` removes `ms` from the production install. Without it, `autoInstallPeers`
   records `ms` under `lib`'s `dependencies` and it survives `--prod`. Dev-only
   metadata shouldn't decide whether a runtime dependency is installed.
3. **The documented behaviour doesn't cover this.**
   [`autoInstallPeers`](https://pnpm.io/settings/peer-dependencies) says
   "any missing non-optional peer dependencies are automatically installed".
   The peer is missing from the production install, but the dev copy counts as
   present when pnpm decides what to auto-install.

## Where the precedence comes from

- pnpm 11, [`getWantedDependencies.ts`](https://github.com/pnpm/pnpm/blob/5dafb0980042af99fb1aa24478d16f03b8474b50/pnpm11/installing/deps-resolver/src/getWantedDependencies.ts#L41-L73):
  peers are spread first (`{ ...pkg.peerDependencies, ...depsToInstall }`), and a
  peer is classed `prod` only when the alias is in none of
  `optionalDependencies` / `dependencies` / `devDependencies`.
- pnpm 12, [`importers.rs`](https://github.com/pnpm/pnpm/blob/5dafb0980042af99fb1aa24478d16f03b8474b50/pnpm/crates/package-manager/src/dependencies_graph_to_lockfile/importers.rs#L353):
  specifiers are looked up in the order `Optional, Prod, Dev`, then `Peer`.

## Possible fixes

Any one of these would avoid the silent runtime failure:

- When `autoInstallPeers` is on, record a non-optional peer that is also a
  devDependency under the importer's `dependencies` (the dev entry still
  decides the version), so `--prod` keeps it.
- Or report the peer as unmet during a `--prod` install, which
  `strictPeerDependencies` would then turn into an error.
- At minimum, document under `autoInstallPeers` that a dev copy suppresses the
  auto-install and is pruned by `--prod`, so a workspace package should declare
  shared runtime packages as peers only.
