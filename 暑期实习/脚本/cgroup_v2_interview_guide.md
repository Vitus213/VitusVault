# DragonOS cgroup v2 面试讲义

## 1. 30 秒总述

我在 DragonOS 里推进的是一个 cgroup v2 的 MVP，但这个 MVP 不是只做几个接口，而是把树模型、`cgroup2` 文件系统、`/proc/[pid]/cgroup`、cgroup namespace、`clone3(CLONE_INTO_CGROUP)` 和 `pids` controller 串成了一条完整链路。

核心设计是：用 `CgroupRoot/CgroupNode` 表达整棵资源控制树，把任务归属落到 PCB 的 `task_cgroup` 生命周期里，再通过 `cgroup.procs`、`pids.max`、namespace 视图和 fork 前校验，把“进程从出生到迁移再到退出”的资源归属闭环打通。

这个项目最难的地方不是建树本身，而是把树模型、文件系统接口、权限检查、namespace 视图和 fork/迁移时序做成一致的系统行为。

---

## 2. 3 分钟源码主线

我一般从数据结构开始讲。整个 cgroup v2 的根在 `kernel/src/cgroup/core.rs:149` 的 `CgroupRoot`，每个节点是 `CgroupNode`，里面维护 `parent/children/tasks/subtree_control/pids_max/pids_events` 这些字段，既能表达树关系，也能承载 controller 状态。根节点和全局 accounting 锁在 `kernel/src/cgroup/core.rs:282-296` 初始化。

然后我把任务归属直接放进 PCB 生命周期里，也就是 `ProcessControlBlock` 持有 `task_cgroup`，位置在 `kernel/src/process/mod.rs:1136-1137`。创建新 PCB 时，idle 进程默认挂到 root cgroup，普通进程默认继承父进程的 `task_cgroup`，这一点在 `kernel/src/process/mod.rs:1269-1273`。这样进程从出生起就带着 cgroup 归属，而不是事后补记。

在文件系统层，我实现了 `cgroup2` 文件系统，入口在 `kernel/src/filesystem/cgroup2/mod.rs:115-136`，会把 cgroup2 挂到 `/sys/fs/cgroup`。这个文件系统里的目录 inode 绑定具体 `CgroupNode`，核心文件包括 `cgroup.procs`、`cgroup.controllers`、`cgroup.subtree_control`、`cgroup.events`、`cgroup.type`、`pids.current/max/events`，定义可见于 `kernel/src/filesystem/cgroup2/mod.rs:83-93` 和 `kernel/src/filesystem/cgroup2/mod.rs:542-567`。

真正关键的写路径是 `cgroup.procs`，实现位于 `kernel/src/filesystem/cgroup2/mod.rs:683-759`。写入时先解析 pid，定位源/目标 cgroup，再检查 namespace 可见性和 attach 权限，然后拿线程组 leader，把整组线程收集出来，最后在 `cgroup_accounting_lock` 保护下做迁移并更新每个任务的 `task_cgroup`。这里特别注意不能在 inode 的 inner lock 持有期间做权限检查和迁移，否则会在 `metadata()` 回入同一 inode 时自死锁，这一点源码注释写在 `kernel/src/filesystem/cgroup2/mod.rs:683-685`。

在 controller 侧，我先打通的是 `pids`。`pids.max` 的读写在 `kernel/src/filesystem/cgroup2/mod.rs:780-797`，而真正的配额判断在 `kernel/src/cgroup/core.rs:361-402`：fork 前会检查目标节点及祖先链上的 `pids_max`，迁移时也会检查目标子树是否超额，超限则增加 `pids_events_max` 并返回错误。这保证了 controller 行为不只是“存个值”，而是能约束真实的进程创建和迁移。

namespace 这层我做的是“视图隔离”。`CLONE_NEWCGROUP` 的实现核心在 `kernel/src/process/namespace/cgroup_namespace.rs:101-139`，新 namespace 会把当前进程所在 cgroup 作为视图根，而不是复制一棵真实树。然后 `/proc/[pid]/cgroup` 会用 `cgroup_path_from_view()` 把目标进程的真实节点路径投影成观察者 namespace 下的路径，代码在 `kernel/src/filesystem/procfs/pid/cgroup.rs:31-39` 和 `kernel/src/cgroup/core.rs:316-339`。所以 namespace 改的是“看到什么”，不是“真实在哪”。

