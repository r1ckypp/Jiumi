# Articulated characters and individual performances

For a humanoid whose acting needs linked arms and knees (running, swordplay), use `pet.py create NAME --character humanoid`, or `--character knight` for the helmet, shield and sword. The built-in run and swing tracks are ready to preview. Reuse sugar presets for cube animals. For a custom animal, start with the closest body plan and replace the necessary attachments.

Both templates accept `--layers layers.json`, a map from joint names to embedded transparent PNG data URLs. Each texture uses a 160×160 canvas with the attachment at (80,80). Keep only the artwork of that part on its layer. A forearm inherits its upper arm's rotation. See the rendering spec for joint names and angle tracks. A single flattened portrait stays intact when imported with --image.

To override one action, supply the existing numbered PNG clip under its motion name (e.g. clips.landing). Import it through the frame editor, or import a complete package. Leave other slots empty to retain template animation. Always test a short tap, a hold followed by release, and a second grab during landing. No account or network connection is needed.
