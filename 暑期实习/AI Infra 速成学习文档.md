# AI Infra 速成学习文档（针对蚂蚁横向对比期）

> **适用场景**：已通过 AI Infra 岗位面试，正在横向对比中，需要快速补齐硬技术栈谈资
> **当前时间**：4 月 15 日
> **可用时间**：2 周（横向对比通常 1-2 周内出结果）
> **个人基础**：有操作系统内核（DragonOS）、Serverless 平台（faasd-in-rust）、Rust 系统编程经验

---

## 一、另一个 AI 计划的评估

### 优点
1. **方向正确**：覆盖了蚂蚁 JD 的核心关键词（vLLM、DeepSpeed、ZeRO、NCCL、GPU）
2. **有产出物意识**：每周末都有明确的交付要求
3. **交叉优势思路对**：强调用你原有的系统能力去理解和切入 AI Infra

### 致命缺陷
1. **时间完全不现实**：4 周计划，但你现在已经在横向对比中，HR 可能 1-2 周就要定人
2. **第 1 周负载过重**：InstructGPT 论文 + RLHF 详解 + DeepSpeed 博客 + vLLM 论文 + PyTorch Distributed + C++ 线程池 = **至少 3-4 周的工作量**。工程岗实习面试**不需要读原始论文**，官方博客和文档就够了
3. **C++ 速成完全错误**：你已经有 Rust 系统编程能力，C++ 的 RAII/智能指针/线程池对你来说是"已知概念的降级翻译"。岗位 JD 也没有要求"必须会 C++"，大量 AI Infra 代码是 Python。学 C++ 是在浪费你最稀缺的时间
4. **动手太少**：前两周几乎都在"读"，没有真正的代码跑动。工程岗最看重的是**你跑过什么、调过什么参数、踩过什么坑**
5. **没有利用现有项目**：没有提到如何把 faasd 或 DragonOS 与 vLLM 结合，错失了你最大的差异化优势
6. **答案过于教科书**：背下来的标准答案在蚂蚁二面/三面很容易露馅，面试官会追问细节

---

## 二、你的核心策略："系统背景 + 快速嫁接 + 深度谈资"

你最大的优势不是"从零开始学大模型"，而是：
- **别人花 3 个月才能理解的系统底层，你已经做过了**
- **你只需要证明：你能在现有系统能力上快速长出 AI Infra 的枝叶**

所以策略是：
1. **抛弃论文阅读，只看博客、文档、源码注释**
2. **3 天内必须跑通 vLLM**，这是最容易快速出成果的
3. **用 faasd 或 DragonOS 做载体**，把 vLLM 塞进去，形成独特故事
4. **不学 C++**，用 Rust 的系统思维去理解 Python/C++ 混合的 AI Infra 代码
5. **准备 3-5 个深度技术点**，每个都能和面试官聊 5 分钟以上

---

## 三、2 周冲刺计划

### 整体时间分配
- **上午 3h**：动手实践（跑代码、调参数、做 benchmark）
- **下午 2h**：读文档/源码（vLLM scheduler、DeepSpeed ZeRO 博客）
- **晚上 1h**：整理笔记、背面试话术、更新进度

---

## 第一周：跑通 vLLM + 建立认知（核心周）

### Day 1（周一）：环境准备 + 跑通第一个 vLLM demo

**学习目标**：让 vLLM 在你机器上真正跑起来

**具体行动**：
1. 安装 vLLM：
   ```bash
   pip install vllm
   ```
2. 下载一个小模型（Qwen2.5-7B-Instruct 或 Llama-3.1-8B-Instruct），用 HuggingFace 或 ModelScope
3. 跑官方 quickstart：
   ```python
   from vllm import LLM, SamplingParams
   llm = LLM(model="Qwen/Qwen2.5-7B-Instruct")
   outputs = llm.generate(["Hello, my name is"], SamplingParams(temperature=0.8))
   ```
4. 记录：你机器的 GPU 型号、显存大小、模型加载后的显存占用

**产出物**：一张截图，证明 vLLM 跑通了

---

### Day 2（周二）：理解 PagedAttention + 读 scheduler 源码

**学习目标**：能用自己的话讲清楚 PagedAttention，能指出 scheduler.py 的核心函数

