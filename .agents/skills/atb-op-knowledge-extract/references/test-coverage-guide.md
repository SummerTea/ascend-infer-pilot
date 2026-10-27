# Test Coverage 提取规则（Step 8）

## 目标

识别 ATK 测试用例位置、覆盖参数、生成执行命令、标记覆盖盲区。

---

## 8.1 测试目录定位

```python
# 路径规则: atk_test/atk_cida_atb/atb/{infer|train}/{OpName}Operation/
op_name_camel = to_camel_case(op_name)  # layer_norm → LayerNorm
test_dir = f"atk_test/atk_cida_atb/atb/{category}/{op_name_camel}Operation/"
```

## 8.2 测试文件识别

| 文件模式 | 类型 | 说明 |
|---------|------|------|
| `all_{Op}_Accu_Generalization.json` | 精度泛化 | 主要测试用例集 |
| `all_{Op}_Perf.json` | 性能测试 | Benchmark |
| `all_{Op}_Dete_Generalization.json` | 确定性 | 同输入多次运行 |
| `all_{Op}_Abnormal.json` | 异常测试 | 非法参数 |
| `nodes_{Op}_Accu.yaml` | 节点配置 | 后端/设备/task 配置 |
| `testcase.yml` | 测试注册 | 测试模式定义 |

## 8.3 Golden 实现定位

```python
# 在 data_generation.py 中搜索
class_pattern = f"class {op_name_camel}.*DataGen"

# 每个类实现:
# - golden(in_tensors, op_params) → CPU 参考输出
# - get_op_type(op_params) → 精度类别
```

## 8.4 执行命令生成

```bash
cd atk_test/atk_cida_atb/atb/{infer|train}/{OpName}Operation/
atk node --backend atb --devices 0 --task accuracy \
    node --backend cpu task \
    -c all_{OpName}Operation_Accu_Generalization.json \
    -ap ../../common
```

## 8.5 覆盖盲区

对比 Step 3 参数空间与测试 JSON 实际覆盖，标记未覆盖的组合及原因。
