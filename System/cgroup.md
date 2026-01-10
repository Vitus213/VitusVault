# Cgroup v2：Linux 资源控制机制详解

## 一、Cgroup 是什么？

### 1.1 术语定义

| 术语 | 定义 |
|------|------|
| **cgroup** | "control group" 的缩写，指单个控制组。本文中统一使用小写形式 |
| **cgroups** | 复数形式，指多个独立的控制组或整个特性 |
| **controller** | 控制器，负责分发特定类型的系统资源（如 CPU、内存、IO） |

> **说明**：本文主要介绍 cgroup v2。现代主流 Linux 发行版已默认启用 v2，通常通过内核参数 `cgroup_no_v1=all` 完全禁用 v1 控制器。

### 1.2 核心概念

cgroup 是 Linux 内核的一种资源管理机制，用于层级化地组织进程，并以可控、可配置的方式分配系统资源。

cgroup 由两个核心组件构成：

| 组件 | 职责 |
|------|------|
| **Core** | 负责层级化组织进程，维护 cgroup 树结构 |
| **Controller** | 负责在层级结构中分配特定类型的系统资源 |

### 1.3 关键特性

**树状结构**

cgroup 构成树状层次结构，每个节点代表一个 cgroup。进程从属于某个 cgroup，cgroup 中包含 core 和 controller 的配置信息。

**进程组织规则**

在默认的 `domain` 模式下：
- 一个进程的所有线程属于同一个 cgroup
- 父进程 `fork()` 出的子进程自动继承父进程的 cgroup
- 进程可以迁移，但必须携带其所有线程一同迁移

**No Internal Process Constraint（无内部进程约束）**

> **重要规则**：如果一个 cgroup 下有子 cgroup，则该 cgroup 不能包含任何进程。

这意味着每个 cgroup 只能扮演一种角色：
- **内部节点（父节点）**：仅用于组织子 cgroup，不存放进程
- **叶子节点**：存放进程，但不能有子 cgroup

此设计避免了父子节点进程之间的资源抢占冲突。

**控制器(Controller)的层次化行为**

- 控制器可在任意 cgroup 上启用或禁用
- 控制器的效果是层次化的：嵌套 cgroup 中启用控制器时，总是进一步限制资源
- 靠近根节点的限制不能被子节点的设置覆盖

---

## 二、Cgroup v1 与 v2 的核心差异

### 2.1 架构差异

| 特性 | Cgroup v1 | Cgroup v2 |
|------|-----------|-----------|
| **层次结构** | 每个 controller 可有独立的树 | 全局单一树结构 |
| **进程归属** | 一个进程可同时属于多个 controller 的不同组 | 一个进程只能位于树中的一个位置 |
| **资源协调** | 各 controller 独立管理，难以协调 | CPU、内存、IO 在同一位置统一管理 |

**v1 的问题**：由于每个 controller 有独立的树，一个进程的 PID 可能同时在 A_group 和 B_group 中，导致管理复杂。当需要跨控制器协调（如因 IO 压力降低 CPU 频率）时难以实现。

**v2 的改进**：全系统只有一棵树，进程只能出现在一个位置，所有资源在同一节点进行核算和记录。

### 2.2 控制器授权机制

v2 引入了显式的资源分发控制：子节点必须通过父节点的 `cgroup.subtree_control` 明确授权，才能使用对应的控制器。

```bash
# 查看根 cgroup 可用的控制器
❯ cat /sys/fs/cgroup/cgroup.subtree_control
cpuset cpu io memory hugetlb pids rdma misc

# 子 cgroup 默认不继承控制器，需要显式启用
```

### 2.3 新增特性

**更精细化的内存管理**

- 内存控制器性能显著提升
- 支持 PSI（Pressure Stall Information）监控
- 引入 `memory.reclaim` 接口主动回收内存

**PSI（压力停滞信息）**

PSI 能够实时统计因 CPU、内存或 IO 不足导致进程停滞的时间比例，为资源调度决策提供数据支持。

---

## 三、基本操作

### 3.1 挂载 Cgroup v2

cgroup v2 使用单一层次结构：

```bash
# 挂载 cgroup v2
mount -t cgroup2 none /sys/fs/cgroup

# 或在 /etc/fstab 中配置
none /sys/fs/cgroup cgroup2 defaults 0 0
```

### 3.2 挂载选项

