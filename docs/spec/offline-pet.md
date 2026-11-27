# Offline pets, motion assets and community plugins

## Runtime contract

A finished pet opens, reacts to touch and runs its installed motions and plugins offline. A standalone HTML file embeds the player, artwork and selected modules. The desktop edition shares the package and feedback semantics and bundles its host. The user needs a browser or the target OS. Compilation happens on the build machine. Image generation is optional during creation. Core playback requires only a browser or the bundled native host.

The Skill includes a maker for single PNGs, color adjustments, motion previews and export. Developers can launch a macOS or Windows window from the CLI or build a standalone application in advance. JSON feedback rules and compiled modules extend the same pet. See the [event specification](event-feedback.md).

## 1. Create motion assets in the Skill and play them in the host

Keep the approved portrait as the cover. Prefer the user's PNG sequences or existing sprite-sheet artwork. If the assistant can generate images, use the approved portrait as reference and start with an idle blink and a touch reaction. Check the outline, proportions, transparent edges and alignment at the feet. Let the user add other motions. If a set fails, is skipped or cannot be generated, keep the accepted frames and fall back per motion to the single-image reaction. Playback needs no generation credentials.

The optional motion table indexes ordered frames, frame duration and looping by motion name. Ship the assets inside the package. Older pets use their original motions. A future sprite-sheet slicer can target the same format. Both a chick and a pig receive `pet.tap`; each character's mapping determines its response.

The maker previews a clip, adjusts speed, replaces or removes its frame set and identifies fallback motions. Exported HTML and editable JSON carry the same assets, settings and UUID. The [package schema](contracts.schema.json) defines the clip format.

## 2. Attach local modules to the pet lifecycle

An author implements a focused feature, such as greeting the user when a focus timer expires. Build and package executable code and static dependencies with a plugin ID, version, host API version and capabilities. Installed code executes on the user's machine. Simple event-to-feedback mappings can use JSON rules.

| Host transition | Plugin responsibility | Host responsibility |
| --- | --- | --- |
| Enable and start | Read owned state and subscribe to events | Mount once per instance |
| Ready or event | Request a motion, particle effect or reminder as supported | Resolve priority and perform the effect |
| Hide or suspend | Pause visuals and commit progress | Notify plugins and stop idle refreshes |
| Show or resume | Recheck current facts and deadlines | Avoid repeating earlier reactions |
| Disable or exit | Commit progress and release resources | Cancel subscriptions and timers and isolate failures |

The host enforces the interface for subscriptions, feedback and owned state. Verify isolation on each host before distributing third-party code. A faulty or stalled plugin must leave the base pet interactive. Capabilities such as OS observation require an explicit local adapter or desktop host. On a browser-only host, disable only the feature that needs that capability.

## 3. Distribute modules and connect event sources

Users import a versioned module from a local file. The host checks compatibility, capabilities and package integrity before storing it locally. HTML embeds the module on export and the desktop host reads its local copy. User-triggered updates preserve the previous version on installation failure.

For example, an approval hook becomes `agent.input_requested`. The host dispatches it, a plugin requests attention, and the character performs its waiting motion. Adding a reaction for an existing source needs only a plugin. Connecting another tool may need an adapter.

Community modules run offline in v1. A future network capability would need host mediation, declared destinations and data, separate user consent and revocation. Declining access or losing connectivity must leave the base pet and offline plugins usable.

## 4. Restore the right state

| Data | Lifetime |
| --- | --- |
| Pet ID, appearance, frames, plugin choices and versions | Portable with the editable package. Recoloring, editing one motion or restoring a pet preserves its UUID. |
| Plugin state | Scoped by pet and plugin. Preserve compatible state across versions. A timer stores its deadline and settles once. Document which values travel. |
| Window position, source bindings, credentials and permissions | Local to a device. Rebind and grant access on a new machine. |
| Current frame, a tap, a waiting assistant | Local to a running instance. On reconnection the source reports current facts. |

The desktop host can persist progress automatically. Browser storage for local files varies. An explicit package export is the portable recovery path. Preserve plugin choices and state if a version is temporarily unavailable so the user can still open the pet.

## Milestones and verification

| Deliverable | Acceptance | Where to verify |
| --- | --- | --- |
| Frames, maker, player and Skill fallback | A pig blinks with supplied frames, reacts to touch with fallback, reopens offline and keeps its ID. Single-image pets still work. | `tests/offline_maker.py` |
| Local SDK, isolated execution, persistence and host | A timer can be installed, disabled and enabled. It settles once after wake. A plugin failure leaves the pet interactive. Browser HTML and a bundled macOS app run offline. | [SDK v1](plugin-sdk.md), `tests/offline_modules.py`, `tests/desktop_bundle.py` |
| Local event adapters | An opted-in hook drives the installed reaction. Disconnecting or disabling it stops delivery. | `tests/event_bridge.py` |

The current release accepts PNG sequences and one safe integer per plugin. macOS supports a native app for the build machine's architecture. Windows has a native WebView2 host in the Skill source. It uses the same offline player and provides a floating window, notification-area management, and seven searchable settings pages. Window preferences, hotkeys, startup registration, and opt-in keyboard timing are device-local. Linux uses standalone HTML. Automatic sprite slicing, network capabilities, and app-store distribution are future work.

### Animation libraries

Each character can carry up to 256 named PNG clips within the existing 8 MB encoded clip budget. An optional clip label is the human-readable name. Use the frame editor to add an ID such as `wing-wave` and select its ordered PNGs. Small pets can omit the library.

Map an intent to candidates with `"motionPools":{"working":["typing","inspect"],"held":["dangle"]}`. Entries refer to clip IDs or built-in motions. The player picks on entry and at sustained playback boundaries, avoiding the previous selection when alternatives exist. A one-shot yields after one pass. Existing per-intent appearance overrides have first choice. Unavailable candidates are skipped; an empty usable pool falls back to the usual motion. State machines can request their own pool by name. Libraries travel with the pet in previews, HTML, native bundles and archives.
