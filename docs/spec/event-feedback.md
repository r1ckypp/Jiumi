# Pet events and feedback v1

**English** · [Simplified Chinese](event-feedback.zh-CN.md)

## Runtime boundary

The offline editor, exported HTML and native window share `mountPet` and its embedded JavaScript scheduler. Running `watch` explicitly starts the native bridge. One listener binds to one local pet using a private socket and exclusive lock. Archives carry character data, motion mappings and selected plugins. Device bindings, event streams and permissions stay on the device.

## Controller

`dispatch(event)` reports a fact. `getState()` returns the combined state and `disconnect(source)` clears that source's sessions. Use `setVisible(false)` to pause motion, `play(name)` for a preview and `dispose()` to release the instance. Rules can consume custom events. A state-machine plugin defines persistent interaction states and their priority.

```json
{"v":1,"id":"req-42","source":"editor","session":"session-a","type":"agent.input_requested","at":1780000000000}
```

Use Unix milliseconds for `at`. Each source, ID, type and session string can contain up to 160 characters. The scheduler remembers the last 1,024 source/ID combinations. Events within a session are ordered by timestamp, then arrival order. Reuse a stable upstream ID where available. The Claude adapter generates an ID for each hook invocation and suppresses repeat notifications on an unchanged transition. Delivery is best effort.

## States and interruption

| Input | Session state | Default one-shot feedback |
| --- | --- | --- |
| `agent.started` / `agent.resumed` | working | none |
| `agent.input_requested` | waiting | attention |
| `agent.completed` | ended | celebrate |
| `agent.closed` | ended | none |
| `pet.tap` | unchanged | affection |

Each source/session pair progresses independently. Waiting takes priority over working, then idle. Keep ended sessions briefly so stale events cannot revive them. Repeated state reports refresh the session without replaying feedback. Expire a session after five minutes of silence on a tick, new event or visibility change. Long-running sources should refresh their state. Events older than 15 seconds can reconstruct state without replaying a reaction. Discard events at least five minutes old or more than five seconds in the future. Initial connection does not query session history.

Use catalog rules selected in `pet.plugins`. A custom body intent overrides the default for that event. Particle effects can run alongside it. Priority goes from manual preview to affection, attention and celebration. A higher-priority action interrupts a lower one. Persistent state keeps updating. Each interruption invalidates the previous completion callback. When an action ends, resume the current state. Hidden tabs receive events and stop motion until visible. Respect reduced-motion settings for particles and body movement.

```json
{"id":"focus-finished","version":1,"name":"Focus complete","on":"timer.finished","intent":"celebrate"}
```

A character can map an intent to an existing motion in `appearance.motions`, for example `{"attention":"greet"}`. Unknown mappings fall back to a built-in motion. Extend the renderer with layers for independent eye or feather movement. Adapters and event rules can keep the same contract.

## Connect a local tool

On macOS, run `python3 agent_events.py watch PET_UUID` to open a listening window. Stopping the listener closes its window. Add the hook to the project the user chose, preserving existing hooks. Substitute the local script path and pet UUID and add an entry for each event you want to observe.

```json
{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"python3 '/absolute/path/agent_events.py' claude PET_UUID"}]}]}}
```

Supported hooks are `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Stop` and `SessionEnd`. Permission requests mean waiting. Tool use begins or resumes work. Stop means the turn ended and defaults to celebration regardless of test results. Ignore `SubagentStop`. The adapter reads the event name and session ID, leaves commands, chat and paths private, and returns no approval decision. Remove its hook entry and stop its listener to disconnect. The adapter uses nonblocking datagrams in a user-private directory. Observations made while disconnected are dropped. Other clients can implement the same protocol.

## Acceptance

Replay work → wait → pet → still waiting → resume → complete with a controlled clock and simulated player. Check independent concurrent sessions, deduplication, expiration, hidden tabs and custom sources. The HTML host receives supplied events. Native Windows monitoring, cross-device live transport, log collection, dashboards and general-purpose rule scripting are outside v1.

The interaction state machine runs alongside the agent session state. Its transition table accepts `pet.grab`, `pet.release` and `pet.cancel`. A grab owns the body until release, then `landing` plays once and returns to the latest session state. Re-grabbing interrupts landing. Cancellation skips landing. Supply looping `clips.held` and an optional one-shot `clips.landing` for character-specific poses. A missing clip uses built-in motion. The bundled pickup plugin declares these transitions. See the [plugin SDK](plugin-sdk.md) for interruption and recovery rules.
