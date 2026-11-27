# Local workflows

## Create and keep a pet

Open the bundled `maker.html`, choose a preset or import a transparent PNG, name the pet, then click or hold and drag it. Export the pet as HTML to play with it, or export its JSON package to continue editing it with another agent. Keep the UUID when editing the same character.

From the Skill directory, import the package into the local library. Substitute the UUID returned by import for PET_ID.

```sh
python3 pet.py import pet.json
python3 pet.py local
python3 pet.py preview PET_ID
```

On macOS or Windows, run `python3 pet.py open PET_ID` to launch the floating pet. Use the macOS menu-bar or Windows notification-area icon for visibility and settings. Run `python3 pet.py desktop-app PET_ID OUTPUT_DIRECTORY` to deliver a standalone app.

If an existing desktop build fails, use the original character JSON and preview. If only the local library is available, open its maker with `python3 pet.py preview PET_ID` and export the character JSON and HTML there. On Windows, an unavailable `dotnet` command means the builder cannot invoke the .NET SDK. See the Windows prerequisites in the desktop client standards.

## Motions and plugins

In the animation frames section, choose a motion and import transparent PNGs numbered in playback order. Use `held` for pickup and `landing` for release. Align feet and attachment points across frames. Override individual motions as needed. Larger libraries can list alternatives in `motionPools.working`.

For an existing pet, inspect installed modules and enabled IDs first. For a community module, obtain the selected ID and version with remote MCP get_community_module. Install its full JSON with local install_pet_module or `python3 pet.py install-module PET_ID module.json --module-id ID --version N`. For a bundled module, use its local JSON and declared version. Supply missing motions with `--clips clips.json` (motion names mapped to clip definitions). Preserve existing motions and unrelated opt-outs. Open the returned preview and export the updated character. For desktop settings or typing, use the [desktop client standards](desktop-client.md).

For the typing companion, render two aligned transparent PNG poses from the same character, lowering the left wing in one and the right wing in the other. Keep the body and canvas fixed. In clips.json, map each missing motion (`type-left` or `type-right`) to an object with `frames` (a list of PNG data URLs), `frameMs` (e.g. 100) and `loop: false`. A single pose per side suffices. Install with `python3 pet.py install-module PET_ID examples/typing.json --module-id typing --version 2 --clips clips.json` for the bundled v2 module.

Import the bundled `examples/focus-timer.json` in the local plugins section and enable it. Copy `examples/pickup.json` to author a reusable interaction graph. For session notices, pass `--module examples/agent-confirm.json` when creating the pet.

When a user requests local monitoring on macOS, run `python3 agent_events.py watch PET_ID`. In the project they select, configure a Claude Code hook to call `python3 /absolute/path/agent_events.py claude PET_ID`. Other hosts can dispatch v1 events through the player. See EVENT-SPEC.md and host-capabilities.md in the distribution for event and session binding details.
