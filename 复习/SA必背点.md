
#### 1. 设计与评估方法步骤

**ADD (Attribute-Driven Design) 属性驱动设计步骤**
1. Choose an element of the system to design / 选择系统的一个元素进行设计
2. Identify the ASRs for the chosen element. / 确定所选元素的架构上重要需求（ASRs）。
3. Generate a design solution for the chosen element. / 为所选元素生成设计解决方案。
4. Inventory remaining requirements and select the input for the next iteration. / 清点剩余需求并选择下一次迭代的输入。
5. Repeat steps 1-4 until all the ASRs have been satisfied. / 重复步骤 1-4，直到所有 ASR 都已满足。

**QAW (Quality Attribute Workshop) 质量属性研讨会步骤**

1. **QAW 介绍**：讲解流程。
2. **业务/项目展示**：理解背景。
3. **架构计划展示**：初步构思。
4. **识别架构驱动因素**：找出核心属性。
5. **场景头脑风暴**：利益相关者提出各种场景。
6. **场景合并**：去重。
7. **场景优先级排序**：投票排序。
8. **场景细化**：完善六要素。

**ATAM (架构权衡分析法) 阶段步骤**

* **重点关注**：第5步**生成效用树**和第6步识别**敏感点**与**权衡点**。

---

#### 2. 质量属性场景 (Scenario) 六要素

*背诵口诀：源、激、环、制、响、量*

* **刺激源 (Source)**：引发事件的主体（如：用户、攻击者）。
* **刺激 (Stimulus)**：具体的事件（如：发送请求、系统故障）。
* **环境 (Environment)**：状态上下文（如：峰值流量、离线状态）。
* **制品 (Artifact)**：受影响的系统部分（如：服务器、数据库）。
* **响应 (Response)**：系统的动作（如：限制访问、自动重启）。
* **响应度量 (Measure)**：量化指标（如：延迟 < 100ms）。

---

#### 3. 架构决策的 13 种原因

1. **满足功能需求**（系统要能干活）
2. **满足质量属性需求**（系统要干得好）
3. **遵循商业约束**（预算问题）
4. **符合标准与规范**（法律法规）
5. **技术可行性**（技术上能不能做）
6. **遗留系统集成**（兼容老代码）
7. **团队技能限制**（招不到会这种技术的人）
8. **成本预算**（人力物力）
9. **进度要求**（急着上线）
10. **降低技术风险**（求稳）
11. **可维护性与演进**（为了以后好改）
12. **市场竞争压力**（抢占先机）
13. **利益相关者偏好**（老板或甲方的喜好）

Module structures / 模块结构
- Decomposition structure / 分解结构
- Uses structure -> Layer pattern / 使用结构 -> 层模式
- Class structure / 类结构
- Data model / 数据模型
Component-and-connector structures / C&C结构，组成-连接器结构
- Service structure / 服务结构
- Concurrency structure / 并发结构
Allocation structures 分配结构
- Deployment structure / 部署结构
- Implementation structure / 实施结构
- Work assignment structure / 工作分配结构
Architecture design is a systematic approach to making design decisions. / 架构设计是一个系统化的方法，用于做出设计决策。
We categorize the design decisions as follows: / 我们将设计决策分类如下：
1. Allocation of responsibilities / 责任分配
2. Coordination model / 协调模型
3. Data model monitor / 数据模型监控
4. Management of resources / 资源管理
5. Mapping among architectural elements / 架构元素之间的映射
6. Binding time decisions / 绑定时间决策
7. Choice of technology / 技术选择
安全性具有三个主要特性，称为CIA：
8. Confidentiality is the property that data or services are protected from unauthorized access.
保密性是数据或服务受到未授权访问保护的属性。
  - For example, a hacker cannot access your income tax returns on a government computer. / 例如，黑客无法访问政府计算机上的个人所得税报表。
2. Integrity is the property that data or services are not subject to unauthorized manipulation.
完整性是数据或服务不受未授权篡改的属性。
  - For example, your grade has not been changed since your instructor assigned it. / 例如，自从教师给你打分后，你的成绩没有被更改。
