## 为什么需要一个vllm
vllm和pytorch/tensorflow的区别
针对llm对显存资源需求以及计算量增长动态变化的问题 ，需要一个推理引擎完成高效的请求调度和资源分配 

## 什么是VLLM
大模型推理框架把大模型提供上限并且提供优化和加速方案 
1. 多用户（提供api key服务）
2. 易用
3. 高吞吐量和低延迟 
## VLLM的关键模块 
以下三个模块都在Engine core 中 
![Drawing 2026-04-19 14.29.16.excalidraw|800](../Excalidraw/Drawing%202026-04-19%2014.29.16.excalidraw.md)
### Engine Core
AsyncLLM和engine core在不同进程，通过queue进行交互，engine core任务由executor下发，scheduler将任务发给多个worker共同完成 ，每个worker有一张gpu卡 
process input：拿取请求，放入队列
process output
run busy loop：处理循环线程，执行step操作（包括请求调度和模型运算） 
### Scheduler
负责多请求之间的调度协同问题 ，组织每次推理需要计算的数据 
1. Continuous-batching：持续不断的将数据往gpu中送，一个请求结束立刻下发新请求
2. Chunked Prefill 分块预填充，讲答的prefill分块分成更小的块
两个主要队列 waiting 和 running ，通过KV manager 配备KV cache ，先到先服务/用户自定义
KV blocks是一个双向链表，采用lru策略淘汰旧数据
### KV Cache manager 
为请求分配kv cache 资源 
#### PagedAttention
1. Parallel Sampling：
	Copy-on-write 

2. Beam Search 束搜索

3. Shared prefix
还融合了前缀树特点
### Model runner 
进行模型运算和物理层的kv cache 分配和管理

分布式并行推理 ，在engine core中抽出engine core client ，给不同的engine core 分配请求 
### Attention
负责承载注意力计算算子
QKV
Metadate
Backend
## 调度原则
先来先服务（First-Come-First-Serve）

抢占式调度 ，后来的请求可以被前面的请求抢占掉
1. 暂停后来任务执行，同时将相关的kv cache 从gpu上释放掉
	1. 释放cach采用all-or-nothing，释放被抢占请求的所有block
	2. 释放可以通过swap交换到cpu上
2. gpu资源充足时恢复执行