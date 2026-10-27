# 矩阵乘法类算子 Tiling 策略

适用于 MatMul、BatchMatMul、MatMulAdd、AddMatMul、MatMulBias 等基于 Cube 单元的矩阵乘法算子。覆盖 tiling 数据结构、核间分配、L2/L1/L0 三级搬运等 tiling 策略逻辑。

> 与本仓其他类算子的 tiling 文档关系：
> - 通用原则：见 `general-tiling-principles.md`（两级 Tiling、Cache Line 对齐、整核/尾核负载均衡）
> - Vector 类典型场景：`elementwise-tiling.md`、`reduction-tiling.md`、`index-tiling.md`
> - 硬件抽象：`hardware-architecture.md`（Cube/Vector 单元、L1/L0/UB 容量、AIC vs AIV）

## 算子特性概述

### 核心计算模式

矩阵乘法类算子的核心计算为：`C = A × B (+ bias)`

| 张量 | 形状 | 说明 |
|------|------|------|
| A | `[M, K]` 或 `[Batch..., M, K]` | 左矩阵，可转置（trans_A） |
| B | `[K, N]` 或 `[Batch..., K, N]` | 右矩阵，可转置（trans_B） |
| C | `[M, N]` 或 `[Batch..., M, N]` | 输出矩阵 |
| bias | `[N]` 或 `[Batch..., N]` | 可选偏置 |

### 与 Vector 类算子的对比

| 维度 | Vector 类（elementwise/reduction/index） | Matmul 类 |
|------|-----------------------------------------|----------|
| 计算单元 | AIV（Vector Unit） | **AIC（Cube Unit）** |
| 主要片上存储 | UB（VECIN/VECCALC/VECOUT） | **L1（A1/B1）+ L0A/L0B/L0C + BT** |
| 切分粒度 | tileLength（元素数） | **baseM × baseN × baseK**（cube 块） |
| Tiling 工具 | 自行计算 + `BaseTilingData` | **`MultiCoreMatmulTiling::GetTiling(TCubeTiling&)`** |
| Kernel 主体 | `CopyIn → Compute → CopyOut` 流水 | **`MatmulImpl` 高阶 API 封装 L1/L0 搬运** |
| 升精度 | fp16/bf16 必须 Cast 到 fp32 | **Cube 内部 FP32 累加，由 MatmulImpl 自动处理** |
| 数据搬运 | tensor data 必须 `DataCopyPad`（参见 data-copy-api.md） | A/B/C 由 `MatmulImpl` 内部搬运；TilingHeader 加载方式见 `matmul-compute-api.md` §4 |

### 支持特性

| 特性 | 说明 |
|------|------|
| 转置支持 | A、B 矩阵均支持转置（`trans_x1` / `trans_x2`） |
| 数据类型 | float16、bfloat16、float32（fp32 通常走 HF32 模式） |
| 数据格式 | ND（普通行优先）、NZ（分形 16×16 cube） |
| Bias | 可选，支持 batch bias |
| HF32 | FP16 输入下走 32 位累加 |
| Split-K | 大 K 维度切分（Single Core / Multi Core / Deterministic） |
| L2 Cache 优化 | M/N 双层切分 + serpentine 反向遍历 |
| Batch | 1~4 维 Batch；可 broadcast；可与 M 合并 |
| ND→NZ 转换 | A/B 任一为 ND 时可在 kernel 内自动转换|

## Tiling 架构总览

### 三级 Tiling

