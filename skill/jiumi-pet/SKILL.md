---
name: jiumi-pet
description: Create a desktop pet locally from a preset or your PNG. Preview, pet and drag it offline, then export a standalone HTML file.
---

# Create a Jiumi pet

Use the user's description to deliver a ready-to-play character. Default to the sugar-cube chick; for a named animal use its preset (e.g. `--animal pig`). Set `--color` only when requested. Ordinary creations use pre-aligned moving parts. Skip technical choices and joint setup.

Run `python3 pet.py create "NAME" --language en --output "DIRECTORY"`. Deliver the HTML preview and the matching desktop build on macOS or Windows. On Windows, run with `python` if `python3` is unavailable, keep the complete `Jiumi-Windows` folder together, and launch `Jiumi.exe`. The notification-area icon controls visibility, position reset and quit. On macOS, double-click the app and manage it from the Jiumi menu-bar icon. Use `--html-only` for an HTML-only request. Preserve supplied artwork with `--image`.

Pass `--language` to match the language of the creation request: `en` for English or `zh-CN` for Chinese. Honor an explicitly requested interface language first. Determine this from the request itself, independently of the pet name or the language of this guide. The user can change it later in Settings → App & System → Interface language.


Load [articulation](references/articulation.md) only when the brief needs independently articulated humanoid limbs, custom part art or a special frame performance. Infer needs from the requested actions. Ask only about a material creative choice the description leaves open.

For local import, launch, plugins or event hooks, consult [local workflows](references/workflows.md) as needed.

For a community installation on an existing pet, use the fixed ID and version from the detail page with remote MCP get_community_module. Inspect the existing character and preserve its motions. Pass the downloaded JSON to local install_pet_module or run `python3 pet.py install-module UUID module.json --module-id ID --version N`. Supply missing character clips through `--clips clips.json` (a map of motion IDs to frame sequences). Export and try the command offline.

The macOS v1 host includes an interaction-first context menu, a management menu in the menu bar, window preferences and an optional per-pet global visibility shortcut. Keep the pet UUID when rebuilding to retain its device settings.

Toggle mouse pass-through in desktop settings, accessible from the Jiumi menu-bar icon. By default the pet stays out of native full-screen Spaces and returns when leaving them unless manually hidden.

In Desktop Settings, macOS 13+ app bundles can opt into Open at Login. Plugins & Interaction Menu shows installed versions, enables and disables plugins live, and edits the order, visibility and names of interaction commands. Export the character package to carry the enabled selection.

## Client identity

Use Jiumi as the default client name for the application bundle, system display name, permission requests, login item and settings window. Keep the pet name in character data and its label. Override the client name only when the user explicitly requests a client name.

For desktop creation, interaction plugins or changes to settings and menus, follow the [desktop client standards](references/desktop-client.md).
