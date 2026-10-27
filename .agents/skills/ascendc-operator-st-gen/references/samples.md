# ATK ST 参考工程示例（当前路径）

| 复杂度 | 示例目录 | 要点 |
|--------|----------|------|
| 简单（单 `api_type` / `BaseApi`） | `./RopeWithSinCosCache/` | `init` 写 `kwargs`，`__call__` 自算；JSON 中 attrs 用**嵌套数组** |
| 复杂（golden + `AclnnBaseApi`） | `./MhcPreSinkhorn/` | nullptr 下标、`-cp` 下 `c_double`、golden 同步 `kwargs` |

算子仓内必读：`op_host/*_def.cpp`（入参顺序）、`docs/aclnn<Op>.md`（`-cp` 类型）、`examples/test_aclnn_*.cpp`（nullptr/shape）。
