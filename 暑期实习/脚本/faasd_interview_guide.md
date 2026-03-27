# faasd-in-rust 面试讲义

## 1. 30 秒总述

我在 `faasd-in-rust` 里做的不是单点接口，而是把一个轻量级 FaaS 平台最关键的两条链路打通：一条是执行闭环，也就是镜像准备、容器创建、CNI 网络、overlay snapshot、task 启动和失败回滚；另一条是访问控制闭环，也就是注册登录、密码哈希、JWT 签发校验和 Bearer 路由保护。

这个项目最想证明的能力不是“我会调 containerd”或者“我会写 JWT”，而是我能把跨组件的执行链路做成异常可控、把运行时隔离边界固化下来，并把访问控制前置到网关入口，让系统达到可部署、可回滚、可隔离、可鉴权的最小可运行闭环。

---

## 2. 3 分钟源码主线

我一般先从执行链路讲起，因为这条链最能体现平台工程能力。部署入口在 `faasd-in-rust/crates/faas-containerd/src/provider/function/deploy.rs:9` 的 `_deploy()`。它不是简单调用 containerd 创建容器，而是按步骤推进：先 `prepare_image` 拉取或准备镜像，再 `create_container` 创建容器元数据，然后创建 CNI 网络和 netns，接着 `prepare_snapshot` 准备 rootfs，最后 `new_task` 拉起任务。这个顺序在 `deploy.rs:13-58` 很清楚。

真正有工程含量的点是失败回滚。部署过程中每成功一步，都会立即注册对应的 `scopeguard` 清理动作：容器创建后注册 `delete_container`，网络创建后注册删除 netns，snapshot 准备后注册 `remove_snapshot`，task 创建后注册 `kill_task_with_timeout`。如果后续任一步失败，前面已经成功的资源会按 best-effort 方式自动回收；只有整条链成功，才通过 `ScopeGuard::into_inner()` 释放 defer，不再回滚。这部分核心在 `deploy.rs:32-63` 和 `deploy.rs:88-92`。

然后我会讲运行时隔离。OCI 运行配置生成在 `faasd-in-rust/crates/faas-containerd/src/impls/spec.rs:23-222`。这里我做的是“最小可运行安全基线”：`rootfs` 只读、`no_new_privileges=true`、显式 capabilities、masked/readonly paths、有限的 `rlimit`，并且通过 5 类 namespace 做隔离：PID、IPC、UTS、Mount 和 Network。其中 network namespace 会绑到 `/var/run/netns/<endpoint>`，对应 `spec.rs:110-132`。这说明隔离不是口头约束，而是直接固化进 OCI spec。

网络侧的实现我放在 `faasd-in-rust/crates/faas-containerd/src/impls/cni/cni_impl.rs:21-104`。这里会初始化默认网络配置，默认是 `bridge + host-local + firewall` 这一套，bridge 名是 `faasrs0`，子网是 `10.66.0.0/16`。真正创建函数网络时，会先新建独立 netns，再调用 CNI bridge 插件拿 IP，成功后把 netns 返回给上层链路，失败则通过 guard 自动删除 netns。这样每个函数实例都拿到独立 network namespace，而不是共享宿主网络。

另一条主线是访问控制闭环。网关路由配置在 `faasd-in-rust/crates/gateway/src/bootstrap/mod.rs:20-97`。这里 `/auth/register` 和 `/auth/login` 是开放入口，而 `/system/*` 和 `/function/*` 则统一挂上 `HttpAuthentication::bearer(protected_endpoint)`。也就是说，核心系统路由默认在网关入口做 Bearer 拦截，而不是把鉴权下放给后面的业务处理器。

Bearer 校验本身在 `faasd-in-rust/crates/gateway/src/oauth/auth_handler.rs:114-139`。中间件会提取 token，调用 `validate_access_token()` 做 JWT 校验，验证通过后把 claims 注入请求扩展；如果 token 过期、无效或格式不对，则明确返回 Unauthorized，而不是把鉴权失败混成通用 500。JWT 的签发和校验逻辑在 `faasd-in-rust/crates/gateway/src/oauth/jwt_utils.rs:16-57`，默认是 HS256，对 access token 设置过期时间和 leeway。