```
┌─────────────────────────────────────────────────────────────┐
│                    全局内存 (GM)                              │
│           A[M,K]   ×   B[K,N]   →   C[M,N]                   │
└─────────────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │ L2 Tile  │     │ L2 Tile  │ ... │ L2 Tile  │   ← L2 级（M/N 切分，serpentine 遍历）
    │ mTileBlock×nTileBlock 个 base 块            │
    └──────────┘     └──────────┘     └──────────┘
          │                │                │
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │  Core 0  │     │  Core 1  │ ... │ Core N-1 │   ← Block 级（核间切分 + 错位）
    │singleCoreM×N│  │singleCoreM×N│  │singleCoreM×N│
    │ realRound 个 base 块，每核轮转处理            │
    └──────────┘     └──────────┘     └──────────┘
          │                │                │
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │ BaseBlock│     │ BaseBlock│ ... │BaseBlock │   ← BaseBlock 级（cube 一次发射）
    │ baseM×baseN×baseK，由 MatmulImpl 调度        │
    └──────────┘     └──────────┘     └──────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ A→A1(L1)→A2(L0A)│   ← MatmulImpl 内部
                  │ B→B1(L1)→B2(L0B)│      管理的 L1/L0 搬运
                  │  Cube → CO1(L0C)│      （depthA1/depthB1 控制双 buffer）
                  │  CO1→CO2(UB)→GM │
                  └─────────────────┘
```

### Tiling 数据结构
```cpp
#pragma pack(push, 8)

// CANN 标准 cube 参数（位于 kernel_tiling/kernel_tiling.h，约 196 字节）
// 由 host 端 MultiCoreMatmulTiling::GetTiling() 自动填充
struct alignas(8) TCubeTiling {
    uint32_t M, N, Ka, Kb;                  // 全局矩阵维度
    uint32_t singleCoreM, singleCoreN, singleCoreK;  // 每核处理大小
    uint32_t baseM, baseN, baseK;           // BaseBlock（cube 一次发射）
    uint32_t depthA1, depthB1;              // L1 双缓冲深度
    uint32_t stepM, stepN, stepKa, stepKb;  // L1 内 base 块步长
    uint32_t isBias;                        // 是否带 bias
    uint32_t usedCoreNum;                   // 实际使用核数
    uint32_t iterateOrder;                  // m-first / n-first
    uint32_t dbL0A, dbL0B, dbL0C;           // L0 双缓冲
    uint32_t shareMode, shareL1Size, shareL0CSize, shareUbSize;
    // ...其他字段（不同 SoC 略有差异）
};

// L2 Cache 切分参数（只用于 V3 大算子；小算子可置 1）
struct alignas(8) L2cacheTilePara {
    uint32_t mTileCntL2;    // M 方向 L2 Tile 数（mTileCnt = ceil(mTotalCnt / mTileBlock)）
    uint32_t nTileCntL2;    // N 方向 L2 Tile 数
    uint32_t mTileBlock;    // 每个 L2 tile 包含的 m 方向 base 块数
    uint32_t nTileBlock;    // 每个 L2 tile 包含的 n 方向 base 块数
    uint32_t calOrder;      // ROW_FIRST=1 / COL_FIRST=2
};

// 运行时 trans / nz / hf32 标志
struct alignas(8) MatMulRunInfo {
    uint32_t transA, transB;        // 转置
    uint32_t nd2nzA, nd2nzB;        // 是否在 kernel 内动态做 ND→NZ
    uint32_t isNzA,   isNzB;        // 输入是否已经是 NZ
    uint32_t isHf32;                // FP16 + HF32 高精度模式
};

struct alignas(8) L2cacheUseInfo { uint32_t l2CacheFlag; };

struct alignas(8) MatmulTilingData {
    TCubeTiling     matmulTiling;
    L2cacheTilePara tileL2cacheTiling;
    MatMulRunInfo   matmulRunInfo;
    L2cacheUseInfo  l2cacheUseInfo;
    uint32_t        baseAN, baseAD, baseBN, baseBD;  // ND→NZ 转换基础块
};

// BatchMatMul 在外层叠加 MultiBatchInfo（参见 batch_mat_mul_v3_tiling_data.h）
struct alignas(8) MultiBatchInfo {
    uint32_t batchUsedCoreNum;
    uint32_t aBatchDimAll, bBatchDimAll, cBatchDimAll;
    uint32_t aBatchDim0, bBatchDim0, cBatchDim0;
    uint32_t aBatchDim1, bBatchDim1, cBatchDim1;
    uint32_t aBatchDim2, bBatchDim2, cBatchDim2;
    uint32_t aBatchDim3, bBatchDim3, cBatchDim3;
    uint32_t iterBatch;       // 单次 IterateBatch 处理 batch 数
    uint32_t biasWithBatch;   // bias 是否带 batch
    uint32_t mOri, batchTileBlock, aBatch, bBatch;
};
struct alignas(8) BatchMatmulTilingData {
    MatmulTilingData matmulTiling;
    MultiBatchInfo   multiBatchInfo;
};

#pragma pack(pop)
```

