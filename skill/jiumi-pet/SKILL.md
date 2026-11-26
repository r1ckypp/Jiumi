---
name: jiumi-pet
description: Create a desktop pet locally from a preset or your PNG. Preview, pet and drag it offline, then export a standalone HTML file.
---

# Create a Jiumi pet

Use the user's description to deliver a ready-to-play character. Default to the sugar-cube chick; for a named animal use its preset (e.g. `--animal pig`). Set `--color` only when requested. Ordinary creations use pre-aligned moving parts. Skip technical choices and joint setup.

Run `python3 pet.py create "NAME" --output "DIRECTORY"`. Deliver the HTML preview and, on macOS, the matching app. Double-click the app for the floating pet; use the paw menu to hide, show or adjust it. Use `--html-only` for an HTML-only request. Preserve supplied artwork with `--image`.

Load [articulation](references/articulation.md) only when the brief needs independently articulated humanoid limbs, custom part art or a special frame performance. Infer needs from the requested actions. Ask only about a material creative choice the description leaves open.

For local import, launch, plugins or event hooks, consult [local workflows](references/workflows.md) as needed.

For a community installation on an existing pet, use the fixed ID and version from the detail page with remote MCP get_community_module. Inspect the existing character and preserve its motions. Pass the downloaded JSON to local install_pet_module or run `python3 pet.py install-module UUID module.json --module-id ID --version N`. Supply missing character clips through `--clips clips.json` (a map of motion IDs to frame sequences). Export and try the command offline.

The macOS v1 host includes an interaction-first context menu, a management menu in the menu bar, window preferences and an optional per-pet global visibility shortcut. Keep the pet UUID when rebuilding to retain its device settings.

Enable mouse pass-through in desktop settings and turn it off from the paw menu. By default the pet stays out of native full-screen Spaces and returns when leaving them unless manually hidden.
