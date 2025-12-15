# Linux SYS_POLL 系统调用深度分析报告

## 执行摘要

本报告针对 Linux 6.6.21 中的 `sys_poll`/`ppoll` 调用链进行深度剖析，聚焦其行为语义、等待/唤醒机制、超时处理与信号重启路径，并结合实现细节给出关键边界与性能观察。

## 1. 系统调用概览

- 入口定义：`SYSCALL_DEFINE3(poll, struct pollfd __user *ufds, unsigned int nfds, int timeout_msecs)` 与 `SYSCALL_DEFINE5(ppoll, …)`，核心实现在 `fs/select.c:974` 经 `do_sys_poll()` 完成。
- 语义：遍历 `pollfd` 数组，对每个 `fd` 查询事件并可睡眠等待，返回“有事件的 fd 数”。`ppoll` 允许同时修改信号掩码与纳秒级超时。

## 2. 核心实现流程（do_sys_poll）

1. **参数校验**：`nfds` 大于 `RLIMIT_NOFILE` 时返回 `-EINVAL`（`fs/select.c:987`）。
2. **用户数组搬移**：小量 `pollfd` 使用栈缓冲（`POLL_STACK_ALLOC`），其余分页分配 `poll_list` 链表（`fs/select.c:990-1007`），失败返回 `-ENOMEM`。
3. **主执行**：初始化 `poll_wqueues` 后调用 `do_poll()`，结束后释放注册的 waitqueue（`fs/select.c:1014-1016`）。
4. **结果回写**：通过 `unsafe_put_user` 将 `revents` 写回用户态（`fs/select.c:1018-1027`）；写失败返回 `-EFAULT`。
5. **清理**：释放可能的分页链表，按错误码或就绪 fd 数返回（`fs/select.c:1030-1044`）。

## 3. 事件检测与等待机制

- **单个 fd 处理（do_pollfd）**：对 `fd<0` 直接视为 `POLLNVAL`；`fdget` 失败同样返回 `EPOLLNVAL`（`fs/select.c:863-868`）。事件掩码由用户 `events` 反向映射为内核 `EPOLL*`（`demangle_poll`），并强制加上 `EPOLLERR|EPOLLHUP`（`fs/select.c:870-876`）。调用 `vfs_poll()` 获取设备自定义的 `poll` 结果，然后过滤并写回 `revents`（`fs/select.c:872-882`）。
- **遍历/计数（do_poll）**：循环所有 `poll_list`，若任一 fd 返回非零事件则递增计数并清空 `_qproc`，避免重复注册等待者（`fs/select.c:904-929`）。未命中事件时检查 `wait->error` 和信号，信号待处理时返回 `-ERESTARTNOHAND`（`fs/select.c:936-939`）。
- **等待者注册**：`poll_initwait` 将 `poll_wqueues.pt._qproc` 设为 `__pollwait`，在设备的 `poll_wait()` 调用链中向每个 `wait_queue_head` 注册 `poll_table_entry`；内联表不够时页级扩展，失败时记录 `-ENOMEM`（`fs/select.c:122-183`）。
- **唤醒与屏障**：`pollwake` 根据 `key` 过滤事件，调用 `__pollwake` 设置 `triggered=1` 并唤醒轮询任务，写内存屏障保证事件可见（`fs/select.c:185-219`）。`poll_schedule_timeout` 在睡眠后使用 `smp_store_mb` 清除 `triggered`，确保下一轮检查的有序性。

## 4. 超时与时间语义

- **超时设置**：`poll_select_set_timeout()` 接收用户秒+纳秒，转换为绝对过期时间；0 超时直接标记“无等待”（`fs/select.c:260-289`）。`poll` 使用毫秒入参，拆分为秒+纳秒传入。
- **等待循环**：首次需要睡眠时将绝对 `timespec64` 转为 `ktime_t`，调用 `poll_schedule_timeout()` 以 `TASK_INTERRUPTIBLE` 状态睡眠（`fs/select.c:955-966`）。超时时返回 0，继续循环则重新检查事件。
- **时间精度/松弛度**：`select_estimate_accuracy()` 基于超时估算 slack（普通进程约 0.1% 且上限 100ms；实时任务为 0），用于 `schedule_hrtimeout_range()` 的过期范围，减少唤醒抖动（`fs/select.c:76-94`）。
- **ppoll 剩余时间回写**：`ppoll`/`ppoll_time32` 通过 `poll_select_finish()` 写回剩余时间，若进程具备 `STICKY_TIMEOUTS` 则不回写并把 `-ERESTARTNOHAND` 转为 `-EINTR`（`fs/select.c:504-557`）。

## 5. 信号与重启路径

- 睡眠期间收到可处理信号时，`do_poll()` 返回 `-ERESTARTNOHAND`（`fs/select.c:936-939`）。系统调用层捕获后在 `restart_block` 中记录 `ufds`、`nfds` 及绝对超时，使用 `do_restart_poll()` 重新进入 `do_sys_poll()`，确保超时从原始绝对时间计算剩余量（`fs/select.c:1048-1090`）。

## 6. 边界与错误处理

- **无效 fd**：`pollfd->fd<0` 或 `fdget` 失败时返回 `POLLNVAL`，计入事件数量；调用者需检查 `revents`。
- **容量与内存**：`nfds` 超限返回 `-EINVAL`；分配分页失败返回 `-ENOMEM` 并清理已分配页面。
- **用户访问**：`copy_from_user`/`put_user` 失败均返回 `-EFAULT`，并在 `Efault` 标签统一清理。
- **忙轮询**：当文件 `poll` 返回 `POLL_BUSY_LOOP` 时进入自旋忙轮询，受 `net_busy_loop_on()` 和 `busy_loop_timeout()` 控制，并在检测到真实事件后关闭忙轮询标志（`fs/select.c:892-929, 944-953`）。

