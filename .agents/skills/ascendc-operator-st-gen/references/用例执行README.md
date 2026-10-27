# 用例执行使用说明

本目录提供 ATK 用例执行阶段的样例文件，按 `pytorch` 和 `aclnn` 两类场景分别存放。

## 文件结构

```text
用例执行/
├── README.md
├── aclnn/
│   └── aclnnUnique.csv
└── pytorch/
    └── torch.max.csv
```

## 样例说明

| 文件 | 说明 |
| --- | --- |
| `pytorch/torch.max.csv` | `torch.max` 的快速执行样例文件，展示一条 PyTorch 场景 case 需要的核心字段。 |
| `aclnn/aclnnUnique.csv` | `aclnnUnique` 的快速执行样例文件，展示一条 PyAclnn 场景 case 的字段组织方式。 |

## 使用方式

### PyTorch 场景

```bash
atk pytorch pytorch/torch.max.csv
```

### PyAclnn 场景

```bash
atk aclnn aclnn/aclnnUnique.csv
```

## 快速测试用例参数说明

### 普通参数设置

普通参数的设置字段说明如下：

| 字段名 | 类型 | 说明 | 是否必需 |
|--------|------|------|---------|
| `id` | int | 用例ID | 否 |
| `name` | str | 算子名称 | 是 |
| `aclnn_name` | str | ACLNN算子名称 | 否 |
| `api_type` | str | API类型（function/pyaclnn/triton_function等） | 否 |

### 精度标准设置

精度标准设置，字段说明如下：

| 字段名 | 类型 | 说明 | 是否必需 |
|--------|------|------|---------|
| `standard.acc` | str | 精度标准（single_bm） | 可选 |


### 输入参数设置

`N` 从0开始，表示第N个输入参数，字段说明如下：

| 字段名 | 类型 | 说明 | 是否必需 |
|--------|------|------|---------|
| `inputN.name` | str | 输入参数名称 | 是 |
| `inputN.type` | str | 输入类型（tensor/scalar/attr） | 是 |
| `inputN.dtype` | str | 数据类型（fp16/float16/fp32/float32/int32/int64/bf16等） | 是 |
| `inputN.shape` | list | 张量形状，如`[2,3,4]` | tensor类型必需 |
| `inputN.range_values` | list | 数值范围，如`[-1,1]`或`[[0,1],[0,10]]` | 是 |

如果输入参数类型是`tensors\attrs`等类型，需要给每一个tensor\attr都设置dtype、shape和range_values，示例如下：
| input1.name | input1.type | input1.dtype | input1.shape | input1.range_values |
|--------|------|------|---------|----------|
| weight | tensors | ["fp32","fp32"] | [[100,200],[20,20]] | [[-5,5],[-5,5]] |

### 其他输入类型

| 字段名 | 说明 | 解析结果 |
|------|------|---------|
| `method_inputN.*` | 方法输入 | 存入`method_inputs`列表 |
| `tensor_inputN.*` | 张量输入 | 存入`tensor_input`列表 |

### 完整示例

#### 单输入算子（torch.abs）

| id | name | aclnn_name | input0.name | input0.type | input0.dtype | input0.shape | input0.range_values | standard.acc |
|----|------|------------|-------------|-------------|--------------|--------------|---------------------|-------------------|
| 0 | torch.abs | aclnnAbs | input0 | tensor | fp16 | [2,3,4] | [-1,1] | single_bm |

#### 双输入算子（torch.add）

| id | name | aclnn_name | input0.name | input0.type | input0.dtype | input0.shape | input0.range_values | input1.name | input1.type | input1.dtype | input1.shape | input1.range_values | standard.acc |
|----|------|------------|-------------|-------------|--------------|--------------|---------------------|-------------|-------------|--------------|--------------|---------------------|-------------------|
| 0 | torch.add | aclnnAdd | input0 | tensor | fp16 | [2,3,4] | [-1,1] | input1 | tensor | fp16 | [2,3,4] | [-1,1] | default |

#### 多输入算子（torch.cat）

| id | name | aclnn_name | input0.name | input0.type | input0.dtype | input0.shape | input0.range_values | input1.name | input1.type | input1.dtype | input1.shape | input1.range_values | input2.name | input2.type | input2.dtype | input2.shape | input2.range_values | standard.acc |
|----|------|------------|-------------|-------------|--------------|--------------|---------------------|-------------|-------------|--------------|--------------|---------------------|-------------|-------------|--------------|--------------|---------------------|-------------------|
| 0 | torch.cat | aclnnCat | input0 | tensor | fp16 | [2,3] | [-1,1] | input1 | tensor | fp16 | [2,4] | [-1,1] | input2 | tensor | fp16 | [2,5] | [-1,1] | default |
