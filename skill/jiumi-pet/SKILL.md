---
name: jiumi-pet
description: Create a desktop pet locally from a preset or your PNG. Preview, pet and drag it offline, then export a standalone HTML file.
---

# Create a Jiumi pet
**English** · [Simplified Chinese](SKILL.zh-CN.md)


Use the user's description to deliver a ready-to-play character. Default to the sugar-cube chick; for a named animal use its preset (e.g. `--animal pig`). Set `--color` only when requested. Ordinary creations use pre-aligned moving parts. Skip technical choices and joint setup.

Run `python3 pet.py create "NAME" --output "DIRECTORY"`. Deliver the HTML preview and, on macOS, the matching app. Double-click the app for the floating pet; use the paw menu to hide, show or adjust it. Use `--html-only` for an HTML-only request. Preserve supplied artwork with `--image`.

Load [articulation](references/articulation.md) only when the brief needs independently articulated humanoid limbs, custom part art or a special frame performance. Infer needs from the requested actions. Ask only about a material creative choice the description leaves open.

For local import, launch, plugins or event hooks, consult [local workflows](references/workflows.md) as needed.
