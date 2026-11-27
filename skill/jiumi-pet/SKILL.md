---
name: jiumi-pet
description: Create or edit a Jiumi desktop pet locally. Use for characters made from a description or PNG, adding motions or plugins to an existing pet, or delivering an offline HTML preview or a macOS or Windows desktop client.
---

# Create or edit a Jiumi pet

Identify the character first, then choose the deliverable. Run commands from the extracted Skill directory. On Windows, use `python` if needed. From a source checkout, run `python3 integrations/local/build.py` at the repository root and extract the Skill archive for the desired language.

| User request | Starting point |
| --- | --- |
| Create a character | Run `python3 pet.py create "NAME" --language en --output "DIRECTORY"`. Add `--image "art.png"` for supplied artwork. Default to the cream-yellow sugar-cube chick. Use the requested animal preset and pass `--color` only for a requested color. |
| Edit a character or install a plugin | Locate its UUID with `python3 pet.py local` or import the user's character package. Inspect existing art, motions and plugin choices. Change only what was requested and retain the UUID and saved language. See [local workflows](references/workflows.md). |
| Deliver HTML only | Add `--html-only` when creating a character, or export from its existing maker page. Creation returns a maker preview. Use “Export pet HTML” for the standalone player, then open it offline and check the artwork and interaction. |
| Deliver a desktop client | Creation also attempts a native build on macOS and Windows by default. For an existing pet run `python3 pet.py desktop-app PET_ID "DIRECTORY"`. |

For a new character, pass `--language en` or `--language zh-CN` to match the request. An explicitly requested interface language takes priority. Use Jiumi for the application, permission prompts, login item and settings. Keep the character's name in its data and label. Override Jiumi only on an explicit client-name request.

## Desktop delivery and recovery

Try the project template on the user's machine first. Build on the target OS: the template selects the current host. A Mac produces a macOS app, and a Windows machine produces the Windows folder. Deliver the launchable app on macOS, or the complete Jiumi-Windows folder containing Jiumi.exe on Windows. Open the client and verify the user's character and requested interactions.

- If creation returns `desktop_error`, keep its pet ID and working HTML preview. Resolve the reported problem where possible and retry only `desktop-app`.
- If Python is unavailable, open the bundled `maker.html` in a browser, select the requested interface language, and import a PNG and export editable character JSON and HTML. For an existing pet, use its own maker page. If only its JSON is available, retain the package for a tool that supports importing it.
- If the target client still cannot be built locally, explain the blocker. Check the [official GitHub Releases](https://github.com/r1ckypp/Jiumi/releases) for the OS, architecture and a documented way to load local character data. Direct the user to a compatible asset, assemble it with their artwork locally and open it to verify. If compatibility, loading or launch cannot be verified, deliver the available character files and working preview and identify the pending desktop work.

Use pre-aligned parts for ordinary characters. Consult [articulation](references/articulation.md) for jointed motion, custom parts or frame performances. For desktop creation, interaction plugins or settings changes, follow the [desktop client standards](references/desktop-client.md).
