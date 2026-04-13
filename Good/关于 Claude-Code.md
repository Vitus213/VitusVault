# Claude Code 架构分析

## 一、Agent Loop

### QueryEngine

- 作为会话层管理多个 query loop
- 负责任务生命周期 orchestration 和结果聚合

### queryLoop

`src/query.ts:281` 中的 `async function* queryLoop()` 是整个系统的核心事件循环：

- 标准 `while (true)` 无限循环结构
- 每次迭代处理一个完整的 LLM 请求 → 流式响应 → 工具执行 → 状态更新流程
- **状态管理策略**：用单个不可变的 `state` 对象替代 9 个独立变量。每次 `continue` 时通过 `state = { ...state, field: newValue }` 整体替换，避免分散赋值导致的状态不一致
- 循环内部按顺序处理：自动压缩检查 → API 请求 → 流式消费 → 工具执行 → hook 处理 → 终止条件判断

### AsyncGenerator 核心抽象

整个 Agent loop、子 Agent 执行、工具执行都基于 `AsyncGenerator` 模式（`src/query.ts:224`）：

1. **驱动异步工具调用流**
   - `queryLoop()` 返回 `AsyncGenerator<StreamEvent | RequestStartEvent | Message | TombstoneMessage | ToolUseSummaryMessage, Terminal>`
   - 通过 `yield` 实时向 UI 层输出流事件、消息更新、墓碑消息
   - `StreamingToolExecutor` 接收流式 tool_use 块，边接收边调度执行

2. **提供中断与恢复机制**
   - 当工具需要权限时，Generator 会 `yield` 一个权限请求状态，UI 响应后通过 `.next()` 恢复执行
   - 用户按 `ESC` 拒绝编辑时，生成合成错误消息并继续循环
   - 支持 graceful degradation：流式回退（streaming fallback）时丢弃失败尝试的结果

3. **级联取消（Cascading Cancellation）**
   - `Ctrl+C` 触发 `AbortController` 信号，通过 `createChildAbortController` 级联传播
   - 自动关闭所有子任务、Bash 进程、内存预取和 skill discovery 请求
   - Generator 的 `.return()` 会关闭上下游两个 generator，确保资源释放

### 消息预处理管线

**先做本地操作，再调用 API 实现重量级操作：**

- **本地折叠（Snip / Context Collapse）**：在发送 API 请求前，先在本地移除、折叠或截断过时消息
- **内存预取**：在 loop 入口处启动 `startRelevantMemoryPrefetch()`，在工具执行期间异步完成，不阻塞主流程
- **Skill 预取**：基于当前消息上下文异步发现相关 skill，隐藏在模型生成和工具执行的时间窗口内
- 只有经过本地裁剪后仍然超出预算时，才触发昂贵的 API 调用进行全量摘要压缩

### 流式工具执行器

`StreamingToolExecutor` (`src/services/tools/StreamingToolExecutor.ts`) 实现并发安全调度：

- 通过 `isConcurrencySafe` 判断工具是否可并发执行
- **分区策略**：
  - 连续并发安全工具组成**并行分区**，在分区内并行执行
  - 遇到非并发安全工具时**开启新分区**，分区间串行执行，分区内并行执行
- 工具结果按接收顺序缓冲，确保最终 yield 的消息顺序与 LLM 输出顺序一致
- 任一工具报错时，通过 `siblingAbortController` 取消同分区内的其他并行工具

### Token Budget

当模型自然停止（`end_turn`）时，可能是碰到了 token 上限，或倾向于把任务简单化。此时系统会发送一个 **nudge** 提示推着她继续工作：

- 若连续 3 次增量小于 500 tokens，则判定为没有实质性进展，停止继续推动
- 预算追踪器 `createBudgetTracker()` 跨压缩边界维护 `task_budget.remaining`

---

## 二、上下文多层压缩策略

Claude Code 的上下文压缩采用 **四层渐进式架构**，优先执行成本低的本地操作，最后才调用 API 做重量级摘要。

### L1：物理折叠与裁剪（Snip / Context Collapse）

- **折叠连续相同工具结果**：如多次 `ReadFile` 读取同一文件且内容未变，合并为单个结果
- **按信息密度渐进式折叠（Context Collapse）**：对旧消息按重要性评分，低分消息物理截断或替换为占位符，保留高分消息的细粒度上下文
- **移除旧消息**：直接删除超出上下文窗口的最早消息（带兜底保证不丢失关键系统上下文）
- 以上操作完全在本地完成，零 API 成本

### L2：自动压缩（AutoCompact）

`src/services/compact/autoCompact.ts` 实现自动触发逻辑：

- **压缩阈值**：`effectiveContextWindow - AUTOCOMPACT_BUFFER_TOKENS`（默认缓冲 13,000 tokens）
- **三级告警线**：
  - `warningThreshold` = threshold - 20,000
  - `errorThreshold` = threshold - 20,000
  - `blockingLimit` = actualContextWindow - 3,000（达到此线后阻塞等待用户手动压缩）
- **熔断机制**：连续 3 次自动压缩失败后停止重试，防止在不可恢复的超限上下文中浪费 API 调用
- **反应式压缩（Reactive Compact）**：当 API 返回 `prompt_too_long` 错误时，即使未达自动阈值也会紧急触发压缩

### L3：微压缩（MicroCompact）

- 在完整压缩之前，先进行轻量级摘要，仅折叠最近几个回合的非关键工具输出
- 由 `microCompact.ts` 实现，作为 AutoCompact 的前置缓冲层

### L4：API 全量压缩

当本地操作仍无法将上下文控制在预算内时，调用子 agent（forked agent）对完整对话历史生成摘要：

