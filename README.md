# Jiumi

**English** · [Simplified Chinese](docs/zh-CN/README.zh-CN.md) · [Documentation](docs/README.md)

Jiumi is a lightweight, extensible framework that makes it easy for any agent to build custom desktop pets.

## Tell your agent

```text
Use this skill: https://github.com/r1ckypp/jiumi/tree/main/skill/jiumi-pet
Make me a blue jiumi named Bubble.
```

![Creating a Jiumi desktop pet with an agent.](docs/assets/create-jiumi-with-agent.gif)

## What you can customize

- **Your artwork, your pet.** A single transparent PNG is enough to start. Add animation frames for a blink or a wave, change how your pet reacts to touch, or extend its behavior with local plugins.
- **Bring your own agent.** An assistant that can read the Skill and run local scripts can follow the creation workflow. See the [support matrix](#desktop-agent-support-matrix) for app-specific integrations.
- **One pet across platforms.** Open the HTML edition in a browser on macOS, Windows, or Linux. On macOS, you can also run it as a floating desktop companion. Native support for more platforms and a mobile experience for Android and iOS are on the roadmap.

## Use the local pet maker

1. Unpack the Skill and open `jiumi-pet/maker.html` in your browser. From a source checkout, run the following command at the repository root, then open `dist/maker.html`.

   ```sh
   python3 integrations/local/build.py
   ```

2. Choose a character or import your own transparent PNG, then give your pet a name. Click your pet to stroke it, or hold and drag to pick it up. Release to watch it land.
3. Use the HTML export at the bottom of the maker to save your pet. Open the downloaded file to play. To keep editing the same character later, also export its JSON package.

![Choose a character, name it, export it and click to pet it.](docs/assets/pet-maker-en.gif)

The source build also produces `dist/jiumi-pet-skill.zip` and `dist/jiumi-local.zip` for compatible plugin hosts. [Skill guide](skill/jiumi-pet/SKILL.md)

Hosted platforms are optional integrations. Your agent creates the pet, and the finished files run on your device.

## Extend Jiumi

Try the bundled focus timer. Expand the local plugins section in the maker and import the timer’s JSON file. Once enabled, the plugin starts a 25-minute timer when it receives an `agent.started` event. The pet saves the deadline. [Example source](examples/focus-timer/index.ts) · [Installable module](examples/modules/focus-timer.json) · [Plugin SDK](docs/spec/plugin-sdk.md)

| If you want to… | Start here |
| --- | --- |
| Create a pet through your assistant | [Skill guide](skill/jiumi-pet/SKILL.md) |
| Connect a tool or map an event to a motion | [Events and feedback](docs/spec/event-feedback.md) |
| Work with a pet package | [Local runtime design](docs/spec/offline-pet.md) · [JSON Schema](docs/spec/contracts.schema.json) |
| Build, test, translate or submit a change | [Contributing](docs/CONTRIBUTING.md) · [Project guidance](AGENTS.md) |

## Roadmap

### Available today

- **Create and keep a pet locally.** Describe a character to an agent or open the bilingual maker with your own PNG. Export a playable HTML file and an editable package that preserves the pet’s ID, artwork and plugin choices. On macOS, the Skill can also build a floating app with menu bar controls. [Local runtime](docs/spec/offline-pet.md)
- **Reuse the same interactions across characters.** Sugar-cube pets use pre-aligned parts, while articulated humanoids use a skeleton. A PNG sequence can override a single motion. Both renderers use the same pickup and landing plugin. [Character rendering](docs/spec/character-rendering.md) · [Plugin SDK](docs/spec/plugin-sdk.md)
- **Respond to tools through local plugins.** Plugins can define when a pet enters, leaves or resumes a state. An opt-in Claude Code CLI hook on macOS can trigger a confirmation notice that stays visible while the pet is dragged. Clicking it can reopen the session when the host has a local binding. [Events](docs/spec/event-feedback.md) · [Host capabilities](docs/spec/host-capabilities.md)

### Planned

- **Desktop agent plugins are the first priority.** Start with ChatGPT desktop on macOS: install the plugin, create a pet in a fresh session, open its preview and uninstall. Then target Doubao Work, WorkBuddy and QwenWork. Where the client exposes session events, verify the confirmation notice and return to the originating session.
- **Sprite-sheet import.** Slice a single sheet into ordered frames for the existing motion editor. Today it accepts individual PNG frames. [Motion assets](docs/spec/offline-pet.md)
- **More platforms.** Extend native floating pets to Windows and Linux, where the standalone HTML edition works today. Android and iOS are longer-term goals. Mobile interaction and distribution are still open design questions. [Current platform support](docs/spec/offline-pet.md)

### Under consideration

- Let plugins request menu items, sound or system notifications when the host supports them. Optional network access would require explicit, revocable permission and would keep local pets usable without a connection. [Host capabilities](docs/spec/host-capabilities.md) · [Plugin distribution](docs/spec/offline-pet.md)

## Desktop agent support matrix

This matrix tracks Jiumi integration work. macOS is the first test platform. Exported HTML opens on Windows and Linux today. Plugin installation, creation inside each client and session integration on those two systems still need verification.

| Desktop client | Priority | Create via Skill | Installable plugin | Session events and return |
| --- | --- | --- | --- | --- |
| [ChatGPT desktop](https://learn.chatgpt.com/docs/plugins) | First | HTML creation tried on macOS | Local install tried on macOS | Desktop test pending |
| [Doubao Work](https://www.doubao.com/work) | Next | To verify | To investigate | To investigate |
| [WorkBuddy](https://cloud.tencent.com/product/workbuddy) | Next | To verify | To investigate | To investigate |
| [QwenWork](https://qwenwork.cn/docs/desktop) | Next | To verify | To investigate | To investigate |
| [Cursor](https://prod.cursor.com/docs/reference/third-party-hooks) | Candidate | To verify | To investigate | Evaluate Claude hook reuse |

Mark a capability verified after exercising it in the named client on the named OS. Update both matrices with the client version, OS, test date and a reproducible check or report. For creation, check a fresh install, invocation, export and uninstall. For sessions, check event delivery, dragging with the notice visible and returning to the correct conversation. See the [local bridge test](tests/event_bridge.py) and [session notice test](tests/session_notice.py).

### Command-line tools

| CLI | Create a pet from the terminal | Session events |
| --- | --- | --- |
| Codex CLI | Skill invocation and export to verify | To investigate |
| Claude Code CLI | Skill invocation and export to verify | macOS hook adapter tested locally. [Event specification](docs/spec/event-feedback.md) |

## License

Jiumi's open core and its documentation are distributed under the MIT License. Official character artwork is maintained separately. For third-party art or plugins, check the terms supplied with those files. [MIT License](LICENSE)
