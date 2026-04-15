## 什么是VLLM
大模型推理框架把大模型提供上限并且提供优化和加速方案 
1. 多用户
2. 易用
3. 高吞吐量和低延迟 
## KV Cache


## PagedAttention
Parallel Sampling：
	Copy-on-write 
Beam Search 束搜索
Shared prefix


## 调度原则
先来先服务（First-Come-First-Serve）

抢占式调度 ，后来的请求可以被前面的请求抢占掉
1. 暂停后来任务执行，同时将相关的kv cache 从gpu上释放掉
	1. 释放cach采用all-or-nothing，释放被抢占请求的所有block
	2. 释放可以通过swap交换到cpu上
2. gpu资源充足时恢复执行