- **输入处理**：先 `stripImagesFromMessages()` 移除图片/文档块，避免压缩请求自身超限
- **摘要保留要素**：
  - 用户原始请求意图
  - 关键技术概念和决策
  - 错误与修复过程
  - 问题解决路径
  - 所有用户显式提供的信息
  - 待办任务（TODO）
  - 当前工作状态和下一步计划
- **会话记忆压缩（Session Memory Compact）**：独立的记忆提取流程，由 `sessionMemoryCompact.ts` 实现。在 forked agent 中运行，避免死锁主线程

### 压缩后重建（Post-Compact Rebuild）

压缩完成后，系统不是只留一个空洞摘要，而是会注入关键上下文以恢复 agent 的工作状态：

- 最多 **5 个关键文件**的完整内容（`POST_COMPACT_MAX_FILES_TO_RESTORE`）
- 每个文件不超过 **5,000 tokens**
- 最多注入 **25,000 tokens** 的 skill 指令（每个 skill 不超过 5,000 tokens）
- 重新挂载当前计划（plan）、附件（attachments）和系统上下文

---

## 三、工具系统

Agent 能做什么，完全由工具系统决定。

### ToolUseContext

每个工具的 `call()` 方法都会接收一个 `ToolUseContext` 对象，包含：

- 文件读取状态跟踪
- 取消信号（`AbortController`）
- Agent ID 标识
- Langfuse trace/span 信息
- 查询链追踪（`queryTracking`，用于防止子 agent 递归死锁）

### 工具注册

分为三类加载方式：

1. **无条件加载**：核心内建工具（BashTool、FileReadTool 等）
2. **Feature Gate 条件加载**：通过 `feature('FLAG_NAME')` 控制实验性工具
3. **运行时加载**：MCP 工具、用户自定义插件

**分区排序优化**：服务端会对工具列表进行 hash 并缓存。内建工具一般不变，因此放在列表前面，防止因后面动态工具变化导致缓存断点失效。

### BashTool 安全隔离

- 每个 Bash 命令在独立子进程中执行
- 通过 `AbortController` 实现超时和强制终止
- 敏感路径（如 `.git/`）即使在 bypass 权限模式下也会触发确认

---

## 四、权限系统

Agent 允许做什么，由权限系统决定，在 AI 高效工作与防止 AI 搞砸一切之间找到平衡。

权限等级从低到高：

```
plan → default → acceptEdits → auto → bypassPermissions
```

### 权限判断主流程

权限判断有一个严格有序的评估管线：

1. **用户显式 ask 规则优先于 bypass 模式**：可以对特定操作添加 `ask` 规则
2. **敏感路径保护**：如 `.git/` 目录，在 `bypass` 模式下也必须确认
3. **拒绝追踪与熔断**：记录拒绝原因，防止高频重复请求

### 规则系统：精细化控制

优先级从低到高：

```
企业策略 → 项目级规则 → local settings → user settings → command 级覆盖
```

---

## 五、多 Agent 协作：蜂群智能

1. **Subagent**
   - 父 agent 同步/异步派生子 agent
   - 通过 `runForkedAgent()` 在独立进程中运行，上下文隔离

2. **Team / Swarm**
   - 成员之间互相通信
   - 有 leader / teammate 角色分工
   - 支持前后端分离协作模式

3. **Coordinator**
   - 纯编排角色，coordinator 不直接操作文件
   - 所有实际工作由 worker agent 完成
   - 支持大规模并行任务分发

### Agent Tool 统一入口路由设计

覆盖优先级：

```
内置 agent → 用户自定义 agent → 插件 agent
```

覆盖机制类似于 settings 的级联覆盖。

---

## 六、System Prompt 工程

### Prompt Cache

- **分段设计**：将 Prompt 拆分为 `string[]` 而非巨型字符串，便于服务端按 prefix 缓存
- **静态与动态严格分离**：
  - 静态区：核心价值观、安全准则（cached，prefix 一致时显著降低 TTFT）
  - 动态区：当前文件列表、对话历史（uncached，随轮次变化）
- **抑制幻觉式工程**：在 system prompt 中注入「三行代码优于过早抽象」的实用主义原则
- **CLAUDE.md 注入**：自动收集并注入当前目录、父目录直至项目根目录的 `CLAUDE.md` 到 user context

---

## 七、设计启发

1. **Fail-Closed 安全默认**
   - 默认无法并发（`isConcurrencySafe` 必须显式声明）
   - 默认只读（`isReadOnly` 为 true 时禁止写操作）

2. **编译时消除特性**
   - 通过 `feature('FLAG_NAME')` 在构建期进行 Dead Code Elimination
   - 外部构建不包含 ant-only 的实验性字符串和逻辑

3. **Prompt Cache 感知架构设计**
   - 保持 prefix 一致性以节省 TTFT（Time To First Token）
   - 工具定义顺序、system prompt 分段都考虑缓存命中率

---

## 八、改进方向

### 声明式权限管理

目前大量权限逻辑以硬编码 `if/else` 散落在 `BashTool.ts` 等文件中，增加新规则时容易出错。建议引入声明式策略引擎，用 YAML 或 JSON 描述权限规则。

### 渐进式上下文管理

当前是全量摘要和物理折叠二选一，一旦触发压缩，大多数细节丢失。可以考虑：

- 多级缓存架构
- 用轻量级模型在后台对上下文进行「脱水」摘要
- 保留原始消息的可回溯索引

### 模块化构建

全局 `App State` 对象过于庞大，多个服务耦合在一起。建议采用微内核或依赖注入（DI）架构，将 Agent 拆分为独立可插拔的 Service。
