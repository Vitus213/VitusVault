---
name: organizing-interview-notes
description: Use when the user asks to 整理面经, 复盘面试, 整理录音转写, or turn interview material into two structured markdown review documents in the VitusVault project
---

# Organizing Interview Notes

## Overview
When the user asks to整理面经, always turn the source material into **two markdown documents** and save them under the VitusVault interview review directory.

Core rule: do not stop at a chat reply. Produce both files and write them to the expected location.

## When to Use
Use this skill when the user asks for any of these outcomes:
- 整理面经
- 面后复盘
- 整理面后文档
- 根据录音/转写整理面试内容
- 生成复盘和二面准备材料

Do **not** use this skill for:
- Generic summarization with no interview context
- Pure Q&A answering without transcript organization
- Cases where the user explicitly asks for only one document

## Required Outputs
Unless the user explicitly requests otherwise, always generate **both** of these:

1. **问题整理文档**
   - A clean interview Q&A record
   - Include only: each interviewer question, the candidate's answer, follow-up / clarification exchanges, reverse-question section and replies
   - Keep it factual and structured
   - Do not mix in evaluation or study advice in this file

2. **分析复盘清单**
   - A combined preparation document for review and next-round prep
   - Include: overall evaluation, strengths and weaknesses, repair suggestions, learning directions, priority areas, weak points, suggested answers to rehearse, and a focused study plan

## Required Save Location
Save both files to:

`~/work/VitusVault/暑期实习/面试录音复盘`

Resolve this to:

`/home/vitus/work/VitusVault/暑期实习/面试录音复盘`

Do not leave the result only in chat unless the user explicitly asks for chat-only output.

## Default File Naming
Use clear names in this style:

- `公司名-届别-岗位-轮次-问题整理.md`
- `公司名-届别-岗位-轮次-分析复盘清单.md`

Example:
- `小红书-27届暑期-社区工程-一面-问题整理.md`
- `小红书-27届暑期-社区工程-一面-分析复盘清单.md`

If some metadata is missing, infer conservatively from transcript/user context. Prefer stable, human-readable Chinese filenames.

## Workflow
1. 读取面试材料，一般在面试录音复盘里面的 '.txt'文件
2. Identify interview metadata if possible:
   - company
   - batch/intern season
   - role
   - round
3. Extract and structure:
   - each interviewer question
   - the candidate's answer
   - follow-up / clarification exchanges
   - reverse-question section and replies
4. Produce the two markdown documents.
5. Save both files under `/home/vitus/work/VitusVault/暑期实习/面试录音复盘`.
6. In chat, briefly report the two output paths.

## Document 1 Template
Suggested sections:
- 标题
- 基本信息
- 逐题整理
  1.Dragonos与linux有什么区别
  2.cgroup有什么别的缺陷吗
- 反问环节
  - 我的问题
  - 面试官回复

## Document 2 Template
Suggested sections:
- 标题
- 整体结论
- 优势与短板
- 逐题复盘
  - 面试官问题
  - 回答评价
  - 修补建议
- 反问环节复盘
- 回答修补建议
- 二面前突击清单
  - 优先级排序
  - 逐项突击内容
  - 3天/7天补强计划
  - 必背答案清单
- 总结

## Common Mistakes
- Only replying in chat and not writing files
- Only generating one document
- Saving outside `~/work/VitusVault/暑期实习/面试录音复盘`
- Producing vague summaries without question-by-question structure
- Omitting reverse-question discussion
- Omitting repair suggestions and learning directions

## Quick Reference
- Trigger: `整理面经`
- Output count: `2`
- Save dir: `/home/vitus/work/VitusVault/暑期实习/面试录音复盘`
- Formats: `问题整理` + `分析复盘清单`
- Final chat reply: `report saved file paths briefly`
