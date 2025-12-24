
#### 1. 设计与评估方法步骤

**ADD (Attribute-Driven Design) 属性驱动设计步骤**

1. **确认输入**：整理功能需求、质量属性场景及设计限制。
2. **选择待设计的系统元素**：明确本次设计是针对整个系统还是特定子系统。
3. **识别候选设计胜任者**：研究匹配的架构风格、模式和策略。
4. **选择设计胜任者**：基于属性优先级和现实约束做出决策。
5. **细化元素并分配职责**：将功能和非功能需求映射到具体的模块。
6. **定义接口和交互**：明确组件之间的通信协议与接口。
7. **验证和迭代**：评估当前设计是否满足需求，必要时返回步骤2。

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

Pipe and Filter Solution