用户数据和密码处理构成了访问控制链的底层支撑。密码在 `faasd-in-rust/crates/gateway/src/oauth/services.rs:11-85` 用 Argon2id 做哈希和校验；数据库连接池在 `faasd-in-rust/crates/gateway/src/models/db.rs:8-20` 通过 `diesel-async + bb8` 创建；用户 DAO 和模型在 `faasd-in-rust/crates/gateway/src/models/mod.rs:15-119`，支持按用户名查询、插入用户、更新用户名和删除用户。这样从注册登录，到 token 签发，再到受保护路由访问，形成了完整闭环。

---

## 3. 讲解目录

### 3.1 整体顺序

建议固定按下面 6 段讲：

1. 先定义这个平台到底解决什么问题
2. 先走执行链路：镜像、容器、网络、snapshot、task
3. 再讲为什么要用 `scopeguard` 把部署做成可回滚流程
4. 再讲运行时隔离：OCI spec + namespace + CNI
5. 再讲访问控制闭环：注册登录、JWT、Bearer 路由保护、DAO
6. 最后主动说明边界：当前是最小可运行闭环，不是生产化全量能力

### 3.2 主调用链

固定按这条主线讲：

`prepare_image`
→ `create_container`
→ `create_cni_network`
→ `prepare_snapshot`
→ `new_task`
→ `scopeguard rollback`
→ `bootstrap` 路由挂载
→ `/auth/register|login`
→ `generate_access_token` / `validate_access_token`
→ `Bearer` 保护 `/system`、`/function`

---

## 4. 四个关键分叉

### 4.1 为什么部署链路必须做成“步骤级回滚”

核心结论：函数部署是多步骤跨组件流程，任何一步失败都可能留下脏容器、脏 snapshot 或脏 netns。这个问题不能靠“人工清理”兜底，所以我把部署设计成 best-effort 事务：每成功一步就注册对应清理动作，只有全链成功才取消回滚。

源码锚点：
- `crates/faas-containerd/src/provider/function/deploy.rs:13-24`
- `crates/faas-containerd/src/provider/function/deploy.rs:32-63`
- `crates/faas-containerd/src/provider/function/deploy.rs:88-92`

### 4.2 为什么隔离基线要先落在 OCI spec 上

核心结论：平台隔离不能靠约定，必须固化成 runtime spec。把 rootfs 只读、`no_new_privileges`、capabilities、masked/readonly paths 和 namespace 都写进 OCI 配置后，容器隔离才是默认行为，而不是“调用方记得配”。

源码锚点：
- `crates/faas-containerd/src/impls/spec.rs:44-76`
- `crates/faas-containerd/src/impls/spec.rs:77-134`
- `crates/faas-containerd/src/impls/spec.rs:136-214`

### 4.3 为什么网络选 `bridge + host-local + firewall`

核心结论：这是单机场景下最务实的最小可用方案。它足够简单、可调试、可维护，同时又能把每个函数放进独立 netns，形成明确的网络边界。先把最小可运行链路做稳，再考虑更复杂的网络方案。

源码锚点：
- `crates/faas-containerd/src/impls/cni/cni_impl.rs:11-20`
- `crates/faas-containerd/src/impls/cni/cni_impl.rs:21-30`
- `crates/faas-containerd/src/impls/cni/cni_impl.rs:38-104`

### 4.4 为什么访问控制要前置到网关入口

核心结论：如果把鉴权放到下游函数或业务路由里，各个服务都会各写一套校验逻辑，既不一致也容易漏。把 JWT/Bearer 校验统一放在网关入口，才能保证系统路由默认受保护，未鉴权流量不会直接打到核心接口。

源码锚点：
- `crates/gateway/src/bootstrap/mod.rs:36-93`
- `crates/gateway/src/oauth/auth_handler.rs:114-139`
- `crates/gateway/src/oauth/jwt_utils.rs:16-57`

