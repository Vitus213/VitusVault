# DragonOS Loop 子系统面试讲义

## 1. 30 秒总述

我在 DragonOS 里实现了完整的 Loop 设备子系统。它的目标是把普通文件封装成块设备，让用户态可以像操作磁盘一样去 mount、读写镜像和做系统测试。

架构上我把它拆成了 `/dev/loop-control`、`LoopManager` 和 `/dev/loopX` 三层：控制面负责生命周期管理，管理器统一做 minor 分配和删除编排，数据面负责真正的块 I/O。

这个项目最核心的难点是并发删除，所以我设计了五态状态机，并配合 `IoGuard + active_io_count` 保证删除时既能拒绝新 I/O，又能等待旧 I/O 收敛，同时失败后还能回滚重试。

---

## 2. 3 分钟源码主线

我一般从初始化开始讲。初始化时会先创建 `LoopManager`，再注册控制设备 `/dev/loop-control`，最后预创建一批 loop 设备，所以系统天然分成控制面、管理层和数据面三层。这个入口在 `kernel/src/driver/block/loop_device/mod.rs:39`。

用户态如果要创建或删除 loop 设备，不是直接操作 `/dev/loopX`，而是先对 `/dev/loop-control` 发 `LOOP_CTL_ADD/REMOVE/GET_FREE` 这类 ioctl。控制入口在 `kernel/src/driver/block/loop_device/loop_control.rs:167`，这些请求会统一转交给 `LoopManager`。

`LoopManager` 是整个控制面的核心，它维护设备表和 minor 分配器，负责设备复用、创建设备、注册到块设备层以及删除流程编排。比如 `loop_add` 最终会调用 `create_and_register_device_locked`，把 `LoopDevice` 接到 `block_dev_manager` 上，让 `/dev/loopX` 真正变成系统里的块设备，这部分在 `kernel/src/driver/block/loop_device/manager.rs:99` 和 `kernel/src/driver/block/loop_device/manager.rs:171`。

不过设备刚创建出来时只是 `Unbound`，也就是设备对象已经存在，但还没有绑定 backing file。只有用户态再通过 `LOOP_SET_FD` 绑定一个普通文件 inode，它才会进入 `Bound` 状态，开始承载真实 I/O。绑定逻辑在 `kernel/src/driver/block/loop_device/loop_device.rs:335`。

真正的数据路径在 `read_at_sync/write_at_sync`，也就是把块设备收到的 LBA 请求，翻译成 backing file 上的偏移读写，并结合 `offset/size_limit/file_size` 做边界控制。这部分在 `kernel/src/driver/block/loop_device/loop_device.rs:1232` 和 `kernel/src/driver/block/loop_device/loop_device.rs:1277`。所以 loop 本质上是一个“块设备语义到文件 inode 读写”的适配层。

我觉得这个项目最难的地方其实不是创建和读写，而是删除。因为删设备时可能还有线程在做 I/O，所以我设计了五态状态机：`Unbound / Bound / Rundown / Draining / Deleting`。删除时先进入 `Rundown` 拒绝新 I/O，再进入 `Draining` 等已有 I/O 排空，最后才执行真正的 unregister 和资源回收。

为了让这个过程可靠，我在 I/O 路径里用了 `IoGuard + active_io_count`：进入 I/O 时原子加计数，退出时 Drop 自动减计数。这样删除线程只需要等计数归零，不需要侵入具体读写逻辑。对应实现可以看 `kernel/src/driver/block/loop_device/loop_device.rs:78`、`kernel/src/driver/block/loop_device/loop_device.rs:736` 和 `kernel/src/driver/block/loop_device/loop_device.rs:810`。

此外我还专门处理了删除失败回滚，比如 I/O 排空超时会 `Draining -> Rundown`，block 设备注销失败会 `Deleting -> Rundown`，这样设备不会卡死成僵尸，后续还能重试删除。这个逻辑分别在 `kernel/src/driver/block/loop_device/loop_device.rs:863` 和 `kernel/src/driver/block/loop_device/manager.rs:255`。