### 自定义算子的轻量替代结构（小算子推荐）

CANN 完整 `MatmulTilingData` 字段较多。对于不需要 L2 切分、Batch、Split-K、ND→NZ 的小算子，可以只保留 `TCubeTiling` 和少量派生计数：

```cpp
// 来自 ascend-kernel/csrc/ops/matmul/op_kernel/matmul_tiling_header.h
#pragma pack(push, 8)
struct TilingHeader {
    AscendC::tiling::TCubeTiling cubeTiling;  // CANN 标准 cube tiling（POD，~196 B）
    int32_t mTotalCnt;    // ceil(M / singleCoreM)
    int32_t nTotalCnt;    // ceil(N / singleCoreN)
    int32_t totalBlock;   // mTotalCnt * nTotalCnt（=blockDim）
    int32_t reserved;     // 8 字节对齐
};
#pragma pack(pop)
```

序列化为 device 端的 `uint8` tensor，kernel 用 4-byte 对齐的标量 GM 读把它整体拷到 stack-resident 的 `TilingHeader` 变量上（不经过 UB / L1）。

## Trans 标志与编译期 kernel 分发（自定义算子必读）

### 现象：MatmulType 的 IS_TRANS 必须是编译期常量

`MatmulType<TPos, Format, T, IS_TRANS>` 的第 4 个模板参数 `IS_TRANS` 是 **constexpr bool**；并且 `MatmulImpl::SetTensorA(gm, isTrans)` 的运行时参数 **必须与模板参数完全一致**，否则 cube 内部 NZ 分形 / L1 双缓冲深度按错的方向计算，结果偏移错位或 NaN。

### 推论：要支持运行时 trans 必须每种 (transA, transB) 组合各编译一份 kernel

| dtype 数 | trans 组合数 (FF/FT/TF/TT) | 总 entry 点 |
|----------|---------------------------|-------------|
| 1 | 4 | 4 |
| 3 (fp16/bf16/fp32) | 4 | **12** |
| 4 (含 fp32→hf32 双路径) | 4 | 16 |

### 推荐实现：模板 + 宏一次铺开 12 个入口

```cpp
template <typename T, bool TRANS_A, bool TRANS_B>
class MatmulKernelImpl {
    using A_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, T, TRANS_A>;
    using B_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, T, TRANS_B>;
    // ...
    mm_.SetTensorA(aGm_[offsetA], TRANS_A);  // 运行时 arg == 编译期 IS_TRANS
    mm_.SetTensorB(bGm_[offsetB], TRANS_B);
};

#define MATMUL_KERNEL_ENTRIES(DTYPE_TAG, T)                                   \
    extern "C" __global__ __aicore__ void matmul_##DTYPE_TAG##_ff(...) { /*...*/ MatmulKernelImpl<T, false, false>; } \
    extern "C" __global__ __aicore__ void matmul_##DTYPE_TAG##_ft(...) { /*...*/ MatmulKernelImpl<T, false, true>;  } \
    extern "C" __global__ __aicore__ void matmul_##DTYPE_TAG##_tf(...) { /*...*/ MatmulKernelImpl<T, true,  false>; } \
    extern "C" __global__ __aicore__ void matmul_##DTYPE_TAG##_tt(...) { /*...*/ MatmulKernelImpl<T, true,  true>;  }

MATMUL_KERNEL_ENTRIES(fp16, half)
MATMUL_KERNEL_ENTRIES(bf16, bfloat16_t)
MATMUL_KERNEL_ENTRIES(fp32, float)
```