**具体行动**：
1. 读 vLLM 官方博客（30 分钟）：https://blog.vllm.ai/2023/06/20/vllm.html
2. 看 PagedAttention 的图解科普（B站/知乎搜索，1 小时）
3. **读源码**（重点不是全读懂，而是抓核心函数）：
   - `vllm/core/scheduler.py` 里的 `Scheduler.schedule()`
   - `vllm/core/block_manager.py` 里的 `allocate()` 和 `free()`
4. 思考并记录：PagedAttention 和操作系统虚拟内存的相似之处（这是你的强项！）

**面试话术**（当晚背熟）：
> "vLLM 的核心创新是 PagedAttention。传统 LLM 推理为每个请求预先分配一块连续的 KV Cache，这很像早期操作系统的连续内存分配，会导致严重的显存碎片化和浪费。vLLM 借鉴了 OS 虚拟内存的分页思想，把 KV Cache 划分成固定大小的 block（默认 16 tokens），通过 block table 做非连续映射。这样不仅能支持更大的 batch size，还能在做 parallel sampling 时共享 prompt 部分的 KV Cache。"

---

### Day 3（周三）：压测 + 观察性能变化

**学习目标**：有真实的 benchmark 数据可以讲

**具体行动**：
1. 用 `benchmark_throughput.py` 或自己写一个简单的 benchmark 脚本
2. 测试不同 `max_num_seqs`（32、64、128、256）下的 throughput 和 latency
3. 测试不同请求长度（短 prompt 100 tokens vs 长 prompt 2000 tokens）下的表现
4. 观察 `nvidia-smi` 中的显存占用和 GPU 利用率变化

**产出物**：一个 Excel/表格，记录不同参数下的性能数据

---

### Day 4（周四）：动手小项目——把 vLLM 和 faasd 嫁接起来

**学习目标**：利用现有项目创造差异化谈资

**具体行动**（二选一，推荐 A）：

**方案 A：在 faasd-in-rust 中调用 vLLM**
- 在 faasd 平台里部署一个函数，该函数内部通过 HTTP 调用你本地启动的 vLLM OpenAI-compatible API
- `vllm serve Qwen/Qwen2.5-7B-Instruct --api-key token-abc123`
- 写一个 faasd 函数，向 `http://localhost:8000/v1/completions` 发请求
- 这证明你的 Serverless 平台可以承载 AI 推理服务

**方案 B：在 DragonOS 容器里尝试跑 vLLM**
- 如果你 DragonOS 的容器运行时已经能跑简单程序，尝试在里面跑一个最小的 vLLM demo
- 这非常有冲击力："我在自己做的操作系统内核上成功部署了大模型推理服务"
- 但这个方案难度更高，如果容器运行时还不稳定，优先方案 A

**产出物**：一段能跑通的代码 + 一张截图

---

### Day 5（周五）：DeepSpeed ZeRO 概念速通

**学习目标**：能回答"ZeRO 是什么、分几个阶段、解决了什么问题"

**具体行动**：
1. 读 DeepSpeed ZeRO 博客（1 小时）：https://www.microsoft.com/en-us/research/blog/zero-deepspeed-new-system-optimization-to-train-deep-learning-models-with-100-billion-parameters/
2. 重点理解三张图：ZeRO-1（分片 optimizer states）、ZeRO-2（再分片 gradients）、ZeRO-3（再分片 parameters）
3. 不需要跑 DeepSpeed，只需要**概念层面**的理解

**面试话术**（当晚背熟）：
> "DeepSpeed ZeRO 解决的是数据并行训练中的显存冗余问题。传统 DDP 每个 GPU 都保存一份完整的优化器状态、梯度和模型参数。ZeRO 的核心思想是把这三样东西分片到不同 GPU 上。ZeRO-1 只分片优化器状态，ZeRO-2 加分片梯度，ZeRO-3 再把模型参数也分片。这样可以在不增加模型并行复杂度的情况下，显著降低单卡显存占用。我在了解这个的时候，联想到我做 cgroup 时学到的资源隔离和配额管理——本质上都是在解决'有限的资源怎么高效共享'的问题。"

---

### Day 6（周六）：分布式训练基础概念补课

**学习目标**：能听懂"数据并行、张量并行、流水线并行"这些词