最后，在 Linux ioctl 兼容性上，我实现了 `LOOP_SET/GET_STATUS64`，并采用“锁内取快照、锁外计算、锁内一次性提交”的方式更新 `offset/size_limit/file_size/flags`，避免 I/O 看到半更新状态。这部分在 `kernel/src/driver/block/loop_device/loop_device.rs:472`。

---

## 3. 讲解目录

### 3.1 整体顺序

建议固定按下面 6 段讲：

1. 先用一句话定义模块在干什么
2. 从入口讲架构：为什么是 `/dev/loop-control + /dev/loopX`
3. 走创建链路：用户态如何拿到一个 loop 设备
4. 走工作链路：`/dev/loopX` 怎么把 I/O 转发到 backing file
5. 走删除链路：为什么删除是整个设计最难的地方
6. 插入关键分叉：控制/数据分离、状态机 + `IoGuard`、`LOOP_SET/GET_STATUS64` 快照提交

### 3.2 主调用链

固定按这条主线讲：

`loop_init`
→ `/dev/loop-control` ioctl
→ `LoopManager::loop_add`
→ 注册 `/dev/loopX`
→ `LOOP_SET_FD` / `bind_file`
→ `read_at_sync` / `write_at_sync`
→ `LOOP_CTL_REMOVE` / `loop_remove`

---

## 4. 三个关键分叉

### 4.1 为什么必须拆成 `/dev/loop-control + /dev/loopX`

核心结论：我不是做了一个单体 loop 设备，而是把它拆成控制面和数据面：`/dev/loop-control` 专门做生命周期管理，`/dev/loopX` 专门做块 I/O。这样控制逻辑不会污染数据路径，数据路径也不需要关心 minor 分配和删除编排。

源码锚点：
- `kernel/src/driver/block/loop_device/mod.rs:39-48`
- `kernel/src/driver/block/loop_device/loop_control.rs:167-204`

### 4.2 为什么必须要 `LoopState + IoGuard + active_io_count`

核心结论：loop 最难的不是创建和读写，而是删除。因为删除时可能还有线程在做 I/O，所以我把问题拆成两半：状态机负责挡住新 I/O，`active_io_count + IoGuard` 负责等待旧 I/O 收敛。

源码锚点：
- `kernel/src/driver/block/loop_device/constants.rs:170-183`
- `kernel/src/driver/block/loop_device/loop_device.rs:78-94`
- `kernel/src/driver/block/loop_device/loop_device.rs:736-747`
- `kernel/src/driver/block/loop_device/loop_device.rs:810-891`
- `kernel/src/driver/block/loop_device/manager.rs:220-281`

### 4.3 为什么 `LOOP_SET/GET_STATUS64` 必须快照式提交

核心结论：`set_status64` 看起来只是改 `offset`、`size_limit`、`flags`，但它实际上会影响后续 I/O 的边界检查。如果更新不是原子的，I/O 线程就可能看到半更新状态，造成越界风险。

源码锚点：
- `kernel/src/driver/block/loop_device/constants.rs:122-168`
- `kernel/src/driver/block/loop_device/loop_device.rs:472-554`
- `kernel/src/driver/block/loop_device/loop_device.rs:567-595`
- `kernel/src/driver/block/loop_device/loop_device.rs:1249-1269`
- `kernel/src/driver/block/loop_device/loop_device.rs:1294-1317`

---

## 5. 高频追问与参考答案

### Q1. 为什么要分 `/dev/loop-control` 和 `/dev/loopX`，不能做成一个设备吗？

**短答：** 不能。因为控制语义和数据语义是两类完全不同的责任。

**展开：** `/dev/loop-control` 负责设备生命周期管理，比如分配 minor、查找空闲设备、删除设备；`/dev/loopX` 负责块 I/O，也就是把读写请求转发到 backing file。拆开之后，控制面只和 `LoopManager` 打交道，数据面只管当前设备自己的映射和读写，边界更清晰。同时这也与 Linux 的 loop 模型保持一致。

