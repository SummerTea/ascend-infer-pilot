# 绑定模式说明

## SVector 字段

`SVector<T>` 字段生成 `def_property` + getter/setter，通过 `AddElements` 与 `std::vector<T>` 互转。

**注意**：`field_overrides` 中 `svector_property_only` 的字段不要同时生成 `def_readwrite`。

## 特殊 init 模式

| 算子 | init_style | 说明 |
|------|-----------|------|
| `SoftmaxParam` | `svector_lambda` | lambda 构造 + axes 参数 |
| `AsStridedParam` | `svector_lambda` | 同上，字段为 size/stride/offset |

## 外部类型

| 类型 | 绑定方式 |
|------|---------|
| `HcclComm` | `opaque_pointer_types`，默认 `nullptr` |
| `aclDataType` / `aclFormat` | 手动区块全局枚举，不随算子生成 |
| `InputLayout` / `CommMode` 等 | `namespace_enums`，手动区块 |

## init_overrides.preserve

复杂算子（LayerNorm、SelfAttention、通信类等）在首次 bootstrap 后设 `preserve`，保留手写 param 绑定，仅自动同步 operation/wrapper/graph_builder 四处。

**勿盲目** `generate.py --regenerate-params`：会跳过 `preserve` 算子，若整文件替换 `bindings_ops.inc` 会丢失这些 param 绑定。

## operation_wrapper / enger_graph_builder 与 .inc

| 源文件 | 生成片段 |
|--------|----------|
| `operation_wrapper.h` | `#include "operation_wrapper_generated.inc"` |
| `operation_wrapper.cpp` | `#include "operation_wrapper_ops.inc"`（**无**手写逐算子构造函数） |
| `enger_graph_builder.h` | `#include "enger_graph_builder_generated.inc"` |
| `enger_graph_builder.cpp` | `#include "enger_graph_builder_ops.inc"` |
| `bindings.cpp` | `#include "bindings_operation_inits.inc"`、`bindings_builder_add_nodes.inc`、`bindings_ops.inc` |

仅同步 `.inc` 而未替换 `operation_wrapper.cpp` 时，编译可能通过但链接缺少新算子符号。

## 四文件一致性

每个 `operation_ops` 算子必须出现在 bindings operation init、operation_wrapper .h/.cpp。

每个 `graph_builder_ops`（减去 skip）算子必须出现在 bindings add_node、enger_graph_builder .h/.cpp。