**具体行动**：
1. 看李沐的分布式训练讲座（B站，挑重点看 2 小时）
2. 理解三个概念：
   - **Data Parallel (DP/DDP)**：每个 GPU 存完整模型，数据分批，梯度 AllReduce
   - **Tensor Parallel (TP)**：把一层模型切开，不同 GPU 算不同部分，通信量大
   - **Pipeline Parallel (PP)**：把不同层放到不同 GPU，像流水线一样传递中间结果
3. 理解为什么大模型训练要**三种并行结合使用**

**面试话术**：
> "大模型训练通常要三种并行结合。数据并行可以扩展 batch size；张量并行解决单卡放不下一个 layer 的问题，但通信开销很大，通常只在同一台机器的 GPU 之间做；流水线并行解决层数太多的问题，把不同层放到不同机器上，像 CPU 流水线一样传递激活值。我在 faasd 项目里做的网络命名空间分发和容器编排，本质上也是在解决多节点之间的通信隔离和资源调度问题。"

---

### Day 7（周日）：整理笔记 + 面试话术打磨

**具体行动**：
1. 整理本周的所有笔记，形成 3-5 个"深度技术点"
2. 每个技术点准备：
   - 30 秒版本（电梯演讲）
   - 3 分钟版本（正常面试回答）
   - 可能的追问（提前想好）
3. 更新简历或面试自我介绍，把 vLLM/DeepSpeed 关键词自然加进去

**本周产出物清单**：
- [ ] vLLM 跑通截图
- [ ] PagedAttention 理解笔记
- [ ] benchmark 数据表格
- [ ] faasd + vLLM 嫁接 demo（代码 + 截图）
- [ ] ZeRO 概念笔记
- [ ] 3-5 个面试话术

---

## 第二周：源码深入 + 差异化项目 + 面试准备

### Day 8-9（周一、周二）：读 vLLM scheduler 核心源码

**学习目标**：能和面试官聊到源码级别

**具体行动**：
1. 精读 `vllm/core/scheduler.py`：
   - `Scheduler._schedule_prefills()`：新请求怎么进入 prefill 阶段
   - `Scheduler._schedule_running()`：正在 decode 的请求怎么调度
   - `Scheduler.schedule()`：整体调度决策入口
2. 精读 `vllm/core/block_manager_v1.py` 或 `block_manager_v2.py`：
   - `BlockTable` 的数据结构
   - `allocate()` 和 `free()` 怎么管理 block
   - `can_allocate()` 的判断逻辑
3. 思考并用 Rust/系统的语言表达：
   - "scheduler 的状态机和我在 DragonOS loop 设备里做的状态机有什么相似之处？"
   - "block manager 的分配策略和操作系统内存分配器的区别？"

**面试话术**：
> "我这一周专门读了 vLLM 的 scheduler 源码。它的调度流程可以分成三步：先尝试调度正在 running 的请求（decode 阶段），再尝试调度 waiting 队列里的新请求（prefill 阶段），最后做 block 分配。调度器需要考虑多个约束：显存上限、max_num_seqs、抢占策略等。这让我联想到我做 DragonOS loop 设备时设计的状态机——I/O 请求进来后也要先做状态检查、再做资源分配、最后才执行。"

---

### Day 10（周三）：NCCL + 高性能网络概念速通

**学习目标**：能回答"为什么大模型训练需要 RDMA/InfiniBand"

**具体行动**：
1. 读 NVIDIA NCCL 文档的 collectives 图解（30 分钟）
2. 理解 AllReduce、AllGather、ReduceScatter 的用途
3. 读 RDMA/InfiniBand 科普文章（1 小时）
4. 重点理解：为什么 TCP 不适合大模型训练集群？（带宽、延迟、CPU 开销）

**面试话术**：
> "大模型训练对通信带宽和延迟极其敏感。以 175B 模型的数据并行为例，每次迭代后需要 AllReduce 数十 GB 的梯度。如果用传统 TCP/IP，数据要经过内核协议栈、CPU 拷贝、网卡发送，延迟和 CPU 开销都很高。而 InfiniBand + RDMA 可以直接从 GPU 显存通过网络发送到另一块 GPU 的显存（GPUDirect RDMA），绕过 CPU 和内核，带宽可达 400Gbps 甚至更高。我做 DragonOS 网络协议栈和 faasd CNI 网络配置的时候，对'数据包怎么从应用到网卡'有比较深的理解，这让我能更快理解 RDMA 为什么能跳过这些路径。"

