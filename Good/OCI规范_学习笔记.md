# OCI 开源容器标准学习笔记

> 基于博客《浅析开源容器标准——OCI》（cnblogs 张明成），结合你当前在研究的容器运行时 / faasd-in-rust 做的整理。

---

## 1. OCI 是什么？为什么会出现？

### 1.1 背景：Docker 火起来之后的问题

- 2013 年 Docker 开源，基于 Linux Namespace + cgroups 提供轻量级“容器化运行环境”，迅速成为事实标准。
- 2014 年开始：
  - 大量企业和开发者用 Docker 做开发 / 测试 / 部署；
  - Kubernetes 第一个 release 出来，容器编排开始爆发；
  - Docker Hub 提供了统一镜像仓库，生态进一步壮大。
- 问题也随之出现：
  - Docker 公司态度强势，希望 **自己主导** 容器生态；
  - Docker Runtime 向下兼容性差，社区对其“封闭性”和“变来变去”有抱怨；
  - 各大厂（Google、Microsoft 等）担心被单一厂商锁死，开始考虑“自己搞一套”。

Linux 基金会出面协调：

- 2015 年，在 DockerCon 上，Linux 基金会联合 Docker、Google、Amazon、Microsoft 等成立 **OCI（Open Container Initiative）**。
- Docker 把：
  - 自己的容器镜像格式草案；
  - 底层运行时代码（libcontainer）

  捐给 OCI，作为开放标准和参考实现的一部分。

> 关键点：Linux 内核里的 Namespace 和 cgroups 本来就不属于 Docker——任何人都可以基于它们做自己的 container runtime。OCI 的出现，是让生态 **在共同的标准上竞争实现**，而不是各玩各的私有格式。

### 1.2 OCI 的目标

OCI 的核心目标是：

- 定义一套 **开放的容器运行时规范**（Runtime Spec）
- 定义一套 **开放的容器镜像规范**（Image Spec）
- 确保：
  - 不同运行时之间的互操作性；
  - 容器可以在不同基础设施上“Build, Ship, and Run Anywhere”。

成果包括：

- `runtime-spec`：容器运行时规范
- `image-spec`：容器镜像规范
- 参考实现：
  - `runc`（runtime-spec 的官方实现）
  - `image-spec` 相关工具

---

## 2. OCI 的两大规范：Runtime & Image

OCI 主要有两块核心规范：

1. **Runtime Specification**（运行时规范）
2. **Image Specification**（镜像规范）

它们一起定义了：一个“标准容器”从磁盘到进程的完整路径。

### 2.1 Runtime Spec：容器“怎么跑”

#### 2.1.1 文件系统 Bundle（容器运行单元）

在 OCI 的视角下，运行一个容器需要先准备一个 **Bundle**，它是一个目录，包含：

- `config.json`：容器运行时配置（必须）
- 根文件系统目录：通常叫 `rootfs/`

Bundle 就是「容器运行的最小单元」，runtime（比如 runc）会：

- 读 `config.json`
- 用 `rootfs/` 作为容器的 root filesystem
- 按规范设置 namespace / cgroups / 挂载等，然后起进程

> 对应到你看过的 `faasd-in-rust`：它用 `oci_spec` 在内存里构造一个 Spec，对应的就是这里 `config.json` 的内容。

#### 2.1.2 容器的基本状态字段

Runtime Spec 定义了容器状态的标准字段（例如通过 `state` 命令输出）：

- `ociVersion`：当前使用的 OCI 规范版本
- `id`：容器 ID（同一主机必须唯一）
- `status`：容器状态
  - `creating`
  - `created`
  - `running`
  - `stopped`
- `pid`：容器进程的 PID
- `bundle`：该容器对应的 bundle 目录路径
- `annotations`：自定义键值对

示例：

```json
{
  "ociVersion": "0.2.0",
  "id": "oci-container1",
  "status": "running",
  "pid": 4422,
  "bundle": "/containers/redis",
  "annotations": {
    "myKey": "myValue"
  }
}
```

#### 2.1.3 生命周期与 Hooks

OCI 定义了容器从创建到删除的生命周期：

