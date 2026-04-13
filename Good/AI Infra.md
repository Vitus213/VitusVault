# AI Infra软硬件定义 

计算资源管理：高效调度GPU K8s,Slurm

分布式框架：万卡同时工作 PyTorch DeepSpeed

存储:训练数据PB

推理加速：TensorRT ,vLLM

## 软件层



- Maas：存储，管理预训练模型 ，微调模型 ，提供接口
- SaaS：推理服务，解决算力不足问题 
- PaaS：AI模型开发的技术基座，底层算子加速库，优化矩阵运算，卷积
- IaaS：聚焦资源落地 