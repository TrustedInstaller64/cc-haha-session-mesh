# 架构

English summary: a Swift CLI that discovers same-project cc-haha sessions, reads their context, sends native messages, blocks recursive session creation, and installs its hooks and skill.

## 数据流

```text
SessionStart / UserPromptSubmit
        |
        v
   HookHandlers  --->  hook-roster.json (locked read/modify/write)
        |
        +--> SessionRegistry
        |       |-- /api/sessions (offset pagination)
        |       |-- state.json members (state, parent, root)
        |       `-- transcript session-meta / ai-title (fallback)
        |
        +--> ProjectIdentity (git common dir; worktree and submodule aware)
        |
        `--> Roster (same project, 2h window, max 8, no child sessions)
                |
                v
        [mesh-roster] / [mesh-peer] / [mesh-policy] context

PreToolUse (CreateSession | CreateSessions)
        |
        v
   HookHandlers.handleGuard
        |
        `--> state.json parentSessionId
                |-- child  -> deny
                `-- top    -> allow (fails open if state is unavailable)

Install
        |
        `--> SettingsStore (backup, merge, lock, atomic write)
             Installer (binary and skill via temp file + replace)
```

## 组件

- `HookHandlers`：处理四个生命周期 hook 和 PreToolUse guard；名册读改写持有文件锁。
- `SessionRegistry`：优先本地 API，回退 `state.json` members 和 transcript 元数据。
- `LocalAPI`：读取 `desktop-server-state.json` 的端口，按 offset 翻页；整页无新增时停止。
- `Roster`：按项目过滤，排除自身、子会话和生成的 worktree 子会话，限制 2 小时和 8 个 peer。
- `ProjectIdentity`：worktree 归并到主仓库；submodule 归并到其工作目录；非 git 用精确路径。
- `SettingsStore`：合并 hooks，先备份，带 matcher 的 PreToolUse 条目也在同一合并逻辑内。
- `Installer`：项目级或用户级安装；先预检 settings，再原子替换二进制和 skill。
- `SpawnTemplate`：生成标题和八段提示词；递归由 PreToolUse guard 实际拦截。

## 发现顺序

1. `/api/sessions`：项目、工作目录、修改时间；不返回 parent。
2. `state.json` members：state、parentSessionId、rootSessionId。
3. transcript `session-meta` / `ai-title`：API 和 state 都不可用时的只读回退。

项目归属优先用 `projectRoot`；缺失时用 `workDir` 推导。worktree 通过 git common dir 归并，submodule 使用自身工作目录。

## 失败行为

- 所有生命周期 hook 和 guard 都 exit 0；解析或写入失败不阻塞宿主。
- API、state 或索引读取失败时逐级回退；全部失败时名册为空。
- guard 在 `state.json` 缺失、会话不在 members、或 hooks 被禁用时 fail-open。它是防递归护栏，不是安全边界。
- 安装先校验 settings 再写文件；settings 合并和名册写入都用文件锁，避免并发进程相互覆盖。

## 证据

行为细节和安全边界见 [../SECURITY.md](../SECURITY.md)。