- `creating`
- `created`
- `running`
- `stopped`

并在 `start` 操作中预留了三类 Hook：

- `prestart`
  - 在容器命名空间已经创建、但用户进程尚未启动时调用
  - 如果失败，需要清理容器进程
- `poststart`
  - 在用户进程启动后、`start` 命令返回前调用
  - 可用于通知“容器已启动”
- `poststop`
  - 在容器被删除、但 `delete` 命令还未返回前调用

这些 Hook 提供了“在容器生命周期关键点插入自定义逻辑”的标准位置。

#### 2.1.4 配置内容（以 Linux 为例）

`config.json` 中主要围绕几个方面配置：

- 元数据：
  - `ociVersion`
  - `hostname`
  - `root.path`（rootfs 位置）及只读/读写
  - 用户信息（UID、GID）
- 资源隔离：namespaces
  - `pid` / `network` / `mount` / `ipc` / `uts` / `user` / `cgroup`
- 资源管理：
  - `rlimit`（文件描述符等）
  - cgroups 下 CPU、内存、blkio 等限制
- 挂载：
  - 一系列 `mounts`，包含 `source`、`destination` 等
- 用户进程配置：
  - `process`：环境变量、工作目录、启动命令、能力集(capabilities)、安全设置、OOM 行为等

这些字段和你在 `faasd-in-rust` 的 `spec.rs` 里看到的是一致的——那段代码本质上就是在程序里构造 `config.json` 的结构体版本。

#### 2.1.5 Namespace（资源隔离）

OCI Runtime Spec 对 Linux 支持的各类 namespace 做了统一抽象：

- `pid`：容器只能看到自己 namespace 内的进程
- `network`：容器拥有自己的网络栈
- `mount`：独立的挂载表
- `ipc`：独立的 IPC 资源
- `uts`：独立 hostname / domainname
- `user`：用户 / 组 ID 映射（主机 ↔ 容器）
- `cgroup`：独立的 cgroup 视图

在 `config.json` 中，这些以 `linux.namespaces` 数组形式存在，每一项指定类型和（可选的）path。

#### 2.1.6 Bundle 再理解

- Bundle = `config.json` + `rootfs/` 目录
- 是“容器运行所需的一切文件”的有组织集合
- 只要有一个符合 OCI spec 的 bundle，就可以用任意兼容的 runtime（runc、Kata、gVisor 等）来运行它。

### 2.2 Image Spec：镜像“长什么样”

Image Spec 主要定义三个层次：

- **filesystem layer**：镜像层（layers）如何序列化、存储和组合；
- **manifest**：描述“某个平台上的一个镜像”需要哪些 layer、用什么 config；
- **image index**：更高一层的抽象，用于表示一个镜像在多个平台（OS/arch）上的变种（类似 manifest list）。

关键点：

- 多层文件系统 + COW（Copy-on-Write）是容器“秒级启动”的基础：
  - 多个容器可以共享只读镜像层
  - 每个容器只在自己的可写层记录变更

Image Spec + Runtime Spec 组合起来，保证：

- 同一个镜像（符合 Image Spec）
- 在任意遵循 Runtime Spec 的 runtime 上
- 可以按同样的方式被解包并运行。

---

## 3. OCI 只管“低层运行时”，不管“高层编排”

文章中特别强调：

- OCI 关注的是 **低层运行时** 的标准化：
  - 要求 runtime 如何接受 bundle / config.json；
  - 定义生命周期操作：`create/start/kill/delete` 等；
  - 定义容器状态 / namespace / cgroups / rootfs 等抽象。
- 高层运行时（Docker、containerd、CRI-O 等）：
  - 在 OCI 之上构建自己的 API、镜像管理、网络 / 存储管理、编排接口等；
  - 可以自由定义“上层 UX”，只要在与 OCI runtime 对接时遵循规范即可。

> 换句话说：OCI 是“最低层的约定”，上层怎么玩都行，但底下要说同一种话。

这和你前面读的《浅析容器运行时》中“高层运行时 vs 低层运行时”的划分正好对应：

