# Making a Jiumi desktop client

Build with the bundled pet.py and shared player. Keep the existing UUID when editing a character. Use Jiumi.app and the sugar-cube chick application and menu-bar icon across characters. Only an explicit client-name request overrides Jiumi. Pass the language of the creation request with --language en or --language zh-CN. Explicit language requests take priority. The saved device preference wins on subsequent launches.

## Settings and menus

Keep show/hide, Settings and Quit in both native menus. Visible plugin actions are available directly on right-click and grouped under Interactions in the menu bar. Put position recovery and click-through under Pet Window, typing permissions under Input & Permissions, export under About, and language under App & System. Appearance controls theme, pet size, opacity, name and idle timing. Keep the visibility shortcut and login setting in their existing pages.

Use the native searchable sidebar and installed-plugin list. Show name, version, a per-row switch and an information button. Double-clicking the name or version opens the same details without toggling the plugin. Vertically center text with the controls and preserve the trailing inset. Include disabled plugins and keep their switch state across launches.

## Authoring behavior

- New pets include the enabled local speech pack in runtime/chatter.json. It selects a line after 35–80 seconds, shows it for 5 seconds and avoids an immediate repeat when alternatives exist. Pause it while hidden or displaying a session notice. Preserve opt-outs on edits. Community speech packs may supply their own text and timing. Screen capture and model calls would need additional host capabilities and consent.
- For a typing companion, install examples/typing.json and provide type-left and type-right motion clips for the character. Desktop monitoring is opt-in. In HTML, input comes from the focused page. Each stroke changes the wing pose immediately and refreshes a five-second inactivity timeout. Only timing reaches the plugin. A held pet keeps its higher-priority pose. At timeout, resume the underlying state.
- Use a state machine's timeoutMs for temporary states and after for transitions on motion completion. For idle variety, give the character a motionPools.idle array with its available motions. The player breathes between actions and samples a fresh wait each cycle (default 8–20 seconds, configurable in Appearance). Typing inactivity and idle pacing are separate settings.

For acceptance, try the packaged character offline. Toggle a plugin and reopen the client. For a typing build, test individual strokes, a burst, five seconds of silence, two idle actions, and pickup during a burst. Verify the initial language and a saved manual switch. Keep the HTML preview and the native app on the same player.
