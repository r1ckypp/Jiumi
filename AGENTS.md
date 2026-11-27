# Contributing to the Jiumi framework

**English** · [简体中文](docs/zh-CN/AGENTS.zh-CN.md)

Jiumi is a lightweight, extensible framework for desktop pets. A creator can supply their own artwork, make a character with their preferred agent or the standalone maker, and run, edit and export it entirely offline. Keep this workflow independent of accounts and running services. External services are optional integrations. See the [README](README.md) for current capabilities.

## Creating and rendering a character

- Start with a description or an image. Preserve the character’s identity, artwork, settings and plugins across edits. A change to eye color should affect only the eyes.
- Use pre-aligned sugar-cube parts by default, with the cream-yellow chick as the starter character. Infer the renderer from the requested character and actions. Load articulated humanoid guidance when a movement needs linked joints. An individual motion can use supplied animation frames. All renderers respond to the same motion names. [Character rendering](docs/spec/character-rendering.md)
- Ship an editable character package and a working host template with local saves, settings and plugin loading. Keep the maker and public types in TypeScript and embed compiled output in the distribution. The standalone maker and exported HTML must work directly from a local file. Use the same player for previews and native windows. On macOS, a creation request normally delivers both an HTML preview and a double-clickable app. [Offline design](docs/spec/offline-pet.md)

## Extending behavior

Adapters report events, plugins request feedback, the host arbitrates interruptions, and each character renders the result. Define entry, exit and recovery in the plugin so adding a behavior does not require changing every host. Keep a runnable example that demonstrates subscription, feedback and cleanup. [Events and feedback](docs/spec/event-feedback.md)

Keep body motion, session notices and user actions independent. Dragging a pet can interrupt its animation while a pending notice remains available. Each host advertises the actions it can perform. Enable local monitoring only at the user’s request. [Host capabilities](docs/spec/host-capabilities.md)

## Host lifecycle and portability

A stable pet ID travels with the artwork, settings, enabled plugins and revision. A running instance belongs to one launch on one device. Keep window position, visibility, device permissions and session destinations local.

| Phase | Host behavior |
| --- | --- |
| First launch | Create defaults and a local save. Show the pet and a way to manage it. |
| Ready | Restore settings and enabled plugins. Report readiness once assets, controls and event handling are available. Keep the pet usable if an optional plugin fails. |
| Running | Coordinate idle motion, touch and movement. After a reaction, resume the applicable state. |
| Hide and show | Keep a way to recall the same instance, such as a menu bar or tray item. Provide controls for visibility, position reset, settings and quit. |
| Suspend and resume | Reconcile elapsed time and task state. Settle each expired reminder once. |
| Exit and recover | Release plugin resources and persist confirmed edits. Reopen the same character with its customization intact. |

## Acceptance and maintenance

Test the baseline offline with a single image and optional plugins disabled. Check preview, touch, HTML export and reopening. For a desktop host, also check hiding and recalling the pet. Test extension enablement, interruption, recovery and failure separately.

Keep entry points and community guides bilingual. Maintain separate English and Chinese Skill directories. Write design specifications in English under `docs/spec/`. Record confirmed design decisions and distinguish implemented behavior from proposals. Use project terminology in names, comments and attribution. Answer requests for advice without editing files unless implementation is requested.

## Submitting changes

Follow the [contribution workflow](docs/CONTRIBUTING.md#commits-and-pull-request-titles) for every commit, issue and pull request. Use English `type(scope): summary` commit and PR titles, report actual verification results, and squash-merge each reviewed PR using its title.

## Client identity

Use Jiumi as the default client name for the application bundle, system display name, permission requests, login item and settings window. Keep the pet name in character data and its label. Override the client name only when the user explicitly requests a client name.

Use the [client authoring guide](skill/jiumi-pet/references/desktop-client.md) for language, icon, native controls and plugin defaults. Keep its Chinese edition and the official distribution aligned with the host contract.
