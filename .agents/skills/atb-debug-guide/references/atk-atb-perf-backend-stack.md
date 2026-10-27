# ATK ATB 性能路径与 NPUBackend 继承关系

本文说明：在 **`--task performance_device`** 且 **`backend: atb`** 时，为何异常栈中会出现 **`atk/tasks/backends/npu_backend.py`**，以及这与「是否跑在 ATB 上」的关系。

## 类型关系（运行时）

在同一套 ATK 安装中（以 Python 内省为准）：

- `AtbBackend` 的直接基类为 **`NPUBackend`**；
- `AtbBackend` **重写**了与 ATB 上下文、算子执行相关的入口（例如设备侧性能采集入口 `run_device_perf`）；
- **`parser_profile_result`、`get_custom_data`、`custom_data_computation`** 等 **Profiling 结果解析与自定义统计合并** 逻辑，在多数版本中 **未在 `AtbBackend` 再次实现**，因此调用会进入父类 **`NPUBackend`** 的实现（编译产物对应 `npu_backend` 扩展模块）。

结论：**栈中出现 `npu_backend` 文件，不等于任务错误地使用了「非 ATB」Backend**；它表示 **ATB 性能流水线复用了与 NPU Profiling 解析共用的父类代码**。

## 典型调用链（概念）

```text
performance_device
  → AtbBackend.run_device_perf
    → NPUBackend.parser_profile_result
      → NPUBackend.get_custom_data
        → NPUBackend.custom_data_computation
```

具体行号随 ATK 版本变化，以本环境安装的 `site-packages/atk` 为准。

## 常见误判

| 现象 | 说明 |
|------|------|
| 栈顶是 `NPUBackend.custom_data_computation` | 多为 Profiling 衍生数据结构不完整或合并逻辑对 `None` 不健壮，**优先对照 `atk.log` 中 `op_summary` / `api_statistic` 是否为 null**，而非更换 Backend |
| 日志中有「自定义 atb api阶段」 | 表明仍在 ATB API 执行路径 |

## 与排查手册的衔接

若遇到 **`TypeError: 'NoneType' object is not subscriptable`** 于上述合并阶段，请同时查阅：

- ATK 插件侧是否在性能阶段提供了 **`export_custom_data`** 且返回 **`dict`**（而非 `None`）；
- Profiler 输出目录下 **`memory_record.csv` / op_summary** 是否缺失（环境或采集开关问题）。

更完整的 ATK 测试陷阱见同包技能 **atb-atk-testcase-generator** 内 `references/common-faq.md`（**Q9**：perf / `PerformanceConfig`）。若你检出的仓库快照尚未包含该目录，请在合入对应技能后再打开；**此处不使用超链接**，避免在仅含 debug 分支的 MR 中出现死链。

## PerformanceConfig 与合并阶段

`NPUBackend.get_custom_data` / **`custom_data_computation`** 的 **`perf` 实参**在多数版本中是 **`atk.configs.results_config.PerformanceConfig`**（Pydantic `BaseModel` 子类），**不是**普通 **`dict`**。

当 Profiling 产物不完整或 ATB 路径未写满字段时，其中常见字段可能保持 **`None`**，例如（以模型定义为准）：

- **`custom_data`**
- **`cube_computation`**、**`api_statistic`**
- **`power_temp_info`**

父类合并逻辑可能对这些对象做**下标或链式访问**：对 **`None`** 下标会得到 **`TypeError: 'NoneType' object is not subscriptable`**。若将 **`power_temp_info`** 误设为**空字典**而缺少 ATK 期望的键（如 **`power`**），则可能在同一阶段出现 **`KeyError: 'power'`**。

**业务侧稳妥做法**（不绑定具体仓库路径）：在 ATK 插件基类（典型文件名为 **`atb_base_api.py`** 一类）**导入并注册 execute API 时**，对 **`NPUBackend.custom_data_computation`** 做**一次性包装**：在调用 Cython 实现前，若 **`isinstance(perf, PerformanceConfig)`**，为上述字段写入**与类型注解一致的安全默认值**（如空 **`dict`**、与 **`List[float]`** 一致长度的零列表、**`power_temp_info`** 中带 **`power`/`temp`** 等键的占位值），再交给原生实现。具体数值以你方 ATK 版本与通过用例为准。

**调试环境变量 `ATK_PERF_DEBUG`**：设为 **`1`**、**`true`** 或 **`yes`** 时，可在进入合并前把 **`PerformanceConfig` 内各属性类型**打印到日志（实现位置因业务仓而异）；在 **`atk.log`** 中搜索 **`[ATK_PERF_DEBUG]`** 可核对字段是否为 **`NoneType`**。