---

## 5. 高频追问与参考答案

### Q1. 你做的 faasd 项目最看重什么产出？

**短答：** 我最看重两条闭环：执行闭环和访问控制闭环。

**展开：** 执行闭环是镜像准备、容器创建、网络接入、snapshot、task 启动和失败回滚；访问控制闭环是注册登录、密码哈希、JWT 签发校验和 Bearer 路由保护。没有闭环，平台只是功能点堆砌，不是可运行系统。

### Q2. 为什么部署链路一定要做回滚？

**短答：** 因为部署是跨 containerd、CNI、snapshot 和 task 的多步骤流程，任一步失败都会留下脏资源。

**展开：** 如果 image 已经准备好、容器创建了、netns 也建好了，但 snapshot 或 task 创建失败，系统里就会残留半创建资源。长远看这会拖垮稳定性和可维护性，所以我用 `scopeguard` 做步骤级 defer 清理，让失败自动回收已成功创建的资源。

### Q3. 为什么不用“强事务”，而是 best-effort rollback？

**短答：** 因为这些外部组件本身不提供统一事务边界，工程上最现实的是步骤级补偿。

**展开：** containerd、CNI 和 snapshotter 分属不同组件，无法像数据库一样给我一个原子提交接口。所以我的选择不是伪造强事务，而是每一步成功后立即记录补偿动作，失败后按逆序清理，保证系统尽量回到一致状态。

### Q4. 你说的运行时隔离，具体是哪些？

**短答：** rootfs 只读、`no_new_privileges`、显式 capabilities、敏感路径只读/屏蔽，以及 5 类 Linux namespace。

**展开：** 在 OCI spec 里我把这些隔离基线都固化了：rootfs 只读，关掉特权升级，限制 capabilities，屏蔽 `/proc/kcore`、`/sys/firmware` 这类敏感路径，并使用 PID/IPC/UTS/Mount/Network 五类 namespace。这样平台默认就是一个受限运行环境。

### Q5. 为什么网络选 `bridge + host-local + firewall`？

**短答：** 因为这是单机场景下成本最低、最容易维护的最小可用网络方案。

**展开：** 它足够简单，排障也容易，而且能满足函数独立 netns、IP 分配和基本流量控制的需求。对于一个轻量级 FaaS 平台，先把网络模型做稳，比一开始追求复杂网络能力更重要。

### Q6. 为什么要单独给每个函数创建 netns？

**短答：** 因为网络隔离必须落到实例粒度，而不是共享宿主网络。

**展开：** `create_cni_network()` 会先创建独立 netns，再调用 CNI bridge 插件分配 IP，成功后把 netns 交给 OCI spec 中的 network namespace 使用。这样每个函数实例都有清晰的网络边界，避免端口、路由和流量互相污染。

### Q7. 访问控制为什么要放在网关，而不是交给下游服务？

**短答：** 因为入口统一鉴权才能保证系统路由默认受保护。

**展开：** 我把 `/system/*` 和 `/function/*` 全挂在 Bearer 中间件后面，网关统一提取 token、做 JWT 校验并注入 claims。这样未鉴权请求根本进不到核心系统接口，不需要每个下游 handler 重复写一套鉴权逻辑。

### Q8. JWT 这条链在你这里具体怎么闭环？

**短答：** 注册登录拿到用户身份，签发 access token，请求进来时再通过 Bearer 中间件校验并注入 claims。

**展开：** 注册/登录 handler 负责建立用户和签发 token；`jwt_utils` 负责 `generate_access_token()` 和 `validate_access_token()`；`protected_endpoint()` 负责提取 Bearer token，校验通过后把 claims 注入请求扩展；路由层再统一把系统接口挂在这个中间件之后。这就是完整访问控制闭环。

### Q9. 为什么选 Argon2 + Diesel + bb8 这套？

**短答：** 因为它分别解决密码安全、类型安全数据库访问和异步连接管理。

