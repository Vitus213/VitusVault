#let cv-color = rgb("#284967")
#set page(margin: (x: 0.9cm, y: 1.0cm))
#set text(
  font: "Source Han Sans SC",
  lang: "zh",
  size: 10pt,
  weight: "medium",
)
#set par(justify: true,leading: 0.8em)
#let chiline = {
  v(-8pt)
  line(stroke: cv-color, length: 100%)
  v(-2pt)
}
#show "|": text(gray, " | ")
#show link: underline
#show heading.where(level: 1): it => text(fill: rgb("#222222"), weight: "semibold", size: 20pt, it) + v(5pt)
#show heading.where(level: 2): it => text(cv-color, weight: "semibold", it) + chiline
#let item(a, b, c) = grid(
  columns: (25%, 1fr, 25%),
  align: (left, center, right),
  text(fill: rgb("#222222"), weight: "semibold", a),
  text(rgb("#222222"), b),
  text(rgb("#222222"), c),
)
#let item2(a, b) = grid(
  columns: (20%, 100%),
  align: (left, center, right),
  text(fill: rgb("#222222"), weight: "semibold", a), text(rgb("#222222"), b),
)
#let project-item(title, date) = grid(
  columns: (1fr, auto),
  column-gutter: 0.8em,
  align: (left, right),
  text(fill: rgb("#222222"), weight: "semibold", title),
  text(fill: rgb("#222222"), date),
)

// -------------------------------------------------------------------
// 个人简历正文
// -------------------------------------------------------------------


#grid(
  columns: (1fr, auto),
  align(center)[
    = 张辉洲
    #set text(rgb("#333333"))

    软件工程 | 系统编程 | 算法竞赛

    13430291898 | https://vituss.me | 2811215248\@qq.com
  ],
  image(width: 50pt, "avatar.png"),
)

#set text(rgb("#444444"))

== 教育背景

#item()[华南理工大学][软件工程（本科）][2023年9月 \~ 至今]



== 项目经历

#project-item[DragonOS 开源社区 / 内核开发][2025.11 — 至今]
*项目概述：* DragonOS 是以 Rust 自研、追求 Linux 兼容性的操作系统。我在社区内主导内核关键子系统建设，围绕块设备、资源控制与系统调用语义，驱动“可兼容、可恢复、可验证”的工程闭环。
- *Loop 设备子系统：* 设计 #strong[/dev/loop-control + /dev/loopX] 架构与 #strong[LoopManager]，用状态机 + #strong[IoGuard] 计数守护并发删除，并通过快照式的 #strong[LOOP_SET/GET_STATUS64] 实现可回滚删除与 Linux ioctl 兼容。
- *cgroup v2：* 建立 #strong[CgroupRoot/CgroupNode] 树模型和 PCB #strong[task_cgroup] 生命周期，保证进程从出生开始就放进指定资源控制树中，实现租户路径隔离、#strong[cgroup.procs] 线程组迁移与 #strong[pids.max] 配额检查。
- *Nix 配置与 Bug Hunter Skill：* 增强 Nix/QEMU/syscall 测试链路，统一 Rust toolchain、QEMU 启动与 c_unitest 打包；实现“Bug Hunter” Skill，形成标准化寻 Bug 流程。
#project-item[DragonOS 开源社区 / Serverless 容器平台][2025.04 — 2025.06]
*项目概述：* faasd-in-rust 是一个以 Rust 作为开发语言、containerd 作为容器管理工具实现的轻量级 FaaS Serverless 平台，支持容器创建、删除与认证鉴权等常见接口。
- *部署链路与回滚：* 实现镜像准备、CNI 网络命名空间分发、#strong[overlay snapshots] 写时复制的完整镜像启动流程，并用 #strong[scopeguard] 回滚，保障部署失败可恢复。
- *运行时隔离：* 基于 #strong[OCI spec] 生成运行配置，落实默认隔离基线，并接入 #strong[CNI bridge/host-local/firewall] 构建容器网络。
- *访问控制与数据层：* 实现 认证注册路由、JWT 与 Bearer 中间件，结合数据库 DAO 层完成用户存储与受保护路由闭环。

== 专业技能
- *编程语言：* 了解 Rust 系统编程、所有权/RAII、Trait 抽象、错误处理与并发资源管理；了解 C++ 基础、结构体、STL/智能指针。
- *操作系统与系统编程：* 掌握进程、线程、锁与原子操作；熟悉 cgroup 资源隔离机制；了解类 Linux 文件系统和块设备。
- *云原生与容器：* 了解 Docker 使用，了解容器网络和容器文件系统。
- *计算机网络：* 了解 TCP/IP 网络，掌握 HTTP 协议基本原理。
- *工程工具与协作：* 掌握 Git 协作、日志定位与多人开源协作。
- *AI：* 掌握 AI 辅助开发、Agent 编排、MCP 与 CLI 使用，了解 Skill 调优。



== 曾获荣誉
#item[2024年10月][2024 ICPC 亚洲成都区域赛][铜奖]
#item[2025年12月][开放原子开源基金会开源贡献奖金][获奖]
#item[2024年5月][第二十一届广东省大学生程序设计竞赛][银奖]
