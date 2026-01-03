# DragonOS 启动流程详解

本文档详细介绍了 DragonOS 从执行 `make run non-graphic` 命令到操作系统完全启动的全过程，包括每一步的详细操作和组件交互。

## 目录

1. [核心组件说明](#核心组件说明)
2. [Make 命令执行阶段](#1-make-命令执行阶段)
3. [内核编译阶段](#2-内核编译阶段)
4. [磁盘镜像准备阶段](#3-磁盘镜像准备阶段)
5. [QEMU 启动阶段](#4-qemu-启动阶段)
6. [GRUB 引导加载阶段](#5-grub-引导加载阶段)
7. [内核早期启动阶段](#6-内核早期启动阶段)
8. [内核初始化阶段](#7-内核初始化阶段)
9. [进入用户空间](#8-进入用户空间)

---

## 核心组件说明

在深入了解启动流程之前，先了解 DragonOS 启动过程中涉及的核心组件及其作用。

### 构建工具链

#### Make
**作用**: 构建自动化工具，协调整个编译和启动流程
- 管理依赖关系（先编译内核，再准备磁盘，最后启动虚拟机）
- 支持并行编译（`-j` 参数）
- 提供多种启动模式（graphic/nographic/uefi 等）

#### Cargo
**作用**: Rust 的包管理器和构建工具
- 编译 Rust 内核代码
- 管理依赖库（alloc, core, 第三方 crate）
- 支持自定义目标（通过 target JSON 文件）
- 从源码构建标准库（`-Z build-std`）

**为什么需要从源码构建标准库？**
- 内核运行在裸机环境（no_std），没有操作系统支持
- 需要自定义内存分配器、panic handler
- 需要针对特定架构优化

#### LD (链接器)
**作用**: 将编译后的目标文件链接成可执行的内核映像
- 按照链接脚本（link.lds）组织内存布局
- 合并多个 .o 文件和静态库
- 生成符号表用于调试
- 支持两次链接以嵌入 kallsyms

#### DADK (DragonOS Application Development Kit)
**作用**: DragonOS 专用的应用开发和磁盘管理工具
- **磁盘镜像管理**: 创建、挂载、卸载磁盘镜像
- **文件系统操作**: 支持 ext4、fat32 等文件系统
- **Loop 设备管理**: 自动分配和管理 loop 设备
- **用户程序构建**: 编译和打包用户空间程序
- **依赖管理**: 管理用户程序的依赖关系

**DADK 的优势**:
- 统一的工具链，简化开发流程
- 自动处理权限问题（sudo）
- 支持增量构建，提高效率

### 虚拟化和仿真

#### QEMU (Quick Emulator)
**作用**: 开源的处理器仿真器和虚拟机监控器
- **全系统仿真**: 模拟完整的计算机系统（CPU、内存、设备）
- **硬件加速**: 支持 KVM（Linux）、HVF（macOS）加速
- **设备模拟**: 提供虚拟硬件设备（磁盘、网卡、串口等）
- **调试支持**: 内置 GDB 服务器，支持远程调试

**QEMU 的两种模式**:
1. **TCG 模式**（软件模拟）: 纯软件翻译执行，速度较慢但兼容性好
2. **KVM 模式**（硬件加速）: 利用 CPU 虚拟化扩展，接近原生性能

**DragonOS 使用的 QEMU 设备**:
- **q35 机器类型**: 现代化的 PC 平台，支持 PCIe
- **virtio 设备**: 半虚拟化设备，性能优于全虚拟化
  - `virtio-blk`: 块设备（磁盘）
  - `virtio-net`: 网络设备
  - `virtio-serial`: 串口设备
- **XHCI 控制器**: USB 3.0 控制器

#### KVM (Kernel-based Virtual Machine)
**作用**: Linux 内核的虚拟化模块
- 将 Linux 内核转变为虚拟机监控器（Hypervisor）
- 利用 CPU 的硬件虚拟化扩展（Intel VT-x / AMD-V）
- 提供接近原生的性能
- 通过 `/dev/kvm` 设备文件与用户空间交互

**检测 KVM 是否可用**:
```bash
# 检查 CPU 是否支持虚拟化
grep -E 'vmx|svm' /proc/cpuinfo

# 检查 KVM 模块是否加载
lsmod | grep kvm

# 检查设备文件是否存在
ls -l /dev/kvm
```

### 引导加载器

#### GRUB2 (GRand Unified Bootloader)
**作用**: 多重引导加载器，负责加载操作系统内核
- **多系统支持**: 可以引导多个操作系统
- **Multiboot2 协议**: 标准化的内核加载接口
- **配置灵活**: 通过 grub.cfg 配置启动选项
- **模块化设计**: 支持加载额外的模块（文件系统驱动等）

**GRUB 的启动流程**:
1. BIOS/UEFI 加载 GRUB 第一阶段（boot.img）
2. 第一阶段加载第二阶段（core.img）
3. 第二阶段读取配置文件（grub.cfg）
4. 根据配置加载内核和 initrd
5. 通过 Multiboot2 协议跳转到内核入口

**DragonOS 中的 GRUB 配置**:
```
menuentry "DragonOS" {
    multiboot2 /boot/kernel.elf init=/bin/dragonreach
}
```

#### Multiboot2 协议
**作用**: 定义引导加载器和内核之间的接口标准
- **标准化**: 内核可以被任何支持 Multiboot2 的引导加载器加载
- **信息传递**: 引导加载器向内核传递系统信息
  - 内存映射（可用内存区域）
  - 帧缓冲区信息（显示设备）
  - ACPI 表地址
  - 命令行参数
- **架构无关**: 支持多种 CPU 架构

**Multiboot2 头部**:
- 必须位于内核文件的前 32KB
- 包含魔数 `0xe85250d6`
- 包含架构标识、校验和等信息

### 内核核心组件

#### kallsyms (内核符号表)
**作用**: 存储内核中所有符号（函数名、变量名）的地址映射
- **调试支持**: 将内存地址转换为可读的函数名
- **堆栈回溯**: panic 时显示调用栈
- **性能分析**: perf 等工具需要符号信息
- **动态追踪**: 支持 kprobe、tracepoint 等功能

**为什么需要两次链接？**
1. 第一次链接生成初步的内核 ELF
2. 从 ELF 中提取符号表，生成 kallsyms.o
3. 第二次链接将 kallsyms.o 嵌入内核
4. 这样内核运行时就能访问自己的符号表

**kallsyms 的数据结构**:
```rust
// 符号地址数组
static KALLSYMS_ADDRESSES: [usize; N];
// 符号名称字符串
static KALLSYMS_NAMES: [u8; M];
// 符号类型（函数/变量/等）
static KALLSYMS_TYPES: [u8; N];
```

#### GDT (全局描述符表)
**作用**: x86_64 架构的段描述符表，定义内存段的属性
- **段选择子**: 代码段、数据段、TSS 等
- **特权级控制**: Ring 0（内核）/ Ring 3（用户）
- **长模式支持**: 64 位模式下段基址和限长被忽略，但仍需要 GDT

**DragonOS 的 GDT 布局**:
```
0x00: 空描述符
0x08: 内核代码段 (Ring 0)
0x10: 内核数据段 (Ring 0)
0x18: 用户代码段 (Ring 3) - 32位
0x20: 用户数据段 (Ring 3) - 32位
0x28: 用户数据段 (Ring 3) - 64位
0x30: 用户代码段 (Ring 3) - 64位
0x38: 内核代码段 (Ring 0) - 32位
0x40: 内核数据段 (Ring 0) - 32位
0x48+: TSS 描述符（每个 CPU 一个）
```

#### IDT (中断描述符表)
**作用**: 定义中断和异常的处理程序入口
- **256 个表项**: 0-31 异常，32-255 中断
- **中断门**: 指向中断处理程序的地址
- **特权级检查**: DPL 字段控制访问权限

**DragonOS 的中断分配**:
- **0-31**: CPU 异常（除零、缺页、保护错误等）
- **32-47**: 传统 IRQ（PIC 中断）
- **48-255**: APIC 中断、系统调用、IPI 等

#### TSS (任务状态段)
**作用**: 保存任务切换时的 CPU 状态
- **RSP0-RSP2**: 不同特权级的栈指针
- **IST**: 中断栈表（7 个独立栈）
- **I/O 位图**: 控制端口访问权限

**为什么需要 TSS？**
- 从用户态（Ring 3）切换到内核态（Ring 0）时需要切换栈
- 某些异常（如双重错误）需要独立的栈，避免栈溢出

### 内存管理组件

#### 页表 (Page Table)
**作用**: 实现虚拟地址到物理地址的映射
- **4 级页表**: PML4 -> PDPT -> PD -> PT（x86_64）
- **页大小**: 4KB（标准页）、2MB（大页）、1GB（巨页）
- **权限控制**: 读/写/执行权限，用户/内核访问控制
- **地址空间隔离**: 每个进程有独立的页表

**DragonOS 的地址空间布局**:
```
0x0000000000000000 - 0x00007fffffffffff: 用户空间 (128TB)
0xffff800000000000 - 0xffffffffffffffff: 内核空间 (128TB)
  0xffff800000000000: 内核直接映射区（物理内存）
  0xffffffff80000000: 内核代码和数据
```

#### 伙伴系统 (Buddy System)
**作用**: 管理物理内存页框的分配和回收
- **按 2 的幂次分配**: 1页、2页、4页、8页...
- **快速合并**: 相邻的空闲块可以合并成更大的块
- **减少碎片**: 通过合并机制减少外部碎片
- **分区管理**: 支持 DMA、Normal、HighMem 等内存区域

**分配示例**:
```
请求 3 页 -> 分配 4 页（2^2）
请求 5 页 -> 分配 8 页（2^3）
```

#### SLAB 分配器
**作用**: 管理小对象的内存分配
- **对象缓存**: 为常用对象（如 PCB、文件描述符）预分配内存
- **减少碎片**: 避免频繁的小内存分配造成的内部碎片
- **性能优化**: 对象重用，减少初始化开销
- **CPU 缓存友好**: 利用 CPU 缓存提高性能

**SLAB 的三层结构**:
1. **Cache**: 特定类型对象的缓存（如 task_struct cache）
2. **Slab**: 一个或多个连续的页框
3. **Object**: Slab 中的单个对象

### 文件系统组件

#### VFS (虚拟文件系统)
**作用**: 提供统一的文件系统接口，屏蔽底层文件系统差异
- **抽象层**: 为不同文件系统提供统一的 API
- **文件操作**: open、read、write、close 等
- **目录操作**: mkdir、rmdir、readdir 等
- **挂载管理**: 支持多个文件系统挂载

**VFS 的核心数据结构**:
- **superblock**: 文件系统元信息
- **inode**: 文件/目录的元数据（权限、大小、时间戳）
- **dentry**: 目录项，连接文件名和 inode
- **file**: 打开的文件实例

#### ext4 文件系统
**作用**: DragonOS 的主要文件系统
- **日志功能**: 保证数据一致性
- **大文件支持**: 支持 16TB 文件
- **扩展属性**: 支持 ACL、SELinux 等
- **延迟分配**: 提高性能

#### devfs (设备文件系统)
**作用**: 提供设备文件的动态管理
- **自动创建**: 设备注册时自动创建设备文件
- **设备节点**: /dev/tty、/dev/null、/dev/random 等
- **字符设备**: 串口、终端等
- **块设备**: 磁盘、分区等

#### procfs (进程文件系统)
**作用**: 以文件形式暴露内核和进程信息
- **/proc/cpuinfo**: CPU 信息
- **/proc/meminfo**: 内存信息
- **/proc/[pid]/**: 进程信息
- **/proc/sys/**: 内核参数（可调整）

### 进程管理组件

#### PCB (进程控制块)
**作用**: 存储进程的所有信息
- **进程状态**: 运行、就绪、阻塞、僵尸等
- **寄存器上下文**: 保存 CPU 寄存器状态
- **内存管理**: 页表指针、内存映射
- **文件描述符表**: 打开的文件列表
- **调度信息**: 优先级、时间片、CPU 亲和性

**PCB 的关键字段**:
```rust
struct ProcessControlBlock {
    pid: Pid,                    // 进程 ID
    state: ProcessState,         // 进程状态
    mm: AddressSpace,            // 地址空间
    files: FileDescriptorTable,  // 文件描述符表
    parent: Option<Arc<PCB>>,    // 父进程
    children: Vec<Arc<PCB>>,     // 子进程列表
}
```

#### CFS 调度器 (完全公平调度器)
**作用**: 决定哪个进程获得 CPU 时间
- **虚拟运行时间**: 每个进程维护 vruntime
- **红黑树**: 按 vruntime 排序，O(log n) 复杂度
- **公平性**: 保证每个进程获得公平的 CPU 时间
- **优先级支持**: nice 值影响时间片长度

**调度决策**:
1. 选择 vruntime 最小的进程
2. 运行一个时间片
3. 更新 vruntime
4. 重新插入红黑树

### 中断和时间子系统

#### APIC (高级可编程中断控制器)
**作用**: 现代 x86 系统的中断控制器
- **Local APIC**: 每个 CPU 核心一个，处理本地中断
- **I/O APIC**: 处理外部设备中断
- **IPI**: 处理器间中断，用于 SMP 通信
- **中断路由**: 将中断分发到不同的 CPU

**APIC vs PIC**:
- PIC（8259A）: 传统中断控制器，最多 15 个中断
- APIC: 支持更多中断，支持多核，性能更好

#### 软中断 (Softirq)
**作用**: 延迟处理中断的下半部分
- **异步执行**: 不在中断上下文中执行耗时操作
- **优先级**: 高于普通进程，低于硬件中断
- **类型**: 定时器、网络收发、块设备 I/O 等

**为什么需要软中断？**
- 硬件中断处理必须快速完成
- 耗时操作（如网络协议栈处理）放到软中断
- 避免长时间关闭中断

#### TSC (时间戳计数器)
**作用**: 高精度时间源
- **CPU 周期计数**: 每个 CPU 周期递增
- **纳秒级精度**: 可以测量极短的时间间隔
- **性能分析**: 用于性能测量和 profiling
- **时间同步**: 多核系统需要同步各 CPU 的 TSC

**读取 TSC**:
```asm
rdtsc  ; 读取 TSC 到 EDX:EAX
```

#### HPET (高精度事件定时器)
**作用**: 系统级高精度定时器
- **独立于 CPU**: 不受 CPU 频率变化影响
- **多个定时器**: 通常有 3-32 个独立定时器
- **纳秒级精度**: 通常 10MHz 或更高频率
- **替代 PIT**: 比传统 8254 PIT 更精确

**HPET vs TSC**:
- TSC: 每个 CPU 独立，速度快但可能不同步
- HPET: 全局共享，速度较慢但可靠

### 驱动和设备管理

#### virtio 设备
**作用**: 半虚拟化设备，专为虚拟化环境优化
- **高性能**: 避免完全模拟硬件的开销
- **标准接口**: 统一的 virtio 协议
- **多种设备类型**: 块设备、网络、串口、GPU 等

**virtio 的工作原理**:
1. **virtqueue**: 虚拟队列，用于 Guest 和 Host 通信
2. **描述符表**: 描述数据缓冲区的位置和大小
3. **通知机制**: 通过 MMIO 或 PCI 配置空间通知对方
4. **零拷贝**: 直接访问 Guest 内存，减少数据拷贝

**DragonOS 使用的 virtio 设备**:
- `virtio-blk`: 磁盘设备，读写磁盘镜像
- `virtio-net`: 网络设备，提供网络连接
- `virtio-serial`: 串口设备，用于控制台输出

#### ACPI (高级配置与电源接口)
**作用**: 提供硬件配置和电源管理的标准接口
- **硬件发现**: 发现系统中的硬件设备（CPU、内存、设备等）
- **中断路由**: 配置设备中断到 CPU 的路由
- **电源管理**: 控制设备和系统的电源状态
- **热插拔**: 支持设备的热插拔

**ACPI 表**:
- **RSDP**: 根系统描述指针，ACPI 的入口
- **XSDT**: 扩展系统描述表，指向其他 ACPI 表
- **MADT**: 多 APIC 描述表，描述 CPU 和 APIC 配置
- **HPET**: HPET 定时器描述表
- **FADT**: 固定 ACPI 描述表，系统硬件信息

**ACPI 的重要性**:
- 没有 ACPI，内核无法知道系统有多少个 CPU
- 没有 ACPI，无法正确配置中断路由
- 现代 x86 系统必须支持 ACPI

#### SMP (对称多处理)
**作用**: 支持多核 CPU 并行执行
- **BSP**: 引导处理器（Bootstrap Processor），第一个启动的 CPU
- **AP**: 应用处理器（Application Processor），其他 CPU 核心
- **IPI**: 处理器间中断，用于 CPU 之间通信
- **CPU 亲和性**: 控制进程在哪个 CPU 上运行

**SMP 启动流程**:
1. BSP 启动并初始化系统
2. BSP 解析 ACPI MADT 表，获取 AP 信息
3. BSP 准备 AP 启动代码（放在低地址内存）
4. BSP 通过 APIC 发送 INIT-SIPI-SIPI 序列唤醒 AP
5. AP 从实模式启动，切换到保护模式/长模式
6. AP 初始化自己的 GDT、IDT、页表
7. AP 进入内核，等待调度

**为什么需要 INIT-SIPI-SIPI？**
- INIT: 初始化 AP，重置到已知状态
- SIPI: 启动 IPI，告诉 AP 从哪里开始执行
- 发送两次 SIPI 是为了可靠性

---

## 1. Make 命令执行阶段

### 1.1 命令入口

**文件**: `Makefile:179-183`

```makefile
run-nographic: check_arch
	$(MAKE) kernel
	SKIP_GRUB=1 $(MAKE) write_diskimage || exit 1
	# $(MAKE) rootfs
	$(MAKE) qemu-nographic
```

当执行 `make run non-graphic` 时，Makefile 会依次执行以下目标：

1. **check_arch** - 检查架构配置是否正确
2. **kernel** - 编译内核
3. **write_diskimage** - 准备磁盘镜像（设置 SKIP_GRUB=1 跳过 GRUB 安装以加快速度）
4. **qemu-nographic** - 启动 QEMU 虚拟机

### 1.2 架构检查

**文件**: `Makefile:53-54`

```bash
check_arch:
	@bash tools/check_arch.sh
```

检查当前 `ARCH` 环境变量是否与 `dadk-manifest.toml` 中配置的架构一致。

---

## 2. 内核编译阶段

### 2.1 内核编译入口

**文件**: `kernel/Makefile:29-31`

```makefile
all:
	$(MAKE) -C ../build-scripts all
	$(MAKE) -C src all ARCH=$(ARCH) || (sh -c "echo 内核编译失败" && exit 1)
```

### 2.2 Rust 内核编译

**文件**: `kernel/src/Makefile:50-51`

```makefile
kernel_rust:
	DRAGONOS_ACTUAL_BUILD=1 RUSTFLAGS="$(RUSTFLAGS)" INITRAM_PATH="$(INITRAM_PATH)" cargo $(TOOLCHAIN) $(CARGO_ZBUILD) build --release --target $(TARGET_JSON)
```

**关键参数**:
- `TOOLCHAIN`: nightly-2025-08-10（指定 Rust 工具链版本）
- `CARGO_ZBUILD`: `-Z build-std=core,alloc,compiler_builtins`（从源码构建标准库）
- `TARGET_JSON`: `arch/x86_64/x86_64-unknown-none.json`（自定义目标配置）

这一步会编译所有内核的 Rust 代码，生成静态库 `libdragonos_kernel.a`。

### 2.3 内核链接

**文件**: `kernel/src/Makefile:105-128` (x86_64 架构)

```makefile
__link_x86_64_kernel:
	# 第一次链接
	$(LD) -b elf64-x86-64 -z muldefs $(LDFLAGS_UNWIND) -o kernel \
	      ../target/x86_64-unknown-none/release/libdragonos_kernel.a \
	      -T arch/x86_64/link.lds --no-relax

	# 生成 kallsyms
	cd debug && $(MAKE) generate_kallsyms

	# 重新链接（包含 kallsyms）
	$(LD) -b elf64-x86-64 -z muldefs $(LDFLAGS_UNWIND) -o kernel \
	      ../target/x86_64-unknown-none/release/libdragonos_kernel.a \
	      ./debug/kallsyms.o -T arch/x86_64/link.lds --no-relax

	# 生成最终的 ELF 文件
	$(OBJCOPY) -I elf64-x86-64 -O elf64-x86-64 kernel ../../bin/kernel/kernel.elf
```

**链接脚本**: `kernel/src/arch/x86_64/link.lds`

链接脚本定义了内核的内存布局：
- **入口点**: `_start` (link.lds:4)
- **加载地址**: 0x100000 (1MB)
- **.text 段**: 代码段（从 0xffff800000000000 + 0x8000 开始）
- **.data 段**: 数据段
- **.rodata 段**: 只读数据段
- **.bss 段**: 未初始化数据段

**两次链接的原因**:
1. 第一次链接生成初步的内核 ELF 文件
2. 提取符号表生成 kallsyms（用于内核调试和符号查找）
3. 第二次链接将 kallsyms 嵌入到内核中

### 2.4 编译产物

最终生成的内核文件：`bin/kernel/kernel.elf`

---

## 3. 磁盘镜像准备阶段

### 3.1 脚本入口

**文件**: `tools/write_disk_image.sh`

执行命令：
```bash
SKIP_GRUB=1 make write_diskimage
```

**环境变量**:
- `SKIP_GRUB=1`: 跳过 GRUB 安装（nographic 模式下不需要）
- `ARCH`: 目标架构（默认 x86_64）
- `DADK`: dadk 工具路径

### 3.2 使用 DADK 工具创建磁盘镜像

**文件**: `tools/write_disk_image.sh:83`

```bash
$DADK -w $root_folder rootfs create --skip-if-exists || exit 1
```

DADK (DragonOS Application Development Kit) 是 DragonOS 的应用开发工具包，负责：
- 创建磁盘镜像文件 `bin/disk-image-x86_64.img`
- 管理文件系统（默认 ext4）
- 挂载/卸载磁盘镜像

### 3.3 挂载磁盘镜像

**文件**: `tools/write_disk_image.sh:85-89`

```bash
$DADK -w $root_folder rootfs mount || exit 1

LOOP_DEVICE=$($DADK -w $root_folder rootfs show-loop-device || exit 1)
mount_folder=$($DADK -w $root_folder rootfs show-mountpoint || exit 1)
```

DADK 会：
1. 在 loop 设备上挂载磁盘镜像
2. 返回 loop 设备路径（如 `/dev/loop0`）
3. 返回挂载点路径（如 `/tmp/dragonos-mount-xxx`）

### 3.4 拷贝内核和用户程序

**文件**: `tools/write_disk_image.sh:106-123`

```bash
# 拷贝内核到 /boot
cp ${kernel} ${mount_folder}/boot/

# 创建目录结构
mkdir -p ${mount_folder}/bin
mkdir -p ${mount_folder}/sbin
mkdir -p ${mount_folder}/dev
mkdir -p ${mount_folder}/proc
mkdir -p ${mount_folder}/usr
mkdir -p ${mount_folder}/root
mkdir -p ${mount_folder}/tmp

# 拷贝用户程序
cp -r ${root_folder}/bin/sysroot/* ${mount_folder}/
```

**目录结构**:
```
/boot/kernel.elf      # 内核文件
/bin/                 # 用户程序（如 busybox, dragonreach 等）
/sbin/                # 系统管理程序
/dev/                 # 设备文件目录
/proc/                # proc 文件系统挂载点
/usr/                 # 用户程序和库
/root/                # root 用户主目录
/tmp/                 # 临时文件目录
```

### 3.5 设置 GRUB 配置（仅当 SKIP_GRUB=0 时）

**文件**: `tools/write_disk_image.sh:126-137`

```bash
touch ${mount_folder}/boot/grub/grub.cfg
cfg_content='set timeout=15
    set default=0
    insmod efi_gop
    menuentry "DragonOS" {
    multiboot2 /boot/kernel.elf init=/bin/dragonreach
}'
echo "${cfg_content}" > ${boot_folder}/grub/grub.cfg
```

**GRUB 配置说明**:
- **timeout**: 15 秒启动超时
- **multiboot2**: 使用 Multiboot2 协议加载内核
- **内核参数**: `init=/bin/dragonreach` 指定 init 进程

### 3.6 卸载磁盘镜像

**文件**: `tools/write_disk_image.sh:180`

```bash
$DADK -w $root_folder rootfs umount || exit 1
```

---

## 4. QEMU 启动阶段

### 4.1 QEMU 启动脚本

**文件**: `tools/run-qemu.sh:131-133`

```bash
qemu-nographic: check_arch
	sh -c "cd tools && bash run-qemu.sh --bios=legacy --display=nographic && cd .."
```

### 4.2 QEMU 参数配置

**关键配置**（基于 `tools/run-qemu.sh`）：

#### 4.2.1 基本配置
```bash
QEMU=$(which qemu-system-${ARCH})  # qemu-system-x86_64
QEMU_DISK_IMAGE="../bin/disk-image-${ARCH}.img"
QEMU_MEMORY="1024M"
QEMU_SMP="2,cores=2,threads=1,sockets=1"  # 2核CPU
```

#### 4.2.2 加速配置
**文件**: `tools/run-qemu.sh:75-86`

```bash
if [ ${ARCH} == "x86_64" ]; then
  if [ -e /dev/kvm ]; then
    qemu_accel="kvm"  # 使用 KVM 硬件加速
  else
    qemu_accel="tcg"  # 软件模拟
  fi
fi

QEMU_ACCELARATE=" -machine accel=${qemu_accel} "
if [ "${qemu_accel}" == "kvm" ]; then
  QEMU_ACCELARATE+=" -enable-kvm "
fi
```

#### 4.2.3 CPU 配置
**文件**: `tools/run-qemu.sh:150-154`

```bash
QEMU_MACHINE=" -machine q35,memory-backend=${QEMU_MEMORY_BACKEND} "
cpu_model=$([ "${qemu_accel}" == "kvm" ] && echo "host" || echo "IvyBridge")
QEMU_CPU_FEATURES+="-cpu ${cpu_model},apic,x2apic,+fpu,check,+vmx,${allflags}"
```

#### 4.2.4 nographic 模式配置
**文件**: `tools/run-qemu.sh:245-270`

```bash
if [ ${QEMU_NOGRAPHIC} == true ]; then
    # 串口和控制台配置
    QEMU_SERIAL=" -serial chardev:mux -monitor chardev:mux \
                  -chardev stdio,id=mux,mux=on,signal=off,logfile=${QEMU_SERIAL_LOG_FILE} "

    # 添加 virtio console 设备
    QEMU_DEVICES+=" -device virtio-serial -device virtconsole,chardev=mux "

    # 内核命令行参数
    KERNEL_CMDLINE=" console=/dev/hvc0 ${KERNEL_CMDLINE}"
    QEMU_MONITOR=""
    QEMU_ARGUMENT+=" --nographic "

    # 直接加载内核（跳过 GRUB）
    QEMU_ARGUMENT+=" -kernel ../bin/kernel/kernel.elf -append \"${KERNEL_CMDLINE}\" "
fi
```

**关键点**:
- nographic 模式下，QEMU 直接加载 kernel.elf，不经过 GRUB
- 使用 virtio console (`/dev/hvc0`) 作为控制台输出
- 内核参数通过 `-append` 传递

#### 4.2.5 存储设备配置
**文件**: `tools/run-qemu.sh:156-166`

```bash
QEMU_DRIVE="id=disk,file=${QEMU_DISK_IMAGE},if=none"
QEMU_DEVICES_DISK="-device virtio-blk-pci,drive=disk \
                   -device pci-bridge,chassis_nr=1,id=pci.1 \
                   -device pcie-root-port "
```

**设备说明**:
- **virtio-blk-pci**: 高性能虚拟块设备
- **pci-bridge**: PCI 桥接设备
- **pcie-root-port**: PCIe 根端口

#### 4.2.6 网络设备配置
**文件**: `tools/run-qemu.sh:276`

```bash
QEMU_DEVICES+=" -netdev user,id=hostnet0,hostfwd=tcp::12580-:12580 \
                -device virtio-net-pci,vectors=5,netdev=hostnet0,id=net0 "
```

**网络配置**:
- **user 模式网络**: 无需 root 权限
- **端口转发**: 主机 12580 -> 虚拟机 12580
- **virtio-net-pci**: 高性能网络设备

#### 4.2.7 USB 配置
```bash
QEMU_DEVICES+=" -usb -device qemu-xhci,id=xhci,p2=8,p3=4 "
```

### 4.3 最终的 QEMU 命令

**文件**: `tools/run-qemu.sh:333-334`

```bash
sudo ${QEMU} ${QEMU_ARGUMENT}
```

完整的命令示例（展开后）：
```bash
sudo qemu-system-x86_64 \
  -machine q35,accel=kvm,memory-backend=dragonos-qemu-shm.ram \
  -enable-kvm \
  -cpu host,apic,x2apic,+fpu,check,+vmx \
  -m 1024M \
  -smp 2,cores=2,threads=1,sockets=1 \
  -object memory-backend-file,size=1024M,id=dragonos-qemu-shm.ram,mem-path=/dev/shm/dragonos-qemu-shm.ram,share=on \
  -drive id=disk,file=../bin/disk-image-x86_64.img,if=none \
  -device virtio-blk-pci,drive=disk \
  -netdev user,id=hostnet0,hostfwd=tcp::12580-:12580 \
  -device virtio-net-pci,vectors=5,netdev=hostnet0,id=net0 \
  -usb -device qemu-xhci,id=xhci,p2=8,p3=4 \
  --nographic \
  -serial chardev:mux -monitor chardev:mux \
  -chardev stdio,id=mux,mux=on,signal=off,logfile=../serial_opt.txt \
  -device virtio-serial -device virtconsole,chardev=mux \
  -kernel ../bin/kernel/kernel.elf \
  -append "console=/dev/hvc0 init=/bin/busybox init AUTO_TEST=none" \
  -s
```

**参数说明**:
- `-s`: 在 1234 端口开启 GDB 远程调试服务器
- `-append`: 传递给内核的命令行参数

---

## 5. GRUB 引导加载阶段

### 5.1 启动模式说明

DragonOS 支持两种启动模式：

1. **GRUB 模式**（`make run` 或 `make run-uefi`）
   - GRUB 读取 `/boot/grub/grub.cfg`
   - 使用 Multiboot2 协议加载内核

2. **直接内核启动模式**（`make run-nographic`）
   - QEMU 使用 `-kernel` 参数直接加载 kernel.elf
   - 跳过 GRUB，直接进入内核

### 5.2 Multiboot2 协议

**文件**: `kernel/src/arch/x86_64/asm/head.S:128-158`

```asm
.section .multiboot2_header
.align MULTIBOOT2_HEADER_ALIGN

multiboot2_header:
    .long MULTIBOOT2_HEADER_MAGIC      // 魔数: 0xe85250d6
    .long MULTIBOOT2_ARCHITECTURE_I386  // 架构: i386
    .long MB2_HEADER_LENGTH             // 头长度
    .long MB2_CHECKSUM                  // 校验和

// 帧缓冲区配置
framebuffer_tag_start:
    .short MULTIBOOT2_HEADER_TAG_FRAMEBUFFER
    .short MULTIBOOT2_HEADER_TAG_OPTIONAL
    .long framebuffer_tag_end - framebuffer_tag_start
    .long 1440   // 宽度
    .long 900    // 高度
    .long 32     // 色深
framebuffer_tag_end:

// 结束标记
    .short MULTIBOOT2_HEADER_TAG_END
    .short 0
    .long 8
multiboot2_header_end:
```

**Multiboot2 信息传递**:
- **EAX**: 魔数 `0x36d76289` (MULTIBOOT2_BOOTLOADER_MAGIC)
- **EBX**: Multiboot2 信息结构体的物理地址

---

## 6. 内核早期启动阶段

### 6.1 内核入口点 (_start)

**文件**: `kernel/src/arch/x86_64/asm/head.S:176-207`

```asm
.global _start
.type _start, @function
_start:
    cli                          // 关闭中断

    mov %ebx, mb_entry_info      // 保存 Multiboot 信息指针
    mov %eax, mb_entry_magic     // 保存魔数

    // 判断是 Multiboot 还是 Multiboot2
    mov $MULTIBOOT_BOOTLOADER_MAGIC, %ebx
    cmp %eax, %ebx
    je bl_magic_is_mb
    mov $MULTIBOOT2_BOOTLOADER_MAGIC, %ebx
    cmp %eax, %ebx
    je bl_magic_is_mb2
    jmp halt

bl_magic_is_mb2:
    mov $BOOT_ENTRY_TYPE_MULTIBOOT2, %ebx
    mov %ebx, boot_entry_type
    jmp protected_mode_setup
```

**当前状态**:
- **模式**: 32位保护模式
- **中断**: 已关闭
- **分页**: 未启用
- **特权级**: Ring 0

### 6.2 切换到长模式（64位）

**文件**: `kernel/src/arch/x86_64/asm/head.S:209-269`

```asm
protected_mode_setup:
    // 1. 启用 PAE（Physical Address Extension）
    mov %cr4, %eax
    or $(1<<5), %eax
    mov %eax, %cr4

    // 2. 设置临时页表（4级页表）
    // PML4 -> PDPT -> PD -> PT
    mov $pml4, %eax
    mov $pdpt, %ebx
    or $0x3, %ebx              // Present + Writable
    mov %ebx, 0(%eax)

    // ... (设置其他页表级别)

    // 3. 加载 CR3（页表基地址）
    mov $pml4, %eax
    mov %eax, %cr3

    // 4. 启用长模式
    mov $0xC0000080, %ecx      // IA32_EFER MSR
    rdmsr
    or $(1<<8), %eax           // 设置 LME (Long Mode Enable)
    wrmsr

    // 5. 启用分页
    mov %cr0, %eax
    or $(1<<31), %eax          // 设置 PG 位
    mov %eax, %cr0

    // 6. 加载临时 GDT
    mov $gdt64_pointer, %eax
    lgdt 0(%eax)

    // 7. 跳转到 64 位代码
    jmp $0x8, $ready_to_start_64
```

**页表映射**:
- 临时页表映射前 512 * 4KB = 2MB 物理内存
- 恒等映射（物理地址 = 虚拟地址）

### 6.3 64位模式初始化 (_start64)

**文件**: `kernel/src/arch/x86_64/asm/head.S:342-551`

```asm
_start64:
    // 初始化段寄存器
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %ss
    mov $0x7e00, %esp

    // 加载 GDTR 和 IDTR
    lgdt GDT_POINTER(%rip)
    lidt IDT_POINTER(%rip)

    // 判断是 BSP 还是 AP 处理器
    movq $0x1b, %rcx           // IA32_APIC_BASE MSR
    rdmsr
    bt $8, %rax                // 测试 BSP 标志位
    jnc load_apu_cr3           // AP 处理器跳转

    // BSP 处理器继续执行
    movq head_stack_start(%rip), %rsp

    // 设置新的页表（映射 100MB 内存）
    // PML4 -> PDPT -> PDE -> PT (50个页表)
    // ...

    // 加载 CR3
    movq $__PML4E, %rax
    movq %rax, %cr3
```

**新页表映射**:
- 映射物理内存 0-50MB
- 低地址和高地址（0xffff800000000000）双重映射
- 为内核的高地址运行做准备

### 6.4 设置中断描述符表（IDT）

**文件**: `kernel/src/arch/x86_64/asm/head.S:503-530`

```asm
setup_IDT:
    // 设置临时中断处理程序（ignore_int）
    leaq m_ignore_int(%rip), %rdx
    movq $(0x08 << 16), %rax   // 段选择子
    movw %dx, %ax

    movq $(0x8e00 << 32), %rcx // Type=1110 P=1 DPL=00
    addq %rcx, %rax

    // 填写 256 个中断描述符
    leaq IDT_Table(%rip), %rdi
    mov $256, %rcx

repeat_set_idt:
    movq %rax, (%rdi)
    movq %rdx, 8(%rdi)
    addq $0x10, %rdi
    dec %rcx
    jne repeat_set_idt
```

### 6.5 启用 FPU/SSE/AVX

**文件**: `kernel/src/arch/x86_64/asm/head.S:300-336`

```asm
ENABLE_FPU_SSE_XSAVE_XCR0:
    // 启用 x87 FPU + SSE
    movq %cr0, %rax
    and $0xFFFB, %ax           // 清除 CR0.EM
    or $0x2, %ax               // 设置 CR0.MP
    movq %rax, %cr0

    // 启用 OSFXSR 和 OSXMMEXCPT
    movq %cr4, %rax
    or $(3 << 9), %ax
    movq %rax, %cr4

    // 检测并启用 XSAVE/AVX
    mov $0x1, %eax
    cpuid
    bt $26, %ecx               // 检测 XSAVE 支持
    jnc .Lno_xsave

    // 启用 CR4.OSXSAVE
    movq %cr4, %rax
    or $(1 << 18), %rax
    movq %rax, %cr4

    // 设置 XCR0（扩展控制寄存器）
    mov $0x3, %eax             // x87 + SSE
    bt $28, %ecx               // 检测 AVX 支持
    jnc .Lxcr0_set
    mov $0x7, %eax             // x87 + SSE + AVX
.Lxcr0_set:
    xor %ecx, %ecx
    xor %edx, %edx
    xsetbv
```

### 6.6 跳转到 Rust 代码 (kernel_main)

**文件**: `kernel/src/arch/x86_64/asm/head.S:541-551`

```asm
    // 准备参数
    movq mb_entry_info, %rdi   // arg1: Multiboot 信息地址
    movq mb_entry_magic, %rsi  // arg2: Multiboot 魔数
    movq %r13, %rdx            // arg3: GDT 大小
    movq %r12, %r10            // arg4: IDT 大小
    movq boot_entry_type, %r8  // arg5: 启动类型

    // 跳转到 kernel_main
    lretq

go_to_kernel:
    .quad kernel_main
```

---

## 7. 内核初始化阶段

### 7.1 kernel_main 函数

**文件**: `kernel/src/arch/x86_64/init/mod.rs:44-76`

```rust
#[no_mangle]
unsafe extern "C" fn kernel_main(
    mb2_info: u64,
    mb2_magic: u64,
    bsp_gdt_size: u64,
    bsp_idt_size: u64,
    boot_entry_type: u64,
) -> ! {
    // 1. 重新加载 GDT 和 IDT（切换到高地址）
    let gdt_vaddr = MMArch::phys_2_virt(PhysAddr::new(&GDT_Table as *const usize as usize)).unwrap();
    let idt_vaddr = MMArch::phys_2_virt(PhysAddr::new(&IDT_Table as *const usize as usize)).unwrap();

    x86::dtables::lgdt(&gdtp);
    x86::dtables::lidt(&idtp);

    // 2. 早期启动初始化（解析 Multiboot 信息）
    early_boot_init(boot_entry_type, mb2_magic, mb2_info).unwrap();

    // 3. 进入通用内核初始化
    start_kernel();
}
```

### 7.2 early_boot_init - 解析启动信息

**文件**: `kernel/src/arch/x86_64/init/boot.rs:39-52`

```rust
pub(super) fn early_boot_init(
    boot_entry_type: u64,
    arg1: u64,
    arg2: u64,
) -> Result<(), SystemError> {
    let boot_protocol = BootProtocol::try_from(boot_entry_type)?;
    match boot_protocol {
        BootProtocol::Multiboot2 => early_multiboot2_init(arg1 as u32, arg2),
        BootProtocol::Linux32Pvh => early_linux32_pvh_init(arg2 as usize),
        _ => loop { spin_loop(); },
    }
}
```

**Multiboot2 信息解析** (`kernel/src/arch/x86_64/init/multiboot2.rs`):
- 内存映射信息
- 帧缓冲区信息
- 启动命令行参数
- ACPI RSDP 表地址
- ELF 符号表

### 7.3 start_kernel - 内核主初始化

**文件**: `kernel/src/init/init.rs:42-53`

```rust
pub fn start_kernel() -> ! {
    // 确保中断已关闭
    assert!(!CurrentIrqArch::is_irq_enabled());

    // 执行主初始化流程
    do_start_kernel();

    // 初始化调度器
    CurrentSchedArch::initial_setup_sched_local();
    CurrentSchedArch::enable_sched_local();

    // 进入 IDLE 循环
    ProcessManager::arch_idle_func();
}
```

### 7.4 do_start_kernel - 详细初始化流程

**文件**: `kernel/src/init/init.rs:56-109`

#### 7.4.1 内存初始化之前的准备

**函数**: `init_before_mem_init()` (init.rs:113-130)

```rust
fn init_before_mem_init() {
    // 1. 串口早期初始化（用于早期日志输出）
    serial_early_init().expect("serial early init failed");

    // 2. 视频初始化
    let video_ok = unsafe { VideoRefreshManager::video_init().is_ok() };
    scm_init(video_ok);

    // 3. 日志系统初始化
    early_init_logging();

    // 4. 架构相关早期初始化
    early_setup_arch().expect("setup_arch failed");

    // 5. 初始化内核命令行
    boot_callbacks()
        .init_kernel_cmdline()
        .ok();
    kenrel_cmdline_param_manager().early_init();
}
```

**early_setup_arch** (`kernel/src/arch/x86_64/init/mod.rs:79-101`):
```rust
pub fn early_setup_arch() -> Result<(), SystemError> {
    // 初始化 XSAVE 支持
    FpState::init_xsave_support();

    // 设置 TSS（任务状态段）
    set_current_core_tss(stack_start, 0);
    TSSManager::load_tr();

    // 初始化异常/中断处理
    arch_trap_init().expect("arch_trap_init failed");

    Ok(())
}
```

#### 7.4.2 打印内核版本信息

**函数**: `print_kernel_version()` (init.rs:133-154)

输出类似：
```
DragonOS release 0.1.10 version 0.1.10 (rustc) #abc123
build time: 2025-01-03 10:00:00 | git branch: master | ...
```

#### 7.4.3 内存管理初始化

**函数**: `mm_init()` (kernel/src/mm/init.rs)

```rust
unsafe fn mm_init() {
    // 1. 物理内存管理器初始化
    mm_early_init();

    // 2. 页表初始化
    page_init();

    // 3. 内核堆分配器初始化
    allocator_init();

    // 4. VMA（虚拟内存区域）管理器初始化
    vma_init();
}
```

**关键步骤**:
- **伙伴系统**: 管理物理页框
- **SLAB 分配器**: 小对象分配
- **vmalloc**: 虚拟内存分配
- **内核页表**: 重建完整的内核页表

#### 7.4.4 重新初始化屏幕管理器

```rust
if scm_reinit().is_ok() {
    if let Err(e) = textui_init() {
        warn!("Failed to init textui: {:?}", e);
    }
}
```

切换到高分辨率图形模式（如果可用）。

#### 7.4.5 内核命令行参数解析

```rust
kenrel_cmdline_param_manager().init();
```

解析从 GRUB 或 QEMU 传递的内核参数，例如：
- `init=/bin/busybox`
- `console=/dev/hvc0`
- `loglevel=7`

#### 7.4.6 系统调用初始化

```rust
syscall_init().expect("syscall init failed");
Syscall::init().expect("syscall init failed");
```

**系统调用表初始化**:
- 注册所有系统调用处理函数
- 设置 MSR (Model Specific Register) 用于 syscall/sysret 指令
- 初始化系统调用入口点

#### 7.4.7 虚拟文件系统（VFS）初始化

```rust
vfs_init().expect("vfs init failed");
```

**VFS 初始化**:
- 注册文件系统类型（ext4, fat32, devfs, procfs, sysfs 等）
- 挂载根文件系统
- 初始化 dcache（目录项缓存）
- 初始化 icache（inode 缓存）

#### 7.4.8 驱动初始化

```rust
driver_init().expect("driver init failed");
```

**驱动框架初始化**:
- **总线子系统**: PCI, USB, Platform 等
- **设备模型**: 设备树、设备注册
- **字符设备**: tty, console 等
- **块设备**: virtio-blk, ahci 等
- **网络设备**: virtio-net, e1000 等

#### 7.4.9 ACPI 初始化

```rust
acpi_init().expect("acpi init failed");
```

**ACPI 功能**:
- 解析 ACPI 表（RSDP, XSDT, MADT, HPET 等）
- 发现系统硬件配置
- 中断路由配置
- 电源管理功能

#### 7.4.10 调度器初始化

```rust
sched_init();
process_init();
```

**调度器组件**:
- **CFS 调度器**: 完全公平调度器
- **实时调度器**: FIFO 和 RR 调度
- **进程管理**: PCB、进程树
- **IDLE 进程**: 0号进程
- **INIT 进程**: 1号进程

#### 7.4.11 SMP（多核）初始化

```rust
early_smp_init().expect("early smp init failed");
setup_arch().expect("setup_arch failed");
CurrentSMPArch::prepare_cpus().expect("prepare_cpus failed");
```

**SMP 启动流程**:
1. 解析 ACPI MADT 表获取 CPU 信息
2. 设置 AP 处理器启动代码
3. 通过 APIC 发送 INIT-SIPI-SIPI 序列
4. AP 处理器启动并初始化
5. 同步所有 CPU

#### 7.4.12 中断子系统初始化

```rust
irq_init().expect("irq init failed");
softirq_init().expect("softirq init failed");
```

**中断处理**:
- **硬件中断**: 设置 APIC、中断控制器
- **软中断**: 定时器、网络、块设备等软中断
- **中断路由**: IRQ 到 CPU 的分配

#### 7.4.13 时间子系统初始化

```rust
timekeeping_init();
time_init();
timer_init();
```

**时间管理**:
- **时钟源**: TSC, HPET, ACPI PM Timer
- **Timekeeping**: 系统时间维护
- **定时器**: 高精度定时器、低精度定时器

#### 7.4.14 内核线程初始化

```rust
kthread_init();
```

创建内核线程：
- **kswapd**: 内存回收
- **events**: 工作队列
- **kthreadd**: 内核线程守护进程

#### 7.4.15 架构后期初始化

```rust
setup_arch_post().expect("setup_arch_post failed");
```

**x86_64 架构**:
```rust
pub fn setup_arch_post() -> Result<(), SystemError> {
    // 初始化 HPET 或 ACPI PM Timer
    let ret = hpet_init();
    if ret.is_ok() {
        hpet_instance().hpet_enable().expect("hpet enable failed");
    } else {
        init_acpi_pm_clocksource().expect("acpi_pm_timer inits failed");
    }

    // 初始化 TSC
    TSCManager::init().expect("tsc init failed");

    Ok(())
}
```

#### 7.4.16 其他子系统初始化

```rust
clocksource_boot_finish();  // 时钟源启动完成
Futex::init();              // Futex（快速用户空间互斥锁）
init_bpf_system();          // BPF（Berkeley Packet Filter）
static_keys_init();         // 静态键（代码热补丁）
```

### 7.5 调度器启动

**文件**: `kernel/src/init/init.rs:48-52`

```rust
// 初始化本地调度器
CurrentSchedArch::initial_setup_sched_local();

// 启用调度器
CurrentSchedArch::enable_sched_local();

// 进入 IDLE 循环
ProcessManager::arch_idle_func();
```

**arch_idle_func** 会：
1. 启用中断
2. 切换到 INIT 进程（PID 1）
3. 在没有可运行进程时，CPU 进入 HLT 状态

---

## 8. 进入用户空间

### 8.1 INIT 进程启动

**内核命令行参数**:
```
init=/bin/busybox init
```

**INIT 进程**:
- **PID**: 1
- **路径**: `/bin/busybox`
- **参数**: `init`
- **功能**: 启动用户空间服务和守护进程

### 8.2 用户空间初始化

Busybox init 会：
1. 解析 `/etc/inittab` 配置文件
2. 挂载 `/proc`, `/sys`, `/dev` 等文件系统
3. 启动系统服务
4. 启动登录终端

### 8.3 控制台输出

**virtio console 设备** (`/dev/hvc0`):
- 内核日志输出
- 用户程序输出
- 交互式 Shell

---

## 组件交互流程图

```
┌────────────────────────────────────────────────────────────────┐
│                     make run non-graphic                        │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   check_arch         │
            └──────────┬───────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   make kernel        │ ◄─── kernel/Makefile
            │   (编译内核)          │      kernel/src/Makefile
            └──────────┬───────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │ write_diskimage      │ ◄─── tools/write_disk_image.sh
            │ (准备磁盘镜像)        │      dadk 工具
            └──────────┬───────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   qemu-nographic     │ ◄─── tools/run-qemu.sh
            │   (启动 QEMU)        │
            └──────────┬───────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  QEMU 直接加载 kernel.elf    │
        │  (-kernel 参数)               │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   _start (32位保护模式)      │ ◄─── head.S:182
        │   - 保存 Multiboot 信息      │
        │   - 检查启动协议             │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  protected_mode_setup        │ ◄─── head.S:209
        │   - 启用 PAE                 │
        │   - 设置临时页表             │
        │   - 启用长模式               │
        │   - 启用分页                 │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  _start64 (64位长模式)       │ ◄─── head.S:345
        │   - 初始化段寄存器           │
        │   - 设置新页表               │
        │   - 设置 IDT                 │
        │   - 启用 FPU/SSE/AVX         │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   kernel_main (Rust)         │ ◄─── arch/x86_64/init/mod.rs:44
        │   - 重新加载 GDT/IDT         │
        │   - early_boot_init          │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   start_kernel               │ ◄─── init/init.rs:42
        │   - do_start_kernel()        │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   init_before_mem_init       │ ◄─── init/init.rs:113
        │   - 串口初始化               │
        │   - 视频初始化               │
        │   - 日志系统初始化           │
        │   - early_setup_arch         │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   mm_init                    │ ◄─── mm/init.rs
        │   - 物理内存管理             │
        │   - 页表初始化               │
        │   - 内核堆分配器             │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   子系统初始化               │
        │   - VFS                      │
        │   - 驱动                     │
        │   - ACPI                     │
        │   - 调度器                   │
        │   - SMP                      │
        │   - 中断                     │
        │   - 时间                     │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   启用调度器                 │
        │   - enable_sched_local       │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   IDLE 循环                  │
        │   - arch_idle_func           │
        │   - 切换到 INIT 进程         │
        └──────────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │   用户空间                   │
        │   - /bin/busybox init        │
        │   - 启动系统服务             │
        │   - 登录 Shell               │
        └──────────────────────────────┘
```

---

## 关键代码位置汇总

| 组件 | 文件路径 | 行号/函数 |
|------|---------|----------|
| **Make 入口** | `Makefile` | 179-183 |
| **内核编译** | `kernel/src/Makefile` | 50-51, 105-128 |
| **链接脚本** | `kernel/src/arch/x86_64/link.lds` | 1-135 |
| **磁盘镜像** | `tools/write_disk_image.sh` | 1-181 |
| **QEMU 启动** | `tools/run-qemu.sh` | 1-351 |
| **Multiboot2 头** | `kernel/src/arch/x86_64/asm/head.S` | 128-158 |
| **_start (32位)** | `kernel/src/arch/x86_64/asm/head.S` | 176-207 |
| **长模式切换** | `kernel/src/arch/x86_64/asm/head.S` | 209-269 |
| **_start64** | `kernel/src/arch/x86_64/asm/head.S` | 342-551 |
| **kernel_main** | `kernel/src/arch/x86_64/init/mod.rs` | 44-76 |
| **start_kernel** | `kernel/src/init/init.rs` | 42-53 |
| **do_start_kernel** | `kernel/src/init/init.rs` | 56-109 |
| **init_before_mem_init** | `kernel/src/init/init.rs` | 113-130 |
| **early_setup_arch** | `kernel/src/arch/x86_64/init/mod.rs` | 79-101 |
| **mm_init** | `kernel/src/mm/init.rs` | - |

---

## 启动时序图

```
时间轴 →

用户执行    编译         磁盘准备      QEMU启动       BIOS/固件     内核启动(汇编)          内核初始化(Rust)
  │           │             │             │              │               │                        │
  │ make run  │             │             │              │               │                        │
  │ non-      │             │             │              │              │                        │
  │ graphic   │             │             │              │               │                        │
  ├──────────►│             │             │              │               │                        │
  │           │ cargo build │             │              │               │                        │
  │           │ ld link     │             │              │               │                        │
  │           ├────────────►│             │              │               │                        │
  │           │             │ dadk create │              │               │                        │
  │           │             │ mount/copy  │              │               │                        │
  │           │             ├────────────►│              │               │                        │
  │           │             │             │ qemu-system- │               │                        │
  │           │             │             │ x86_64       │               │                        │
  │           │             │             ├─────────────►│               │                        │
  │           │             │             │              │ 加载          │                        │
  │           │             │             │              │ kernel.elf    │                        │
  │           │             │             │              ├──────────────►│ _start (32位)          │
  │           │             │             │              │               │ 切换长模式             │
  │           │             │             │              │               │ _start64 (64位)        │
  │           │             │             │              │               │ 设置页表/IDT           │
  │           │             │             │              │               ├───────────────────────►│ kernel_main
  │           │             │             │              │               │                        │ start_kernel
  │           │             │             │              │               │                        │ 早期初始化
  │           │             │             │              │               │                        │ mm_init
  │           │             │             │              │               │                        │ 子系统初始化
  │           │             │             │              │               │                        │ 启动调度器
  │           │             │             │              │               │                        │
  │           │             │             │              │               │                        │ IDLE 循环
  │           │             │             │              │               │                        │ ↓
  │           │             │             │              │               │                        │ INIT 进程
  │           │             │             │              │               │                        │ 用户空间

  0s          2s            3s            3.5s           4s              4.5s                     5s-10s
```

---

## 总结

DragonOS 的启动流程可以分为以下几个主要阶段：

1. **编译构建阶段**: 使用 Rust + Cargo 编译内核，通过链接脚本生成 ELF 文件
2. **镜像准备阶段**: 使用 DADK 工具创建磁盘镜像，拷贝内核和用户程序
3. **虚拟机启动阶段**: QEMU 直接加载内核 ELF（nographic 模式下）
4. **早期汇编启动**: 从 32 位保护模式切换到 64 位长模式，设置页表和中断
5. **Rust 初始化**: 内存管理、VFS、驱动、调度器等核心子系统初始化
6. **进入用户空间**: 启动 INIT 进程，进入用户态运行

整个流程充分利用了 Rust 的安全特性和现代操作系统设计理念，同时保留了必要的汇编代码用于底层硬件初始化。

---

## 附录：调试技巧

### A.1 使用 GDB 调试内核

```bash
# 终端 1: 启动 QEMU（带 GDB 服务器）
make run-nographic  # -s 参数已经包含在内

# 终端 2: 连接 GDB
make gdb
(gdb) break _start
(gdb) continue
```

### A.2 查看启动日志

```bash
# QEMU 串口日志
cat serial_opt.txt

# 内核日志（如果日志监控启动）
make log-monitor
```

### A.3 常用断点位置

```gdb
# 汇编启动阶段
break _start           # 32位入口
break _start64         # 64位入口
break kernel_main      # Rust 入口

# 初始化阶段
break start_kernel
break mm_init
break driver_init
break process_init
```

---

**文档版本**: 1.0
**最后更新**: 2025-01-03
**适用版本**: DragonOS master (commit: 3a5cf980)
