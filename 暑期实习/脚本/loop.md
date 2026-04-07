>  整体思路：原来怎么做 → 优缺点 →  我做了什么 → 我做过哪些优化 → 如果让我重写会怎么改 → 做完之后怎么评价它值不值

## loop 为什么存在

- loop 要解决的，不是“怎么去读一个文件”，而是“怎么把一个普通文件接进标准块设备生态”。
- 挂载镜像、做文件系统测试、构建 rootfs/ISO、做取证分析，这类流程天然都是围绕块设备接口展开的。
- 如果没有 loop，上层工具链就得反复区分“这是文件”还是“这是块设备”，最后接口会越来越碎，很多现成能力也没法直接复用。

所以 loop 的意义，不在于造出一种新设备，而在于把 file→block 这层适配补上。这样一来，挂载、分区、fsck、调试这些已有工具链就都还能沿着原来的路径工作。

## Linux 原来是怎么做的

Linux 里的 loop，核心上就是三件事。

1. **file→block 语义映射**
   - 用户看到的是 `/dev/loopX` 这样的块设备；
   - 内核收到块请求后，把 LBA 翻译成 backing file 上的偏移；
   - 再结合 `offset`、`size_limit` 和文件大小，决定这次 I/O 是否有效。

2. **控制面和数据面分离**
   - `/dev/loop-control` 负责创建设备、分配 minor、管理 lifecycle；
   - `/dev/loopX` 负责真正的数据路径和设备状态接口；
   - 这样创建设备、删除设备、分配 minor 这些慢路径，不会直接污染热路径上的 I/O 逻辑。

3. **设备对象和后端文件解耦**
   - 设备可以先创建出来，再去绑定 backing file；
   - 这样设备的创建、绑定、切换、复用就都能放在统一的控制模型里处理。

### 优点

- 它把普通文件接进了现有的块设备生态；
- 用户态接口简单，工具链已经很成熟；
- 控制面和数据面分得比较清楚；
- 对镜像挂载、测试、构建这类工作流非常实用。

### 缺点

- Linux 里管理 loop 设备，不是一个显式的 manager 层，而是全局索引、全局锁、每个 `loop_device` 实例再加上一组过程函数共同完成，整体更偏过程式管理；
- 如果配置不当，可能出现 page cache 和块设备路径叠加后的双重缓存问题；
- 相比直接读文件，多了一层块设备抽象和状态检查；
- 文件本身有 page cache，loop 这一层再叠加逻辑后，写回和一致性语义会更难理解；
- 生命周期管理存在隐式风险，旧 fd、挂载引用或者后台探测进程都可能影响设备真正销毁；
- loop 本身不负责 COW / snapshot / clone；
- 控制面在创建和删除设备时比较依赖全局锁 `loop_ctl_mutex`。

---

## DragonOS的设计思路

讲解思路 ：

`loop_init`
→ `/dev/loop-control` ioctl
→ `LoopManager::loop_add`
→ 注册 `/dev/loopX`
→ `LOOP_SET_FD` / `bind_file`
→ `read_at_sync` / `write_at_sync`
→ `LOOP_CTL_REMOVE` / `loop_remove`

 一、核心架构：`LoopManager` + `/dev/loop-control` + `/dev/loopX`

  - 控制面用 `/dev/loop-control` + `LoopManager` 管理设备生命周期和复用；
  - 数据面用 `/dev/loopX` 承接块 I/O，把 LBA 翻译成文件偏移；
  - `LoopManager` 统一维护设备表和 minor 分配器，负责分配、复用、删除编排和设备注册；
  - 只有 `Unbound` 状态的设备才允许复用，避免把正在删除流程里的设备错误地重新发出去。

  二、设备状态机与删除路径

  - DragonOS 把设备状态拆成 `Unbound / Bound / Rundown / Draining / Deleting`；
  - 删除时不是一步摘掉，而是先 `Rundown` 拒绝新 I/O，再 `Draining` 等旧 I/O 排空，最后 `Deleting` 做注销和回收；
  - 这里的关键是，“不再接新请求”和“等待旧请求结束”不是同一件事，所以必须显式拆开；
  - 对空设备，删除路径可以直接从 `Unbound` 跳到 `Deleting`，不做无意义的 I/O 排空。

  三、配置更新和 I/O 收敛

  - 在 `IoGuard + active_io_count` 这条路径上，进入 I/O 时 `io_start()` 加计数，退出时通过 `Drop` 自动 `io_end()`，删除线程只需要等待活跃计数归零；
  - 一旦设备已经进入 `Rundown / Draining / Deleting`，新的 I/O 会直接被拒绝；
  - `LOOP_SET_STATUS64` 不是简单改几个字段，而是按“锁内取快照 → 锁外计算 → 锁内一次性提交”的方式更新 `offset / size_limit / flags / file_size`；
  - 这样可以避免 I/O 线程看到“新 offset + 旧 file_size”这种半更新状态。

  四、当前实现状态

  - 支持 `LOOP_CTL_ADD / REMOVE / GET_FREE` 这类控制面 ioctl；
  - 支持 `LOOP_SET_FD / LOOP_CHANGE_FD / LOOP_SET_STATUS64 / LOOP_GET_STATUS64 / LOOP_SET_CAPACITY` 等常见设备操作；
  - 用户态 `test_loop.c` 已经覆盖了基础读写、只读模式、后端切换、容量刷新、并发删除、删除未绑定设备、重复删除、删除后不可访问这些场景；

