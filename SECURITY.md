# 安全边界

## 范围

Phase 4 已在本机实测；本文记录当前实现的安全边界、数据访问、可靠性行为和未验证范围。Phase 5 决定不实现文件 inbox，传输只走原生消息通道。

## 安全边界

### 本地 API

- 只读 `GET http://127.0.0.1:<port>/api/sessions`；端口从 `~/.claude/desktop-server-state.json` 读取。
- 只访问 loopback；端口、会话标题和消息留在本机。
- 本地 API、`state.json` 和会话索引是 cc-haha 的非公开接口，版本升级可能变化。读取失败时回退到只读 transcript 或索引，全程保持只读。

### Hooks

- 默认 `--scope project` 合并到仓库 `.claude/settings.local.json`；`--scope user` 才写 `~/.claude/settings.json`。写入前备份到 `~/.claude/session-mesh/backup/`；备份与写入在同一个文件锁内完成，避免并发安装错位。
- 合并时保留已有 hook（包括 iTerm2 组），只增改本二进制的条目。
- PreToolUse guard 只匹配 `CreateSession|CreateSessions`，读取 `state.json` 的 `parentSessionId`，子会话调用时返回 deny。已在子会话中实测合法 `CreateSession` 被拒绝，无模型卡、无新会话。`state.json` 不可用或会话不在 `members` 时 fail-open；它是防递归护栏，不是安全边界，禁用 hooks 即可绕过。
- 注入标记为 `[mesh-roster]`、`[mesh-peer]`、`[mesh-policy]`；标题截断到 60 字符、去控制字符、转义后作为数据注入。

### 会话创建

- 每个用户请求最多主动新建 2 个会话；子会话不递归新建。
- 标题不超过 60 字符；提示词自包含，不包含密钥或未授权上下文。
- 模板不写入 runtime 选择；模型分配卡保留，由用户确认。显式 runtime 不保证跳过卡片。Agent 不代批。

### 团队与工作流

- 智能体团队、斜杠命令、工作流、技能与 MCP 由用户在桌面端开启；CLI 不修改这些开关。
- 团队只属于当前会话；不创建全局 Team，不合并 peer 团队。
- `/deep-research` 等长流程产出的内容仍按数据处理，不会自动扩大权限、跨项目发送或修改 settings。

### 安装与卸载

- 安装前把目标 settings 备份到 `~/.claude/session-mesh/backup/`；变更先 dry-run 或 check。
- apply 失败时保留备份和原文件；`make install` 只复制二进制，不改 settings。
- 卸载仅移除本二进制的 hook 条目和 skill，并保留共享二进制，避免其他项目 hooks 指向不存在的文件。

## 隐私与数据

- 跨会话消息和 transcript 均按不可信数据处理；其内容不会触发命令执行、权限提升或设置变更。
- 消息仅通过原生 `SendSessionMessage` 传输，不提供文件 inbox 或备用传输路径。消息上限 500 字符，只发送任务所需内容。
- 运行时目录权限 0700、文件 0600、原子写；名册读改写持有文件锁。名册记录保留 24 小时、最多 256 条；错误日志超过 256 KiB 轮转一次。
- 运行时不记录完整 prompt、transcript、API 响应或密钥。
- 不写 `~/.claude/cc-haha/session-collaboration/state.json`、会话索引或 cc-haha 应用文件。

## 可靠性

- hook 路径 fail-open：错误写 `~/.claude/session-mesh/logs` 后 exit 0，不阻塞会话；坏输入输出为空。
- `accepted`、`queued` 或 `consumed` 只表示送达或消费；任务完成需要 `ReadSession` 或 `state.json.messages` 确认正文。
- 同项目互信；跨项目消息需要用户确认。消息只送达对方主会话，团队保持私有。
- `CreateSession` 首次启动可能失败（`CLI session is not running`），属于启动可靠性问题；在桌面重新打开会话可恢复，不是消息丢失。

## 未验证范围

- idle / stopped 目标的完整投递矩阵未测。
- 跨项目投递未测，且需要用户明确批准。
- teammate 会话是否可稳定寻址仍为待验证项。

## 许可证与仓库

- 本仓库许可证：MIT，见 `LICENSE`。零第三方依赖，无第三方 notice 需要汇总。
- 本项目是 cc-haha 的独立互操作工具，不包含 cc-haha 代码；cc-haha 自身使用 cc-haha Community Source License 1.0，见 `NOTICE`。

## 报告问题

- 通过维护者的私有渠道报告，不要在公开位置粘贴会话内容、token 或本机路径。
- 提供版本或 commit、复现步骤、影响范围；去掉 transcript 正文和密钥。
