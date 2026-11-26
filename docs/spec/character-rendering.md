# Portable character rendering

[Simplified Chinese](character-rendering.zh-CN.md)

An unspecified creation uses the sugar chick. A requested species uses its preset. An explicit humanoid with complex coordinated movements uses the human skeleton; choose knight equipment for a knight brief. The assistant infers this from the user's brief. Single supplied portraits and previously issued packages keep their artwork. User-facing creation has no renderer selector.

The optional portable rig names the sugar or humanoid performer and carries its layers and local pose tracks. Sugar animals use siblings for ears, feet, arms, body, muzzle and eyes. Preset origins are fixed in a 160-unit square. The humanoid uses forward kinematics: torso → thigh → shin, torso → upper arm → forearm → equipment, torso → head → plume. Built-in tracks cover pickup, landing and idle; custom tracks specify duration in milliseconds and an ordered list of local rotation angles in degrees per joint. Playback interpolates these across one duration. A layer replaces the drawable at a joint while retaining its children. A missing layer uses the preset drawing.

Common attachment IDs include body, eyes, muzzle, earLeft, armRight and legLeft. Additional humanoid IDs include torso, plate, shinLeft, forearmRight, head, plume, shield and blade. A PNG attachment places its pivot at the centre of a 160-square artboard. Package validation bounds attachment count, image bytes, track lengths, angles and duration.

The input adapter emits pet.grab and pet.release. The pickup graph enters held, then landing, and resumes the prior state when playback completes. The player chooses a direct clip or mapped performance, then a rig pose or whole-image motion. A named clip overrides the matching pose. Cancelling playback cancels joint animations and frame timers together. Reduced motion skips transient playback. A known-character HTML embeds only its required performer. Archives include rig data; plugins and adapters do not depend on rig type.