---

### Day 11（周四）：Checkpoint + 容错机制

**学习目标**：能聊训练中的容错和恢复

**具体行动**：
1. 读 PyTorch Distributed Checkpoint 文档（1 小时）
2. 理解同步 checkpoint 和异步 checkpoint 的区别
3. 思考：如果训练过程中一个 GPU 节点挂了，系统怎么恢复？

**面试话术**：
> "大模型训练周期长、成本高，节点故障是常态。最常见的容错机制是定期做分布式 checkpoint，把模型参数、优化器状态、随机种子持久化到分布式存储（如 HDFS/S3）。节点挂掉后，调度器重新分配节点，从最近的 checkpoint 恢复训练。为了降低 checkpoint 的 overhead，可以用异步 checkpoint——训练主线程不阻塞，由后台线程把状态写盘。我在 faasd 项目里用 scopeguard 设计的失败回滚机制，本质上也是在解决'状态一致性和错误恢复'的问题，只是场景从容器编排换到了分布式训练。"

---

### Day 12（周五）：模拟面试 + 弱点修补

**具体行动**：
1. 找一个朋友或自己对着镜子，模拟 30 分钟技术面试
2. 重点练习这 5 个高频问题（见下方）
3. 记录自己卡壳的地方，当天修补

---

### Day 13-14（周六、周日）：项目收尾 + 叙事打磨

**具体行动**：
1. 把 faasd + vLLM 的 demo 做到能稳定演示的程度
2. 写一份 1 页的"项目说明"，包含：
   - 背景：为什么要把 vLLM 和 faasd 结合
   - 架构图：请求怎么从网关 -> faasd 函数 -> vLLM 服务
   - 关键数据：latency、throughput、资源占用
   - 遇到的问题和解决方案
3. 准备一段 2 分钟的"学习进展汇报"，如果 HR/面试官主动联系你，可以直接发过去

---

## 四、高频交叉问题 & 回答模板

### Q1: 你之前做内核和容器，跟大模型训练/推理系统有什么关系？

**回答**：
> "大模型 Infra 的核心挑战是资源隔离、通信效率和异常恢复，这三块正是我之前的强项。比如在 DragonOS 里我做的 cgroup v2 资源控制，对应到 AI 集群里就是 GPU 显存/计算资源的调度和隔离；我做的 loop 设备状态机和并发安全，对应到推理引擎里就是请求调度器的状态管理和 I/O 收敛；我做 faasd 时的多步骤事务回滚，和训练 pipeline 中的 checkpoint 恢复思路完全一致。所以我不是从零开始切入 AI Infra，而是把已有的系统能力往这个新场景上迁移。"

---

### Q2: 你了解 vLLM 吗？它的核心创新是什么？

**回答**：
> "vLLM 的核心是 PagedAttention。传统 LLM 推理为每个请求预先分配一块连续的 KV Cache，这就像操作系统早期的连续内存分配，会导致严重的显存碎片化和浪费。vLLM 借鉴了 OS 虚拟内存的分页思想，把 KV Cache 划分成固定大小的 block，通过 block table 做非连续映射。
>
> 这样做有两个好处：第一，显存利用率大幅提升，可以支持更大的 batch size；第二，在做 parallel sampling 或 beam search 时，同一个 prompt 的 KV Cache block 可以被多个序列共享，避免重复计算。
>
> 我最近不仅读了它的文档，还动手部署了 Qwen2.5-7B，做了不同 batch size 下的 benchmark，也读了 scheduler.py 和 block_manager.py 的核心源码。"

---

### Q3: DeepSpeed 的 ZeRO 是什么？为什么要分阶段？

**回答**：
> "ZeRO 解决的是数据并行训练中的显存冗余问题。传统 DDP 每个 GPU 都保存一份完整的优化器状态、梯度和模型参数。ZeRO 的核心思想是把这三样东西分片到不同 GPU 上，而不是每个 GPU 都存完整副本。
>
> - ZeRO-1：只分片优化器状态（optimizer states）
> - ZeRO-2：再加分片梯度（gradients）
> - ZeRO-3：再把模型参数（parameters）也分片
>
> 阶段越靠后，单卡显存占用越低，但通信量会增加。实际使用中要根据模型大小和集群带宽做 trade-off。"

