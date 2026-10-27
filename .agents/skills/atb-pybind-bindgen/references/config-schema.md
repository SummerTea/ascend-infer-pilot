# config.json 字段说明

## 路径

| 字段 | 说明 |
|------|------|
| `header` | 相对 ATB 仓库的头文件路径 |
| `output_dir` | 生成 `.inc` 输出目录 |
| `test_output_dir` | forward 测试输出目录 |
| `op_param_test_file` | param 冒烟测试文件 |

## 算子列表

| 字段 | 说明 |
|------|------|
| `whitelist` | 参与绑定的 Param 结构体名 |
| `operation_ops` | 注册 Operation(py::init) 的算子 |
| `graph_builder_ops` | 注册 Builder.add_node 的算子 |
| `skip_ops_in_graphbuilder` | 有 Operation 但无 GraphBuilder AddNode |

## 类型覆盖

| 字段 | 说明 |
|------|------|
| `external_structs` | 跨命名空间结构体 |
| `field_overrides` | 字段级绑定模式覆盖 |
| `init_overrides` | 构造器风格：svector_lambda / preserve |
| `opaque_pointer_types` | 不透明指针，默认 nullptr |
| `golden_mappings` | forward 测试生成配置（`torch_builtin`/`torch_compose`/`custom_manual`/`comm_skip`/`skip_npu`） |

生成测试输出：`<op>_bindgen_test.py`（含 CPU golden + `check_float`/`check_move`）。Recipe 定义在 `atb_bindgen/golden_recipes.py`。