最后，`clone3(CLONE_INTO_CGROUP)` 这条链我也接进了 fork 前校验。实现位于 `kernel/src/process/fork.rs:827-941`：先从 fd 解析出目标 cgroup2 目录，再检查文件系统类型、目录类型、namespace 可见性、迁移权限、`pids.max` 余量，以及线程上下文是否合法，然后在真正把子进程加入进程表之前完成 cgroup 归属决策。这保证了“进程一出生就在目标 cgroup 中”，而不是先出生再补迁移。

---

## 3. 讲解目录

### 3.1 整体顺序

建议固定按下面 6 段讲：

1. 先定义这个 MVP 到底解决什么问题
2. 从 `CgroupRoot/CgroupNode` 讲树模型和任务归属
3. 讲 PCB `task_cgroup` 如何进入进程生命周期
4. 讲 `cgroup2` 文件系统如何把树暴露给用户态
5. 讲 `cgroup.procs` / `pids.max` / namespace / `clone3` 如何串成闭环
6. 插入关键分叉：树模型、迁移写路径、namespace 视图、fork 前准入

### 3.2 主调用链

固定按这条主线讲：

`CgroupRoot/CgroupNode`
→ PCB `task_cgroup`
→ `cgroup2_init` 挂载 `/sys/fs/cgroup`
→ 写 `cgroup.procs`
→ `check_attach_permissions` + `cgroup_accounting_lock`
→ `set_task_cgroup_node`
→ `pids.max` / `pids.events`
→ `/proc/[pid]/cgroup` 视图投影
→ `clone3(CLONE_INTO_CGROUP)` fork 前校验

---

## 4. 四个关键分叉

### 4.1 为什么要先建 `CgroupRoot/CgroupNode` 树模型

核心结论：我不是先做文件系统接口，再反推内核状态；而是先用 `CgroupRoot/CgroupNode` 建立稳定的内核真相源，再让文件系统、procfs、namespace 和 fork 都围绕这棵树工作。

源码锚点：
- `kernel/src/cgroup/core.rs:16-26`
- `kernel/src/cgroup/core.rs:149-165`
- `kernel/src/cgroup/core.rs:177-205`

### 4.2 为什么 `task_cgroup` 必须进入 PCB 生命周期

核心结论：如果 cgroup 归属不是 PCB 的一部分，就只能靠外部文件系统写入去“事后修正”，这样 fork、exit、迁移和 namespace 都会出现时序漏洞。把 `task_cgroup` 放进 PCB，才能保证进程从出生开始就在正确的资源控制树里。

源码锚点：
- `kernel/src/process/mod.rs:1136-1137`
- `kernel/src/process/mod.rs:1269-1273`
- `kernel/src/process/mod.rs:2113-2129`
- `kernel/src/process/mod.rs:729-730`

### 4.3 为什么 `cgroup.procs` 写路径要“先锁内取快照、锁外做慢操作”

核心结论：`cgroup.procs` 写入真正难的不是移动 pid，而是不能让权限检查、inode 元数据访问和迁移过程在同一把 inode 锁里相互重入，否则会自死锁。所以这里必须先把 `cgroup` 和 `ty` 快照出来，再在锁外做权限检查、线程组收集和迁移。

源码锚点：
- `kernel/src/filesystem/cgroup2/mod.rs:683-685`
- `kernel/src/filesystem/cgroup2/mod.rs:686-759`
- `kernel/src/filesystem/cgroup2/mod.rs:259-279`

### 4.4 为什么 `CLONE_NEWCGROUP` 和 `CLONE_INTO_CGROUP` 都要做

核心结论：`CLONE_NEWCGROUP` 解决的是“看见哪棵树”的问题，`CLONE_INTO_CGROUP` 解决的是“新进程出生在哪个节点”的问题。前者是视图隔离，后者是归属控制，两者合起来才构成容器场景里完整的 cgroup 语义。