## 7. 语义要点与性能观察

- **事件计数语义**：返回值是“有事件的 fd 数”，包含错误/挂起事件（如 `POLLERR`、`POLLHUP`、`POLLNVAL`），与 `select` 的“就绪描述符数”一致。
- **一次注册，多次检查**：进入等待前已完成所有 waitqueue 注册，后续循环将 `_qproc` 置空，避免重复注册/注销开销。
- **栈占用受控**：最多使用 `POLL_STACK_ALLOC`（256 字节）栈空间存放小数组，其余按页扩展，适配大规模 `nfds`。
- **绝对时间的超时逻辑**：`poll`/`ppoll` 将用户超时转换为绝对时间并在重启时复用，确保因信号中断后仍按原始到期点计算。
- **可见性保证**：`__pollwake` 与 `poll_schedule_timeout` 的内存屏障确保事件状态与唤醒顺序一致，防止丢事件。

## 8. 进一步调研建议

1. 对特定驱动的 `f_op->poll` 行为进行抽样，验证忙轮询路径是否频繁触发并评估 CPU 消耗。
2. 在高 `nfds` 场景下评估分页链表分配次数与频繁复制带来的开销，必要时考虑 epoll/多路复用替代。
3. 检查用户态库是否正确处理 `POLLNVAL` 情况（返回值计数包含此类事件），避免误判“没有事件”的场景。

## 9. DragonOS 实现问题与测例失败对照

- PollTest.InvalidFds：`kernel/src/filesystem/poll.rs:93-108` 直接用 `UserBufferWriter::new` 构造切片，`verify_area` 仅做“地址落在用户态”检查，`pollfd_ptr=nullptr` 且 `nfds>0` 时不会返回 EFAULT，而是形成指向 0 地址的大切片，后续访问触发 ENOEXEC。`nfds=-1` 被当作超大无符号值，缺少 RLIMIT 校验与溢出检测，未能按 Linux 返回 EINVAL。
- PollTest.NegativeTimeout：`poll_all_fds` 在 `nfds=0` 时传入 `max_events=0` 给 `EventPoll::epoll_wait_with_file`，后者直接返回 0；完全未进入可中断睡眠，也没有信号重启路径，导致计时器 SIGALRM 不会打断，返回值错误地为 0。
- PollTest.NonBlockingEventPOLLHUP：`add_pollfds` 仅把用户请求的位掩码转换为 `EPollEventType`（同文件 40-58 行），没有像 Linux 那样强制附加 `POLLERR|POLLHUP`。`ep_item_poll` 又会用注册的掩码与设备返回值相与（`kernel/src/filesystem/epoll/mod.rs:90-116`），因此挂断事件被过滤，`revents` 为空。
- 其他潜在差异：未实现 RLIMIT_NOFILE 上限检查（`PollTest.Nfds` 会返回错误值），无效 fd 会在 `epoll_ctl_with_epfile` 处直接抛 EBADF，缺少逐条 `POLLNVAL` 回写与计数语义；用户缓冲区长度未做 `checked_mul`，存在长度溢出风险。

## 10. 修复方案（建议实现路径）

1. 参数与用户空间校验  
   - 在 `Syscall::poll/ppoll` 中对 `nfds` 做 `checked_mul`，溢出直接返回 EOVERFLOW/EINVAL；获取 `rlim_cur = current_pcb.get_rlimit(RLimitID::Nofile)`，若 `nfds > rlim_cur` 则返回 EINVAL。  
   - 当 `nfds>0` 时使用 `UserBufferWriter::new_checked`/`buffer_checked`，确保空指针或未映射页返回 EFAULT；`nfds=0` 可跳过用户区映射。
2. 主逻辑贴近 Linux `do_sys_poll`  
   - 为每个 `pollfd` 计算 `req = events | POLLERR | POLLHUP`，无论用户是否请求都要监听错误/挂断。  
   - `fd<0` 直接忽略；查表失败时设置 `revents=POLLNVAL` 并计入返回值，避免整个系统调用失败。  
   - 其余 fd 调用底层 `file.poll()`，`revents = mask & req`，就绪则计数并清理等待器；未就绪时注册等待队列（可复用现有 epoll 等待队列或实现简版 `poll_wqueues`）。
3. 超时与信号语义  
   - 将用户超时转换为绝对 `Instant`，循环中用 `saturating_sub` 计算剩余时间；超时返回 0。  
   - 睡眠应可被信号中断：有待处理未屏蔽信号时返回 `-ERESTARTNOHAND`，在 `poll_select_finish` 中转换成 EINTR，并填充重启块保持原始超时。`nfds=0` 时也要走同样的信号/超时路径，而非直接返回。  
4. 挂断/错误语义  
   - 在回填 `revents` 时始终保留 `POLLERR|POLLHUP|POLLRDHUP`，即使不在用户请求列表中；仅当底层 `poll()` 报告可读写再与用户掩码相与。确保无数据的管道仅返回 HUP，而不会被掩码过滤为 0。  
5. 回归验证  
   - 增加针对指针非法、`nfds=-1/0`、挂断路径的内核自测；手动运行 `./opt/tests/gvisor/tests/poll_test`，确认 `InvalidFds`、`NegativeTimeout`、`NonBlockingEventPOLLHUP` 与 `Nfds` 均通过。