host 端按 `(scalar_type, transA, transB)` 选择对应入口 — **不要**在单 kernel 内做运行时 trans 分支。

### Trans 标志驱动的 GM 偏移公式（最容易错的点之一）

A、B 的 single-core tile GM 偏移公式与 trans 标志严格相关；记错一行就是输出错位 / 全零 / NaN：

| 标志 | 物理 layout | tile (mIdx, nIdx) 起始偏移 |
|------|-------------|----------------------------|
| `transA=false` | A 是 `[M, K]` | `offsetA = mIdx * singleCoreM * K` |
| `transA=true ` | A 是 `[K, M]` | `offsetA = mIdx * singleCoreM` |
| `transB=false` | B 是 `[K, N]` | `offsetB = nIdx * singleCoreN` |
| `transB=true ` | B 是 `[N, K]` | `offsetB = nIdx * singleCoreN * K` |

注意 C 始终非转置：`offsetC = mIdx * singleCoreM * N + nIdx * singleCoreN`。

```cpp
// 通用模板：在 kernel 中按编译期 trans flag 直接选择
const uint64_t offsetA = TRANS_A
    ? static_cast<uint64_t>(mIdx) * singleCoreM
    : static_cast<uint64_t>(mIdx) * singleCoreM * static_cast<uint64_t>(K);
const uint64_t offsetB = TRANS_B
    ? static_cast<uint64_t>(nIdx) * singleCoreN * static_cast<uint64_t>(K)
    : static_cast<uint64_t>(nIdx) * singleCoreN;
const uint64_t offsetC =
    static_cast<uint64_t>(mIdx) * singleCoreM * static_cast<uint64_t>(N)
  + static_cast<uint64_t>(nIdx) * singleCoreN;
```

### 用例 / 测试侧的 shape 校验同样要按 trans

```python
# transA=true: a 物理形状是 [K, M]，b=[K, N] 时 K 必须 == a.shape[0]
# transA=true, transB=false 的常见错误：a=[256, 512], b=[128, 512]
#   → Ka = a.shape[0] = 256, Kb = b.shape[0] = 128 → K mismatch
# 正确写法：
#   a=[K, M]=[256, 128], b=[K, N]=[256, 512]  →  output [M, N]=[128, 512]
```

> 性能用例 / 精度用例的 dataset 必须按上表生成 a/b shape；混淆 trans 后的物理 layout 会触发 host TORCH_CHECK 失败。

---

## L2 级 Tiling（M/N 方向切分）

### 目的

| 目的 | 收益 |
|------|------|
| 减少 L2 Cache 抖动 | 每个 L2 Tile 内的 A/B 子块尽量驻留 L2 |
| 提高数据局部性 | 同一行/列 base 块共享 L2 中的 A 行或 B 列 |
| 配合 serpentine 遍历 | 反向 N 遍历时下一个 L2 Tile 直接复用本 tile 末端的 B 行 |

### 切分公式

```cpp
mTileCntL2 = ceil(M_in_block_count, mTileBlock);
nTileCntL2 = ceil(N_in_block_count, nTileBlock);
mCnt = ceil(mTotalCnt, mTileCntL2);  // 每个 L2 Tile 包含的 M 方向 base 块数
nCnt = ceil(nTotalCnt, nTileCntL2);  // 每个 L2 Tile 包含的 N 方向 base 块数
totalTileCnt = mCnt * nCnt;          // 单个 L2 Tile 内的 base 块总数
```

> **小算子退化**：若 `M*N*dtype` 整体能塞进 L2，置 `mTileCntL2 = nTileCntL2 = 1`，跳过 L2 切分，直接进入 Block 级。