### Q2. `LoopManager` 为什么不能省掉？

**短答：** 因为它是控制面的真相源，统一管理 minor、设备表、复用策略和删除流程。

**展开：** `LoopManager` 同时维护 `devices` 数组和 `id_alloc`，负责分配/回收 minor、判断设备是否可复用、创建设备并注册到块设备层，还负责删除编排。如果没有它，这些逻辑就会散落在 ioctl 入口和设备对象里，后续很难保证一致性。

### Q3. 为什么删除要设计成 `Rundown -> Draining -> Deleting`，直接一个 `Deleting` 不行吗？

**短答：** 不行，因为“拒绝新 I/O”和“等待旧 I/O 结束”是两个不同问题。

**展开：** `Rundown` 的作用是立刻拒绝新 I/O，`Draining` 的作用是等待已有 I/O 自然收尾，`Deleting` 才是真正执行注销和资源回收。这样删除过程既能快速响应删除请求，又不会在还有活跃 I/O 时直接把设备摘掉。

### Q4. 为什么 `IoGuard` 比直接手动 `fetch_add/fetch_sub` 更好？

**短答：** 因为它把 I/O 计数的正确性从“人工纪律”变成了“语言机制”。

**展开：** 如果手动在每个读写路径里做加减计数，最大风险是错误路径漏减。`IoGuard` 在 I/O 入口构造，在 Drop 时自动 `io_end()`，无论正常还是异常返回，计数都会收敛。这样删除线程只需要读 `active_io_count`，不需要侵入每条 I/O 逻辑。

### Q5. 删除失败了为什么要回滚状态？

**短答：** 因为不回滚的话，设备可能卡在半删除状态，后面既不能用也不能再删。

**展开：** 删除流程跨越 I/O 排空、清 backing file、block 设备注销等多个步骤。如果中间失败而状态已经推进到 `Draining` 或 `Deleting`，设备很容易变成 zombie。所以我把 `Draining -> Rundown`、`Deleting -> Rundown` 也设计成合法状态转换，让后续可以重试删除。

### Q6. `LOOP_SET_STATUS64` 为什么不能直接在锁里把字段全改了？

**短答：** 因为计算新的 `file_size` 需要访问 inode metadata，这可能是慢操作，不能在 spinlock 里做。

**展开：** `set_status64` 不只是改几个字段，还要基于 backing inode 重新计算 effective size。如果把这件事全放在自旋锁里做，会有阻塞风险，也会拉长锁持有时间。所以采用“锁内取快照、锁外计算、锁内一次性提交”的方式，兼顾性能和正确性。

### Q7. 为什么不能先改 `offset`，再改 `file_size`？

**短答：** 因为这会产生半更新窗口，I/O 线程可能看到不一致状态。

**展开：** 读写路径在做边界检查时，会一起读取 `offset` 和 `file_size` 来计算 `limit_end`。如果分两步更新，中间窗口里 I/O 线程可能看到“新 offset + 旧 file_size”，这样边界判断就不可信了，严重时会带来越界读写风险。

### Q8. 你怎么证明这套设计真的可验证，而不是你自己觉得对？

**短答：** 我用用户态 `c_unitest` 去验证 ABI、I/O 路径和并发删除行为。

**展开：** `test_loop.c` 覆盖了基本读写、只读模式、`LOOP_CHANGE_FD`、`LOOP_SET_CAPACITY` 和并发 I/O 删除。特别是并发删除测试，不只是看能不能删掉，还验证删除过程中用户态看到的错误码和收敛行为是不是符合预期。

---

## 6. 临场短答卡片

