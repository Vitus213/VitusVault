这是一份为你量身定制的数据库系统复习指南。考虑到你目前的“零基础”状态，我将这份卷子中的散点知识重新组织成了**四个逻辑模块**。

每一部分都遵循这样的结构：

1. **原题考点**：试卷里考了什么。
2. **核心概念科普**：用通俗语言解释这是什么。
3. **深度解析**：详细拆解知识细节。

---

# 数据库系统复习指南 (基于2013年部分题解)

## 第一部分：数据库的“世界观” (基础理论)

这部分主要解决“数据库长什么样”和“怎么描述数据”的问题。

### 1. 数据模型 (Data Model)

> 
> **原题引用**：A Data Model is a collection of conceptual tools for describing data, data relationships, data semantics and consistency constraints. 
> 
> 

* **小白科普**：
想象你要盖房子，你需要图纸。**数据模型**就是数据库的“设计图纸”。如果只有一堆二进制数据（砖块），没有模型（图纸），你就不知道这些数据代表什么是用户，什么是商品，以及它们之间有什么关系。
* **深度解析**：
一个完整的数据模型必须包含四个要素：
1. **数据 (Data)**：描述事物的静态特征（如：姓名、年龄）。
2. **数据关系 (Data Relationships)**：事物之间的联系（如：学生“选修”课程）。
3. **数据语义 (Data Semantics)**：数据的含义（如：`1` 代表男，`0` 代表女）。
4. **一致性约束 (Consistency Constraints)**：数据的规则（如：年龄不能是负数）。



### 2. 数据抽象的三级模式 (Three-level Abstraction)

> 
> **原题引用**：The three-level of data abstraction in database system includes: physical level, logical level and view level. 
> 
> 

* **小白科普**：
这是为了让不同的人看到不同的东西，从而隐藏复杂性。
* **物理层**：给硬盘看（数据存在哪个磁道，用了什么B+树结构）。
* **逻辑层**：给程序员看（有哪些表，表里有哪些字段）。
* **视图层**：给最终用户看（只给你看你能看的数据，比如普通员工看不到老板的工资）。


* **考点记忆**：从低到高依次是 **Physical (物理) -> Logical (逻辑) -> View (视图)**。

### 3. 视图 (View)

> 
> **原题引用**：A view is a virtual relation that is not part of the logical model, but is mode visible to a user. 
> 
> 

* **核心概念**：
视图是**虚拟的表 (Virtual Relation)**。它本身**不存储数据**，只存储一条 SQL 查询语句。当你打开视图时，数据库现场执行查询给你看结果。
* **为什么需要它？**
1. **简化复杂查询**：把几百行的连接查询保存成一个视图，下次直接 `Select * from view` 即可。
2. **安全性**：隐藏敏感字段。



### 4. 实体参与度 (Participation)

> 
> **原题引用**：...total participation if every entity in E participate in at least one relationship in R... if only some entities... partial. 
> 
> 

* **场景理解**：
假设有两个集合：“员工”和“部门”。
* **全部参与 (Total Participation)**：规定**每一个**员工都必须属于一个部门。那么“员工”在“归属”这个关系中就是全部参与。
* **部分参与 (Partial Participation)**：并不是**每一个**部门都有员工（可能是新成立的部门）。那么“部门”在“归属”这个关系中就是部分参与。



---

## 第二部分：保护数据的规则 (完整性约束)

这部分解决“如何防止垃圾数据进入数据库”的问题。

### 1. 常见的完整性约束

> 
> **原题引用**：Integrity constrains guard against accidental damage... include primary key. ...not null, unique and default, foreign key, check predicate. 
> 
> 

你需要记住这五大金刚，它们是建表时的保护神：

1. **Primary Key (主键)**：身份证号。唯一标识一行数据，且**不能**为空。
2. **Foreign Key (外键)**：引用链接。比如“订单表”里的`用户ID`必须是“用户表”里真实存在的 ID。
3. **Not Null (非空)**：必填项。
4. **Unique (唯一)**：不能重复（比如手机号），但允许为空（除非同时也设了 Not Null）。
5. **Default (默认值)**：不填就用这个值（比如注册时间默认为当前时间）。
6. **Check Predicate (检查谓词)**：自定义逻辑（比如 `Check score >= 0`）。

---

## 第三部分：SQL 实战 (建表与查询)

这部分是考试的计算/编程题核心。

### 1. 建表语句 (Create Table) 解析

参考题目中的 `apply_form`, `repairer` 等表的创建 。

* **基础语法**：
```sql
Create table 表名 (
   字段名 数据类型 约束,
   ...
)

```


* **核心代码段拆解**：
* 
`apply_id char(11) not null` ：定义一个定长字符字段，不允许为空。


* 
`add constraint A_id primary key (apply_id)` ：**定义主键**。这行代码把 `apply_id` 设为这张表的唯一标识。


* 
`add constraint FK_A foreign key R_id references repair_record(Recoed_id)` ：**定义外键**。


* 这表示当前表里的 `R_id` 字段，必须对应 `repair_record` 表里的 `Recoed_id` 字段。
* 这是为了保证数据的一致性（你不能维修一条不存在的记录）。