源码锚点：
- `kernel/src/process/namespace/cgroup_namespace.rs:101-139`
- `kernel/src/filesystem/procfs/pid/cgroup.rs:31-39`
- `kernel/src/process/fork.rs:896-941`

---

## 5. 高频追问与参考答案

### Q1. `CgroupRoot/CgroupNode` 这套数据结构到底解决什么问题？

**短答：** 它把整棵 cgroup 树和 controller 状态变成了内核里的真相源。

**展开：** `CgroupNode` 同时维护父子关系、任务集合、`subtree_control`、`pids_max` 和 `pids_events_max`，所以它既能表达树形拓扑，也能承载资源控制状态。`CgroupRoot` 则负责根节点、ID 分配和全局查找。后续文件系统、procfs、namespace、fork 都围绕这棵树工作。

### Q2. 为什么 `task_cgroup` 必须进入 PCB 生命周期？

**短答：** 因为进程的 cgroup 归属必须从出生开始正确，而不是出生后再补迁移。

**展开：** PCB 里直接持有 `task_cgroup`，普通进程创建时默认继承父进程，fork 时也会在进入进程表之前完成 `CLONE_INTO_CGROUP` 校验和归属决策，退出时再从 node 的任务集合中移除。这保证了“进程一生”都和 cgroup 归属绑定，而不是只在文件系统接口层维护一个外部映射。

### Q3. `cgroup.procs` 写入的完整步骤是什么？

**短答：** 解析 pid，定位源/目标节点，检查 namespace 和权限，拿线程组，最后在 accounting 锁下整组迁移。

**展开：** 写 `cgroup.procs` 时先解析输入 pid，拿到源 cgroup 和目标 cgroup；如果开启 `nsdelegate`，还要检查 namespace 根是否能看到源/目标；然后对目标 `cgroup.procs` 和源/目标公共祖先的 `cgroup.procs` 做写权限校验；接着获取线程组 leader，把整个线程组收集出来；最后在 `cgroup_accounting_lock` 下做 `cgroup_migrate_vet_dst_with_src()` 检查，并逐个 `set_task_cgroup_node()` 完成迁移。

### Q4. 为什么 `cgroup.procs` 要迁移整个线程组，而不是单线程？

**短答：** 因为 cgroup v2 的 `cgroup.procs` 语义本来就是线程组级别，不是单 task 级别。

**展开：** 代码里会先找 group leader，再把同组还没退出的线程一起收集出来，然后统一迁移。这样可以避免组内线程落在不同 cgroup 导致的语义混乱，也更符合 Linux 用户态对 `cgroup.procs` 的预期。

### Q5. 为什么要加 `cgroup_accounting_lock`？

**短答：** 因为迁移和 fork 准入都会同时读写子树任务数与配额状态，需要一个全局顺序保证。

**展开：** `pids.max` 的判断不是看单节点任务数，而是看目标节点及祖先链上的 `subtree_task_count()`。如果迁移和 fork 并发执行，没有统一 accounting 锁，很容易在计算用量和提交归属之间出现竞态，导致超配或者误拒绝。

### Q6. `pids.max` 和 `pids.events` 是怎么串起来的？

**短答：** `pids.max` 是约束，`pids.events` 是可观察性。

**展开：** `pids.max` 允许写 `max` 或数值，真正的限制逻辑在 `cgroup_can_fork_in()` 和 `cgroup_migrate_vet_dst_with_src()`，它们会沿祖先链检查可用配额。超限时会增加 `pids_events_max` 并返回错误，这样 controller 行为不仅生效，而且能被用户态观察到。

### Q7. `/proc/[pid]/cgroup` 的 namespace 视图是怎么做的？

**短答：** 不是改真实路径，而是把真实节点路径投影成观察者 namespace 根下的相对视图。

**展开：** 进程真实所在节点还是 `task_cgroup_node()`，但 `/proc/[pid]/cgroup` 输出时会拿当前观察者的 cgroup namespace 根，然后用 `cgroup_path_from_view()` / `cgroup_path_projected_from_view()` 把真实路径投影出来，所以可能看到 `/`、`/child`、`/../sibling` 这类相对视图。