**展开：** Argon2id 用于密码哈希和校验，避免明文密码和弱哈希；Diesel 保证查询构造的类型安全；`diesel-async + bb8` 让数据库访问可以在 async runtime 下稳定工作，不会把数据库 IO 粗暴塞进同步路径。

### Q10. 这个项目的边界在哪里？

**短答：** 当前已经有最小可运行闭环，但还不是完整生产化平台。

**展开：** 仓库里已经能证明执行链路和鉴权链路都打通了，但像 token 刷新/撤销、细粒度 RBAC、密钥轮换、审计、更多运行时策略和更复杂网络模型，都还是后续生产化增强项。我会主动把这个边界讲清楚。

---

## 6. 临场短答卡片

### 1. 这个项目最看重什么产出？
- **10 秒答法：** 两条闭环：执行闭环和访问控制闭环。
- **30 秒答法：** 执行闭环保证函数可部署、可启动、失败可回滚；访问控制闭环保证用户可注册登录、token 可签发校验、系统路由默认受保护。两条闭环一起成立，平台才算可用。
- **收束金句：** 我做的不是单点功能，而是把平台最关键的两条链路闭合了。

### 2. 为什么部署链路必须做回滚？
- **10 秒答法：** 因为部署跨多个组件，失败会留下脏资源。
- **30 秒答法：** image、container、netns、snapshot、task 是逐步创建的，任一步失败都可能让系统残留半创建状态。`scopeguard` 的价值是把每一步成功后的补偿动作立刻注册进去，让异常自动收敛。
- **收束金句：** 平台可维护性的关键，不是成功路径多顺，而是失败路径能不能自己收场。

### 3. 为什么用 best-effort rollback，而不是强事务？
- **10 秒答法：** 因为 containerd、CNI、snapshot 本身没有统一事务边界。
- **30 秒答法：** 外部系统之间没法像数据库那样原子提交，所以工程上更现实的是补偿式事务：每一步成功就注册反向清理动作，失败按逆序回收，尽量恢复系统一致性。
- **收束金句：** 跨组件系统里，最务实的事务模型往往是补偿，而不是强原子性。

### 4. 运行时隔离具体做了什么？
- **10 秒答法：** rootfs 只读、`no_new_privileges`、显式 capabilities、敏感路径只读/屏蔽、5 类 namespace。
- **30 秒答法：** 我把这些隔离策略都固化到 OCI spec：rootfs 只读、限制 capabilities、关掉特权升级、设置 masked/readonly paths，并使用 PID/IPC/UTS/Mount/Network 五类 namespace，确保函数运行环境默认受限。
- **收束金句：** 隔离边界只有写进 runtime spec，才算真正落地。

### 5. 为什么网络方案选 `bridge + host-local + firewall`？
- **10 秒答法：** 因为这是单机场景下最简单、最稳的最小可用方案。
- **30 秒答法：** 它足够简单，排障容易，又能满足独立 netns、IP 分配和基本流量控制的需求。对轻量 FaaS 来说，先把网络主链做稳，比一开始追求复杂方案更重要。
- **收束金句：** 网络方案的第一目标不是炫技，而是稳定、可调试、可维护。

### 6. 为什么要单独创建 netns？
- **10 秒答法：** 因为每个函数实例都需要独立网络边界。
- **30 秒答法：** `create_cni_network()` 会先创建 netns，再调用 CNI bridge 插件拿 IP，成功后把这个 netns 交给 OCI spec 使用。这样每个函数实例都不是跑在宿主网络里，而是有自己独立的网络上下文。
- **收束金句：** 网络隔离只有落到实例粒度，才真正有平台意义。

### 7. 为什么访问控制要放在网关入口？
- **10 秒答法：** 因为入口统一鉴权才能保证系统路由默认受保护。
- **30 秒答法：** 我把 `/system` 和 `/function` 路由统一挂在 Bearer 中间件后面，让网关负责 token 提取、JWT 校验和 claims 注入。这样未鉴权流量不会直接打到核心接口，也避免各个服务重复写鉴权逻辑。
- **收束金句：** 访问控制前置到网关，本质是在系统边界上做统一防线。

