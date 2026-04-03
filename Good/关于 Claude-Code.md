### query.ts
整个系统的心脏 ，负责处理上下文工具，压缩和api调用 
agenttool递归调用query.ts 本质上是一个新的query loop 示例 ，拥有自己的 独立上下文窗口和工具集
### utils 
有权限系统，bash 安全检查， 模型管理， bash解析器，文件历史，session存储
### ui
