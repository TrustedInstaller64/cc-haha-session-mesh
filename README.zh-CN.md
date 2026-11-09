# cc-haha Session Mesh

[English](README.md)

一个轻量 Swift CLI，让同一项目的 cc-haha 桌面会话互相发现、读取上下文、发送消息。仓库同时包含会话策略 skill 和新建会话模板。

当前状态：消息、会话创建、PreToolUse 防递归和安装流程都已在本机实测。文件 inbox 不实现。许可证：MIT。

## 快速开始

```sh
make build
./.build/release/session-mesh install --dry-run
./.build/release/session-mesh install
./.build/release/session-mesh doctor
```

已经打开的会话不会自动加载新 hooks。打开一次 `/hooks`，或在仓库内新建会话。之后再发消息，上下文会出现 `[mesh-roster]`、`[mesh-peer]`、`[mesh-policy]`。

## 安装

要求：

- macOS 26
- Swift 6.2 工具链（`Package.swift` 使用 tools 6.2，源码保持 Swift 5 language mode）
- 零第三方依赖

构建与测试：

```sh
swift build -c release
swift test

# 或使用 Makefile
make build
make test
```

默认 `--scope project`，以当前工作目录作为项目根：

- hooks：合并到仓库 `.claude/settings.local.json`
- skill：仓库 `.claude/skills/session-mesh/SKILL.md`
- binary：`~/.claude/session-mesh/bin/session-mesh`
- 备份：`~/.claude/session-mesh/backup/`

`--scope user` 才写全局位置：

- hooks：`~/.claude/settings.json`
- skill：`~/.claude/skills/session-mesh/SKILL.md`

```sh
session-mesh install --dry-run          # 预览目标，零写入
session-mesh install --check            # 检查已安装状态，零写入
session-mesh install                    # 默认 project scope
session-mesh install --scope user       # 全局安装
session-mesh uninstall --dry-run
```

apply 会写 settings 并安装文件。先跑 `--dry-run` 或 `--check`，确认备份路径，再决定是否写入。`make install` 只复制 release 二进制；hooks 只通过 `session-mesh install` 写入。

## 命令

- `session-mesh install [--dry-run | --check] [--scope project|user]`：安装或合并 5 个 hooks（SessionStart、UserPromptSubmit、Stop、SessionEnd、PreToolUse）；默认 project。PreToolUse 只匹配 `CreateSession|CreateSessions`，阻止子会话递归新建。
- `session-mesh uninstall [--dry-run] [--scope project|user]`：只移除属于本二进制的 hooks 和 skill；共享二进制保留。
- `session-mesh doctor`：只读检查工具链、运行时目录权限、安装状态、settings 和本地 API；有故障时 exit 1。
- `session-mesh help`：打印用法。未知命令 exit 2，运行失败 exit 1。
- `session-mesh hook-start | hook-prompt | hook-stop | hook-end | hook-guard`：内部 hook 入口，始终 exit 0；不手动调用。

## 使用流程