### 8. 这条 JWT 链具体怎么闭环？
- **10 秒答法：** 注册登录拿身份，签发 token，请求进来再统一校验 token。
- **30 秒答法：** 注册/登录 handler 先建立用户身份，`jwt_utils` 负责签发和校验 access token，Bearer 中间件负责从请求里提取 token、验证并把 claims 注入请求上下文，受保护路由只接收已通过校验的请求。
- **收束金句：** JWT 不是一个库函数，而是一条从身份建立到路由保护的完整链路。

### 9. 为什么选 Argon2 + Diesel + bb8？
- **10 秒答法：** 因为它们分别解决密码安全、类型安全数据库访问和异步连接管理。
- **30 秒答法：** Argon2id 负责现代密码哈希，Diesel 提供类型安全的 ORM 能力，`diesel-async + bb8` 提供异步连接池，把数据库访问接进 Actix 的 async 模型里。这套组合能比较稳地支撑认证链路。
- **收束金句：** 技术选型不是堆名词，而是让每一层都解决一个明确问题。

### 10. 你怎么主动说明边界？
- **10 秒答法：** 我会明确说当前已经有最小可运行闭环，但还不是全量生产化能力。
- **30 秒答法：** 我会先确认执行链路和鉴权链路都已经落地，再主动说明像 refresh token、撤销、RBAC、密钥轮换、审计和更复杂网络策略还属于后续增强。这样既不虚报，也能体现我对系统成熟度的判断。
- **收束金句：** 好的工程表达，不只是讲做到了什么，也要讲清楚还没做到什么。

---

## 7. 高频金句

1. 我做的不是单点功能，而是把平台最关键的两条链路闭合了。
2. 平台可维护性的关键，不是成功路径多顺，而是失败路径能不能自己收场。
3. 跨组件系统里，最务实的事务模型往往是补偿，而不是强原子性。
4. 隔离边界只有写进 runtime spec，才算真正落地。
5. 网络方案的第一目标不是炫技，而是稳定、可调试、可维护。
6. 访问控制前置到网关，本质是在系统边界上做统一防线。
7. JWT 不是一个库函数，而是一条从身份建立到路由保护的完整链路。
8. 好的工程表达，不只是讲做到了什么，也要讲清楚还没做到什么。

---

## 8. 最后 1 分钟收束陈词

如果让我总结这个项目，我最想强调的是“可控性工程化”。执行路径上，我不是只把函数跑起来，而是把镜像、容器、网络、snapshot、task 这些跨组件步骤做成了异常可收敛的部署链路；隔离路径上，我把 OCI 运行规范和 CNI/netns 结合起来，先落地最小可运行安全基线；访问路径上，我把注册登录、密码哈希、JWT 校验和 Bearer 路由保护前置到网关边界，形成统一入口控制。

所以这个项目最能说明我的，不是会不会调某个库，而是我能把执行、隔离和访问控制三条线同时拉通，并且主动说明系统边界：当前已经形成最小可运行闭环，但仍然为后续的生产化增强留出了清晰演进空间。

---

## 9. 测试与证据锚点

- 执行链路与回滚：
  - `crates/faas-containerd/src/provider/function/deploy.rs`
- OCI 运行时隔离：
  - `crates/faas-containerd/src/impls/spec.rs`
- CNI 网络与 netns：
  - `crates/faas-containerd/src/impls/cni/cni_impl.rs`
- 网关入口路由保护：
  - `crates/gateway/src/bootstrap/mod.rs`
- JWT 签发与校验：
  - `crates/gateway/src/oauth/jwt_utils.rs`
- 注册登录与 Bearer 中间件：
  - `crates/gateway/src/oauth/auth_handler.rs`
- 密码哈希与用户服务：
  - `crates/gateway/src/oauth/services.rs`
- DAO 与数据库模型：
  - `crates/gateway/src/models/{db.rs,mod.rs}`