- 低层：runc / runv / runsc … → 对接 OCI Runtime Spec
- 高层：Docker / containerd / CRI-O … → 在上面做镜像生命周期、网络、编排等。

---

## 4. runc：OCI Runtime Spec 的参考实现

### 4.1 runc 的来源

- 最早 Docker 用的是自己的 `libcontainer` 作为容器引擎；
- 捐赠给 OCI 后，发展为独立的、标准化的运行时实现；
- `runc` 就是基于 `libcontainer` 演化来的官方参考实现：
  - 完全遵循 OCI Runtime Spec
  - 被 Docker（1.11+）、containerd 等作为底层组件使用

### 4.2 runc 提供的能力

从 `runc -h` 可以看到它的定位：

- “按 OCI 规范打包的应用” 的命令行运行工具；
- 支持容器的完整生命周期管理：
  - `create` / `start` / `run` / `kill` / `delete`
  - `pause` / `resume`
  - `checkpoint` / `restore`（配合 CRIU 做进程迁移）
  - `state` / `list` / `ps` / `events`
- 容器通过“bundle 目录”来描述自身（`config.json` + rootfs）。

一行概括：

> runc = “会读 bundle + config.json，并按 OCI Spec 把容器进程跑起来”的 CLI 工具。

### 4.3 典型使用流程（文章中的示例思路）

以运行一个容器为例，流程大致是：

1. 准备一个目录，比如 `/opt/runc-demo`
2. 在目录里执行：

   ```bash
   runc spec
   ```

   生成默认的 `config.json` 模板。

3. 修改 `config.json`：
   - 设置 rootfs
   - 设置 process.args（例如改成 `/usr/bin/cadvisor`）
   - 根据需要调整 namespace / cgroups / mounts 等

4. 准备 rootfs：
   - 可以从现有镜像导出，也可以手工构建一个最小文件系统

5. 运行：

   ```bash
   runc run <container-id>
   ```

   runc 会：
   - 读当前目录的 `config.json`
   - 用 rootfs 挂载好文件系统
   - 设置 namespace / cgroups
   - `exec` 用户配置的进程

对你现在在看 `faasd-in-rust` 的工作而言：

- `faasd-in-rust` 里的 `Spec` 构造 + snapshot 准备 + 调 containerd，其实就是**在程序里替你完成了「runc 读 bundle + 起容器」这一步**。

---

## 5. 这篇文章的价值 & 与你当前工作的联系

### 5.1 文章的主线价值

- 给出了 OCI 产生的背景：从 Docker 独大到多家协作的标准化过程；
- 解构了容器规范中的「运行时」与「镜像」两个维度；
- 澄清了：
  - OCI 只规范低层 runtime，不管高层编排；
  - runc 是 runtime-spec 的参考实现，而不是 Docker 专属；
- 提供了将来你在阅读 containerd / runc 源码时的重要“坐标系”。

### 5.2 和你在看的 faasd-in-rust / 容器运行时的联系

你刚才已经在啃 `faasd-in-rust`：

- 里面用 `oci_spec` 生成的 `Spec`，本质就是 `config.json` 的结构体版；
- `prepare_snapshot + rootfs` 对应的是 OCI Bundle 中的 `rootfs`；
- containerd + runc 的组合，就是“高层 runtime + 低层 runtime 按 OCI 协议合作”的实例。

读完这篇 OCI 文章之后：

- 之前你在 `faasd-in-rust` 代码里看到的各个字段（namespaces、cgroups_path、mounts 等）会更有“语义感”；
- 以后如果你想写一个自己的 runtime，或者想扩展现有 runtime 的行为，可以直接对照 OCI 规范来设计：
  - 需要支持哪些 lifecycle 操作？
  - config.json 里哪个字段对你关心的场景最关键？

---

## 6. 一句话收尾

> OCI 让“容器”从某个厂商（Docker）的实现，变成了整个行业共同遵守的一组协议；runc 和 containerd 则是这套协议在工程世界里的典型落地。你现在在读的 faasd-in-rust，就是在这条标准化链路上的一个「高层 runtime + 调用 OCI runtime」的具体案例。