3. Availability is the property that the system will be available for legitimate use.
可用性是系统能为合法使用提供可用性的属性。


### 第一部分：方法论细节补充 (Methodology Supplements)

#### 1. ATAM 的核心产出物 (Outputs of ATAM)

*在步骤中识别出的四个关键概念，必须背诵定义：*

* **Risk (风险)**: An architectural decision that may lead to undesirable consequences in light of quality attribute requirements. / 可能导致质量属性无法满足的架构决策。
* **Non-risk (非风险)**: An architectural decision that is deemed safe. / 被认为是安全的架构决策。
* **Sensitivity Point (敏感点)**: A property of one or more components (and/or component relationships) that is critical for achieving a particular quality attribute response. / 对**某个**质量属性有显著影响的架构属性（动一发而动全身）。
* *例子：加密级别越高（属性），安全性越高，但性能越低。加密级别就是一个敏感点。*


* **Trade-off Point (权衡点)**: A property that affects more than one attribute and is a sensitivity point for more than one attribute. / 影响**多个**质量属性的属性，通常是一个属性变好，另一个变差。
* *例子：提高加密级别提高了安全性，但降低了性能。这就是一个权衡点。*



#### 2. Utility Tree (效用树) 的优先级

*ATAM 第5步的核心，如何决定哪个场景最重要？*

* **Structure**: Root -> QA (e.g., Performance) -> Attribute Refinement (e.g., Latency) -> Scenario.
* **Prioritization (H/M/L)**: Scenarios are prioritized by pairs (Importance to stakeholders, Difficulty for architect). / 场景通过两维度排序：（对利益相关者的重要性，实现的难度）。
* **(H, H)**: High importance, High difficulty -> **Must focus on these first! (重点分析对象)**
* (H, M): High importance, Medium difficulty.
* (L, L): Low importance, Low difficulty -> Ignore or defer.



---

### 第二部分：核心架构策略 (Key Architectural Tactics)

*这是架构设计的“手段”，考试常问：“为了实现高可用性，你可以采用什么策略？”*

#### 1. Availability Tactics (可用性策略)

*目标：Detect (检测) -> Recover (恢复) -> Prevent (预防)*

* **Fault Detection**: Ping/Echo (Ping/回显), Heartbeat (心跳), Exception Detection (异常检测).
* **Recovery - Preparation & Repair**:
* **Active Redundancy (Hot Spare)** / 主动冗余（热备）：所有节点并行处理，毫秒级切换。
* **Passive Redundancy (Warm/Cold Spare)** / 被动冗余（冷/暖备）：主节点挂了，备节点才启动或接管。
* **Voting** / 投票：多数派表决，屏蔽错误结果。


* **Recovery - Reintroduction**: Shadow (影子运行), Resynchronization (状态重同步).

#### 2. Performance Tactics (性能策略)

*目标：Resource Demand (资源需求) -> Resource Management (资源管理)*

* **Control Resource Demand**:
* **Manage Sampling Rate** / 管理采样率（降低频率）。
* **Limit Event Response** / 限制事件响应（丢弃过载请求）。
* **Prioritize Events** / 事件优先级排序。


* **Manage Resources**:
* **Increase Resources** / 增加资源（加CPU/内存）。
* **Introduce Concurrency** / 引入并发（多线程/并行）。
* **Maintain Multiple Copies** / 数据副本（缓存 Caching）。
* **Bound Queue Sizes** / 限制队列大小。



#### 3. Modifiability Tactics (可修改性策略)

*目标：Reduce Coupling (降低耦合) -> Increase Cohesion (提高内聚)*

* **Localize Changes (局部化变更)**: Semantic Coherence (语义一致性).
* **Prevention of Ripple Effects (防止涟漪效应)**:
* **Hide Information** / 信息隐藏（封装）。
* **Maintain Existing Interfaces** / 维持现有接口（适配器模式）。
* **Restrict Communication Paths** / 限制通信路径（分层）。
* **Use an Intermediary** / 使用中间件（解耦）。


