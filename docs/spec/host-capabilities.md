# Host capabilities and session notices

Adapters report facts with v1 events. A portable plugin requests feedback. Each host renders supported feedback and resolves user actions against device-local capabilities. Archives carry the plugin definition. Session destinations, pending requests, credentials and device grants stay local.

## Body and notice channels

The body continues to use the interaction graph. A session notice lives independently through touch, grab, landing and visibility changes on the same mounted player. The newest pending notice is visible. Clearing it reveals the previous one. Scope is the tuple of plugin ID, event source and session ID. Resuming, completing or closing another session leaves this notice alone. Disconnecting a source clears its notices. Player disposal clears all transient notices. Up to 32 notices are retained.

## Example contract

Install examples/agent-confirm.json in the maker or pass it to pet.py create with --module. A session-notice declares show, clear, title and action. The example shows on agent.input_requested and clears on agent.started, agent.resumed, agent.completed or agent.closed. Events may include a short plain-text summary (160 characters). A request opens a notice; only a subsequent user click requests session.open. Opening the client leaves the request pending until the originating adapter reports a clearing event. A successful open means the OS accepted the destination, not that permission was granted in the agent.

A host may pass a fourth argument to mountPet with session(method,{source,session}), returning a boolean or promise. The player asks available before rendering the action, then open on click. It emits pet.action on the stage with action, source, session and ok. A host may also implement layout(visible). Keep target resolution on the device. Never take a destination URL from a plugin or event.

## Run locally

On macOS, bind the particular source and session to a known client conversation URL, then run the listener. Use the existing Claude hook, or pipe a v1 event into emit. The user provides a trusted HTTPS conversation link or a client deep link of the form scheme://threads/SESSION_UUID. Rebinding replaces the local target. Binding and watching use the same pet ID and library.

```sh
python3 agent_events.py bind "$PET_ID" "$SOURCE" "$SESSION" "$CONVERSATION_URL"
python3 agent_events.py watch "$PET_ID"
# From another terminal, using the same source and session
python3 agent_events.py emit "$PET_ID" < event.json
```

Pure HTML runs offline. In the exported pet, start the sample session reminder and drag the pet while the notice is visible. End the sample to dismiss the notice. A connected embedding can supply real events using stage.feedback.dispatch(event). Without session.open, the pet shows the summary and the source/session for manual return. Standalone HTML never monitors other applications.

## Future extensions

Apply the same capability negotiation to sound and notifications. Exclusive performances can later request a time-limited lease that user gestures revoke. Network providers and cross-device delivery belong to opt-in integrations. These are design directions. The current example implements a notice and user-initiated session return.

## macOS desktop host v1

Every native build uses the same AppKit host. The pet context menu starts with enabled plugin actions. Both menus offer show/hide, settings and quit. The menu-bar item groups visible plugin actions under Interactions. Keep configuration, window recovery and export in settings. Both menus route to the same handlers. Hiding explicitly suspends player feedback. Reopening the app shows the existing panel.

Window size, floating level, opacity, name visibility, remembered position and the optional global visibility shortcut belong to this device and pet identity. The shortcut starts unbound. Register a replacement with the OS before releasing the existing registration. On conflict, leave the previous binding and stored preference intact. Clearing the shortcut releases it. Screen changes constrain the window to a visible display. Resetting window position and resetting preferences are separate commands.

Mouse pass-through is off by default. Settings remain accessible from the menu bar when the pet ignores mouse events. Full-screen avoidance is on by default and uses native macOS full-screen Spaces. Space transitions never issue a show command, so manually ordering out the pet also keeps it hidden on return. Both preferences are local to the pet and can be changed in desktop settings.

The bundled macOS 13+ app reads and changes its own login-item registration through SMAppService. Settings report system approval or registration errors. Unbundled previews do not register. The plugin manager shows installed versions and applies enablement changes to the mounted player. Active sessions, notices and unrelated workers survive these edits. Device preferences restore individual plugin overrides before startup; exporting the character records the current enabled IDs. Interaction labels, visibility and ordering remain device preferences. Reset Menu restores the default arrangement without changing plugin enablement. Fixed host recovery commands remain available with every plugin disabled. The host suspends player feedback on workspace sleep and reconciles visibility on wake.

## Client identity

Use Jiumi as the default client name for the application bundle, system display name, permission requests, login item and settings window. Keep the pet name in character data and its label. Override the client name only when the user explicitly requests a client name.

## Settings and interaction defaults

The standard host uses the sugar-cube chick for its app and status item. The creator passes en or zh-CN from the request language into defaultLanguage. Explicit user language choices take precedence. App & System changes the interface live and persists the override per device. Appearance exposes the minimum and maximum idle interval (initially 8 and 20 seconds).

Plugins & Interactions lists every installed module, including disabled modules, in a native table. Center the name and version with the switch and information button and retain trailing padding. Double-clicking a row opens its details without changing enablement.

The built-in chatter module is enabled for new pets. The optional typing module observes host-provided timing, alternates type-left/type-right and renews its five-second timeout on each stroke. Only the user can enable cross-application input in the native host. See [the plugin SDK](plugin-sdk.md) for speech, interruption and recovery.