### 1. 为什么拆成 `/dev/loop-control + /dev/loopX`？
- **10 秒答法：** 因为控制语义和数据语义不同，前者管生命周期，后者管块 I/O，拆开后边界更清晰。
- **30 秒答法：** `/dev/loop-control` 只负责 `LOOP_CTL_ADD/REMOVE/GET_FREE` 这类管理操作，`/dev/loopX` 只负责把块请求转发到 backing file。这样创建、删除、minor 分配这些控制逻辑不会污染数据路径，数据路径也不用关心设备表状态。同时这也和 Linux 的 loop 模型一致。
- **收束金句：** 这不是简单兼容 Linux，而是把“管理平面”和“数据平面”彻底解耦。

### 2. `LoopManager` 为什么不能省？
- **10 秒答法：** 因为它是控制面的真相源，统一管理 minor、设备表、复用策略和删除流程。
- **30 秒答法：** `LoopManager` 不是一个普通 helper，它同时维护 `devices` 数组和 `id_alloc`，负责分配/回收 minor、判断设备能否复用、创建设备并注册到块设备层，还负责删除编排。如果没有它，这些逻辑会散在 ioctl 层和设备对象里，很难保证一致性。
- **收束金句：** `LoopManager` 的价值在于把“设备生命周期”集中到一个地方管理，而不是到处散着。

### 3. 为什么删除要分 `Rundown / Draining / Deleting`？
- **10 秒答法：** 因为拒绝新 I/O 和等待旧 I/O 结束是两个不同阶段，必须拆开。
- **30 秒答法：** `Rundown` 的作用是立刻拒绝新 I/O，`Draining` 的作用是等待已有 I/O 自然收尾，`Deleting` 才是真正执行注销和回收。这样删除就不是一把梭，而是一个可控流程，既能快速响应删除请求，也不会在有活跃 I/O 时直接把设备摘掉。
- **收束金句：** 删除安全的本质不是“删掉”，而是“在正确的时机删掉”。

### 4. 为什么要 `IoGuard`？
- **10 秒答法：** 因为它能保证 I/O 计数在所有返回路径上自动收敛，不会漏减。
- **30 秒答法：** 进入 I/O 时构造 `IoGuard`，内部调用 `io_start()` 增加 `active_io_count`；函数返回时不管是正常路径还是错误路径，`Drop` 都会自动调用 `io_end()`。这样删除线程只需要观察计数是否归零，不需要侵入每条 I/O 分支。
- **收束金句：** `IoGuard` 把计数正确性从“人工纪律”变成了“RAII 保证”。

### 5. 删除失败为什么要回滚状态？
- **10 秒答法：** 因为不回滚的话，设备可能卡在半删除状态，后面既不能用也不能再删。
- **30 秒答法：** 删除流程会跨多个步骤，比如 I/O 排空、清 backing file、block 设备注销。如果中间失败而状态已经推进到 `Draining` 或 `Deleting`，设备很容易变成 zombie。所以我把 `Draining -> Rundown`、`Deleting -> Rundown` 也设计成合法状态转换，让后续可以重试删除。
- **收束金句：** 真正稳的删除流程，不是一次成功，而是失败以后还能恢复到可重试状态。

### 6. `LOOP_SET_STATUS64` 为什么不能直接在锁里全做完？
- **10 秒答法：** 因为要读 inode metadata，这可能是慢操作，不能放在 spinlock 里。
- **30 秒答法：** `set_status64` 不只是改几个字段，还要基于 backing inode 重新计算 effective size。这个过程可能访问 metadata，存在阻塞风险，所以不能在自旋锁里做。于是我采用“锁内取快照、锁外计算、锁内提交”的方式，兼顾性能和正确性。
- **收束金句：** 自旋锁只保护短临界区，不应该包住可能阻塞的计算路径。

### 7. 为什么不能先更新 `offset`，再更新 `file_size`？
- **10 秒答法：** 因为这会产生半更新窗口，I/O 线程可能看到不一致快照。
- **30 秒答法：** 读写路径会同时读取 `offset` 和 `file_size` 来做边界检查。如果我先更新 `offset`，再更新 `file_size`，中间窗口里 I/O 线程可能读到“新 offset + 旧 file_size”，这样 `limit_end` 就不可信了，严重时会带来越界风险。所以必须整体提交。
- **收束金句：** 配置更新不是“字段赋值”，而是“状态原子切换”。