### 2. SQL 查询语句 (Select) 技巧

题目中包含多个查询示例 ，涵盖了最难的逻辑。

#### A. 聚合函数 (Aggregate)

> 
> **例子**：`Select PNO From PART Where PART.weight = MIN (weitht)` 
> 
> 

* **知识点**：`MIN()` 是找最小值。
* **逻辑**：从 `PART` 表中找出重量等于最小重量的那个零件号 (`PNO`)。

#### B. 复杂的“除法”逻辑 (Not Exists / Except)

> 
> **例子**： `And not exists ( select ... except select ... )`
> 
> 

* **小白科普**：这是 SQL 里最难的逻辑，通常用来解决“查询完成了**所有**工作的员工”或者“供应了**所有**零件的供应商”这类问题。
* **逻辑拆解**：
1. `Except` 是**差集**运算（A - B）。
2. `Not Exists (A Except B)` 的意思是：**不存在 (A 集合里有，但 B 集合里没有的东西)**。
3. 即：**B 包含了 A 的所有内容**。


* 题目中的逻辑是：查询供应商，该供应商供应了 `J1` 工程所需要的**所有**零件。



#### C. 分组与排序 (Group By & Order By)

> 
> **例子**：`Order by JNO ASC Group by JNO` 
> 
> 

* 
**Group By**：将数据按某列打包。比如按 `JNO`（项目号）打包，然后用 `count(PNO)`  数每个包里有多少个零件。


* **Order By**：排序。`ASC` 是升序（1,2,3...），`DESC` 是降序。

#### D. 修改与删除 (Insert / Delete)

* 
**Delete** ：`delete from 表 where 条件`。如果条件是一个子查询，先执行子查询拿到 ID，再删除。


* 
**Insert** ：`Insert into 表 (列1, 列2) Values (值1, 值2)`。



---

## 第四部分：数据库底层原理 (性能与事务)

这部分解释数据库如何跑得快、跑得稳。

### 1. ACID 特性 (事务四大金刚)

> 
> **原题引用**：The ACID properties of transaction are: atomicity, consistency, isolation, durability. 
> 
> 

这是必考题，必须背诵：

* **A (Atomicity) 原子性**：要么全做，要么全不做。不能只转账一半，钱扣了对方没收到。
* **C (Consistency) 一致性**：事务前后数据必须合规。比如转账前后，两个人的钱加起来总数不变。
* **I (Isolation) 隔离性**：你做你的事务，我做我的，互不干扰。
* **D (Durability) 持久性**：一旦保存（Commit），数据就永久写在硬盘上了，断电也不怕。

### 2. 索引与 B+ 树 (Index & B+ Tree)

> 
> **原题引用**：...path from the root to the leaf node is no longer than log n /2( K ) 
> 
> 

* **小白科普**：索引就是书的“目录”。
* **B+ 树**：数据库最常用的目录结构。
* **公式含义**：。不要被数学吓到，这个公式只是告诉你，B+ 树非常“扁平”。哪怕有一亿条数据 ()，因为每个节点能存很多路 ()，我们也只需要跳很少几次（也就是树的高度）就能找到数据。

### 3. 并发控制与锁 (Locks)

> 
> **原题引用**：Data items can be locked... exclusive mode and shared mode... 
> 
> 

为了防止多人同时修改同一条数据导致冲突，需要加锁：

* **Shared Mode (S锁/共享锁)**：**只读锁**。我读的时候，你也只能读，不能改。
* **Exclusive Mode (X锁/排他锁)**：**写锁**。我改的时候，你既不能读也不能改，必须等我弄完。

### 4. 查询优化 (Heuristic Rules)

> **原题引用**：(a) perform selection & projection ... early; (b) perform most restrictive selection and join ... early. 
> 
> 

* **核心思想**：**尽早变小**。
* **解释**：
1. 如果只查“男学生”，就先执行 `Selection` 把女生过滤掉，别带着女生数据去跑后面的流程。
2. 如果只查“姓名”列，就先执行 `Projection` 把其他无关列扔掉。
3. 这样可以大幅减少数据传输量和计算量。



### 5. 立即修改方案 (Immediate Modification)

> 
> **原题引用**：...allows database modifications to be output to the database while the transaction is still in the uncommitted state. 
> 
> 

* **解释**：这是一种“急躁”的策略。事务还没确认为“成功”（Uncommitted）时，就先把修改写进硬盘了。
* **风险**：如果还没提交系统就崩了，重启后必须把这些还没确认的脏数据**撤销 (Undo)** 回去。

---

### 复习建议

1. **背诵英文名词**：Exam 中出现的 `Atomicity`, `Integrity`, `View`, `Primary Key` 等是填空题常客。
2. **理解 SQL 顺序**：`Select` -> `From` -> `Where` -> `Group by` -> `Having` -> `Order by`。
3. **搞懂“部分/全部参与”**：画两个圆圈（实体集）和一条线（关系），想一下是否每个人都必须连线。

希望这份文档能帮你快速建立知识框架！如果对某个 SQL 语句的具体逻辑还不清楚，随时问我。