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

Apply the same capability negotiation to menu contributions, sound and notifications. Exclusive performances can later request a time-limited lease that user gestures revoke. Network providers and cross-device delivery belong to opt-in integrations. These are design directions. The current example implements a notice and user-initiated session return.
