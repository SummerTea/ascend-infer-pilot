---
name: atb-debug-guide
description: >
  ATB 调试指南技能。当用户遇到 ATB 算子测试问题、需要分析错误原因、或需要了解 ATB 环境配置时调用此技能。
  覆盖：GDB core dump 分析、NZ格式丢失、异步析构segfault、TaskQueue OpCommand 陷阱、ATK ATB perf 栈与 NPUBackend 继承关系、PerformanceConfig 合并阶段 TypeError/KeyError 等场景。
keywords:
    - atb
    - debug
    - error
    - troubleshooting
    - 昇腾
    - NPU
    - 调试
    - core dump
    - segfault
    - nz
    - atk
    - performance_device
    - NPUBackend
metadata:
  version: "1.5.1"
  updated: "2026-05-12"
  skill-type: debug
---

# ATB Debug Guide

## Quick Reference

**用途**：对 ATB 编译/运行/测试问题做快速分诊、定位和修复建议输出。

**渐进式披露阅读顺序**：

1. 先完成「执行前 Checklist」锁定问题上下文
2. 再看下方「索引」打开对应延伸阅读
3. 环境与连通性排查优先使用 [`references/environment-checklist.md`](references/environment-checklist.md)

## 执行前 Checklist

- [ ] 已收集错误现象（报错信息、日志、触发命令）
- [ ] 已确认 `CANN_PATH` 与 `ATB_REPO_PATH`
- [ ] 已确认当前 ABI/环境变量状态
- [ ] 已确认输出目标格式（仅定位结论 / 定位+修复建议 / 完整排查报告）

## 功能概述

提供 ATB 调试指南，覆盖环境配置问题、ABI版本不匹配、内存错误、CSV测试失败、ACLNN接口问题、NZ格式丢失、异步析构segfault等常见场景。

## 调用时机

在以下情况下调用此技能：

- 用户遇到 ATB 算子测试问题
- 用户需要分析错误原因
- 用户需要了解 ATB 环境配置

## 路径约束（必须执行）

执行此技能前，**必须从用户处获取以下路径**（如未提供则使用默认路径）：

- `<CANN_PATH>`: CANN 安装路径（如 `/usr/local/Ascend/cann-9.0.0-beta.2`）
- `<ATB_REPO_PATH>`: ATB 仓库路径

---

## 索引

详细步骤、命令与代码片段见 **[常见错误分类与诊断](references/error-scenarios.md)**；环境与检查表见 **[environment-checklist.md](references/environment-checklist.md)**。

### ATK ATB 性能与 Backend 栈

跑 **`performance_device`** 且 **`backend: atb`** 时，堆栈中可能出现 **`npu_backend`**（例如 `NPUBackend.custom_data_computation`）。这是因为 **`AtbBackend` 继承 `NPUBackend`**，Profiling 解析与自定义统计合并在父类实现，**不代表任务误切非 ATB**。详见 **[atk-atb-perf-backend-stack.md](references/atk-atb-perf-backend-stack.md)**。

| 问题类型 | 快速定位 | 延伸阅读 |
|----------|----------|----------|
| GDB Core Dump 分析 | SIGSEGV, core dump, 退出码 139 | [error-scenarios.md § GDB](references/error-scenarios.md#gdb-core-dump-分析) |
| ABI版本不匹配 | undefined symbol, shared object file | [§ ABI](references/error-scenarios.md#abi-版本不匹配错误) |
| 内存错误 | ERROR_OUT_OF_HOST_MEMORY | [§ 内存](references/error-scenarios.md#内存错误) |
| Tensor维度错误 | ERROR_INVALID_TENSOR_DIM | [§ Tensor](references/error-scenarios.md#tensor-维度错误) |
| 数据类型错误 | KeyError: 'float32', ERROR_INVALID_TENSOR_INI_MATCH | [§ 数据类型](references/error-scenarios.md#数据类型错误) |
| ACLNN函数签名错误 | 161001, 161002, undefined symbol | [§ ACLNN 签名](references/error-scenarios.md#aclnn-函数签名不匹配) |
| ACLNN MoE场景不匹配 | {xxx}Quant 等非MoE算子 | [§ MoE](references/error-scenarios.md#aclnn-moe-场景不匹配) |
| NZ格式丢失（ConvertToAtbTensor） | format: nd, InferShape fail | [§ NZ](references/error-scenarios.md#nz格式丢失converttoatbtensor) |
| 异步模式析构Segfault | segfault at MkiNodeImplement::Run | [§ 异步析构](references/error-scenarios.md#异步模式析构segfault) |
| 析构函数错误处理 | catch (...) 空块吞异常 | [§ 析构](references/error-scenarios.md#析构函数错误处理) |
| 日志分析方法 | plog日志, atb日志 | [§ 日志](references/error-scenarios.md#日志分析方法) |
| ATK perf：`TypeError`/`KeyError` @ `custom_data_computation` | `performance_device`、`perf` 常为 **`PerformanceConfig`**；Profiling 不全时字段为 None 或缺 **`power`** | [atk-atb-perf-backend-stack.md](references/atk-atb-perf-backend-stack.md) |

---

## 环境与检查清单

完整的 Step-by-step 环境检查、调试检查表与记录模板见 **[references/environment-checklist.md](references/environment-checklist.md)**。

---

## 相关文档

- [ATB Skills 索引](../../SKILL.md)
