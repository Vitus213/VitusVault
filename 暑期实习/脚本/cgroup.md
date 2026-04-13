>  整体思路：原来怎么做 → 优缺点 →  我做了什么 → 我做过哪些优化 → 如果让我重写会怎么改 → 做完之后怎么评价它值不值

## cgroup 为什么存在

- DragonOS 是一个 从零开始的操作系统内核，我们要在上面跑容器运行时（runcell），需要挂载/sys/fs/cgroup，同时我们要保证在多线程环境下，进行资源的控制和限制使用 。
- 没有进程分组的话，无法对一组进程施加统一策略

## Linux 原来是怎么做的

linux核心设计有三点：

1. **层级树（hierarchy）**
   - 通过树的结构实现资源治理
     - 父节点可以看和限制整棵子树；
     - 子节点默认继承父节点约束；
     - 用树表达“service → subservice → worker”这种现实层级。

2. **统一层级（v2）**
   - v1 时代，各个 controller 可以挂在不同的树上，导致“CPU 树是这么组织，内存树又是另一个结构”，理解成本巨大；
   - v2 把 controller 收敛到一棵统一的树上，工作负载只需要在一个层级中定位。

3. **控制器挂在树上，而不是把逻辑写死在任务上**
   - 树只表达“归属关系”；
   - controller 再根据树结构和本身规则去控制 CPU/memory/io/pids；
   - 好处是：资源治理的“谁归谁”与“具体怎么限”解耦，可以扩展 controller。

### 优点

- 把操作对象从“单个 pid”提升到“workload 单元”；
- 按父子树表达继承、聚合和预算传播，天然贴合 systemd / 容器 / 批处理场景；
- 所有的congroller都挂载在树上，方便控制 CPU、内存、I/O、pids 和可观测性；
- 经过长期生产验证，系统族（systemd、K8s、容器运行时）都围绕它构建。

### 缺点 

- 单一层级树，无法表现不同资源维度的差异化竞争关系 

- 非叶子节点不能包含进程,为了管理优雅而打破了灵活性需要增加强制的目录分层增加内核路径查找的开销
- **历史包袱重**：v1多树、多 controller 组合和兼容行为，需要长期维护；
- 全局mutex大规模场景下操作串行化，一次性锁一整颗树。
- cpu尾延迟 
- 内存page cache 记账不合理 
- 网络带宽控制不在框架中 ，使用ebpf外部机制控制
- controller 启用非原子，大规模出现不一致状态 

---

## DragonOS的设计思路 

讲解思路 ：

`CgroupRoot/CgroupNode`
→ PCB `task_cgroup`
→ `cgroup2_init` 挂载 `/sys/fs/cgroup`
→ 写 `cgroup.procs`
→ `check_attach_permissions` + `cgroup_accounting_lock`
→ `set_task_cgroup_node`
→ `pids.max` / `pids.events`
→ `/proc/[pid]/cgroup` 视图投影
→ `clone3(CLONE_INTO_CGROUP)` fork 前校验

 一、核心架构：单一层级树 + cgroupfs 接口

  - CgroupRoot 作为全局唯一层级树的根，通过 CGROUP_ROOT 懒静态管理，维护 next_id 原子计数器和 all_nodes
    全局节点注册表（SpinLock 保护）。
  - CgroupNode 是树的基本单元，持有 parent（弱引用防循环）、children（RwLock 保护的子节点 Map）、tasks（RwLock保护的进程 PID 集合）、subtree_control（RwLock 保护的已启用 controller 列表）。
  - Cgroup2Fs 以 cgroup2 文件系统挂载到 /sys/fs/cgroup，目录结构直接映射 cgroup 树，核心接口文件包括
    cgroup.procs（进程迁移）、cgroup.controllers（可用 controller）、cgroup.subtree_control（子树 controller
    启用）、cgroup.events、cgroup.type。
  - 进程通过 TaskCgroupRef（Arc<CgroupNode> 的轻量包装）绑定到 cgroup，每个 PCB 持有一个 task_cgroup 字段，fork
    时子进程自动继承。

  二、Controller 模型与当前实现状态

  - Controller 通过 AVAILABLE_CONTROLLERS 静态数组注册，目前仅实现了 pids
    controller（pids.max、pids.current、pids.events），无 cpu/memory/io 等资源 controller，也没有 css（Cgroup
    Subsystem State）抽象层——controller 逻辑直接写在 CgroupNode 中。
  - 锁模型采用细粒度分散锁而非 Linux 的全局 cgroup_mutex：每个 CgroupNode 的 children、tasks、subtree_control
    各自有独立 RwLock，全局 all_nodes 用 SpinLock，跨 cgroup 操作用 CGROUP_ACCOUNTING_LOCK。
  - 支持 cgroup namespace（CLONE_NEWCGROUP），命名空间内路径解析隔离，为容器场景提供基础。
  - 尚未实现：叶子节点进程限制（v2 规则）、controller 的 css alloc/online/offline 生命周期、rstat
    递归统计、delegation 委派机制。

---

## 实现Cgroup过程中的难点 

- **难点在迁移、退出、namespace 和多视图同步上**；

1. 任务迁移时，树结构、PCB、`/proc` 视图、事件统计都要一致更新；
2. namespace 不复制一棵树，只是改变视图根，路径投影要保持语义；
3. 多挂载点下，要保证视图一致，而不是出现“有的路径看见，有的路径看不见”的鬼状态。

---

## DragonOS目前的优化

目前的优势在与结构更紧凑，与cgroup v1脱轨，更符合当下容器编排环境下的容器治理问题

- 相较于 linux里对一整颗树的cgroup的大锁，我拆成了非常多颗粒度的小锁，对每个children，tasks，都用上读写锁
- 不许要兼容就的v1历史报复
- 减少强制创建中间冗余层，如果未启用subtree_control时可以放进程

- **统一真相源**：所有接口围绕 `CgroupRoot/CgroupNode + task_cgroup`，避免多份状态；
- **记账路径**：用 `cgroup_accounting_lock` 先兜住 `pids.max` 的正确性；
- **视图投影**：`/proc/[pid]/cgroup` 用投影函数计算相对路径，而不是简单截断；

---

## 未来改进方向

- 实现css抽象层（Cgroup subsystem state）把controller做成一个trait，不要直接把状态存在cgroup node 中，通过 特征类型回调，把资源治理从树结构中解耦
- cpu 引入 burst 机制
- i/o重视writeback，比如对pagecache的划分，不仅仅是吞吐

- 内存：结合 PSI，让 reclaim 更平滑。

## 实现过程中解决的困难 

1. 为什么要accounting lock

保证检查pids配额的时候以及执行迁移之间不会有其他迁移操作插入

2. cgroup.procs` 写路径要“先锁内取快照、锁外做慢操作”

`cgroup.procs` 写入真正难的不是移动 pid，而是不能让权限检查、inode 元数据访问和迁移过程在同一把 inode 锁里相互重入，否则会自死锁。所以这里必须先把 `cgroup` 和 `ty` 快照出来，再在锁外做权限检查、线程组收集和迁移。

3. clone3（CLONE_INTO_CGROUP) 

解决 clone 出来的进程可能在旧的cgroup中有pids.max导致fork失败，所以我直接在一个新的cgroup中创建 