### Q8. `CLONE_NEWCGROUP` 的本质是什么？

**短答：** 它改变的是“视图根”，不是“真实树”。

**展开：** 创建新 cgroup namespace 时，会把当前进程所在 cgroup 设成新 namespace 的 `root_cgroup`。这意味着这个 namespace 看到的 `/sys/fs/cgroup` 和 `/proc/[pid]/cgroup` 都以当前节点为根，但内核里真实的 `CgroupNode` 树并没有复制。

### Q9. `clone3(CLONE_INTO_CGROUP)` 为什么要在 fork 前完成？

**短答：** 因为它要求子进程一出生就在目标 cgroup，而不是先出生再迁移。

**展开：** 实现上会先从 fd 解析出目标 cgroup2 目录，再检查文件系统类型、目录类型、namespace 可见性、attach 权限、`pids.max` 余量和线程语义，全部通过后才把目标节点写进子进程的 `task_cgroup`。这样保证 fork 结果从一开始就落在正确的 cgroup 里。

### Q10. 为什么强调这是 MVP？

**短答：** 因为当前 controller 以 `pids` 为主，但基础设施已经搭完整了。

**展开：** 现在还没有把 cpu、memory 这些 controller 全接进来，所以从功能覆盖看它是 MVP；但从架构看，树模型、文件系统、procfs、namespace、`clone3`、任务生命周期和测试链路都已经贯通，后续加新 controller 不需要重构基本骨架。

---

## 6. 临场短答卡片

### 1. `CgroupRoot/CgroupNode` 解决什么问题？
- **10 秒答法：** 它把 cgroup 树和 controller 状态变成了内核里的真相源。
- **30 秒答法：** `CgroupNode` 同时保存父子关系、任务集合、`subtree_control`、`pids_max` 和事件计数，所以不只是树节点，而是资源控制状态节点。`CgroupRoot` 则负责根节点和全局索引，后续文件系统、procfs、namespace 和 fork 全围绕它工作。
- **收束金句：** 我先建稳定的内核真相源，再让接口层围绕它展开。

### 2. 为什么 `task_cgroup` 要放进 PCB？
- **10 秒答法：** 因为进程的 cgroup 归属必须从出生开始正确。
- **30 秒答法：** PCB 直接持有 `task_cgroup`，普通进程继承父进程，`clone3(CLONE_INTO_CGROUP)` 会在 fork 前重定向目标节点，退出时又会从节点任务集合里移除。这样 cgroup 归属贯穿整个进程生命周期，而不是靠外部表做补记。
- **收束金句：** 资源归属应该是进程生命周期的一部分，而不是事后附着的信息。

### 3. `cgroup.procs` 写入怎么走？
- **10 秒答法：** 解析 pid，检查源/目标和权限，拿线程组，在 accounting 锁下整组迁移。
- **30 秒答法：** 写入时先把 pid 解析成 task，拿到源 cgroup 和目标 cgroup；然后检查 namespace 可见性和 attach 权限；接着拿 group leader，把整组线程收集出来；最后在 `cgroup_accounting_lock` 下做准入检查并逐个更新 `task_cgroup`。
- **收束金句：** `cgroup.procs` 不是写一个 pid，而是在改一整组线程的资源归属。

### 4. 为什么 `cgroup.procs` 要锁外做慢操作？
- **10 秒答法：** 因为权限检查和迁移如果还拿着 inode 锁，会自死锁。
- **30 秒答法：** 写路径先从 inode 内部取出 `cgroup` 和文件类型快照，然后在锁外做权限校验、线程组收集和迁移。否则 `metadata()` 或权限检查回入同一 inode 时可能重拿这把锁，造成 self-deadlock。
- **收束金句：** 文件接口层的锁只保护 inode 状态，不应该包住跨子系统的慢路径。

