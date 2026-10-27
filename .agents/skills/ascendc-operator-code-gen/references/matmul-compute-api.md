# AscendC MatMul 类算子 API 参考（纯 CUBE 路径）

本文档覆盖 AscendC 中 **基于 `MatmulImpl`** 的纯 Cube 算子的高阶 API，适用于 MatMul / BatchMatMul / MatMulAdd 等单组矩阵乘算子。

> 与本目录其他参考文档关系：
> - 数据搬运 / 基础数据结构：本目录 `data-copy-api.md`、`basic-data-structures-api.md`
> - 资源管理（TPipe/TQue/TBuf/UB 容量）：本目录 `resource-management-api.md`
> - kernel 通用约束：本目录 `kernel-constraints.md`


## 目录

- [1. MatMul 类算子全景](#1-matmul-类算子全景)
- [2. 基础概念](#2-基础概念)
- [3. MatmulImpl API](#3-matmulimpl-api)
  - [3.6 完整 Kernel 骨架（L2 / Split-K / Batch）](#36-完整-kernel-骨架l2--split-k--batch)
- [4. Tiling Header GM → stack 装载](#4-tiling-header-gm--stack-装载)
  - [4.4 反模式（必须避免）](#44-反模式必须避免)
- [5. AIC / AIV 关系与数据类型支持](#5-aic--aiv-关系与数据类型支持)
- [6. 接口调用流程速查](#6-接口调用流程速查)
- [7. 常见问题与排错](#7-常见问题与排错)

---

## 1. MatMul 类算子全景

| 子类 | 计算公式 | 高阶 API | Type 包装 | Tiling 入口（host） |
|------|---------|---------|----------|---------------------|
| **MatMul** | `C = A · B (+ bias)` | `MatmulImpl<A,B,C,Bias,MM_CFG>` | `MatmulType<TPosition,CubeFormat,T,trans>` | `MultiCoreMatmulTiling::GetTiling(TCubeTiling&)` |
| **BatchMatMul** | `C[b] = A[b] · B[b]` | 同上（用 `IterateBatch`） | 同上 | 同上 + `SetBatchNum` |
| **MatMulAdd** | `C = A · B + D` | 同上（外层 atomic add 或 elementwise add） | 同上 | 同上 |


---

## 2. 基础概念

### 2.1 TPosition

| 位置 | 说明 | MatMul 算子用途 |
|------|------|----------------|
| `TPosition::GM` | 全局内存 | 所有 user-level 输入输出 tensor 的位置 |
| `TPosition::A1 / B1` | L1 buffer | `MatmulImpl` 内部自动管理 |
| `TPosition::A2 / B2` | L0A / L0B | 同上 |
| `TPosition::CO1` | L0C | cube 累加结果，由 fixpipe 写回 |
| `TPosition::CO2` | UB（仅 vector 后处理路径用） | 纯 CUBE 算子无须显式涉及 |

> User-level 算子 **只在 `TPosition::GM` 上声明 type**；L1/L0/L0C 由 `MatmulImpl::Init` 内部调度。

### 2.2 数据格式枚举

| 体系 | 类型 | 取值 |
|------|------|------|
| MatmulImpl | `CubeFormat` | `ND`（行优先）、`NZ`（16×16 fractal）、`Z`、`VECTOR` |

### 2.3 通用对齐约束

```cpp
ALIGNED_H = 16;        // M / K 维度
c0Size    = 16;        // fp16/bf16 NZ 的 N 维 fractal
c0Size    = 8;         // fp32 NZ 的 N 维 fractal
```

---

## 3. MatmulImpl API

> 适用算子：MatMul / BatchMatMul / MatMulAdd / 其他形如 `C = f(A·B + bias)` 的单组矩阵乘算子。

### 3.1 MatmulImpl 模板

```cpp
#include "lib/matmul_intf.h"
using namespace matmul;

template <
    class A_TYPE,                                          // MatmulType<TPosition, CubeFormat, T, isTrans>
    class B_TYPE,                                          // MatmulType<TPosition, CubeFormat, T, isTrans>
    class C_TYPE,                                          // MatmulType<TPosition::GM, CubeFormat::ND, T>
    class BIAS_TYPE,                                       // MatmulType<TPosition::GM, CubeFormat::ND, BiasT>
    const MatmulConfig& MM_CFG = MM_CFG_NO_PRELOAD,        // 关键：见 §3.3
    class MM_CB = MatmulCallBackFunc<nullptr,nullptr,nullptr>
>
class MatmulImpl;
```

```cpp
// 标准用法
using A_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, half,  /*isTrans=*/false>;
using B_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, half,  /*isTrans=*/false>;
using C_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, half>;
using BIAS_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, float>;   // bias 一般 fp32
MatmulImpl<A_TYPE, B_TYPE, C_TYPE, BIAS_TYPE, MM_CFG_NO_PRELOAD> mm_;
```

### 3.2 核心方法

| 方法 | 说明 | 调用时机 |
|------|------|---------|
| `void Init(const TCubeTiling* tiling, TPipe* pipe)` | 初始化（**tiling 必须是 stack 指针**，见 §4） | 每核 1 次 |
| `void SetSubBlockIdx(uint32_t idx)` | 设置子块索引 | `Init` 之前；通常 `0` |
| `void SetHF32(bool enable, uint32_t mode)` | 配置 cube 精度模式（默认 `false,0` = CubeMathType=4 全 FP32；`true,1` = HF32） | 计算前 |
| `void SetOrgShape(uint32_t oriM, oriN, oriKa, oriKb, oriN2)` | NZ 格式必调；ND 多数情况可省 | 计算前 |
| `void SetSingleShape(uint32_t singleM, singleN, singleK)` | 当前 single-core tile 的实际尺寸（含尾块） | 每个 tile 之前 |
| `void SetTensorA(GlobalTensor<A_T>& aGm, bool isTrans)` | 设置 A | 每个 tile |
| `void SetTensorB(GlobalTensor<B_T>& bGm, bool isTrans)` | 设置 B | 每个 tile |
| `void SetBias(GlobalTensor<BiasT>& biasGm)` | 设置 bias | 每个 tile（按需） |
| `void SetBatchNum(uint32_t batchA, batchB)` | BatchMatMul 内层 batch 数 | `IterateBatch` 之前 |
| `void SetNBatchOutNum(uint64_t batchOutNum)` | 一次 IterateBatch 输出多少个 batch | `IterateBatch` 之前 |
| `bool Iterate()` | 触发 **一个** baseBlock | Split-K / 显式 atomic 累加 |
| `void GetTensorC(GlobalTensor<C_T>& cGm, uint8_t enAtomic = 0)` | Iterate 后取回 | 与 `Iterate` 配对；`enAtomic=2` 即 ATOMIC_ADD |
| `void IterateAll(GlobalTensor<C_T>& cGm, uint8_t enAtomic = 0)` | **遍历当前 single-core tile 的所有 baseBlock 并写回 GM** | 推荐：与 `MM_CFG_NO_PRELOAD` 配合 |
| `void IterateBatch(...)` | 一次处理多个 batch | BatchMatMul |
| `void End()` | 结束 + 释放资源 | 每核 1 次 |

### 3.3 MatmulConfig 选择

`MM_CFG` 决定 cube 的搬运、流水、写回行为。

| 配置 | 关键参数 | 用途 |
|------|---------|------|
| **`MM_CFG_NO_PRELOAD`** | `enUnitFlag=true` | **大多数自定义算子默认**：使能 fixpipe 把 L0C 写回 GM |
| `MM_CFG_VEC_ND2NZ` | `isVecND2Nz=true` | A/B 输入 ND，让 vector 在 kernel 内做 ND→NZ |
| `MM_CFG_PRELOAD_MK` | `doMTE2Preload=2` | M-K 方向预取 A |
| `MM_CFG_PRELOAD_NK` | `doMTE2Preload=1` | N-K 方向预取 B |
| `MM_CFG_K_SHIFT` | `kShift=true` | K 方向流水分段 |
| `MM_CFG_MDL` | 默认 MDL | 简单大算子 |
| `CFG_MDL` / `NZ_CFG_MDL` | weight 是 NZ 时选 NZ 版 | NZ 输入 |
| `MM_CFG_ORDER_M` | `IterateOrder::ORDER_M` | BatchMatMul 内层 M 优先 |
| `MM_CFG_MULTI_BATCH_OUT` | `BatchOutMode::MULTI_BATCH` | BatchMatMul 一次输出多 batch |

```cpp
// 自定义算子推荐配置（MM_CFG_NO_PRELOAD 的等价定义）
constexpr MatmulConfig MM_CFG_NO_PRELOAD =
    GetMDLConfig(/*enableMixDualMaster=*/false,
                 /*enableUnitFlag=*/false,
                 /*doMTE2Preload=*/0,
                 /*isVecND2Nz=*/false,
                 /*isPerTensor=*/false,
                 /*isSplitK=*/false,
                 /*enUnitFlag=*/true);   // ← 关键
```

> **enUnitFlag=true 的坑**：是 `GetMDLConfig` 第 7 个参数，AscendC 默认 `false`，意味着 cube 完成 L0C 累加后 **不会** 触发 fixpipe 把结果送回 GM。自定义算子如果直接 `MatmulImpl<A,B,C,Bias>`（不显式指定 MM_CFG）且 host 没有再调 `mm_.GetTensorC(cGm)`，输出 buffer 将保持初始（零）状态。

### 3.4 IterateAll vs Iterate + GetTensorC

| API | 行为 | 适用 |
|-----|------|------|
| `Iterate()` + `GetTensorC(cGm, enAtomic)` | 处理 **一个** baseBlock，需要在每个 baseBlock 之间插自定义逻辑（错位、Atomic、Split-K 累加） | 自定义错位、Split-K |
| **`IterateAll(cGm, enAtomic)`** | 自动遍历当前 `[singleCoreM × singleCoreN]` 内所有 baseBlock 并写回 GM | **小算子推荐**：单核一次拿整个 tile |

### 写回模式

```cpp
mm_.SetSingleShape(curSingleM, curSingleN, K);
mm_.SetTensorA(aGm[offsetA], /*isTrans=*/false);
mm_.SetTensorB(bGm[offsetB], /*isTrans=*/false);
if (header.cubeTiling.isBias) mm_.SetBias(biasGm[offsetBias]);

// 推荐：一次写完整个 single-core tile
mm_.IterateAll(cGm[offsetC], /*enAtomic=*/0);

// 手动模式（Split-K 累加场景）：
// while (mm_.Iterate()) {
//     mm_.GetTensorC(cGm[offsetC], /*enAtomic=*/2);  // ATOMIC_ADD
// }
```

### 3.5 完整最小骨架

```cpp
template <typename T, typename BiasT = float>
class MatmulKernelImpl {
public:
    using A_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using B_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using C_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T>;
    using BIAS_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, BiasT>;

    __aicore__ inline void Init(GM_ADDR aGM, GM_ADDR bGM, GM_ADDR biasGM,
                                GM_ADDR cGM, GM_ADDR tilingGM, TPipe* pipe) {
        if ASCEND_IS_AIV { return; }                              // (1) 仅 AIC 执行
        LoadTilingFromGM<TilingHeader>(tilingGM, header_);        // (2) GM→stack
        aGm_.SetGlobalBuffer((__gm__ T*)aGM, M*K);
        bGm_.SetGlobalBuffer((__gm__ T*)bGM, K*N);
        cGm_.SetGlobalBuffer((__gm__ T*)cGM, M*N);
        if (header_.cubeTiling.isBias) biasGm_.SetGlobalBuffer((__gm__ BiasT*)biasGM, N);
        mm_.SetSubBlockIdx(0);
        mm_.Init(&header_.cubeTiling, pipe);                      // (3) stack 指针
        // 默认 CubeMathType=4 (KEEP_FLOAT_DTYPE)，FP32 走全精度 cube；
        // 配合 host 端 tilingApi.SetMadType(MatrixMadType::NORMAL) 使用。
        mm_.SetHF32(false, 0);
    }

    __aicore__ inline void Process() {
        if ASCEND_IS_AIV { return; }
        const int32_t blockIdx = GetBlockIdx();
        if (blockIdx >= header_.totalBlock) return;
        const int32_t mIdx = blockIdx / header_.nTotalCnt;
        const int32_t nIdx = blockIdx % header_.nTotalCnt;
        // 尾块、偏移略
        mm_.SetSingleShape(curSingleM, curSingleN, K);
        mm_.SetTensorA(aGm_[offsetA], false);
        mm_.SetTensorB(bGm_[offsetB], false);
        if (header_.cubeTiling.isBias) mm_.SetBias(biasGm_[offsetBias]);
        mm_.IterateAll(cGm_[offsetC], 0);
        PipeBarrier<PIPE_ALL>();
    }

    __aicore__ inline void End() { mm_.End(); }
private:
    TilingHeader header_{};
    MatmulImpl<A_TYPE, B_TYPE, C_TYPE, BIAS_TYPE, MM_CFG_NO_PRELOAD> mm_;
    GlobalTensor<T> aGm_, bGm_, cGm_;
    GlobalTensor<BiasT> biasGm_;
};
```

### 3.5.1 编译期 trans 标志 + 多 dtype 的 12-entry 模板（推荐）

`MatmulType<TPos, Format, T, IS_TRANS>` 的第 4 个模板参数 `IS_TRANS` 是 **constexpr bool**，且 `SetTensorA(gm, isTrans)` 的运行时参数 **必须与 IS_TRANS 模板参数完全一致**——cube 内部 NZ 分形 / L1 双缓冲深度按错的方向计算后会输出错位 / NaN。要支持运行时 `(transpose_a, transpose_b)` 的 4 种组合 × 3 种 dtype，**必须每种组合各编译一份 kernel**：

```cpp
template <typename T, bool TRANS_A, bool TRANS_B>
class MatmulKernelImpl {
public:
    using A_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     TRANS_A>;
    using B_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     TRANS_B>;
    using C_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T>;
    using BIAS_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, float>;

    __aicore__ inline void Process() {
        if ASCEND_IS_AIV { return; }
        // ... blockIdx → (mIdx, nIdx) + 尾块尺寸 ...

        // 编译期 trans 决定 GM 偏移公式（见下表）
        const uint64_t offsetA = TRANS_A
            ? uint64_t(mIdx) * singleCoreM
            : uint64_t(mIdx) * singleCoreM * uint64_t(K);
        const uint64_t offsetB = TRANS_B
            ? uint64_t(nIdx) * singleCoreN * uint64_t(K)
            : uint64_t(nIdx) * singleCoreN;

        mm_.SetSingleShape(curSingleM, curSingleN, K);
        mm_.SetTensorA(aGm_[offsetA], TRANS_A);   // 运行时 arg == 编译期 IS_TRANS
        mm_.SetTensorB(bGm_[offsetB], TRANS_B);
        mm_.IterateAll(cGm_[offsetC], 0);
    }
};

// 用宏一次铺开 4 个 trans 组合 × 一种 dtype = 4 个 entry
#define MATMUL_KERNEL_ENTRIES(DTYPE_TAG, T)                                                   \
    extern "C" __global__ __aicore__ void <op>_##DTYPE_TAG##_ff(                              \
        GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM, GM_ADDR tilingGM) {                            \
        TPipe pipe; MatmulKernelImpl<T, false, false> op;                                     \
        op.Init(aGM, bGM, cGM, tilingGM, &pipe); op.Process(); op.End();                      \
    }                                                                                         \
    extern "C" __global__ __aicore__ void <op>_##DTYPE_TAG##_ft(GM_ADDR a,GM_ADDR b,GM_ADDR c,GM_ADDR t){ \
        TPipe pipe; MatmulKernelImpl<T, false, true>  op; op.Init(a,b,c,t,&pipe); op.Process(); op.End();}\
    extern "C" __global__ __aicore__ void <op>_##DTYPE_TAG##_tf(GM_ADDR a,GM_ADDR b,GM_ADDR c,GM_ADDR t){ \
        TPipe pipe; MatmulKernelImpl<T, true,  false> op; op.Init(a,b,c,t,&pipe); op.Process(); op.End();}\
    extern "C" __global__ __aicore__ void <op>_##DTYPE_TAG##_tt(GM_ADDR a,GM_ADDR b,GM_ADDR c,GM_ADDR t){ \
        TPipe pipe; MatmulKernelImpl<T, true,  true>  op; op.Init(a,b,c,t,&pipe); op.Process(); op.End();}

MATMUL_KERNEL_ENTRIES(fp16, half)
MATMUL_KERNEL_ENTRIES(bf16, bfloat16_t)
MATMUL_KERNEL_ENTRIES(fp32, float)
// → 共 12 个 extern "C" __global__ entry，host 按 (dtype, transA, transB) 分发
```

**Trans 标志驱动的 GM 偏移公式速查**（C 始终非转置）：

| 标志 | 物理 layout | tile 起始偏移 |
|------|-------------|---------------|
| `transA=false` | A 是 `[M, K]` | `offsetA = mIdx * singleCoreM * K` |
| `transA=true ` | A 是 `[K, M]` | `offsetA = mIdx * singleCoreM` |
| `transB=false` | B 是 `[K, N]` | `offsetB = nIdx * singleCoreN` |
| `transB=true ` | B 是 `[N, K]` | `offsetB = nIdx * singleCoreN * K` |
| C（始终）      | `[M, N]`     | `offsetC = mIdx * singleCoreM * N + nIdx * singleCoreN` |

> **常见陷阱**：在测试用例 / 性能用例的数据准备阶段忘记按 trans 调整 a/b 物理 shape — 例如 `transA=true` 时 a 应是 `[K, M]` 而不是 `[M, K]`，否则 host TORCH_CHECK(Ka==Kb) 当场失败。详见 `matmul-tiling.md` §"用例 / 测试侧的 shape 校验同样要按 trans"。

### 3.5.2 No-bias 变体（很多自定义 matmul / linear 不带 bias）

实际工程中大量 matmul / linear 算子不带 bias（如纯 attention QK^T、MM）。对应简化：

| 位置 | 改动 |
|------|------|
| Kernel `extern "C"` 入口签名 | 从 `(aGM, bGM, biasGM, cGM, tilingGM)` → `(aGM, bGM, cGM, tilingGM)` |
| `BIAS_TYPE` 模板参数 | **仍然要传** `MatmulType<...float>`（cube 内部按 `header.cubeTiling.isBias` 判定是否真的 SetBias） |
| `header_.cubeTiling.isBias` | 由 host 端 `tilingApi.SetBias(false)` 写入；kernel 端 `if (isBias) mm_.SetBias(...)` 直接进 false 分支 |
| Host `EXEC_KERNEL_CMD` | 不传 bias_tensor：`EXEC_KERNEL_CMD(<op>_fp16_ff, blockDim, a, b, c, tiling_tensor)` |

**不要**省掉 `BIAS_TYPE` 模板参数 — `MatmulImpl<A,B,C>` 三参数版本会让 cube 内部走错重载路径，部分 SoC 会拒绝编译。

### 3.5.3 op.End() 必须显式调用

`mm_.End()` 用来释放 cube 占用的 L1/L0 资源句柄。简化骨架（§3.5）的最小启动代码是：

```cpp
TPipe pipe;
MatmulKernelImpl<T, TRANS_A, TRANS_B> op;
op.Init(aGM, bGM, cGM, tilingGM, &pipe);
op.Process();
op.End();   // ← 必加；漏掉会让多次连续调用累积 L1 句柄泄露，最终 init 失败
```

### 3.6 完整 Kernel 骨架（L2 / Split-K / Batch）

适用于需要 L2 Cache 优化、Split-K 累加、Batch 维度处理的大算子。tiling 策略（L2 切分、核间分配、错位分核等）详见 `ascendc-operator-design/references/matmul-tiling.md`。

```cpp
template <class A_TYPE, class B_TYPE, class C_TYPE, class BIAS_TYPE,
          class BLOCK_TYPE = MatmulBaseBlock,
          const MatmulConfig &MM_CFG = MM_CFG_NO_PRELOAD>
class MatmulKernel {
public:
    __aicore__ inline void Init(GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM,
                                GM_ADDR biasGM, GM_ADDR tilingGM, TPipe *pipe) {
        if ASCEND_IS_AIV { return; }                                  // (1) 仅 Cube 执行

        LoadTilingFromGM(tilingGM, header_);                          // (2) GM→stack

        aGm_.SetGlobalBuffer(reinterpret_cast<__gm__ A_T*>(aGM), uint64_t(M) * Ka);
        bGm_.SetGlobalBuffer(reinterpret_cast<__gm__ B_T*>(bGM), uint64_t(Kb) * N);
        cGm_.SetGlobalBuffer(reinterpret_cast<__gm__ C_T*>(cGM), uint64_t(M) * N);
        if (isBias) biasGm_.SetGlobalBuffer(reinterpret_cast<__gm__ BiasT*>(biasGM), N);
        SetL2CacheEnable(l2cacheUseInfo, aGm_, bGm_, cGm_, biasGm_);

        mm_.SetSubBlockIdx(0);
        mm_.Init(&header_.cubeTiling, pipe);                          // (3) stack 指针

        if (NZ format) SetOrgShape(...);                              // (4) NZ 格式
    }

    __aicore__ inline void Process() {
        if ASCEND_IS_AIV { return; }
        if (GetBlockIdx() >= totalBlock) return;                       // (5) 越界守卫

        mm_.SetHF32(false, 0);
        if (isHf32) mm_.SetHF32(true, 1);

        bool reverse = true;
        for (uint64_t mTile = 0; mTile < mTileCntL2; ++mTile) {        // (6) L2 双层循环
            reverse = !reverse;
            for (uint64_t t = 0; t < nTileCntL2; ++t) {
                uint64_t nTile = reverse ? (nTileCntL2 - t - 1) : t;   //     serpentine
                block_.UpdateBlockCnt(mTile, nTile);
                block_.InitBlockIndex(index);
                for (uint64_t r = 0; r < block_.realRound; ++r) {       // (7) 核内 round 循环
                    if (rowOrder == 0) block_.UpdateBasicIndex(r);      //     错位分核
                    if (block_.index < block_.totalTileCnt) {
                        block_.UpdateBlockParams(mTile, nTile);
                        block_.CalcGMOffset(mTile, nTile);
                        mm_.SetSingleShape(block_.singleCoreM,
                                           block_.singleCoreN, K);
                        mm_.SetTensorA(aGm_[off.A], block_.isTransposeA);
                        mm_.SetTensorB(bGm_[off.B], block_.isTransposeB);
                        if (isBias) mm_.SetBias(biasGm_[off.Bias]);
                        mm_.Iterate();                                  //     单 base 块
                        mm_.GetTensorC(cGm_[off.C], enAtomic);
                    }
                    block_.UpdateBlockIndex();
                }
            }
        }

        PipeBarrier<PIPE_ALL>();                                        // (8) 收尾
        SetAtomicNone();
        mm_.SetHF32(false, 0);
    }

    __aicore__ inline void End() { mm_.End(); }
};
```

> **小算子简化**：若不需要 L2/Split-K/Batch，且 `(M,N)` 直接按 (mIdx, nIdx) 一次性切分到核，可以把 (6)(7) 合并为 §3.5 的 `IterateAll` 模式。

---

## 4. Tiling Header GM → stack 装载

> **这是自定义 MatMul 类算子最容易出错的点之一。** tiling 数据结构定义见 `ascendc-operator-design/references/matmul-tiling.md` §"Tiling 数据结构"。

### 4.1 正确实现（4-byte 对齐 GM 标量读）

```cpp
template <typename HeaderT>
__aicore__ inline void LoadTilingFromGM(GM_ADDR tilingGM, HeaderT &dstStack) {
    static_assert(alignof(HeaderT) % sizeof(int32_t) == 0,
                  "TilingHeader must be 4-byte aligned for int32-wise GM scalar reads");
    constexpr uint32_t HEADER_INTS =
        (sizeof(HeaderT) + sizeof(int32_t) - 1U) / sizeof(int32_t);
    const auto *gmInts  = reinterpret_cast<const __gm__ int32_t *>(tilingGM);
    auto       *dstInts = reinterpret_cast<int32_t *>(&dstStack);
    for (uint32_t i = 0; i < HEADER_INTS; ++i) {
        dstInts[i] = gmInts[i];
    }
}
```

### 4.2 TilingHeader 推荐写法

```cpp
#pragma pack(push, 8)
struct TilingHeader {
    AscendC::tiling::TCubeTiling cubeTiling;   // CANN 标准 cube tiling（POD，~196 字节）
    int32_t mTotalCnt;                         // ceil(M / singleCoreM)
    int32_t nTotalCnt;                         // ceil(N / singleCoreN)
    int32_t totalBlock;                        // mTotalCnt * nTotalCnt
    int32_t reserved;                          // 8 字节对齐
};
#pragma pack(pop)
```

### 4.3 反模式（必须避免）

```cpp
// ❌ 1-byte 标量循环：N 倍多的 GM 访问，且 cross-cache-line 时编译器可能保留
//    严格 __gm__ 语义导致结果不可预测。
template <typename T>
__aicore__ inline void GmToLocalCopy(T &dst, const __gm__ T &src) {
    auto *pDst = reinterpret_cast<uint8_t*>(&dst);
    const auto *pSrc = reinterpret_cast<const __gm__ uint8_t*>(&src);
    for (uint32_t i = 0; i < sizeof(T); ++i) pDst[i] = pSrc[i];
}

// ❌ DataCopyPad 到 UB（arch ≥ 220 AIC 无 UB 分配权 → MPU fault）
TBuf<> tilingBuf;  // 默认 TPosition::UB
pipe->InitBuffer(tilingBuf, ...);                    // ← AIC 上 fault

// ❌ DataCopy 到 L1 + reinterpret_cast<HeaderT*>(GetPhyAddr())
//    (DMA 本身可以成功，但把 L1 物理地址当 scalar pointer 喂给 MatmulImpl::Init
//     会在内部 dereference 时 MPU fault)
TBuf<TPosition::A1> tilingBuf;
LocalTensor<int32_t> l1Local = tilingBuf.Get<int32_t>();
DataCopy(l1Local, gmTensor, alignedInts);
auto *header = reinterpret_cast<const HeaderT*>(l1Local.GetPhyAddr());  // ← 危险
mm_.Init(&header->cubeTiling, pipe);                                     // ← MPU fault
```

---

## 5. AIC / AIV 关系与数据类型支持

### 5.1 AIC / AIV 守卫

| 算子类 | 入口守卫 | 说明 |
|--------|---------|------|
| MatMul / BatchMatMul | `if ASCEND_IS_AIV { return; }` | 纯 AIC，AIV 直接退出 |

### 5.2 数据类型支持矩阵

| A | B | C | Bias | 说明 |
|---|---|---|------|------|
| float16 | float16 | float16 | float16 / float | 标准 FP16 |
| bfloat16 | bfloat16 | bfloat16 | bfloat16 / float | 标准 BF16，bias 推荐 fp32 |
| float | float | float | float | FP32，**默认配 `SetHF32(false, 0)` 走全精度 23-bit mantissa cube（CubeMathType=4 KEEP_FLOAT_DTYPE）** |


### 5.3 HF32 模式 / CubeMathType 选择

CANN aclnn 层 `CubeMathType` 在 AscendC 算子的对应实现：

| CubeMathType | 语义 | host SetMadType | kernel SetHF32 | 精度 (FP32) | 吞吐 |
|---|---|---|---|---|---|
| 1 ALLOW_FP32_DOWN_PRECISION | 允许 FP32→HF32 | `MatrixMadType::HF32` | `SetHF32(true, 1)` | ~10-bit mantissa (~2e-3 vs FP64) | ≈ 4x |
| 3 USE_HF32 | 强制 HF32 | `MatrixMadType::HF32` | `SetHF32(true, 1)` | 同上 | ≈ 4x |
| **4 KEEP_FLOAT_DTYPE** | **强制全 FP32** | **`MatrixMadType::NORMAL`** | **`SetHF32(false, 0)`** | **~23-bit mantissa (~7e-5 vs FP64)** | **1x** |

```cpp
// 推荐默认：CubeMathType=4 (KEEP_FLOAT_DTYPE)，通过 SKILL precision-eval 严格 FP32 阈值
// host:
tilingApi.SetMadType(matmul_tiling::MatrixMadType::NORMAL);
// kernel:
mm_.SetHF32(false, 0);

// 性能优先 / 训练前向常用：CubeMathType=3 (USE_HF32)
tilingApi.SetMadType(matmul_tiling::MatrixMadType::HF32);
mm_.SetHF32(true, 1);
```

**关键约束**：host madType 与 kernel SetHF32 必须配对。
- 若 host 用 NORMAL 但 kernel `SetHF32(true)`：tiling 按全精度分配 buffer，但 cube 仍走 HF32 — 浪费 buffer，且行为依赖具体 CANN 版本，不可移植。
- 若 host 用 HF32 但 kernel `SetHF32(false)`：tiling 按 HF32 分配较小 buffer，全精度路径可能 buffer 不足 → 编译/运行报错。

**与 `torch.mm` 行为对应**：
- `torch.npu.matmul.allow_hf32 = False` ↔ CubeMathType=4 (本算子默认) → MaxAbs vs FP64 ~ 1e-4
- `torch.npu.matmul.allow_hf32 = True`  ↔ CubeMathType=1/3 → MaxAbs vs FP64 ~ 2e-2

---

## 6. 接口调用流程速查

```
Init                           // (1) ASCEND_IS_AIV 守卫 → LoadTilingFromGM
   ↓
SetGlobalBuffer (A,B,C,Bias)
   ↓
mm_.SetSubBlockIdx(0)
mm_.Init(&header.cubeTiling, pipe)
mm_.SetHF32(...)               // (可选)
   ↓
Process / 每核循环：
   blockIdx → (mIdx, nIdx)
   尾块尺寸 + GM 偏移
   mm_.SetSingleShape(...)
   mm_.SetTensorA / SetTensorB / SetBias
   mm_.IterateAll(cGm[off], enAtomic)
   ↓
PipeBarrier<PIPE_ALL>()        // 收尾
SetAtomicNone()
   ↓
mm_.End()
```

---