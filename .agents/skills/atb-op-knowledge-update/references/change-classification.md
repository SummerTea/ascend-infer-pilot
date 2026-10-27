# 变更分类矩阵（Step 3-4）

## 11 种变更模式 → 受影响章节

| # | 变更模式 | 示例 | 受影响章节 | 重提取策略 |
|---|---------|------|-----------|-----------|
| 1 | param struct 增删字段 | `infer_op_params.h` 新增成员 | §3 Params + §4 Pipeline | 全量重提取 §3-4 |
| 2 | enum 值增删 | KernelType 新增枚举 | §3 Params + §4 Pipeline + §5 Exec | 重提取 §3-5 |
| 3 | InferShape dtype 修改 | `outTensorDescs.dtype` 变更 | §4 Pipeline | 重提取 §4 |
| 4 | CreateRunner 逻辑变更 | 新增平台判断分支 | §5 Execution Paths | 重提取 §5 |
| 5 | ACLNN API 升级 | `aclnnXxx` → `aclnnXxxV2` | §5 Exec + §6 Kernel | 重提取 §5-6 |
| 6 | Kernel 模板/Tiling 变更 | `*_tiling.h` 修改 | §6 Kernel Deps | 重提取 §6 |
| 7 | 错误处理变更 | 新增 ATB_LOG(ERROR) | §7 Known Issues | 重提取 §7 |
| 8 | 常量/对齐变更 | ALIGNMENT 修改 | §3 Params + §6 Tiling | 重提取 §3, §6 |
| 9 | 新增/删除 Runner 文件 | 新增 `*_runner_910c.cpp` | §1 Source Map + §5 Exec | 重提取 §1, §5 |
| 10 | 平台适配新增 | 新增 BNSD/910C 支持 | §5 Exec + §1 Source Map | 重提取 §1, §5 |
| 11 | include 依赖变更 | 新增/删除 #include | §1 Source Map | 重提取 §1 |

## 变更检测优先级

```
param struct 变更 > InferShape dtype 变更 > CreateRunner 变更 > 文件增删 > 常量修改
     ▲                  ▲                    ▲               ▲            ▲
   立即全量            仅Pipeline          仅Exec路径       SourceMap    约束表
```

## 增量重提取 vs 全量重提取

| 策略 | 触发条件 | 操作 |
|------|---------|------|
| 增量 | 单文件变更，明确章节映射 | 仅重提取受影响章节 |
| 全量 | 共享文件变更 (laser_attention, norm/) | 重提取所有关联 Op 的全部 9 章节 |
| 保守 | 不确定影响范围 | 全量重提取（不误更、不漏更） |
