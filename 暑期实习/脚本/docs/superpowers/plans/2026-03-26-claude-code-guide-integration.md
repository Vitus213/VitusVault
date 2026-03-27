# Claude Code Guide Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md` into one unified AI Coding methodology guide that fully absorbs the two companion documents while matching the approved integration spec.

**Architecture:** Keep a single target markdown file as the final guide, but rebuild its structure around principles, role boundaries, file-based governance, execution flow, context management, verification, Claude Code tooling, failure modes, templates, and summary. Use the approved spec as the source of truth, persist a topic-coverage checklist inside this plan, then rewrite and verify the target file chapter by chapter so no required source content is dropped and no comparison framing survives.

**Tech Stack:** Markdown, Claude Code workflow concepts, local repository files

---

## Coverage checklist

| Required topic | Destination chapter |
| --- | --- |
| 上下文是稀缺资源 | 2. AI Coding 的四个底层约束 |
| 验证比自我汇报更重要 | 2. AI Coding 的四个底层约束 / 8. 验证体系 |
| session 不是长期记忆 | 2. AI Coding 的四个底层约束 / 7. 上下文管理 |
| 流程强度按复杂度分级 | 2. AI Coding 的四个底层约束 / 6. 渐进式规范 |
| 人的职责与 AI 的边界 | 3. 人、AI、文件分别负责什么 |
| `AGENTS.md` 与 `CLAUDE.md` 的边界 | 4. 文件体系：把状态、约束、验收写进文件 |
| `spec.md` / `plan.md` / `tasks.md` | 4. 文件体系 / 5. 运行流程 |
| `verify.json` / `verify-report.md` | 4. 文件体系 / 8. 验证体系 |
| Spec-Driven Development | 5. 运行流程 |
| 给 Claude 足够具体的上下文 | 7. 上下文管理 |
| AskUserQuestion / 采访模式 | 9. Claude Code 落地 |
| `/clear`、`/compact`、`/rewind` | 7. 上下文管理 |
| Prompt Caching 与稳定前缀 | 7. 上下文管理 |
| UI / screenshot 验证 | 8. 验证体系 |
| 权限系统与预批准安全命令 | 9. Claude Code 落地 |
| CLI / MCP / Hooks / Skills / Subagents / Worktree | 9. Claude Code 落地 |
| `.claude/settings.json`、`.claude/skills/`、`.claude/agents/`、`.mcp.json` | 9. Claude Code 落地 |
| headless automation / 并行 / 规模化 | 9. Claude Code 落地 / 11. 推荐工作流模板 |
| 常见失败模式与规避策略 | 10. 常见失败模式与规避策略 |
| 最终总结 | 12. 总结：把 Claude Code 用成执行引擎，而不是聊天工具 |

---

### Task 1: Rebuild the title, positioning, and table of contents

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/docs/superpowers/specs/2026-03-26-claude-code-guide-integration-design.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Re-read the approved spec and copy the exact target chapter order into working notes**

Expected result: the chapter sequence for the final guide matches the approved spec.

- [ ] **Step 2: Rewrite the opening title and positioning block in the target guide**

Expected result: the opening explains that this is one unified AI Coding methodology guide, not a comparison or source commentary.

- [ ] **Step 3: Rewrite the table of contents to match the approved chapter structure**

Expected result: the TOC reflects all 12 target chapters in the approved order.

- [ ] **Step 4: Verify the opening contains no comparison-style wording**

Check that the title, introduction, and TOC do not use phrases such as `BeatAI vs`、`哪篇更强`、`哪篇更适合谁`、`对比对象`、`两者结合`.

Expected result: comparison framing is absent from the top of the document.

### Task 2: Rewrite chapter 1 and chapter 2

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 工程实践经验.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 方法论对比：BeatAI vs 工程实践经验.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 1 to explain what problem the guide solves**

Expected result: chapter 1 frames the guide for both individual developers and teams.

- [ ] **Step 2: Rewrite chapter 2 to cover the four core constraints**

Include:
- context scarcity
- verification over self-report
- session is not long-term memory
- process intensity scales with task complexity

Expected result: chapter 2 becomes the unified principle layer for the whole guide.

- [ ] **Step 3: Read chapter 1 and chapter 2 together for overlap**

Expected result: the two chapters are complementary and not repetitive.

### Task 3: Rewrite chapter 3 and chapter 4

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 工程实践经验.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 3 for humans, AI, and files**

Expected result: the guide clearly assigns responsibilities to the human, the AI, and persistent files.

- [ ] **Step 2: Rewrite chapter 4 for the file-based governance model**

Include and distinguish:
- `AGENTS.md`
- `CLAUDE.md`
- `spec.md`
- `plan.md`
- `tasks.md`
- `verify.json`
- `verify-report.md`

Expected result: chapter 4 explains the canonical file system and boundaries consistently.

- [ ] **Step 3: Verify terminology consistency inside chapter 3 and chapter 4**

Expected result: canonical file names are used consistently, with no drift back to source-only naming.

### Task 4: Rewrite chapter 5

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 工程实践经验.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite the standard execution flow as chapter 5**