---

### Q4: 分布式训练里，AllReduce 是怎么工作的？

**回答**：
> "AllReduce 的目标是让每个节点最终都拥有聚合后的完整结果。最经典的实现是 Ring-AllReduce，它把 N 个 GPU 排成一个环，分两个阶段：
>
> 第一阶段 Scatter-Reduce：每个 GPU 只累加自己负责的那部分数据，绕环传递；
> 第二阶段 AllGather：把完整结果再绕环传递一圈。
>
> 这样总的通信量只和数据大小有关，和 GPU 数量无关，非常适合大规模集群。NCCL 内部就是高度优化的 Ring-AllReduce 实现。"

---

### Q5: 如果训练过程中一个节点挂了，怎么恢复？

**回答**：
> "首先训练框架会定期做分布式 checkpoint，比如每隔 N 步保存模型状态、优化器状态和随机种子到分布式存储。节点挂掉后，集群调度器（比如 Kubernetes + Volcano）会检测到失败事件，重新分配一个节点，从最近的 checkpoint 恢复训练。
>
> 为了降低 checkpoint 开销，可以用异步 checkpoint——训练主线程不阻塞，由后台线程写存储。我在 faasd 项目里设计的 scopeguard 失败回滚机制，也是把资源生命周期和错误处理前置，这和训练系统的容错设计思路是一致的。"

---

## 五、关键策略提醒

### 1. 不要读原始论文
你是工程岗，不是研究岗。**博客 > 文档 > 源码 > 论文**。论文是最后才看的东西。

### 2. 必须动手
"我读了"在面试里没有说服力，"我跑了、我调了、我测了"才有。

### 3. 利用现有项目制造差异化
同样是学 vLLM，你比别人的优势是：
- 你有一个自己做的 Serverless 平台可以承载它
- 你有一个自己做的操作系统内核可以尝试跑它
- 这是 99% 的候选人做不到的事情

### 4. 横向比较期主动出击
如果超过 10 天没有消息，可以发一条跟进消息：
> "面试官您好，我这段时间一直在主动学习 AI Infra 相关的技术。最近我完成了 vLLM 的本地部署和性能测试，也在尝试把它和我之前做的 faasd Serverless 平台结合。我对这个方向非常有热情，希望能有机会加入团队。"

---

## 六、为什么要学这些？学完能解决什么？

| 学习模块 | 为什么要学 | 学完能解决什么 |
|---|---|---|
| **vLLM 部署 + 压测** | 岗位要求明确写了"熟悉 vLLM/sglang"，这是第一优先级 | 能在面试中说"我部署过、测过、读过源码"，有真实谈资 |
| **PagedAttention + scheduler 源码** | 推理系统的核心优化，也是 vLLM 面试最爱问的 | 能聊到源码级别，体现工程深度 |
| **DeepSpeed ZeRO 概念** | 岗位要求明确写了"熟悉 DeepSpeed/Megatron-LM" | 能回答分布式训练的基础问题，不被一问就卡壳 |
| **NCCL + RDMA/InfiniBand** | 岗位要求写了"高性能网络""大规模训练集群" | 能把你的网络底层知识和 AI 集群通信联系起来 |
| **faasd + vLLM 嫁接项目** | 制造差异化竞争力 | 简历和面试中有一个独特的、别人讲不出来的故事 |

**最终目标**：让蚂蚁 HR 和面试官相信——你不是"一个会用 AI 写代码的系统工程师"，而是"一个正在快速补齐 AI Infra 硬技术栈、并且能把系统底层能力和上层应用打通的潜力股"。


“您好，我是 张辉洲，面试 超级计算技术部的AI基础设施工程岗位的。想咨询一下横向进度。我对这个岗位的技术氛围和业务非常向往，
目前我也有其他友商在推进流程，但我对贵公司岗位意向程度很高。我看目前横向了半个月没有推进，所以想确认一下目前流程反馈是否正面，大概什么时候能有进一步消息”