* **Defer Binding Time (推迟绑定时间)**: Runtime Registration (运行时注册), Configuration Files (配置文件).

#### 4. Security Tactics (安全性策略)

* **Detect**: Intrusion Detection (入侵检测).
* **Resist**: Authentication (认证), Authorization (授权), Encryption (加密), Limit Access (限制访问).
* **React**: Revoke Access (撤销访问), Lock Computer (锁定).
* **Recover**: Audit Trails (审计追踪/日志).

---

### 第三部分：架构模式补全 (Architectural Patterns Expansion)

#### 1. Pipe and Filter (管道与过滤器)

* **Definition**: Data arrives at a filter, is transformed, and passed via a pipe to the next filter. / 数据到达过滤器，被转换，通过管道传给下一个过滤器。
* **Key Elements**: Filter (Transformer), Pipe (Connector).
* **Strengths**: Easy to maintain/reuse (filters are independent), Concurrency (parallel processing), Flexible (rearrange filters). / 易维护复用，支持并发，灵活。
* **Weaknesses**: Latency (data transfer), Data parsing overhead (format conversion). / 延迟高，数据解析开销大。
* **Context**: Compilers, Video processing, Unix shell.

#### 2. Layered Pattern (分层模式)

* **Definition**: Components are organized in horizontal layers, each layer performs a specific role. / 组件按水平层组织，每层扮演特定角色。
* **Key Rule**: A layer can only use the layer strictly below it (Strict Layering) or any layer below it (Relaxed Layering). / 严格分层（只调下一层）vs 宽松分层（可跨层）。
* **Strengths**: Design simplicity, Portability (replace lower layers), Maintainability.
* **Weaknesses**: Performance (data must pass through all layers).

#### 3. Broker Pattern / Publish-Subscribe (代理/发布-订阅)

* **Definition**: Decouples senders (publishers) and receivers (subscribers).
* **Strengths**: High scalability, Loose coupling (anonymity). / 高扩展，松耦合。
* **Weaknesses**: Reliability (broker failure), Message delivery guarantee issues. / 代理是单点故障，消息送达难以完全保证。

#### 4. Model-View-Controller (MVC)

* **Definition**: Separates application into Model (Data), View (UI), Controller (Logic).
* **Strengths**: Multiple views for same data, Separation of concerns (easy to test/modify). / 同一数据多视图，关注点分离。
* **Weaknesses**: Complexity for simple UI. / 简单界面略显复杂。

#### 5. MapReduce

* **Definition**: For large-scale data processing. Map (sort/filter) -> Shuffle -> Reduce (summary).
* **Strengths**: Scalability on commodity hardware, Fault tolerance. / 廉价硬件上的高扩展，容错强。

---

### 第四部分：其他重要质量属性定义 (Other Quality Attributes Definitions)

*除了 CIA (安全)，这几个也是必背的：*

1. **Modifiability (可修改性)**: The cost and difficulty of changing the system. / 修改系统的成本和难度。
2. **Performance (性能)**: Responsiveness (latency) and Throughput. / 响应能力（延迟）和吞吐量。
3. **Interoperability (互操作性)**: The ability of systems to exchange and use information. / 系统间交换和使用信息的能力。
4. **Testability (可测试性)**: The ease with which software can be made to demonstrate its faults. / 软件能够轻松展示其故障的容易程度（通过测试发现Bug的难易度）。
5. **Usability (易用性)**: How easy it is for the user to accomplish tasks. / 用户完成任务的难易程度。

---

### 建议复习策略

1. **先背诵六要素和CIA**：这是送分题。
2. **理解 ADD/ATAM 流程**：不用死记每一步，但要明白 **Utility Tree** 和 **Risk/Trade-off** 是在哪一步出现的。
3. **重点攻克 Tactics（策略）**：考试如果问“如何提高系统的可用性？”，你不能只回答“做冗余”，要回答“采用 **Active Redundancy** 或 **Heartbeat** 策略”。
4. **模式对比**：搞清楚 **Pipe-Filter** 和 **Layered** 的优缺点区别。