### Serpentine 反向遍历
```cpp
bool reverse = true;
for (uint64_t mTileIndex = 0; mTileIndex < mTileCntL2; ++mTileIndex) {
    reverse = !reverse;
    for (uint64_t t = 0; t < nTileCntL2; ++t) {
        // 偶数行正向、奇数行反向，使下一个 L2 Tile 的 B 列与当前末端复用
        uint64_t nTileIndex = reverse ? (nTileCntL2 - t - 1) : t;
        ProcessL2Tile(mTileIndex, nTileIndex);
    }
}
```

### 行优先 vs 列优先

| `calOrder` | 适用条件 | 收益 |
|------------|---------|------|
| `ROW_FIRST = 1` | A 矩阵较大 / M ≫ N | 优先复用 A 行（同 mIdx 对应 A 列内多个 N 块） |
| `COL_FIRST = 2` | B 矩阵较大 / N ≫ M | 优先复用 B 列 |

## Block 级 Tiling（核间切分）

### 整核/尾核策略

```cpp
round       = ceil(totalTileCnt, usedCoreNum);      // 每核最大处理轮数
preCoreNum  = totalTileCnt % usedCoreNum;           // 处理 round 次的"整核"数
if (preCoreNum == 0) preCoreNum = usedCoreNum;       // 整除时全部为整核
// 其余 (usedCoreNum - preCoreNum) 个核处理 round-1 次
```

负载均衡：所有核之间最多差 1 个 base 块。

### 错位分核（avoid bank conflict）

直接把第 i 个核固定处理 `[i*round, (i+1)*round)` 会让相邻核同时访问同一行 A 或同一列 B，造成 L2/L1 bank 冲突。CANN 用 LCM 错位：

```cpp
// 来自 mat_mul_base_block.h::UpdateBasicIndex
uint64_t newBlockIdx = (GetCurrentBlockIdx() + usedCoreNum - blockIdxStart) % usedCoreNum
                     + roundIdx * usedCoreNum;
uint64_t mIdx = newBlockIdx % mCntUse;
uint64_t nIdx = (newBlockIdx + newBlockIdx / Lcm(mCntUse, nCntUse)) % nCntUse;
params_.index = mIdx * nCntUse + nIdx;
```

### 跨调用 batch 平滑（BatchMatMul / 多次复用）

`indexInit_` 标志使本次 `Process(index)` 的 `blockIdxStart` 等于上次的 `blockIdxEnd`，避免每次都从核 0 开始导致的尾核空转。

## BaseBlock 级（cube 一次发射）

### 经验值

| 数据类型 | 推荐 baseM | 推荐 baseN | 推荐 baseK | 备注 |
|---------|-----------|-----------|-----------|------|
| float16 | 128 / 256 | 128 / 256 | 32 / 64 | L0A=64KB 时 256×64 fp16 占 32KB |
| bfloat16 | 128 / 256 | 128 / 256 | 32 / 64 | 同 fp16 |
| float32 | 64 / 128 | 64 / 128 | 16 / 32 | L0A 容量减半 |

> **优先使用 `MultiCoreMatmulTiling::GetTiling(TCubeTiling&)`** 自动给出对当前 SoC 最优的 base/single/L1 深度组合。手算只在该 API 不可用时使用。

### 对齐约束

```cpp
ALIGNED_H = 16;       // M、K 维度对齐到 16
c0Size    = 16;       // fp16/bf16 NZ 块的 N 维（fp32 为 8）

baseM, baseN, singleCoreM, singleCoreN 必须为 ALIGNED_H 的整数倍
baseK 通常为 ALIGNED_H 的整数倍（fp16/bf16=16, fp32=8）
```

### 单核处理大小与尾块