### 5. 为什么需要 `cgroup_accounting_lock`？
- **10 秒答法：** 因为迁移和 fork 会同时读写配额与任务数，需要统一顺序。
- **30 秒答法：** `pids.max` 的判断要看整个子树和祖先链的任务数，迁移和 fork 又都可能并发改变这些计数。统一的 accounting 锁保证“检查配额”和“提交归属”之间没有竞态。
- **收束金句：** 配额检查只有和归属变更放进同一个原子时序里才可信。

### 6. `pids.max` 和 `pids.events` 怎么联动？
- **10 秒答法：** `pids.max` 负责限制，`pids.events` 负责把限制行为暴露给用户态。
- **30 秒答法：** fork 和迁移都会沿祖先链检查 `pids_max`；一旦超限，就增加 `pids_events_max` 并返回错误。这样 controller 既能拦住超额行为，又能在 `pids.events` 里留下可观察结果。
- **收束金句：** 一个好的 controller 不只是能拒绝，还要能解释为什么被拒绝。

### 7. `CLONE_NEWCGROUP` 和 `CLONE_INTO_CGROUP` 分别解决什么问题？
- **10 秒答法：** 前者改视图，后者改归属。
- **30 秒答法：** `CLONE_NEWCGROUP` 会把当前 cgroup 设成新 namespace 的视图根，所以影响的是 `/proc/[pid]/cgroup` 和 `/sys/fs/cgroup` 的展示；`CLONE_INTO_CGROUP` 则是在 fork 前决定新进程应该落在哪个目标 cgroup 中，影响的是出生归属。
- **收束金句：** 一个解决“你看到哪里”，一个解决“你出生在哪里”。

### 8. 为什么强调这是 MVP？
- **10 秒答法：** 因为 controller 目前以 `pids` 为主，但整条基础链路已经打通了。
- **30 秒答法：** 当前还没有把 cpu、memory 等 controller 全接上，所以功能上是 MVP；但树模型、文件系统、procfs、namespace、fork 前准入和测试都已经跑通，后续新增 controller 时可以直接沿着现有骨架扩展。
- **收束金句：** MVP 说的是 controller 覆盖面，不是系统设计深度。

---

## 7. 高频金句

1. 我先建稳定的内核真相源，再让接口层围绕它展开。
2. 资源归属应该是进程生命周期的一部分，而不是事后附着的信息。
3. `cgroup.procs` 不是写一个 pid，而是在改一整组线程的资源归属。
4. 文件接口层的锁只保护 inode 状态，不应该包住跨子系统的慢路径。
5. 配额检查只有和归属变更放进同一个原子时序里才可信。
6. 一个好的 controller 不只是能拒绝，还要能解释为什么被拒绝。
7. `CLONE_NEWCGROUP` 解决视图，`CLONE_INTO_CGROUP` 解决出生归属。
8. MVP 说的是 controller 覆盖面，不是系统设计深度。

---

## 8. 最后 1 分钟收束陈词

如果让我总结这个项目，我觉得它体现的不是“我做了一个资源限制接口”，而是我把 cgroup v2 里最关键的系统骨架搭起来了：树模型、任务生命周期、文件系统接口、namespace 视图、fork 前准入和用户态测试都打通了。

它之所以值得写进简历，不是因为现在已经支持了很多 controller，而是因为我把 `pids` 这个最小 controller 做成了一条完整闭环：进程从出生开始有 `task_cgroup` 归属，用户态能通过 `cgroup.procs` 和 `pids.max` 改变和观察行为，namespace 能提供隔离视图，`clone3(CLONE_INTO_CGROUP)` 能保证新进程从第一刻就在目标 cgroup 中。

所以这个项目最能说明我的，是我处理系统级树模型、权限边界、时序一致性和接口闭环的能力。

---

## 9. 测试锚点

- `user/apps/c_unitest/test_cgroup_mvp_basic.c`
  - 验证挂载、创建子 cgroup、写 `cgroup.procs`、`/proc/self/cgroup` 视图、`subtree_control`、多挂载点一致性。
- `user/apps/c_unitest/test_cgroup_mvp_ns_clone.c`
  - 验证 `unshare(CLONE_NEWCGROUP)`、`setns()`、`clone3` bad-fd/成功路径、sibling namespace 视图、`CLONE_INTO_CGROUP` 权限失败路径。
