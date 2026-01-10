# Linux Control Group v2 深度分析

> 基于内核官方文档 (Documentation/admin-guide/cgroup-v2.rst)
> 作者: Tejun Heo <tj@kernel.org>
> 文档日期: 2015年10月

---

## 目录

1. [概述](#1-概述)
2. [基本操作](#2-基本操作)
3. [资源分配模型](#3-资源分配模型)
4. [核心接口文件](#4-核心接口文件)
5. [控制器详解](#5-控制器详解)
6. [命名空间](#6-命名空间)
7. [v1 的问题与 v2 的改进](#7-v1-的问题与-v2-的改进)

---

## 1. 概述

### 1.1 术语说明

- **cgroup**: "control group" 的缩写，永远小写
- **cgroups**: 复数形式，指多个独立的控制组
- **controller**: 控制器，负责分发特定类型的系统资源

### 1.2 什么是 cgroup？

cgroup 是一种按层次结构组织进程并以可控、可配置的方式沿层次结构分发系统资源的机制。

#### 核心组成

| 组件 | 职责 |
|------|------|
| **cgroup core** | 主要负责按层次结构组织进程 |
| **controllers** | 负责沿层次结构分发特定类型的系统资源 |

#### 关键特性

1. **树形结构**: cgroups 形成树状结构，系统中的每个进程属于且仅属于一个 cgroup
2. **线程归属**: 进程的所有线程属于同一个 cgroup
3. **继承机制**: 创建新进程时，子进程诞生时进入父进程所属的 cgroup
4. **进程迁移**: 进程可以迁移到另一个 cgroup，但不影响已存在的后代进程

#### 控制器规则

- 控制器可以按选择性在 cgroup 上启用或禁用
- 所有控制器行为都是层次化的
- 嵌套 cgroup 中启用控制器时，总是进一步限制资源分发
- 靠近根部的限制不能被远离根部的设置覆盖

---

## 2. 基本操作

### 2.1 挂载

与 v1 不同，cgroup v2 只有一个单一层次结构。

```bash
# 挂载 cgroup v2
mount -t cgroup2 none $MOUNT_POINT
```

#### 文件系统特性

- **magic number**: `0x63677270` ("cgrp")
- **自动绑定**: 所有支持 v2 且未绑定到 v1 层次结构的控制器会自动绑定到 v2 层次结构

#### 挂载选项

| 选项 | 说明 |
|------|------|
| `nsdelegate` | 将 cgroup 命名空间视为委托边界 |
| `favordynmods` | 降低动态 cgroup 修改的延迟 |
| `memory_localevents` | 仅在当前 cgroup 填充 memory.events |
| `memory_recursiveprot` | 递归应用内存保护到整个子树 |
| `memory_hugetlb_accounting` | 将 HugeTLB 内存计入内存控制器 |
| `pids_localevents` | 恢复 v1 风格的 pids.events:max 行为 |

### 2.2 组织进程和线程

#### 进程操作

```bash
# 创建子 cgroup
mkdir $CGROUP_NAME

# 查看进程列表
cat cgroup.procs

# 迁移进程 (写入 PID)
echo $PID > cgroup.procs

# 删除空 cgroup
rmdir $CGROUP_NAME
```

**关键点**:
- 一次写入只能迁移一个进程
- 写入进程的任何线程 PID 会迁移整个进程的所有线程

#### 查看进程所属

```bash
cat /proc/$PID/cgroup
# 输出示例: 0::/test-cgroup/test-cgroup-nested
```

#### 线程模式

cgroup v2 支持线程粒度控制，适用于需要在线程间进行层次化资源分发的场景。

**线程模式类型**:

| 类型 | 说明 |
|------|------|
| **domain controllers** | 不支持线程模式的控制器 |
| **threaded controllers** | 支持线程模式的控制器 (cpu, cpuset, perf_event, pids) |

**启用线程模式**:

```bash
echo threaded > cgroup.type
```

**线程模式特性**:
- 线程可以分散在子树中的不同 cgroup
- 不受"无内部进程"约束限制
- 非叶节点 cgroup 可以启用线程控制器

### 2.3 控制器管理

#### 查看可用控制器

```bash
cat cgroup.controllers
# 输出示例: cpu io memory
```

#### 启用/禁用控制器

```bash
# 启用 cpu 和 memory，禁用 io
echo "+cpu +memory -io" > cgroup.subtree_control
```

#### 顶级约束

1. **自上而下的约束**: 子 cgroup 只能分发从父 cgroup 分配给它的资源
2. **无内部进程约束**: 只有不含自己进程的非根 cgroups 才能在其 `cgroup.subtree_control` 中启用域控制器

### 2.4 委托

委托允许将 cgroup 的管理权移交给非特权用户。

#### 委托方式

1. **目录访问委托**: 授予对目录及其特定文件的写访问权限
2. **命名空间委托**: 设置 `nsdelegate` 挂载选项时自动委托

#### 委托文件列表

- `cgroup.procs`
- `cgroup.threads`
- `cgroup.subtree_control`

#### 委托约束

被委托的子层次结构是受约束的——被委托者不能将进程移入或移出子层次结构。

---

## 3. 资源分配模型

cgroup 控制器实现多种资源分配方案，取决于资源类型和预期用例。

### 3.1 权重 (Weights)

**原理**: 通过累加所有活动子项的权重，给予每个子项与其权重占总和比例相匹配的分数。

**特性**:
- 工作保守型 (work-conserving): 只有当前能使用资源的子项参与分配
- 适用于无状态资源

**参数范围**: [1, 10000]，默认值 100

**示例**: `cpu.weight`

```
权重分配示例:
- 子组 A: 权重 100
- 子组 B: 权重 100
- 子组 C: 权重 200
→ A 获得 25%, B 获得 25%, C 获得 50%
```

### 3.2 限制 (Limits)

**原理**: 子项只能消耗不超过配置数量的资源。

**特性**:
- 可以过度分配 (子项限制总和可以超过父项可用资源)
- 范围: [0, max]，默认 "max" (无操作)

**示例**: `io.max`

### 3.3 保护 (Protections)

**原理**: 只要所有祖先的使用量都在其保护级别之下，cgroup 就会受到保护，免受回收影响。

**类型**:
- **硬保证**: 如 `memory.min`
- **最佳努力软边界**: 如 `memory.low`

**特性**:
- 可以过度分配
- 范围: [0, max]，默认 0 (无操作)

### 3.4 分配 (Allocations)

**原理**: cgroup 独占分配一定数量的有限资源。

**特性**:
- 不能过度分配 (子项分配总和不能超过父项可用资源)
- 范围: [0, max]，默认 0 (无资源)
- 某些配置组合无效，进程迁移可能被拒绝

**示例**: `cpu.rt.max`

---

## 4. 核心接口文件

所有 cgroup 核心文件都以 `cgroup.` 为前缀。

### 4.1 cgroup.type

读写单值文件，指示 cgroup 的当前类型。

| 值 | 说明 |
|-----|------|
| `domain` | 普通有效域 cgroup |
| `domain threaded` | 作为线程子树根的线程域 cgroup |
| `domain invalid` | 处于无效状态的 cgroup |
| `threaded` | 线程子树的成员 cgroup |

### 4.2 cgroup.procs

读写换行分隔值文件，列出属于 cgroup 的所有进程 PID。

**写入条件**:
1. 必须对目标 `cgroup.procs` 有写访问权限
2. 必须对源和目标 cgroup 的共同祖先的 `cgroup.procs` 有写访问权限

### 4.3 cgroup.threads

与 `cgroup.procs` 类似，但操作的是线程 ID (TID)。

**约束**: 只能在同一资源域内移动线程。

### 4.4 cgroup.controllers

只读空格分隔值文件，显示 cgroup 可用的所有控制器。

### 4.5 cgroup.subtree_control

读写空格分隔值文件，控制从 cgroup 到其子项的资源分发。

```
# 启用控制器
echo "+cpu +memory" > cgroup.subtree_control

# 禁用控制器
echo "-io" > cgroup.subtree_control
```

### 4.6 cgroup.events

只读平面键值文件，包含以下条目:

| 条目 | 说明 |
|------|------|
| `populated` | cgroup 或其后代是否包含活动进程 (0/1) |
| `frozen` | cgroup 是否被冻结 (0/1) |

### 4.7 冻结与杀戮

| 文件 | 类型 | 说明 |
|------|------|------|
| `cgroup.freeze` | 读写 | 写入 "1" 冻结 cgroup 及所有后代 |
| `cgroup.kill` | 只写 | 写入 "1" 杀死 cgroup 及所有后代中的所有进程 |

### 4.8 统计信息

| 文件 | 说明 |
|------|------|
| `cgroup.stat` | 可见后代 cgroup 总数、垂死后代计数等 |
| `cgroup.max.descendants` | 最大允许后代 cgroup 数量 |
| `cgroup.max.depth` | 最大允许后代深度 |

---

## 5. 控制器详解

### 5.1 CPU 控制器

调节 CPU 周期的分发，实现权重和绝对带宽限制模型。

#### 接口文件

| 文件 | 说明 | 默认值 |
|------|------|--------|
| `cpu.stat` | 统计信息 | - |
| `cpu.weight` | 权重 [1, 10000] | 100 |
| `cpu.weight.nice` | nice 值 [-20, 19] | 0 |
| `cpu.max` | 带宽限制 "$MAX $PERIOD" | "max 100000" |
| `cpu.max.burst` | 突发值 [0, $MAX] | 0 |
| `cpu.pressure` | CPU 压力停顿信息 | - |
| `cpu.uclamp.min` | 最小利用率钳制 | 0 |
| `cpu.uclamp.max` | 最大利用率钳制 | max |
| `cpu.idle` | SCHED_IDLE 策效 | 0 |

#### 重要说明

```
警告: cgroup v2 的 cpu 控制器尚不支持实时进程的带宽控制。
启用 CONFIG_RT_GROUP_SCHED 时，只有当所有 RT 进程都在根 cgroup 中时，
才能启用 cpu 控制器。
```

### 5.2 Memory 控制器

调节内存的分发，实现限制和保护模型。

#### 主要接口文件

| 文件 | 说明 | 默认值 |
|------|------|--------|
| `memory.current` | 当前内存使用量 | - |
| `memory.min` | 硬内存保护 | 0 |
| `memory.low` | 最佳努力内存保护 | 0 |
| `memory.high` | 内存使用节流限制 | max |
| `memory.max` | 内存使用硬限制 (触发 OOM) | max |
| `memory.reclaim` | 触发内存回收 (只写) | - |
| `memory.peak` | 峰值内存使用记录 | - |
| `memory.stat` | 详细内存统计 | - |
| `memory.events` | 内存事件计数器 | - |
| `memory.swap.current` | 当前 swap 使用量 | - |
| `memory.swap.max` | swap 硬限制 | max |
| `memory.zswap.current` | zswap 压缩后端消耗 | - |
| `memory.pressure` | 内存压力信息 | - |

#### 内存统计类型

```
memory.stat 包含的关键条目:
- anon: 匿名映射内存 (brk, mmap)
- file: 文件系统数据缓存
- kernel: 内核内存总量
- kernel_stack: 内核栈内存
- pagetables: 页表内存
- shmem: swap 支持的缓存文件系统数据
- slab: 内核数据结构内存
- swapcached: swap 缓存
- inactive_anon/active_anon: 非活动/活动匿名内存
- inactive_file/active_file: 非活动/活动文件内存
```

#### 使用指南

**memory.high** 是控制内存使用的主要机制:
- 超过不会触发 OOM killer，而是节流违规 cgroup
- 管理代理有充分机会监控并采取适当行动

**保护机制**:
- `memory.min`: 硬保护，内存不会被回收
- `memory.low`: 软保护，除非没有其他可回收内存

### 5.3 IO 控制器

调节 IO 资源的分发，实现基于权重和绝对带宽/IOPS 限制。

#### 接口文件

| 文件 | 说明 |
|------|------|
| `io.stat` | IO 统计 (按设备) |
| `io.weight` | 权重 [1, 10000] |
| `io.max` | BPS 和 IOPS 限制 |
| `io.pressure` | IO 压力信息 |
| `io.latency` | IO 延迟目标 |
| `io.cost.qos` | QoS 配置 (仅根) |
| `io.cost.model` | 成本模型配置 (仅根) |

#### io.max 示例

```bash
# 设置读限制 2MB/s，写限制 120 IOPS
echo "8:16 rbps=2097152 wiops=120" > io.max

# 移除写 IOPS 限制
echo "8:16 wiops=max" > io.max
```

#### Writeback 机制

页面缓存通过缓冲写入和共享 mmap 变脏，由 writeback 机制异步写回。

**支持文件系统**: ext2, ext4, btrfs, f2fs, xfs

### 5.4 PID 控制器

限制 cgroup 可以创建的进程数量，用于防止 fork 炸弹等攻击。

#### 接口文件

| 文件 | 说明 | 默认值 |
|------|------|--------|
| `pids.max` | 进程数量硬限制 | max |
| `pids.current` | 当前进程数 | - |
| `pids.peak` | 峰值进程数 | - |
| `pids.events` | 事件计数器 | - |

```
注意: 组织操作不受 cgroup 策略阻止，因此可能出现 pids.current > pids.max。
但通过 fork() 或 clone() 违反策略时会返回 -EAGAIN。
```

### 5.5 Cpuset 控制器

约束任务在指定 CPU 和内存节点上的放置，特别适用于大型 NUMA 系统。

#### 接口文件

| 文件 | 说明 |
|------|------|
| `cpuset.cpus` | 请求使用的 CPU |
| `cpuset.cpus.effective` | 实际授予的 CPU |
| `cpuset.mems` | 请求使用的内存节点 |
| `cpuset.mems.effective` | 实际授予的内存节点 |
| `cpuset.cpus.partition` | 分区状态 |

#### 分区类型

| 值 | 说明 |
|-----|------|
| `member` | 分区的非根成员 |
| `root` | 分区根 |
| `isolated` | 无负载平衡的分区根 |

### 5.6 Device 控制器

管理对设备文件的访问，包括创建新设备文件和访问现有设备文件。

**实现**: 基于 cgroup BPF，无独立接口文件

### 5.7 RDMA 控制器

调节 RDMA 资源的分发和记账。

#### 接口文件

| 文件 | 说明 |
|------|------|
| `rdma.max` | 资源限制 |
| `rdma.current` | 当前使用量 |

### 5.8 HugeTLB 控制器

限制每个控制组的 HugeTLB 使用量。

#### 接口文件

| 文件 | 说明 |
|------|------|
| `hugetlb.<hugepagesize>.current` | 当前使用量 |
| `hugetlb.<hugepagesize>.max` | 硬限制 |
| `hugetlb.<hugepagesize>.events` | 事件计数器 |

### 5.9 Misc 控制器

提供无法抽象为其他 cgroup 资源的标量资源的限制和跟踪机制。

#### 接口文件

| 文件 | 说明 |
|------|------|
| `misc.capacity` | 可用标量资源 (仅根) |
| `misc.current` | 当前使用量 |
| `misc.peak` | 历史最大使用量 |
| `misc.max` | 最大使用限制 |
| `misc.events` | 事件计数器 |

---

## 6. 命名空间

cgroup 命名空间提供虚拟化 `/proc/$PID/cgroup` 文件和 cgroup 挂载的机制。

### 6.1 基础

```bash
# 创建新的 cgroup 命名空间
unshare -c

# 或者使用 clone(2) 与 CLONE_NEWCGROUP 标志
```

### 6.2 效果

**创建命名空间前**:
```
# cat /proc/self/cgroup
0::/batchjobs/container_id1
```

**创建命名空间后**:
```
# cat /proc/self/cgroup
0::/
```

### 6.3 cgroupns root

- cgroupns root 是创建命名空间时进程所在的 cgroup
- 即使命名空间创建者后来移动到不同的 cgroup，cgroupns root 也不会改变

### 6.4 迁移和 setns(2)

允许条件:
(a) 进程对其当前用户命名空间拥有 CAP_SYS_ADMIN
(b) 进程对目标 cgroup 命名空间的 userns 拥有 CAP_SYS_ADMIN

---

## 7. v1 的问题与 v2 的改进

### 7.1 多层次结构问题

#### v1 的问题

- 允许任意数量的层次结构
- 每个层次结构可以托管任意数量的控制器
- 看似灵活，但实际上在实践中没有用处

#### 实际问题

1. 每个控制器只有一个实例，实用型控制器只能在一个层次结构中使用
2. 控制器一旦绑定到层次结构，就无法移动
3. 同一层次结构上的所有控制器必须具有完全相同的层次结构视图
4. 用户空间最终管理多个相似的层次结构

#### v2 的解决方案

- **单一层次结构**: 只有一个层次结构
- **统一视图**: 所有控制器共享同一层次结构
- **控制器合作**: 控制器可以相互协作

### 7.2 线程粒度问题

#### v1 的问题

- 允许进程的线程属于不同的 cgroups
- 对某些控制器没有意义
- 模糊了应用程序接口和系统管理接口之间的界限

#### v2 的解决方案

- **域控制器**: 默认情况下，进程的所有线程属于同一个 cgroup
- **线程控制器**: 支持需要线程级控制的使用场景
- **明确的委托模型**: 避免滥用

### 7.3 内部节点与线程竞争

#### v1 的问题

- 属于父 cgroup 和子 cgroups 的线程竞争资源
- 不同控制器有不同的处理方式
- 行为不一致

#### v2 的解决方案

- **无内部进程约束**: 只有不含自己进程的非根 cgroups 才能启用域控制器
- **统一规则**: 保证进程总是在叶节点上

### 7.4 内存控制器的改进

#### soft limit → memory.low

**v1 soft limit 的问题**:
- 没有层次意义
- 所有配置组都在全局 rbtree 中组织
- 回收过于激进

**v2 memory.low**:
- 自上而下分配的保留
- 支持子树委托
- 回收压力与超额成正比

#### hard limit → memory.high + memory.max

**v1 hard limit 的问题**:
- 严格限制，即使需要调用 OOM killer
- 违反充分利用可用内存的目标

**v2 方案**:
- `memory.high`: 节流分配但从不调用 OOM killer
- `memory.max`: 硬限制，最终防护

---

## 总结

cgroup v2 是对 v1 的重大改进，主要特点包括:

1. **单一层次结构**: 简化系统管理和配置
2. **统一的接口约定**: 控制器间的一致性
3. **明确的委托模型**: 清晰的权限边界
4. **改进的资源控制**: 更精细和灵活的控制选项
5. **线程粒度支持**: 在需要时支持线程级控制
6. **更好的可组合性**: 控制器可以相互协作

这些改进使 cgroup v2 成为一个更适合容器化、资源管理和系统管理的统一平台。