```cpp
mTotalCnt   = ceil(M, singleCoreM);
nTotalCnt   = ceil(N, singleCoreN);
mBaseTail   = M - (mTotalCnt - 1) * singleCoreM;  // M 方向最后一行的实际大小
nBaseTail   = N - (nTotalCnt - 1) * singleCoreN;  // N 方向最后一列的实际大小
```

Kernel 内分发：

```cpp
const int32_t mIdx = blockIdx / nTotalCnt;
const int32_t nIdx = blockIdx % nTotalCnt;
const int32_t curSingleM = (mIdx == mTotalCnt - 1) ? mBaseTail : singleCoreM;
const int32_t curSingleN = (nIdx == nTotalCnt - 1) ? nBaseTail : singleCoreN;
```

## Batch 维度处理

### 通用规则

| A Batch | B Batch | C Batch | 模式 |
|---------|---------|---------|------|
| N | 1 | N | B 广播 |
| 1 | N | N | A 广播 |
| N | N | N | 一对一 |
| N | M | LCM(N,M) | 多维广播 |

### Batch 合并到 M

当 `batchB == 1 && !transA` 时，把 A 的 batch 维度合并到 M：

```cpp
if (batchB == 1 && !transA) {
    M = batchA * M;
    batchA = 1;
}
```

### Batch 负载均衡

```cpp
iterBatch = min(batchC, coreNum);
loopTimes = ceil(batchC, iterBatch * coreNum);
batchUsedCoreNum = min(batchC, coreNum);
// kernel 端循环 loopTimes 次，每次 IterateBatch 处理 iterBatch 个 batch
```

## Split-K 策略

| 类型 | 触发条件 | 实现 |
|------|---------|------|
| Single Core Split-K | K 中等、希望减少 base 块尺寸时 | 单核 K 切分，串行累加 |
| Multi Core Split-K | K ≫ M*N，多核可并行 K | 多核并行计算，最后 Atomic Add 到 GM 同一 C 块 |
| Deterministic Split-K | 需要可复现 | 多核计算 + workspace 累加 + 最终归约 |


## ND2NZ 转换

当输入是 ND 但 cube 内部需要 NZ 时，tiling 端需要计算对齐后的维度供 `SetOrgShape` 使用：

```cpp
constexpr uint32_t c0Size    = (sizeof(T) == 4) ? 8 : 16;
alignedM = ceil(M, c0Size) * c0Size;
alignedK = ceil(K, ALIGNED_H) * ALIGNED_H;
```

## Tiling 关键参数总结

| 参数类别 | 字段 | 来源 |
|---------|------|------|
| 矩阵维度 | `M, N, Ka, Kb` | host 输入 |
| 单核切分 | `singleCoreM, singleCoreN, singleCoreK` | `MultiCoreMatmulTiling` |
| 基础块 | `baseM, baseN, baseK` | `MultiCoreMatmulTiling` |
| L1 深度 | `depthA1, depthB1, stepM, stepN, stepKa, stepKb` | `MultiCoreMatmulTiling` |
| L0 双缓冲 | `dbL0A, dbL0B, dbL0C` | `MultiCoreMatmulTiling` |
| L2 切分 | `mTileCntL2, nTileCntL2, mTileBlock, nTileBlock, calOrder` | host 自定义计算 |
| 核数 | `usedCoreNum` | host（≤ `GetCoreNumAic()`） |
| 转置 | `transA, transB` | host 输入 |
| 格式 | `isNzA, isNzB, nd2nzA, nd2nzB` | host 输入 |
| 精度 | `isHf32` | host 选项 |
| Bias | `isBias` | host 输入 |
| Batch | `batchUsedCoreNum, iterBatch, loopTimes, biasWithBatch, batchDim0..3` | BatchMatMul host |

## Tiling 计算流程（host 端模板）

