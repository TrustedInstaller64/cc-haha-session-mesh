# v0.1.0

[中文](#中文) | [English](#english)

## 中文

首个可用版本。目标很窄：同一项目的 cc-haha 桌面会话能互相发现、读取上下文、发消息，并能安全地新建会话。

### 包含

- `session-mesh` CLI：安装、卸载、`doctor` 自检、内部 hook 入口。
- 5 个 hooks：SessionStart、UserPromptSubmit、Stop、SessionEnd、PreToolUse。
- 同项目名册：2 小时窗口、最多 8 个 peer；排除子会话和 cc-haha 生成的 worktree 子会话。
- PreToolUse 防递归：子会话调用 `CreateSession` / `CreateSessions` 会被拒绝；依赖 `state.json`，缺失时 fail-open。
- 项目级或用户级安装；settings 合并前备份，二进制、skill 和名册写入均为原子操作。
- 会话策略 skill 和新建会话模板（八段提示词、每请求最多 2 个、模型卡由用户确认）。

### 安装

```sh
swift build -c release
./.build/release/session-mesh install --dry-run
./.build/release/session-mesh install --scope project
./.build/release/session-mesh doctor
```

已打开的会话需要打开一次 `/hooks`，或在仓库内新建会话，才能加载新 hooks。

### 要求

- macOS 26
- Swift 6.2 工具链
- 零第三方依赖

### 已知限制

- 没有文件 inbox；只使用原生 `SendSessionMessage`。
- idle / stopped 目标的完整投递矩阵和跨项目投递未验证。
- 名册依赖 cc-haha 的非公开 API、`state.json` 和会话索引，版本升级可能失效。
- 防递归 hook 不是安全边界；禁用 hooks 即可绕过。
- Ollama `qwen3.5:0.8b-mlx` 在当前工具集下首轮提示词超过上下文上限，暂不可用。

### 许可证

MIT。见仓库根目录 `LICENSE`。本项目是独立工具，不包含 cc-haha 代码；cc-haha 自身许可与商业使用限制见 `NOTICE`。

## English

First usable release. The scope is narrow: cc-haha desktop sessions in the same project can find each other, read context, send messages, and start new sessions safely.

### Included

- `session-mesh` CLI: install, uninstall, `doctor`, and internal hook entry points.
- Five hooks: SessionStart, UserPromptSubmit, Stop, SessionEnd, PreToolUse.
- Same-project roster: two-hour window, at most eight peers; child sessions and cc-haha-generated worktree children are excluded.
- PreToolUse recursion guard: child sessions are denied when they call `CreateSession` or `CreateSessions`. It reads `state.json` and fails open when the file is unavailable.
- Project or user scope install. Settings are backed up before merging; binary, skill, and roster writes are atomic.
- Session policy skill and a new-session template: eight-section prompt, at most two sessions per request, user-confirmed model card.

### Install

```sh
swift build -c release
./.build/release/session-mesh install --dry-run
./.build/release/session-mesh install --scope project
./.build/release/session-mesh doctor
```

Open `/hooks` once, or start a new session in the repo, so already-open sessions pick up the new hooks.

### Requirements

- macOS 26
- Swift 6.2 toolchain
- No third-party dependencies

### Known limitations

- No file inbox; transport uses the native `SendSessionMessage` only.
- The full delivery matrix for idle and stopped targets, and cross-project delivery, are unverified.
- The roster depends on private cc-haha interfaces, `state.json`, and the session index; version upgrades may break it.
- The recursion guard is not a security boundary. Disabling hooks bypasses it.
- With the current tool set, an Ollama `qwen3.5:0.8b-mlx` child session exceeds the context limit on its first prompt and is not usable yet.

### License

MIT. See `LICENSE` at the repository root. This project is an independent tool and does not include cc-haha code; cc-haha's own license and commercial-use terms are in `NOTICE`.