---

## 实现Loop过程中的难点

1. 删除设备时，控制线程可能已经准备回收，但旧 fd 还在继续做 I/O；
2. 设备“没绑定文件”不等于“可以立刻复用”，删除中的设备如果被过早复用，新旧语义会交叉；
3. `LOOP_SET_STATUS64` 这种配置更新，看起来只是改参数，实际上会直接影响 I/O 边界；
4. 删除流程跨了 I/O 排空、解绑 backing file、注销块设备和资源回收，中间任何一步失败都可能把设备卡在半删除状态。

---

## DragonOS目前的优化

- `Rundown` 和 `Draining` 这两个状态，是对 Linux 里退出路径状态表达较粗的一种补强，在 Linux 里你很难直接看见设备处于哪个转换中间态；（linux设备删除用粗颗粒的锁和串行化以及冻结队列进行删除）
- `LoopManager` 集中化之后，设备池、minor 分配、复用策略和删除编排都有了统一收口，而不是散在多个控制入口里；
- 控制面 / 数据面分离；
- 设备状态机细化，删除可恢复；
- I/O 计数用 RAII guard 收敛，避免错误路径漏减计数；
- 配置更新路径避免半更新快照；
- 测试重点放在并发删除、只读模式、后端切换和错误路径上，而不仅是基本读写成功。

- **统一真相源**：控制面围绕 `LoopManager + LoopDevice` 收口，避免设备池、复用状态和删除流程散在多处；
- **删除路径显式化**：把 Linux 里比较粗的退出语义拆成 `Rundown / Draining / Deleting`；
- **I/O 收敛路径**：通过 `IoGuard + active_io_count` 先兜住并发删除时的在途 I/O 正确性；
- **配置更新原子性**：`set_status64()` 用快照式提交，避免边界检查看到半更新状态；
- **失败后可重试**：支持 `Draining -> Rundown` 和 `Deleting -> Rundown` 回滚，不会轻易把设备卡成 zombie。

---

## 未来改进方向

- 做更统一的 image backend 抽象，不要把 loop 永远限定在普通文件后端上，后面可以为压缩镜像、COW、远端后端留接口；
- 继续梳理 buffered/direct I/O 的边界，减少不必要的数据拷贝，把缓存和性能语义讲清楚；
- 增加可观测性，把状态机状态、活跃 I/O 数、删除失败原因这些信息更直接地暴露出来；
- 补更贴近真实镜像工作流的集成验证，而不是只停留在用户态单测；
- 如果后面继续扩展，还可以把 loop 从“文件接块设备”的适配层，往更完整的镜像后端管理层再推进一步。

## 实现过程中解决的困难

1. 设备复用没有收紧到unbound

因为“当前没绑定文件”并不等于“生命周期已经结束”。删除中的设备如果被过早重新发出去，新旧两轮使用会交叉，所以 `manager.rs` 里明确只把 `Unbound` 视为可复用状态。

2. 为什么删除要拆成 `Rundown / Draining / Deleting`

因为“拒绝新 I/O”和“等待旧 I/O 结束”是两件不同的事。如果不拆开，删除流程要么太激进，要么会把设备卡在模糊的中间态。所以我把删除做成显式状态推进，而不是一个大而化之的 `Deleting`。

3. 为什么 `set_status64` 一定要快照式提交

因为它改的不只是配置字段，而是后续 I/O 的边界语义。如果先改 `offset` 再改 `file_size`，I/O 线程就可能看到半更新状态，边界检查会失真。所以这里必须做成“锁内取快照、锁外计算、锁内一次性提交”。

4. 为什么删除失败后一定要能回滚

因为删除不是一个函数调用，而是一整条流程。只要中间有一步失败，设备就可能卡在半删除状态。`Draining -> Rundown` 和 `Deleting -> Rundown` 这两条回滚路径，解决的就是“失败以后还能不能继续重试”这个问题。