```
1. 输入校验（dtype、shape、K 维度匹配）
        ↓
2. 通过 PlatformAscendC 拿到 coreNumAic / l1Size / l0A/l0B/l0C / ubSize
        ↓
3. （可选）batch 合并、shape 规范化
        ↓
4. 调用 MultiCoreMatmulTiling::GetTiling(TCubeTiling&)
   ├─ 自动决定 baseM/baseN/baseK、singleCoreM/N、L1 深度
   ├─ 自动给出 usedCoreNum
   └─ 校验 K = Ka = Kb 一致
        ↓
5. （大算子）计算 L2 级 mTileCntL2/nTileCntL2/mTileBlock/nTileBlock
        ↓
6. （大算子）核间负载均衡 round / preCoreNum
        ↓
7. 计算派生计数 mTotalCnt / nTotalCnt / totalBlock
        ↓
8. （BatchMatMul）填充 MultiBatchInfo
        ↓
9. 把 TilingHeader 序列化到一个 device 端的 uint8 tensor
   ⚠️ 必须 blocking copy（CPU→NPU），保证 kernel 启动前数据已就位
        ↓
10. EXEC_KERNEL_CMD(<op_name>, blockDim=usedCoreNum, A, B, C, [Bias], tilingTensor)
```

## 性能优化要点

1. **L2 Cache 优化**：合理设置 mTileBlock × nTileBlock，使每个 L2 Tile 内的 A/B 工作集 ≤ L2/2
2. **负载均衡**：整核/尾核误差 ≤ 1 个 base 块；尾核数 = `usedCoreNum - preCoreNum`
3. **错位分核**：用 LCM 错位避免多核同时访问相同 A 行/B 列引起的 bank 冲突
4. **Serpentine 遍历**：N 方向偶/奇行交替反向，复用 L2 中已加载的 B 列
5. **enUnitFlag**：99% 的自定义算子需要 `enUnitFlag=true`，否则结果不写回 GM
6. **L1 Full Load**：当 `M*Ka` 或 `Kb*N` 能塞进 L1 时启用 `MM_CFG_L1_FULL_LOAD_*`
7. **Split-K**：K ≫ M*N 时启用；优先选 Multi Core Split-K + ATOMIC_ADD
8. **Batch 合并**：`batchB==1 && !transA` 把 batchA 合并到 M
9. **DB 与流水**：默认 `dbL0A = dbL0B = dbL0C = 2`，由 `MultiCoreMatmulTiling` 给出
10. **ND→NZ**：A、B 维度对齐到 16 时不要做 ND→NZ 转换；非对齐时考虑 kernel 端 `MM_CFG_VEC_ND2NZ`

## 算子差异化特性

| 算子类型 | 特殊特性 | Tiling 差异 |
|---------|---------|------------|
| MatMul | 基础 | 无 batch；可选 L2/Split-K |
| BatchMatMul | 多 batch | 叠加 `MultiBatchInfo`；kernel 端用 `IterateBatch` |
| MatMulBias | 带 bias | `isBias=1`；kernel 端用 `SetBias` |
| MatMulAdd / AddMatMul | 与额外加法融合 | 在 Iterate 后/前插入 vector 加法 |
| MatMulQuant | INT8 量化 | A/B INT8、C FP16/INT32；deqScale fixpipe |

## 通用约束

- **维度匹配**：`Ka == Kb`；BatchMatMul 满足广播规则
- **对齐**：`baseM, baseN, singleCoreM, singleCoreN` 是 `ALIGNED_H=16` 的整数倍；`baseK` 与数据类型挂钩（fp16/bf16=16, fp32=8）
- **核数**：`usedCoreNum ≤ ascendcPlatform->GetCoreNumAic()`
- **Batch 维度**：最多 4 维
- **格式**：ND ↔ NZ 偏移计算不同；NZ 必须 `SetOrgShape`（见 `matmul-compute-api.md` §7.3）
- **TilingHeader 加载**：4-byte 对齐的 GM → stack 标量读，**不**经过 UB / L1
- **MM_CFG**：自定义算子默认选 `MM_CFG_NO_PRELOAD`（enUnitFlag=true）