Include:
- Explore
- Plan
- Implement
- Review
- Verify
- Commit / Merge as workflow outcomes, not as a promise to commit in this session

Expected result: chapter 5 presents a coherent operating loop from requirement to acceptance.

- [ ] **Step 2: Add explicit Spec-Driven Development framing inside chapter 5**

Expected result: the reader can see where `spec.md` / `plan.md` / `tasks.md` fit in the flow.

- [ ] **Step 3: Add session-isolation guidance inside chapter 5**

Expected result: chapter 5 explains why review and verification often deserve fresh context.

### Task 5: Rewrite chapter 6 and chapter 7

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 工程实践经验.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 6 for gradual process escalation**

Include:
- small changes
- single-module tasks
- cross-module or architectural tasks
- escalation triggers such as concurrency, permissions, security boundaries, and critical data flow

Expected result: chapter 6 tells the reader when to use light versus heavy process.

- [ ] **Step 2: Rewrite chapter 7 for context management**

Include:
- fixed / semi-fixed / dynamic context layers
- Prompt Caching implications
- why `AGENTS.md` / `CLAUDE.md` must stay short and stable
- when to use `/clear`, `/compact`, `/rewind`, new sessions, and subagents
- how to give Claude enough but precise context

Expected result: chapter 7 combines practical context control with governance logic.

- [ ] **Step 3: Read chapter 6 and chapter 7 together for sequencing clarity**

Expected result: process escalation and context control reinforce each other cleanly.

### Task 6: Rewrite chapter 8

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 工程实践经验.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 8 for verification**

Include:
- tests
- lint
- typecheck
- command-output checks
- UI / screenshot verification

Expected result: chapter 8 clearly explains how Claude verifies work in observable ways.

- [ ] **Step 2: Add hooks and structured verification assets inside chapter 8**

Include:
- hooks as lightweight deterministic checks
- `verify.json` and `verify-report.md` as heavyweight structured acceptance assets

Expected result: chapter 8 distinguishes verification execution from verification definition and evidence storage.

- [ ] **Step 3: Verify chapter 8 uses machine-observable acceptance language**

Expected result: the chapter emphasizes objective evidence over subjective self-judgment.

### Task 7: Rewrite chapter 9

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 方法论对比：BeatAI vs 工程实践经验.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 9 for Claude Code-native tooling**

Include the role of:
- permissions
- CLI tools
- MCP
- hooks
- skills
- subagents
- worktree

Expected result: chapter 9 presents tooling as part of the workflow architecture, not as a feature dump.

- [ ] **Step 2: Add explicit coverage for Claude Code-specific artifacts**

Include:
- `.claude/settings.json`
- `.claude/skills/`
- `.claude/agents/`
- `.mcp.json`
- AskUserQuestion / interview mode

Expected result: chapter 9 preserves the actionable Claude Code ecosystem details.

- [ ] **Step 3: Add headless automation and scale-up guidance**

Include headless mode, parallel sessions, and worktrees as scale-up tools.

Expected result: chapter 9 retains the automation and scale content required by the spec.

### Task 8: Rewrite chapter 10, chapter 11, and chapter 12

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/AI Coding 方法论对比：BeatAI vs 工程实践经验.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`
- Modify: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Rewrite chapter 10 for common failure modes**

Expected result: the guide has a dedicated failure-pattern chapter instead of scattering warnings elsewhere.

- [ ] **Step 2: Rewrite chapter 11 for reusable workflow templates**

Include both:
- a solo-developer workflow template
- a team workflow template using structured specs, plans, tasks, and verification assets

Expected result: the document visibly serves both target audiences.

- [ ] **Step 3: Rewrite chapter 12 as the final summary**

Expected result: the guide ends with a concise unified methodology summary, not a source recap.

- [ ] **Step 4: Read chapters 10–12 together for ending flow**

Expected result: the ending feels conclusive and cohesive.

### Task 9: Verify the full document against the spec and the coverage checklist

**Files:**
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/docs/superpowers/specs/2026-03-26-claude-code-guide-integration-design.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/docs/superpowers/plans/2026-03-26-claude-code-guide-integration.md`
- Read: `/home/vitus/work/VitusVault/暑期实习/脚本/Claude Code 最佳实践指南（BeatAI·整理版）.md`

- [ ] **Step 1: Check chapter coverage against the approved spec**

Expected result: all required chapters appear in the target guide.

- [ ] **Step 2: Check every coverage-checklist topic against the rewritten guide**

Expected result: no required source topic is missing.

- [ ] **Step 3: Check terminology and anti-comparison rules across the full document**

Verify:
- canonical file names are used consistently
- forbidden comparison phrases do not appear in the body, TOC, or section titles

Expected result: terminology is stable and comparison framing is absent.

- [ ] **Step 4: Read the full guide top to bottom for duplication, transitions, and clarity**

Expected result: the guide reads like one coherent document.

- [ ] **Step 5: If the user later explicitly requests commits, prepare a separate commit step**

Expected result: the plan does not assume commit permission in advance.
