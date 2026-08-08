<!--
  Maintainers (human or agent): this README is written per the /pg skill,
  house style "code spans + structure only" — no bold, no italics; headers
  and `code spans` do the scanning. Edit it through that voice.
-->

# osfacts-client

The TypeScript face of the [osfacts](../) binary. Spawn it at a path you
supply, refuse a schema version you do not speak, and hand back typed
process, listener, socket-holder, unreadable, source-error, and host rows.
Nothing more.

```ts
import { Effect } from "effect";
import { snapshotHost } from "osfacts-client";

const program = Effect.gen(function* () {
  const reading = yield* snapshotHost(process.env.OSFACTS_BIN!, {
    procs: true,
    uid: true,
    cwd: true,
    status: true,
    argv: true,
    cpuTime: true,
  });
  if (reading.errors.length > 0) {
    // This consumer rejects partial source failures; another may render them.
    throw new Error(JSON.stringify(reading.errors));
  }
  // reading.procs · reading.uids · reading.cwds · reading.statuses · reading.argv
  return reading;
});
```

No `@kolu` imports. One npm runtime dependency, `effect` — otherwise
`node:child_process` and friends — so a second consumer can pin this package
without dragging kolu's monorepo graph. kolu (via padi and its daemon
supervisor) and drishti both ship it.

## The Effect surface

Every SPAWNING verb — `snapshotSubtree`, `snapshotHost`, `snapshotPids`,
`processIdentityAsync`, `socketHolders`, `host`, and the function
`osfactsSocketHolders` returns — hands back an
`Effect.Effect<Reading, OsfactsClientError>`. Nothing spawns until you run it,
every failure the client declares is in the type rather than in a comment, and
a caller that stops waiting INTERRUPTS the work: the in-flight child is killed
rather than left to run out its five-second deadline against a host nobody is
reading. That last part is the capability a `Promise` could not express, and
the reason the spawn is an `Effect.callback` around node's own `execFile`
rather than a platform command layer — the child-level timeout stays
kernel-enforced, and the exit-status rules below keep reading node's own error
shapes.

Three functions are a deliberate SYNC ISLAND and stay synchronous, throwing
rather than failing: `snapshotPidsSync`, `processIdentity`, and
`processIdentityFromEnv`. Their consumers' single-instance gate is a
synchronous claim path — async there reorders the gate against the boot side
effects it guards — and `execFileSync` cannot be interrupted, so an Effect
wrapper would advertise a capability the call does not have. The parsers and
folds (`parseSnapshotOutput`, `parseSocketHoldersOutput`, `parseHostOutput`,
`foldSocketOccupancy`, `snapshotFacetNames`, `bakedOsFactsBin`) are pure
functions over a string you already have, and throw for the same reason.

The error vocabulary is three tagged classes — `OsfactsSpawnError` (the child
could not be launched or would not answer), `OsfactsVersionError` (the document
speaks a format this reader does not), and `OsfactsParseError` (a row it cannot
read) — with `OsfactsClientError` as their union and `isOsfactsClientError` as
the guard that narrows a `catch`. They are `Error`s, which is what lets the sync
island go on throwing them.

Policy about what a fact *means* — which blindness matters, whether to reject
or render a partial reading, what to do about a holder — is the consumer's,
not this package's. The one deliberate exception: where a verb's reading has a
single honest domain answer every consumer would otherwise hand-write the same
way, the FOLD ships here beside the parser (`processIdentity*` over the
start-time reading, `socketHolders`/`foldSocketOccupancy` over the holder
reading). Both keep an "absent" arm that must never collapse into the others,
which is exactly the mistake a per-consumer copy makes.

## What it does

- Spawn an exact-pid, subtree, or true host-wide process snapshot at a supplied
  absolute binary path.
- Gate on `V 2` — a mismatched format fails loudly.
- Parse every row; a line it cannot read is an error, never a skip.
- Return partial facts when one requested source is blind. The process exits
  successfully when other facts survived, keeps the source failure in
  `reading.errors`, and leaves reject-versus-render policy to the caller.
- Return the raw tables: process identity, uid, cwd, state/nice/thread count,
  full argv, RSS, start time, and cumulative user-plus-system CPU microseconds;
  listener rows with explicit
  claimed/unclaimed status and network-order hex addresses; host gauges and
  cumulative counters; unreadable facets; and source errors.
- Ask which processes hold a unix socket path. `socketHolders(bin, path, {
  procs: true })` returns a `SocketHoldersReading` whose `holders` are
  discriminated rows — `{ status: "claimed", pid }` or `{ status: "unclaimed"
  }` — so a bound socket nobody readable claims stays distinct from an empty
  answer, and a blind search stays distinct from both.
- Keep the three verbs apart. `snapshot*` returns a `SnapshotReading`,
  `socketHolders` a `SocketHoldersReading`, and `host` a `HostReading` —
  separate types, separate parsers, separate facet vocabularies. Feeding one
  verb's output to another's parser is a loud error, not a silently empty
  field, and `mem` can mean process RSS in one and host RAM in the other
  without a consumer matching across them by accident.
- Refuse a document the binary wrote while REFUSING the ask. The version line
  is written on the usage path too, so only exit 1 — the documented
  "V line, then E rows" total failure — is parsed. An older binary that lacks
  the verb you asked for exits 2, and reading that as "nothing found" is how a
  caller concludes a live socket is free.
- Name the facets an ask can be answered with. `snapshotFacetNames({ procs:
  true, ports: true })` returns
  `{ unreadable: ["proc", "ports"], source: ["proc", "ports",
  "ports_unclaimed", "ports_uid"] }` — the flag-to-wire-name map is not
  mechanical, so it lives here instead of being re-derived by every consumer.
  Which of those named facets counts as blindness is still the consumer's
  call.

## What it does not

- Read `KOLU_OSFACTS_BIN` (or any env) on your behalf. `bakedOsFactsBin(name)`
  reads the env var you name — loudly, with no PATH fallback — and a
  composition root calls it ONCE. Every verb takes a resolved path.
- Classify addresses into any / loopback / interface.
- Fold ports, rank scopes, or decide that a U row blinds a terminal.
- Decide what a fact MEANS. `processIdentity*` reports a pid's
  start-qualified identity; whether that answers "is this still the same
  process?" is a supervisor's gate policy, and it belongs beside the supervisor
  that owns it.
- Depend on zod, pino, or anything beyond `effect` and Node built-ins.

## The facet vocabulary

`UNREADABLE_FACETS`, `SNAPSHOT_SOURCE_FACETS`, `SOCKET_HOLDERS_SOURCE_FACETS`,
and `HOST_SOURCE_FACETS` are not maintained by hand against the binary. `osfacts/facets.json` is checked in
beside the Rust crate, a Rust test pins it to the `Facet` enum that produces
every wire name, and `src/facets.test.ts` pins these three lists to the same
file. Adding a facet on one side without the other fails the unit lane on both
— it used to surface as `unknown unreadable facet` in a consumer's parse, at
runtime, on whichever platform emitted it.