| 选项 | 说明 |
|------|------|
| `nsdelegate` | 将 cgroup 命名空间视为委托边界，减少容器对特权的依赖 |
| `favordynmods` | 降低动态 cgroup 修改的延迟 |
| `memory_localevents` | 仅在当前 cgroup 填充 memory.events |
| `memory_recursiveprot` | 递归应用内存保护到整个子树 |
| `memory_hugetlb_accounting` | 将 HugeTLB 内存计入内存控制器 |
| `pids_localevents` | 恢复 v1 风格的 pids.events:max 行为 |

### 3.3 nsdelegate 详解

`nsdelegate` 选项对容器安全具有重要意义：

```
nsdelegate: 将 cgroup 命名空间视为委托边界。该选项仅在系统级 init 命名空间挂载时设置。
在非 init 命名空间挂载中，该选项被忽略。
```

**对容器的影响**：

1. **隔离边界**：容器进程被限制在自己的 Cgroup Namespace 中
2. **虚拟根节点**：容器内 `/sys/fs/cgroup` 呈现为以容器自身为根的视图，而非宿主机的全局视图
3. **权限委托**：容器内的进程拥有在其"虚拟根"下创建子目录、分配资源的权限，无需宿主机特权干预

这有效减少了 Docker 等容器运行时对特权操作的依赖。

---

## 四、线程模式

### 4.1 设计背景

默认的 `domain` 模式要求同一进程的所有线程属于同一个 cgroup。然而某些场景（如 JVM）需要对单个进程内的不同线程进行差异化资源分配。

线程模式（threaded mode）应运而生，支持以线程粒度进行资源控制。

### 4.2 控制器分类

| 类型 | 说明 | 支持的控制器 |
|------|------|--------------|
| **domain controllers** | 不支持线程模式，只能以进程为单位操作 | memory, io, hugetlb, rdma |
| **threaded controllers** | 支持线程模式，可对单个线程操作 | cpu, cpuset, perf_event, pids |

### 4.3 启用线程模式

```bash
# 将 cgroup 标记为线程子树的根
echo threaded > cgroup.type

# 在父节点启用线程控制器
echo "+cpu +cpuset" > cgroup.subtree_control
```

### 4.4 线程模式特性

| 特性 | 说明 |
|------|------|
| 线程分散 | 同一进程的线程可以分布在子树的不同 cgroup 中 |
| 无内部进程约束豁免 | 不受"无内部进程约束"限制 |
| 非叶节点控制器 | 非叶子 cgroup 可以启用线程控制器 |

### 4.5 设计权衡

线程模式是一种折衷设计：
- 统一管理内存等难以细粒度控制的资源
- 在 CPU、IO 等支持细粒度控制的资源上提供灵活分配
- 在保护系统性能的前提下提供可扩展的配置选项

---

## 五、关键接口文件

cgroup 文件系统通常挂载在 `/sys/fs/cgroup`，下文介绍核心接口文件。

### 5.1 核心控制文件

#### cgroup.type

读写单值文件，指示 cgroup 的当前类型：

| 值 | 说明 |
|-----|------|
| `domain` | 普通有效域 cgroup（默认） |
| `domain threaded` | 作为线程子树根的线程域 cgroup |
| `domain invalid` | 处于无效状态的 cgroup |
| `threaded` | 线程子树的成员 cgroup |

#### cgroup.procs

读写换行分隔的 PID 列表，列出属于该 cgroup 的所有进程。

**写入条件**：
1. 对目标 `cgroup.procs` 有写权限
2. 对源和目标 cgroup 的共同祖先的 `cgroup.procs` 有写权限

#### cgroup.threads

与 `cgroup.procs` 类似，但操作的是线程 ID (TID)。

**约束**：只能在同一资源域内移动线程。

#### cgroup.controllers

只读空格分隔文件，显示该 cgroup 可用的所有控制器。

#### cgroup.subtree_control

读写空格分隔文件，控制从该 cgroup 向其子节点分发哪些控制器。

```bash
# 启用控制器
echo "+cpu +memory" > cgroup.subtree_control

# 禁用控制器
echo "-io" > cgroup.subtree_control
```

#### cgroup.events

只读键值文件，包含状态信息：

| 条目 | 说明 |
|------|------|
| `populated` | cgroup 或其后代是否包含活动进程 (0/1) |
| `frozen` | cgroup 是否被冻结 (0/1) |

