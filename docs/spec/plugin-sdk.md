# Offline plugin SDK v1

The focus timer in `examples/focus-timer/index.ts` shows how to compile the AssemblyScript subset of TypeScript to WebAssembly. Authors need a compiler at build time. The host runs the result offline. SDK v1 supports small modules that keep time, receive assistant events and request pet motions.

## Package and execution

Distribute a JSON object with `id`, `version`, `api`, `name`, `events`, `capabilities`, `wasm` and `sha256`. Encode the Wasm bytes as Base64 and their SHA-256 digest as hexadecimal. The digest checks integrity. Publisher trust depends on the distribution source. A pet supports up to eight modules. Each runs in its own worker. The host checks the binary format, allowed imports and memory limit, and terminates a worker on error or timeout.

## Callback

Export `step(event:i32, now:f64, state:f64):void`. The event number indexes the manifest's zero-based event list. Time is Unix milliseconds. State is one safe integer per pet and plugin, initially zero. Import `pet.save(f64)` with the `state` capability and `pet.play(i32)` with the `motion` capability. Motion 1 requests focus and 2 a greeting. After a successful callback the host applies the last write and motion request. A timer can store its deadline in the integer. Upgrades must preserve the meaning of stored values.

## Lifecycle and installation

The host emits `host.ready`, `host.hide`, `host.resume`, `host.tick` and `host.stop`. A visible pet ticks about once per second. Compare actual time against a deadline. Disabling a plugin releases its worker and timers. Forced page closure may skip the final stop event, so commit recoverable progress during each meaningful event. An explicitly enabled device adapter translates OS events into v1 events. Modules have no network, filesystem or ambient host imports.

Import module JSON in the maker. Use the checkbox to enable or disable it, or remove the code package. Disabling preserves state. A portable pet carries enabled IDs, versioned bytes and progress. Older packages open without these fields. Export current JSON from the browser or the macOS window's context menu. The local CLI reads progress saved by the native host.

## Declarative interaction states

Copy `examples/pickup.json` from the installed Skill (repository source: `skill/jiumi-pet/runtime/pickup.json`). Import it under local plugins or pass `--module examples/pickup.json` to `pet.py create`. The pickup graph ships by default in every player. An installed graph with the same ID replaces the default, and disabling that installed copy mutes it. Removing the override restores the bundled behavior.

Give new behavior its own plugin ID, priority (0–100), entry event and state names. For a grab, `enter` maps `pet.grab` to `held`. Its `on` table maps release to `landing`, whose `after` target runs when its animation finishes. Omit `after` for a persistent state. A target may name a local state, use `$resume` to resume the interrupted plugin, or use `$base` to clear the stack and show the latest agent state. Completion transitions can form a sequence. Automatic cycles are rejected. The existing state's own event handler has first refusal. Otherwise a higher-priority entry can interrupt it; ties between eligible candidates use plugin ID order.

The interrupted state's `resumeAt` selects its own state (`$self`, default), another state in that plugin, or `$discard`. Resuming restarts the chosen motion. Suspended frames can still consume their exit events. Hiding the host clears transient interactions. Each state's `motion` may reference a built-in motion or a custom clip key; missing artwork falls back to idle. This format runs offline without Wasm. A new OS signal still requires an event source; an existing adapter or module can reuse events it already emits.
