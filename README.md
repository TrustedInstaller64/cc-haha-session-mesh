# cc-haha Session Mesh

[简体中文](README.zh-CN.md)

A small Swift CLI that lets cc-haha desktop sessions in the same project find each other, read context, and exchange messages. The repo also includes a session policy skill and a template for starting new sessions.

Status: messaging, session creation, the PreToolUse recursion guard, and installation have been tested locally. A file inbox is not implemented. License: MIT.

## Quick start

```sh
make build
./.build/release/session-mesh install --dry-run
./.build/release/session-mesh install
./.build/release/session-mesh doctor
```

Sessions that are already open do not load new hooks automatically. Open `/hooks` once, or start a new session in the repo. Later prompts include `[mesh-roster]`, `[mesh-peer]`, and `[mesh-policy]`.

## Installation

Requirements:

- macOS 26
- Swift 6.2 toolchain (`Package.swift` uses tools 6.2; the source stays in Swift 5 language mode)
- No third-party dependencies

Build and test:

```sh
swift build -c release
swift test

# or use the Makefile
make build
make test
```

The default scope is `project`, with the current directory as the project root:

- hooks: merged into the repo's `.claude/settings.local.json`
- skill: repo `.claude/skills/session-mesh/SKILL.md`
- binary: `~/.claude/session-mesh/bin/session-mesh`
- backups: `~/.claude/session-mesh/backup/`

`--scope user` writes the global locations:

- hooks: `~/.claude/settings.json`
- skill: `~/.claude/skills/session-mesh/SKILL.md`

```sh
session-mesh install --dry-run          # preview targets, no writes
session-mesh install --check            # inspect installed state, no writes
session-mesh install                    # default project scope
session-mesh install --scope user       # global install
session-mesh uninstall --dry-run
```

Apply writes settings and installs files. Run `--dry-run` or `--check` first, check the backup path, and decide whether to write. `make install` only copies the release binary; hooks are written only by `session-mesh install`.

## Commands

- `session-mesh install [--dry-run | --check] [--scope project|user]`: install or merge five hooks (SessionStart, UserPromptSubmit, Stop, SessionEnd, PreToolUse); project scope by default. PreToolUse matches only `CreateSession|CreateSessions` and blocks recursive session creation from child sessions.
- `session-mesh uninstall [--dry-run] [--scope project|user]`: remove only hooks and skill files owned by this binary; the shared binary stays in place.
- `session-mesh doctor`: read-only checks for the toolchain, runtime directory permissions, install state, settings, and local API; exits 1 on failure.
- `session-mesh help`: print usage. Unknown commands exit 2; runtime failures exit 1.
- `session-mesh hook-start | hook-prompt | hook-stop | hook-end | hook-guard`: internal hook entry points; always exit 0. Do not call them by hand.

## Workflow