### 5.2 进程控制文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `cgroup.freeze` | 读写 | 写入 "1" 冻结 cgroup 及所有后代中的进程 |
| `cgroup.kill` | 只写 | 写入 "1" 终止 cgroup 及所有后代中的所有进程 |

### 5.3 统计信息文件

| 文件 | 说明 |
|------|------|
| `cgroup.stat` | 后代 cgroup 总数、死亡后代计数等 |
| `cgroup.max.descendants` | 最大允许后代 cgroup 数量限制 |
| `cgroup.max.depth` | 最大允许后代深度限制 |

### 5.4 PSI（压力停滞信息）

#### cpu.pressure / memory.pressure / io.pressure

显示因资源短缺导致的进程停滞时间。

**输出格式**：
```
some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```

| 指标 | 含义 |
|------|------|
| `some` | 至少有一个进程因等待资源而停滞的时间比例 |
| `full` | **所有**进程因等待资源而停滞的时间比例 |

> **诊断提示**：如果 `full` 值较高，说明系统处于严重资源争用状态，所有进程都在等待资源，系统接近"假死"状态。

#### irq.pressure

显示硬中断/软中断处理带来的系统压力。

### 5.5 资源统计文件

#### memory.stat

详尽的内存使用明细，包括：
- `anonymous`：匿名内存（堆、栈、mmap 私有段）
- `file`：文件页缓存
- `kernel_stack`：内核栈
- `sock`：网络 socket 缓冲区
- 等等

#### cpu.stat

累计 CPU 使用时间及被 throttled 的次数。

#### io.stat

每个磁盘设备的读写统计：
- `rbytes`/`wbytes`：读/写字节数
- `rios`/`wios`：读/写 IO 次数

#### memory.reclaim

主动触发内存回收：

```bash
# 尝试回收 1GB 内存
echo "1G" > memory.reclaim
```

---

## 六、实战示例

### 6.1 限制进程 CPU 使用

```bash
# 创建子 cgroup
mkdir /sys/fs/cgroup/limited

# 启用 CPU 控制器(一般情况下默认都会启用)
echo "+cpu" > /sys/fs/cgroup/cgroup.subtree_control

# 限制 CPU 使用为 50%（单核）
echo "50000 100000" > /sys/fs/cgroup/limited/cpu.max

# 将进程（PID 1234）加入
echo 1234 > /sys/fs/cgroup/limited/cgroup.procs
```

### 6.2 限制进程内存

```bash
# 创建子 cgroup
mkdir /sys/fs/cgroup/memory_limited

# 启用内存控制器（一般情况下默认都会启用）
echo "+memory" > /sys/fs/cgroup/cgroup.subtree_control

# 设置内存上限为 512MB
echo "512M" > /sys/fs/cgroup/memory_limited/memory.max

# 将进程加入
echo 1234 > /sys/fs/cgroup/memory_limited/cgroup.procs

# 查看内存使用情况
cat /sys/fs/cgroup/memory_limited/memory.stat
```

### 6.3 冻结进程

```bash
# 冻结 cgroup 中的所有进程
echo 1 > /sys/fs/cgroup/target/cgroup.freeze

# 解冻
echo 0 > /sys/fs/cgroup/target/cgroup.freeze
```

---

## 七、常见问题

### 7.1 容器技术基础

Docker 等容器技术主要依赖两个 Linux 内核特性：

| 特性 | 作用 |
|------|------|
| **Namespace** | 提供资源隔离（进程、网络、文件系统等） |
| **Cgroup** | 提供资源限制和监控 |

### 7.2 特权容器 vs 安全容器

| 类型 | 特点 |
|------|------|
| **特权容器** | 以特权模式运行，可访问宿主机设备，安全性较低 |
| **安全容器** | 结合 Namespace、Cgroup、seccomp、AppArmor 等多重隔离，安全性更高 |

### 7.3 如何判断系统使用的是 cgroup v1 还是 v2？

```bash
# 检查 v2 是否挂载
mount | grep cgroup2

# 或检查文件系统类型
stat -f -c %T /sys/fs/cgroup
```

输出 `cgroup2fs` 表示使用 v2，`tmpfs` 表示使用 v1。

---

## 八、参考资料

- [Linux Kernel cgroup v2 Documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html)
- [Red Hat: Introduction to control groups (cgroups)](https://red.ht/3X7Y9xK)
- [Systemd and cgroups](https://systemd.io/CGROUP_DELEGATION/)
