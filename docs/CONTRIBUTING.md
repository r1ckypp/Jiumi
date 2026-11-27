# Contributing to Jiumi

**English** · [简体中文](zh-CN/CONTRIBUTING.zh-CN.md)

A useful first contribution might be a clearer translation, a pet that demonstrates a missing motion, or an adapter for a tool you already use. Describe what the pet should do and how someone can see the change on their own machine.

## Build a working copy

Use Node.js 20 or later, npm 10 or later, and Python 3. From the repository root:

```sh
npm ci
npm run build
node tests/event_feedback.cjs
```

Open `dist/maker.html`, create a pet, and try the exported HTML with networking disabled. Edit the maker's TypeScript in `src/` and rebuild the checked-in browser output. Edit the focus timer in `examples/focus-timer/index.ts` and rebuild its JSON module with the same command.

## Choose a check for your change

The browser checks use Python Playwright and Google Chrome. Install Playwright in a virtual environment with `python3 -m pip install playwright` and use a machine with Chrome installed. Run commands from the repository root.

| Changed area | What to run |
| --- | --- |
| Events, priorities or interruption | `node tests/event_feedback.cjs` |
| Maker, PNG frames or HTML export | `python3 tests/offline_maker.py` |
| Plugin imports, lifecycle or saved state | `python3 tests/offline_modules.py` |
| Local hook and Unix socket | `python3 tests/event_bridge.py` on macOS |
| Floating macOS application | `python3 tests/desktop_bundle.py` on macOS with Swift command-line tools and a graphical session |

## Report a bug or propose a change

- For a bug, give the host, OS, browser or runtime version, and the smallest sequence that shows the problem. Say what you expected and what happened. A tiny pet package made with shareable art is especially helpful for animation bugs.
- For a new plugin or adapter, describe its input event, requested capabilities, visible reaction and offline behavior. For changes to the package format, explain how an older pet will still open.
- For a pull request, keep related changes together. Describe the user-visible result, link a related issue when available, and list the checks you actually ran. A before-and-after frame or short recording helps reviewers evaluate visual edits.
- Keep example artwork and module dependencies redistributable. Identify their source and license. Contribute original work or work you are authorized to submit under the repository license.

## Translate and review

Project and community translations live in `docs/zh-CN/`. Keep English Skill instructions in `skill/jiumi-pet/` and Chinese instructions in `skill/jiumi-pet-zh/`. Maintain design specifications in English under `docs/spec/`. For behavior changes, update the relevant specification, both sets of user instructions and the example. Keep tool names, file names, protocol fields and commands intact. Small fixes and reports are welcome in either language.

Discuss ideas respectfully, protect other people's private data and give feedback about the work. See the [community guidelines](CODE_OF_CONDUCT.md) and [private security reporting guidance](SECURITY.md).

## Commits and pull request titles

Maintainers, external contributors and agents use the same English title format for each commit and PR. Use `type(scope): summary`. Choose the primary area as the scope, in lowercase letters, digits and hyphens. Write a short verb phrase that describes one observable change. Put motivation and trade-offs in the body. For a breaking change use `type(scope)!: summary` and include a `BREAKING CHANGE:` paragraph with migration steps.

| Type | Use |
| --- | --- |
| `feat`, `fix` | A capability or a bug fix |
| `docs`, `test` | Documentation or test coverage |
| `refactor`, `perf` | Internal restructuring or performance |
| `build`, `ci`, `chore` | Packaging, automation or repository maintenance |
| `revert` | Undo a change and identify the original commit in the body |

Examples include `fix(maker): keep the pet name when switching languages`, `feat(player): animate landing after a drag` and `docs(skill): explain how to import custom artwork`. Other common scopes include `desktop`, `plugins`, `events` and `repo`. GitHub adds the PR number when squash-merging.

## From issue to merge

1. Search open and closed issues and PRs. Add new evidence to an existing report. Open a bug or feature form for a distinct problem. English and Simplified Chinese forms are available. Give a bug title that names the failing action and symptom, such as “Dragging a pet hides the session reminder”. For a proposal, name the capability, such as “Let a timer plugin play a custom motion”. For a proposed capability, describe the user interaction and what would demonstrate success. Small, self-contained fixes and translations can go straight to a PR. Discuss changes to public contracts or new platform support before investing in implementation.
2. Branch from the latest `main` in your fork or checkout. Keep each commit focused. Open a PR against `main` with the title format above. Link a related issue with `Refs #123`, or use `Closes #123` when merging resolves it.
3. Explain the problem, the change and the checks you ran with observed results. Identify any untested host. Attach screenshots for appearance changes and a short recording for motion or timing. List compatibility or migration steps when an existing pet or plugin is affected. Contributors own the result, including work produced with an agent.
4. Reviewers check the reported behavior, relevant tests, compatibility, artwork rights and paired documentation. Maintainers label confirmed bugs with `bug` and proposals with `enhancement`. When closing a duplicate, link the original. When more evidence is needed, ask for a specific reproduction step or result.
5. Address feedback on the same branch. Maintainers check the final title and verification evidence, then squash-merge with the PR title. Each merged PR contributes one change to the history of `main`. The PR title workflow checks the format when a PR opens, changes title or receives new commits.

[Open an issue](https://github.com/r1ckypp/jiumi/issues/new/choose) · [Browse existing pull requests](https://github.com/r1ckypp/jiumi/pulls)
