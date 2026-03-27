所以的进程 ，轻量级进程，内核线程在底层都是一个 task_struct
A. struct mm_struct *mm (内存资源)

    普通进程： 指向一个专属的 mm_struct（有独立的页表 PGD）。

    LWP (线程)： 指向父进程的 mm_struct（多个 task 共享同一个）。

    内核线程： NULL。它不需要用户空间，运行在内核公共区域。

B. pid_t pid 与 pid_t tgid (标识符)

这是最容易搞晕的地方：

    PID (Process ID)： 在内核层面，其实代表的是 线程 ID。每个 task_struct 的 PID 都是唯一的。

    TGID (Thread Group ID)： 这才是我们在用户态看到的 进程 ID。

    逻辑： 一个进程下的所有 LWP，它们的 tgid 都是一样的（等于主线程的 pid），但它们各自的 pid 互不相同。

C. void *stack (内核栈)

    所有任务： 无论什么身份，每一个 task_struct 必须拥有自己独立的内核栈。

    原因： 当任务陷进内核（系统调用或中断）时，它必须有地方保存自己的寄存器快照。如果共享内核栈，那就全乱套了。

2. 调度器的“一视同仁”

当你写 DragonOS 的调度器（Scheduler）时，你的函数签名大概是这样的：
void schedule(struct task_struct *prev, struct task_struct *next);

调度器根本不关心 next 是进程还是线程。 它只负责：

    切换硬件上下文（寄存器）。

    根据 mm 判断： 如果 next->mm 和 prev->mm 不一样，就顺手把 CR3 换了（切页表）；如果一样，就假装没看见，直接跳过。

3. 为什么 LWP 和 用户线程 也是一个 task_struct？

这是因为 Linux 采用了 1:1 线程模型。

    你在用户态调 pthread_create，内核就 copy_process 出一个新的 task_struct。

    这个新的 task_struct 就是 LWP。

    它和用户态那个“线程”对象是生死与共的关系。

例外：协程（Coroutine）
唯独协程不是 task_struct。协程只是用户态线程里的一段变量（状态机）。内核只看到一个 task_struct 在运行，至于这个 task 内部是在切协程 A 还是协程 B，内核完全不知道。
协程是一个 可以保存 中间状态的函数式状态机，可以通过await()这样的接口把将协程进行异步运行时等待，然后他再运行的时候可以通过resume（）在任何一个线程加载协程的上下文。