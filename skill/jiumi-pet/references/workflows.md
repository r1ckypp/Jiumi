# Local workflows

## Create and keep a pet

Open the bundled `maker.html`, choose a preset or import a transparent PNG, name the pet, then click or hold and drag it. Export the pet as HTML to play with it, or export its JSON package to continue editing it with another agent. Keep the UUID when editing the same character.

From the Skill directory, import the package into the local library. Substitute the UUID returned by import for PET_ID.

```sh
python3 pet.py import pet.json
python3 pet.py local
python3 pet.py preview PET_ID
```

On macOS, run `python3 pet.py open PET_ID` to launch the floating pet. Use the paw menu for visibility and settings. Run `python3 pet.py desktop-app PET_ID OUTPUT_DIRECTORY` to deliver a standalone app.

## Motions and plugins

In the animation frames section, choose a motion and import transparent PNGs numbered in playback order. Use `held` for pickup and `landing` for release. Align feet and attachment points across frames. Override individual motions as needed. Larger libraries can list alternatives in `motionPools.working`.

Import the bundled `examples/focus-timer.json` in the local plugins section and enable it. Copy `examples/pickup.json` to author a reusable interaction graph. For session notices, pass `--module examples/agent-confirm.json` when creating the pet.

When a user requests local monitoring on macOS, run `python3 agent_events.py watch PET_ID`. In the project they select, configure a Claude Code hook to call `python3 /absolute/path/agent_events.py claude PET_ID`. Other hosts can dispatch v1 events through the player. See EVENT-SPEC.md and host-capabilities.md in the distribution for event and session binding details.