### 8. 你怎么验证这套设计真的成立？
- **10 秒答法：** 我用用户态 `c_unitest` 去验证 ABI、I/O 路径和并发删除行为。
- **30 秒答法：** 我写了 `test_loop.c`，覆盖了基本读写、只读模式、`LOOP_CHANGE_FD`、`LOOP_SET_CAPACITY` 和并发 I/O 删除。特别是并发删除测试，不只是看能不能删掉，还验证删除过程中 I/O 只会在 `ENODEV/ENOENT` 这类预期错误上退出，所以能证明状态机和删除策略是真的 work。
- **收束金句：** 我验证的不是 happy path，而是边界条件下的语义正确性。

---

## 7. 最推荐死记的 8 句金句

1. 我把管理平面和数据平面彻底解耦了。
2. `LoopManager` 是控制面的真相源，不只是一个构造器。
3. 删除安全的关键不是删掉，而是在正确的时机删掉。
4. `IoGuard` 把计数正确性从人工纪律变成了 RAII 保证。
5. 稳定的删除流程，失败后一定要能回到可重试状态。
6. 自旋锁只保护短临界区，不能包住慢路径。
7. 配置更新不是字段赋值，而是状态原子切换。
8. 我验证的不是 happy path，而是边界条件下的语义正确性。

---

## 8. 最后 1 分钟收束陈词

如果让我总结这个项目，我觉得它最能体现我的不是“写了一个驱动”，而是我把一个看起来简单的块设备功能，真正做成了可兼容、可恢复、可验证的系统模块。

可兼容体现在 Linux 风格的 `/dev/loop-control + /dev/loopX` 模型和 `LOOP_SET/GET_STATUS64` ioctl；可恢复体现在删除流程的状态机和失败回滚；可验证体现在用户态 `c_unitest` 对并发删除、只读模式和容量刷新这些边界路径的覆盖。

所以这个项目最能代表我的，其实是我处理系统级状态、一致性和失败路径的能力。

---

## 9. 实战追问清单

### 第一轮：主线
1. 你先别讲细节，用源码主线讲一下 Loop 子系统是怎么跑起来的。
2. 你说 `/dev/loop-control` 是控制面，那它和 `/dev/loopX` 的边界到底怎么划？

### 第二轮：架构
3. `LoopManager` 为什么一定要单独存在？我把逻辑都写进 `loop_control.rs` 不行吗？
4. 你说设备复用有策略，那什么样的设备能复用？为什么不是“没绑定文件就能复用”？

### 第三轮：并发删除
5. 你一直说删除最难，那难点到底在哪？
6. 为什么要分 `Rundown` 和 `Draining` 两个状态？一个 `Deleting` 不够吗？
7. 如果一个线程已经开始删设备，另一个线程这时候又来读 `/dev/loopX`，你的代码怎么保证不出事？
8. 为什么 `IoGuard` 不能换成手写 `fetch_add/fetch_sub`？

### 第四轮：失败路径
9. 如果排空 I/O 超时了，为什么要回滚到 `Rundown`，而不是继续卡在 `Draining`？
10. 如果已经到 `Deleting` 了，block 设备注销失败怎么办？

### 第五轮：一致性
11. `LOOP_SET_STATUS64` 不就是改几个字段吗？为什么你把它讲得这么重？
12. 为什么不能直接在锁里读 metadata、算 size、再更新字段？
13. 为什么不能先更新 `offset`，再更新 `file_size`？

### 第六轮：兼容性
14. 你说自己做了 Linux ioctl 兼容，具体兼容在哪里？
15. 兼容是不是只是“值一样”就行？

### 第七轮：验证
16. 你怎么证明你的并发删除真的 work？
17. 如果我让你选一个最能体现你能力的函数，你选哪个？为什么？