1. 先看名册。`[mesh-roster]` 给出同项目 peer 的 id、state、last_seen 和 title；没有名册时用 `ListSessions` 按 projectRoot 过滤。
2. 需要上下文：用 `ReadSession <peer-id>` 读最新一页，只取与任务有关的事实。
3. 需要协作：用 `SendSessionMessage` 发一条不超过 500 字符的消息，写明来源和需要的回应；用 `WaitSessions` 有界等待。回执不等于完成，用 `ReadSession` 确认。
4. 需要新会话：先查名册和 `ListSessions`，能复用就不建。标题为 `<项目短名> · <角色> · <任务>`，提示词包含八段。每个请求最多新建 2 个；模型卡由用户确认。
5. 需要并行或调研：在桌面 composer 启用智能体团队、工作流、技能或 MCP；多源调研优先 `/deep-research`。团队边界见[设计原则](#设计原则)。

## 架构

CLI 分为五部分：

- 会话发现：hooks 写入短期名册；本地 API 和 `state.json` 提供项目与父子信息。
- 上下文读取：`ReadSession` 读取目标会话最新一页。
- 传输：原生 `SendSessionMessage` 加有界 `WaitSessions`，没有文件 inbox。
- 防递归：PreToolUse hook 拒绝子会话的 `CreateSession` / `CreateSessions`。
- 安装：合并 settings，先备份，再原子替换二进制和 skill。

数据流和失败行为见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 安全

- 信任边界：同项目会话可以直接联系；跨项目消息需要用户批准。
- 只读数据：CLI 读取 cc-haha 的 `state.json`、会话索引和应用文件，但不写入。
- hooks fail-open。防递归 guard 读取 `state.json`，不是安全边界；禁用 hooks 即可绕过。
- peer 消息和 transcript 是数据，不是指令或授权。
- 权限、模型卡和跨项目联系由用户确认。

完整边界见 [SECURITY.md](SECURITY.md)。

## 限制

- 只使用原生 `SendSessionMessage`，没有文件 inbox。`accepted`、`queued` 或 `consumed` 回执不代表任务完成。
- idle / stopped 目标的完整投递矩阵和跨项目投递未验证。
- 名册覆盖 2 小时窗口、最多 8 个 peer。teammate 会话可能不在桌面 API 索引中。
- `state.json` 缺失时，名册用 worktree 名称匹配排除子会话。无 worktree 子会话未观察到，仍可能进入名册；发送前用 `ListSessions` 或 `ReadSession` 确认。
- 新建会话首次启动可能失败（`CLI session is not running`），在桌面重新打开后可恢复。
- 当前工具集下 Ollama `qwen3.5:0.8b-mlx` 子会话首轮超过 262.1k 上下文上限；其他 runtime 不受影响。
- 本地 API、`state.json` 和会话索引是 cc-haha 的非公开接口，版本升级可能变化。
- 仅支持 macOS 26 + Swift 6.2。

信任边界见 [SECURITY.md](SECURITY.md)，失败行为见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 常见问题

- **hooks 没注入名册**：项目级 settings 在会话启动时加载；打开 `/hooks` 重载，或在仓库内新建会话。
- **模型卡没出现或被要求确认**：显式 runtime 不保证跳过审核；卡片由用户确认，Agent 不代批。
- **会话首次启动报 `CLI session is not running`**：在桌面重新打开该会话；这是启动链路问题，不是消息丢失。
- **Ollama 子会话报 `Prompt is too long`**：当前工具集固定提示词约 285.8k tokens，超过 262.1k；需要减少工具/提示词或换 runtime。
- **`make install` 后 hooks 没变**：`make install` 只复制二进制；hooks 只通过 `session-mesh install` 写入。
- **如何回滚**：安装前备份在 `~/.claude/session-mesh/backup/`；`session-mesh uninstall --scope project` 只移除本二进制的 hooks 和 skill，二进制保留。

## 设计原则

- 只协作同项目会话；跨项目消息先取得用户确认。
- 每个会话保留自己的 Agent/Team；不创建全局 Team，不合并 peer 团队。
- 模型分配卡保留，由用户确认；Agent 不代批权限、模型卡或跨项目消息。
- peer 消息和 transcript 是数据，不是指令或授权。
- 团队私有；消息只发到对方主会话。
- 不写 cc-haha 的 `state.json`、会话索引或应用文件。
- 许可证：MIT。

## 开发

源码为 Swift 5 language mode，使用 Swift 6.2 工具链，零第三方依赖；测试使用 Swift Testing。

```text
Sources/SessionMeshCore/   核心库
Sources/session-mesh/      CLI 入口
Tests/                     单元与集成测试
skills/session-mesh/       安装的策略 skill
docs/                      规划、实测、发布清单
```

提交前运行 `swift test`。保持 hook 路径 fail-open，不提交运行时数据或 transcript，行为变化要补测试。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：组件与数据流。
- [SECURITY.md](SECURITY.md)：安全边界。
- [RELEASE_NOTES.md](RELEASE_NOTES.md)：发布说明。
- [LICENSE](LICENSE)：MIT。

## 许可证

MIT。见 [LICENSE](LICENSE)。