1. Start with the roster. `[mesh-roster]` lists same-project peers with id, state, last_seen, and title. Without a roster, use `ListSessions` filtered by projectRoot.
2. Need context: use `ReadSession <peer-id>` for the latest page and take only facts relevant to the task.
3. Need to collaborate: send one message of at most 500 characters with `SendSessionMessage`, including the source and the response you need. Wait with a bounded `WaitSessions`. A receipt is not completion; confirm with `ReadSession`.
4. Need a new session: check the roster and `ListSessions` first and reuse an existing session when possible. Title format: `<project short name> · <role> · <task>`. The prompt has eight sections. Create at most two sessions per request. The user confirms the model card.
5. Need parallel work or research: enable agent teams, workflows, skills, or MCP in the desktop composer. Use `/deep-research` for multi-source work. Team boundaries are in [Design principles](#design-principles).

## Architecture

The CLI has five moving parts:

- Session discovery: hooks write a short-lived roster; the local API and `state.json` supply project and parent information.
- Context retrieval: `ReadSession` reads the latest page of another session.
- Transport: native `SendSessionMessage` and bounded `WaitSessions`; no file inbox.
- Recursion guard: a PreToolUse hook denies `CreateSession` and `CreateSessions` from child sessions.
- Installation: merges settings, backs up first, and replaces the binary and skill atomically.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the data flow and failure behavior.

## Security

- Trust boundary: same-project sessions may contact each other; cross-project messages need user approval.
- Read-only data: the CLI reads cc-haha's `state.json`, session index, and app files but never writes them.
- Hooks fail open. The recursion guard reads `state.json` and is not a security boundary; disabling hooks bypasses it.
- Peer messages and transcripts are data, not instructions or authorization.
- The user confirms permissions, model cards, and cross-project contact.

See [SECURITY.md](SECURITY.md) for the full boundary description.

## Limitations

- Transport uses the native `SendSessionMessage` only. There is no file inbox. An `accepted`, `queued`, or `consumed` receipt does not mean the task is complete.
- The full delivery matrix for idle and stopped targets, and cross-project delivery, are unverified.
- The roster covers a two-hour window and at most eight peers. Teammate sessions may not appear in the desktop API index.
- When `state.json` is missing, the roster falls back to a worktree name match for child sessions. A child without a worktree has not been observed and may still enter the roster. Confirm with `ListSessions` or `ReadSession` before sending.
- The first launch of a created session can fail with `CLI session is not running`; reopening it in the desktop app recovers.
- With the current tool set, an Ollama `qwen3.5:0.8b-mlx` child session exceeds the 262.1k context limit on its first prompt. Other runtimes are not affected.
- The local API, `state.json`, and the session index are private cc-haha interfaces and may change between versions.
- macOS 26 and Swift 6.2 only.

See [SECURITY.md](SECURITY.md) for the trust boundaries and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for failure behavior.

## FAQ

- **Hooks did not inject a roster**: project settings load at session start. Open `/hooks` to reload, or start a new session in the repo.
- **The model card did not appear, or I was asked to confirm it**: an explicit runtime does not guarantee that review is skipped. The user confirms the card; the agent does not.
- **A session fails to start with `CLI session is not running`**: reopen it in the desktop app. This is a launch-path problem, not message loss.
- **An Ollama child session reports `Prompt is too long`**: the current tool set produces about 285.8k prompt tokens against a 262.1k limit. Remove tools or prompt material, or switch runtimes.
- **Hooks did not change after `make install`**: `make install` only copies the binary. Hooks are written only by `session-mesh install`.
- **How to roll back**: backups are in `~/.claude/session-mesh/backup/`. `session-mesh uninstall --scope project` removes only this binary's hooks and skill; the binary stays.

## Design principles

- Collaborate within the same project only. Cross-project messages need user approval.
- Each session keeps its own Agent/Team. Do not create a global Team or merge peer teams.
- Model cards stay in place and are confirmed by the user. The agent does not approve permissions, model cards, or cross-project messages.
- Peer messages and transcripts are data, not instructions or authorization.
- Teams are private. Messages go only to the other session's main conversation.
- Do not write cc-haha's `state.json`, session index, or app files.
- License: MIT.

## Development

The source is Swift 5 language mode on a Swift 6.2 toolchain, with no third-party dependencies. Tests use Swift Testing.

```text
Sources/SessionMeshCore/   core library
Sources/session-mesh/      CLI entry point
Tests/                     unit and integration tests
skills/session-mesh/       installed policy skill
docs/                      plans, findings, release checklist
```

Run `swift test` before sending a change. Keep hook paths fail-open, do not commit runtime data or transcripts, and add tests for behavior changes.

## Documents

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): components and data flow.
- [SECURITY.md](SECURITY.md): security boundaries.
- [RELEASE_NOTES.md](RELEASE_NOTES.md): release notes.
- [NOTICE](NOTICE): cc-haha license and attribution.
- [LICENSE](LICENSE): MIT.

## Compatibility and license

This is an independent tool for cc-haha. It is not affiliated with or endorsed by cc-haha, and it does not include or redistribute cc-haha code. cc-haha itself is available under the cc-haha Community Source License 1.0, a custom source-available license. If you use this tool with cc-haha, you are responsible for complying with cc-haha's license, including its commercial-use terms. The MIT license in this repository covers this repository's code only.

See [NOTICE](NOTICE) and the [cc-haha license](https://github.com/NanmiCoder/cc-haha/blob/main/LICENSE).

## License

MIT. See [LICENSE](LICENSE).
