// Licensed under the BSD 3-Clause License  (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://opensource.org/licenses/BSD-3-Clause
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// ============================================================
// MatMul / BatchMatMul 算子 op_kernel 参考模板
//
// 本文件给出 **两种** 模板：
//   A. 编译期 trans 模板 + 12-entry 宏（无 bias，覆盖 fp16/bf16/fp32 × FF/FT/TF/TT）
//      ── 推荐用于支持运行时 (transpose_a, transpose_b) 的自定义 matmul
//      ── 真实落地参考 ascend-kernel/csrc/ops/matmul/op_kernel/kernel_matmul.cpp
//   B. 单 trans 简化模板 + bias（仅 dtype 维度的 3-entry）
//      ── 适用于 transA/B 编译期固定、需要 bias 的场景
//
// 通用流程（详见 references/matmul-tiling.md）:
//
// MatmulConfig 选择规则:
//   * **MM_CFG_NO_PRELOAD（enUnitFlag=true）是大多数自定义算子的默认**
//   * 缺少 enUnitFlag 会导致 cube 不把 L0C 写回 GM → 输出全零
//   * Split-K 用 ATOMIC_ADD + Iterate（不是 IterateAll）
//   * BatchMatMul 用 MM_CFG_ORDER_M
//
// 编译期 trans 标志的硬性约束:
//   * MatmulType<TPos, Format, T, IS_TRANS> 第 4 参数 IS_TRANS 是 constexpr bool；
//     SetTensorA(gm, isTrans) 的运行时 arg 必须与该 IS_TRANS 完全一致，否则 cube
//     内部 NZ 分形 / L1 双缓冲深度按错的方向计算，结果偏移错位 / NaN。
//   * 要支持运行时 (transA, transB) 的 4 种组合 × 3 种 dtype，必须铺 12 个
//     extern "C" 入口（见模板 A）。
//
// GM 偏移表（C 始终非转置）:
//   transA=false: A is [M,K]  → offsetA = mIdx*singleCoreM*K
//   transA=true : A is [K,M]  → offsetA = mIdx*singleCoreM
//   transB=false: B is [K,N]  → offsetB = nIdx*singleCoreN
//   transB=true : B is [N,K]  → offsetB = nIdx*singleCoreN*K
//   C (always)  :              offsetC = mIdx*singleCoreM*N + nIdx*singleCoreN
//
// 数据搬运规则（必读 references/data-copy-api.md）:
// ============================================================

#include "kernel_operator.h"
#include "lib/matmul_intf.h"

#include "<op_name>_tiling_header.h"

using namespace AscendC;
using namespace matmul;

namespace {

// ============================================================
// MatmulConfig：来自 ops-nn/matmul/mat_mul_v3/op_kernel/mat_mul_v3_common.h
// ============================================================

// 自定义算子默认配置：
//   enUnitFlag=true ── 使能 L0C → fixpipe → GM 的写回单元
//                       缺这个 flag 会导致 IterateAll/GetTensorC 无效，输出全零
constexpr MatmulConfig MM_CFG_NO_PRELOAD =
    GetMDLConfig(/*enableMixDualMaster=*/false,
                 /*enableUnitFlag=*/false,
                 /*doMTE2Preload=*/0,
                 /*isVecND2Nz=*/false,
                 /*isPerTensor=*/false,
                 /*isSplitK=*/false,
                 /*enUnitFlag=*/true);

// BatchMatMul 推荐配置（M-first 内层遍历 + IterateBatch 接口）
constexpr MatmulConfig MM_CFG_BMM_ORDER_M =
    GetNormalConfig(/*intrablockPartSum=*/false,
                    /*enableUnitFlag=*/false,
                    /*enableMixDualMaster=*/false,
                    /*batchMode=*/BatchMode::BATCH_LESS_THAN_L1,
                    /*isPerTensor=*/true,
                    /*iterateOrder=*/IterateOrder::ORDER_M);

// ============================================================
// 工具函数：把 TilingHeader 从 GM 拷到 stack（4-byte 对齐标量读）
// ============================================================
//
template <typename HeaderT>
__aicore__ inline void LoadTilingFromGM(GM_ADDR tilingGM, HeaderT &dstStack)
{
    static_assert(alignof(HeaderT) % sizeof(int32_t) == 0,
                  "TilingHeader must be 4-byte aligned for int32-wise GM scalar reads");

    constexpr uint32_t HEADER_BYTES = sizeof(HeaderT);
    constexpr uint32_t HEADER_INTS  = (HEADER_BYTES + sizeof(int32_t) - 1U) / sizeof(int32_t);

    const auto *gmInts  = reinterpret_cast<const __gm__ int32_t *>(tilingGM);
    auto       *dstInts = reinterpret_cast<int32_t *>(&dstStack);
    for (uint32_t i = 0; i < HEADER_INTS; ++i) {
        dstInts[i] = gmInts[i];
    }
}

}  // namespace

// ============================================================
// 模板 A：编译期 trans 模板 + 12-entry（无 bias，推荐用于 plain matmul / linear）
//
// 适用场景：
//   - 需要支持运行时 (transpose_a, transpose_b) 全部 4 种组合
//   - 不带 bias 的 plain matmul / linear（Q·K^T、纯 MM 等）
//   - 不需要 L2 / Split-K（小算子）
//
// 核心设计：
//   1. trans 是模板参数（TRANS_A、TRANS_B），与 MatmulType<...IS_TRANS> 模板参数
//      和 SetTensorA(gm, isTrans) 运行时 arg 三处保持完全一致（cube 内部 NZ 分形
//      会按编译期 IS_TRANS 计算，运行时 arg 不一致会输出错位/NaN）。
//   2. BIAS_TYPE 仍要传 MatmulType<...float>（cube 内部按 isBias 标志判定是否
//      真的 SetBias，但模板参数不能省 — 三参数 MatmulImpl<A,B,C> 在部分 SoC 编译失败）。
//   3. 用宏 MATMUL_KERNEL_ENTRIES(DTYPE_TAG, T) 一次铺开 4 个 trans 组合的 entry，
//      3 种 dtype 共 12 个入口。
// ============================================================
template <typename T, bool TRANS_A, bool TRANS_B>
class <OpName>KernelImplTrans {
public:
    using Header = ascend_kernel::<op_name>_op::TilingHeader;

    using A_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     TRANS_A>;
    using B_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     TRANS_B>;
    using C_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using BIAS_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, float, /*isTrans=*/false>;

    __aicore__ inline <OpName>KernelImplTrans() {}

    __aicore__ inline void Init(GM_ADDR aGM, GM_ADDR bGM,
                                GM_ADDR cGM, GM_ADDR tilingGM, TPipe *pipe)
    {
        if ASCEND_IS_AIV { return; }
        pipe_ = pipe;

        LoadTilingFromGM<Header>(tilingGM, header_);

        const int32_t M = header_.cubeTiling.M;
        const int32_t N = header_.cubeTiling.N;
        const int32_t K = header_.cubeTiling.Ka;

        aGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(aGM),
                             static_cast<uint64_t>(M) * static_cast<uint64_t>(K));
        bGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(bGM),
                             static_cast<uint64_t>(K) * static_cast<uint64_t>(N));
        cGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(cGM),
                             static_cast<uint64_t>(M) * static_cast<uint64_t>(N));

        mm_.SetSubBlockIdx(0);
        mm_.Init(&header_.cubeTiling, pipe_);

        // KEEP_FLOAT_DTYPE (CubeMathType=4)：FP32 走 4-way FP16 high/low 分解全精度路径
        // 与 host SetMadType(NORMAL) 配对；改 SetHF32(true, 1) 切到 HF32（cube ≈ 4× 吞吐，
        // 精度从 ~23-bit mantissa 降至 ~10-bit）。
        mm_.SetHF32(false, 0);
    }

    __aicore__ inline void Process()
    {
        if ASCEND_IS_AIV { return; }

        const int32_t blockIdx   = static_cast<int32_t>(GetBlockIdx());
        const int32_t totalBlock = header_.totalBlock;
        if (blockIdx >= totalBlock) return;            // 越界守卫：blockDim 可能 > totalBlock

        const int32_t mTotalCnt = header_.mTotalCnt;
        const int32_t nTotalCnt = header_.nTotalCnt;
        const int32_t mIdx      = blockIdx / nTotalCnt;
        const int32_t nIdx      = blockIdx % nTotalCnt;

        const int32_t M           = header_.cubeTiling.M;
        const int32_t N           = header_.cubeTiling.N;
        const int32_t K           = header_.cubeTiling.Ka;
        const int32_t singleCoreM = header_.cubeTiling.singleCoreM;
        const int32_t singleCoreN = header_.cubeTiling.singleCoreN;
        const int32_t curSingleM  = (mIdx == mTotalCnt - 1) ? (M - mIdx * singleCoreM) : singleCoreM;
        const int32_t curSingleN  = (nIdx == nTotalCnt - 1) ? (N - nIdx * singleCoreN) : singleCoreN;

        // 编译期 trans 决定 GM 偏移公式（详见文件头部"GM 偏移表"）
        const uint64_t offsetA = TRANS_A
            ? static_cast<uint64_t>(mIdx) * static_cast<uint64_t>(singleCoreM)
            : static_cast<uint64_t>(mIdx) * static_cast<uint64_t>(singleCoreM)
                                          * static_cast<uint64_t>(K);
        const uint64_t offsetB = TRANS_B
            ? static_cast<uint64_t>(nIdx) * static_cast<uint64_t>(singleCoreN)
                                          * static_cast<uint64_t>(K)
            : static_cast<uint64_t>(nIdx) * static_cast<uint64_t>(singleCoreN);
        const uint64_t offsetC = static_cast<uint64_t>(mIdx) * static_cast<uint64_t>(singleCoreM)
                                                             * static_cast<uint64_t>(N)
                               + static_cast<uint64_t>(nIdx) * static_cast<uint64_t>(singleCoreN);

        mm_.SetSingleShape(curSingleM, curSingleN, K);
        mm_.SetTensorA(aGm_[offsetA], TRANS_A);   // 运行时 arg == 编译期 IS_TRANS（强约束）
        mm_.SetTensorB(bGm_[offsetB], TRANS_B);
        mm_.IterateAll(cGm_[offsetC], /*enAtomic=*/0);

        PipeBarrier<PIPE_ALL>();
        SetAtomicNone();
    }

    __aicore__ inline void End() { mm_.End(); }

private:
    TPipe              *pipe_ = nullptr;
    Header              header_{};
    GlobalTensor<T>     aGm_;
    GlobalTensor<T>     bGm_;
    GlobalTensor<T>     cGm_;
    MatmulImpl<A_TYPE, B_TYPE, C_TYPE, BIAS_TYPE, MM_CFG_NO_PRELOAD> mm_;
};

// 用宏一次铺开 4 个 trans 组合 × 一种 dtype = 4 个 entry。
// host 端按 (a.scalar_type(), transpose_a, transpose_b) 选择对应入口。
//
// 命名约定：<op>_<dtype>_<ta><tb>，其中 t/f 表示 true/false：
//   <op>_fp16_ff = (transA=false, transB=false)
//   <op>_fp16_ft = (transA=false, transB=true )
//   <op>_fp16_tf = (transA=true , transB=false)
//   <op>_fp16_tt = (transA=true , transB=true )
#define MATMUL_KERNEL_ENTRIES(DTYPE_TAG, T)                                                       \
    extern "C" __global__ __aicore__ void <op_name>_##DTYPE_TAG##_ff(                             \
        GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM, GM_ADDR tilingGM)                                  \
    {                                                                                             \
        TPipe pipe;                                                                               \
        <OpName>KernelImplTrans<T, false, false> op;                                              \
        op.Init(aGM, bGM, cGM, tilingGM, &pipe);                                                  \
        op.Process();                                                                             \
        op.End();   /* 必加：释放 cube L1/L0 句柄 */                                               \
    }                                                                                             \
    extern "C" __global__ __aicore__ void <op_name>_##DTYPE_TAG##_ft(                             \
        GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM, GM_ADDR tilingGM)                                  \
    {                                                                                             \
        TPipe pipe;                                                                               \
        <OpName>KernelImplTrans<T, false, true> op;                                               \
        op.Init(aGM, bGM, cGM, tilingGM, &pipe);                                                  \
        op.Process();                                                                             \
        op.End();                                                                                 \
    }                                                                                             \
    extern "C" __global__ __aicore__ void <op_name>_##DTYPE_TAG##_tf(                             \
        GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM, GM_ADDR tilingGM)                                  \
    {                                                                                             \
        TPipe pipe;                                                                               \
        <OpName>KernelImplTrans<T, true, false> op;                                               \
        op.Init(aGM, bGM, cGM, tilingGM, &pipe);                                                  \
        op.Process();                                                                             \
        op.End();                                                                                 \
    }                                                                                             \
    extern "C" __global__ __aicore__ void <op_name>_##DTYPE_TAG##_tt(                             \
        GM_ADDR aGM, GM_ADDR bGM, GM_ADDR cGM, GM_ADDR tilingGM)                                  \
    {                                                                                             \
        TPipe pipe;                                                                               \
        <OpName>KernelImplTrans<T, true, true> op;                                                \
        op.Init(aGM, bGM, cGM, tilingGM, &pipe);                                                  \
        op.Process();                                                                             \
        op.End();                                                                                 \
    }

MATMUL_KERNEL_ENTRIES(fp16, half)
MATMUL_KERNEL_ENTRIES(bf16, bfloat16_t)
MATMUL_KERNEL_ENTRIES(fp32, float)

#undef MATMUL_KERNEL_ENTRIES

// ============================================================
// 模板 B：单 trans 简化模板 + bias（trans 编译期固定，3-entry）
//
// 适用场景：
//   - trans_a / trans_b 在算子设计阶段已固定（如 BMM 总是 transB=true）
//   - 需要 bias
//   - 不需要 L2 级切分（M*N*dtype ≤ L2/2）
//   - 不需要 Split-K
//   - 单 batch
//
// 大算子骨架请参考 mat_mul_base_kernel.h 的 L2 双层循环版本。
// ============================================================
template <typename T, typename BiasT = float>
class <OpName>KernelImpl {
public:
    using Header   = ascend_kernel::<op_name>_op::TilingHeader;

    using A_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using B_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using C_TYPE    = MatmulType<TPosition::GM, CubeFormat::ND, T,     /*isTrans=*/false>;
    using BIAS_TYPE = MatmulType<TPosition::GM, CubeFormat::ND, BiasT, /*isTrans=*/false>;

    __aicore__ inline <OpName>KernelImpl() {}

    __aicore__ inline void Init(GM_ADDR aGM, GM_ADDR bGM, GM_ADDR biasGM,
                                 GM_ADDR cGM, GM_ADDR tilingGM, TPipe *pipe)
    {
        if ASCEND_IS_AIV {
            return;  // 仅 Cube 执行
        }
        pipe_ = pipe;

        // 1. GM → stack TilingHeader（4-byte 标量读）
        LoadTilingFromGM<Header>(tilingGM, header_);

        const int32_t M = header_.cubeTiling.M;
        const int32_t N = header_.cubeTiling.N;
        const int32_t K = header_.cubeTiling.Ka;

        // 2. GlobalTensor 视图
        aGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(aGM),
                             static_cast<uint64_t>(M) * K);
        bGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(bGM),
                             static_cast<uint64_t>(K) * N);
        cGm_.SetGlobalBuffer(reinterpret_cast<__gm__ T *>(cGM),
                             static_cast<uint64_t>(M) * N);
        if (header_.cubeTiling.isBias) {
            biasGm_.SetGlobalBuffer(reinterpret_cast<__gm__ BiasT *>(biasGM), N);
        }

        // 3. MatmulImpl 初始化（&header_.cubeTiling 是 stack 指针，安全）
        mm_.SetSubBlockIdx(0);
        mm_.Init(&header_.cubeTiling, pipe_);

        // 4. 显式禁用 HF32 = CubeMathType=4 (KEEP_FLOAT_DTYPE)
        //
        // 默认情况下 cube 的 SetHF32 行为依赖编译期/运行期推断；为保证
        //   - FP32 输入走全 23-bit mantissa 路径（4-way FP16-high/low decomp）；
        //   - SKILL ascendc-operator-precision-eval 的 FP32 阈值
        //     (Threshold = 2^-13 ≈ 1.22e-4) 可被通过；
        //   - 与 `torch.mm/torch.bmm`（allow_hf32=False）输出一致；
        // 我们对所有 dtype 都显式 SetHF32(false, 0)。
        //
        // 若性能优先而精度允许 ~10-bit mantissa（如训练前向 / Attention QK），
        // 可改为 SetHF32(true, 1) 走 HF32 单 pass cube 路径，cube 吞吐 ≈ 4x。
        mm_.SetHF32(false, 0);
    }

    __aicore__ inline void Process()
    {
        if ASCEND_IS_AIV {
            return;
        }

        // 1. 越界守卫：blockDim 可能 > totalBlock
        const int32_t blockIdx   = static_cast<int32_t>(GetBlockIdx());
        const int32_t totalBlock = header_.totalBlock;
        if (blockIdx >= totalBlock) {
            return;
        }

        // 2. blockIdx → (mIdx, nIdx)
        const int32_t mTotalCnt = header_.mTotalCnt;
        const int32_t nTotalCnt = header_.nTotalCnt;
        const int32_t mIdx      = blockIdx / nTotalCnt;
        const int32_t nIdx      = blockIdx % nTotalCnt;

        // 3. 尾块尺寸（最后一行/列实际大小）
        const int32_t M           = header_.cubeTiling.M;
        const int32_t N           = header_.cubeTiling.N;
        const int32_t K           = header_.cubeTiling.Ka;
        const int32_t singleCoreM = header_.cubeTiling.singleCoreM;
        const int32_t singleCoreN = header_.cubeTiling.singleCoreN;
        const int32_t curSingleM  = (mIdx == mTotalCnt - 1) ? (M - mIdx * singleCoreM) : singleCoreM;
        const int32_t curSingleN  = (nIdx == nTotalCnt - 1) ? (N - nIdx * singleCoreN) : singleCoreN;

        // 4. GM 偏移
        const uint64_t offsetA = static_cast<uint64_t>(mIdx) * singleCoreM * K;
        const uint64_t offsetB = static_cast<uint64_t>(nIdx) * singleCoreN;
        const uint64_t offsetC = static_cast<uint64_t>(mIdx) * singleCoreM * N
                               + static_cast<uint64_t>(nIdx) * singleCoreN;

        // 5. 配置 cube 输入并触发计算
        mm_.SetSingleShape(curSingleM, curSingleN, K);
        mm_.SetTensorA(aGm_[offsetA], /*isTrans=*/false);
        mm_.SetTensorB(bGm_[offsetB], /*isTrans=*/false);
        if (header_.cubeTiling.isBias) {
            const uint64_t offsetBias = static_cast<uint64_t>(nIdx) * singleCoreN;
            mm_.SetBias(biasGm_[offsetBias]);
        }
        // IterateAll 内部完成 single-core tile 内所有 base 块的 cube 调度 + 写回 GM
        mm_.IterateAll(cGm_[offsetC], /*enAtomic=*/0);

        // 6. 收尾
        PipeBarrier<PIPE_ALL>();
        SetAtomicNone();
    }

    __aicore__ inline void End() { mm_.End(); }

private:
    TPipe              *pipe_ = nullptr;
    Header              header_{};             // stack-resident, scalar-addressable for MatmulImpl::Init
    GlobalTensor<T>     aGm_;
    GlobalTensor<T>     bGm_;
    GlobalTensor<T>     cGm_;
    GlobalTensor<BiasT> biasGm_;
    MatmulImpl<A_TYPE, B_TYPE, C_TYPE, BIAS_TYPE, MM_CFG_NO_PRELOAD> mm_;
};

// ============================================================
// 入口函数：每种 dtype 一个 extern "C" 入口
// ============================================================
extern "C" __global__ __aicore__ void <op_name>_bias_fp16(
    GM_ADDR aGM, GM_ADDR bGM, GM_ADDR biasGM, GM_ADDR cGM, GM_ADDR tilingGM)
{
    TPipe pipe;
    <OpName>KernelImpl<half> op;
    op.Init(aGM, bGM, biasGM, cGM, tilingGM, &pipe);
    op.Process();
    op.End();   // 必加：释放 cube L1/L0 句柄；漏掉会让多次连续调用累积 L1 句柄泄露
}

extern "C" __global__ __aicore__ void <op_name>_bias_bf16(
    GM_ADDR aGM, GM_ADDR bGM, GM_ADDR biasGM, GM_ADDR cGM, GM_ADDR tilingGM)
{
    TPipe pipe;
    <OpName>KernelImpl<bfloat16_t> op;
    op.Init(aGM, bGM, biasGM, cGM, tilingGM, &pipe);
    op.Process();
    op.End();
}

extern "C" __global__ __aicore__ void <op_name>_bias_fp32(
    GM_ADDR aGM, GM_ADDR bGM, GM_ADDR biasGM, GM_ADDR cGM, GM_ADDR tilingGM)
{
    TPipe pipe;
    <OpName>KernelImpl<float> op;
    op.Init(aGM, bGM, biasGM, cGM, tilingGM, &pipe);
    op.Process();
    op.End();
}

// ============================================================
// 大算子完整 L2+Block+BaseBlock 三级骨架（参考结构，按需实例化）
// ============================================================
//
// template <class A_TYPE, class B_TYPE, class C_TYPE, class BIAS_TYPE,
//           class BLOCK_TYPE = MatmulBaseBlock,
//           const MatmulConfig &MM_CFG = MM_CFG_NO_PRELOAD>
// class MatmulFullKernel {
// public:
//     __aicore__ inline void Process(uint64_t index = 0, uint8_t enAtomic = 0) {
//         if ASCEND_IS_AIV { return; }
//         mm_.SetHF32(false, 0);
//         if (block_.params_.isHf32) mm_.SetHF32(true, 1);
//
//         bool reverse = true;
//         for (uint64_t mTile = 0; mTile < block_.params_.mTileCntL2; ++mTile) {
//             reverse = !reverse;
//             for (uint64_t t = 0; t < block_.params_.nTileCntL2; ++t) {
//                 uint64_t nTile = reverse
//                     ? (block_.params_.nTileCntL2 - t - 1)
//                     : t;                                           // serpentine
//                 block_.UpdateBlockCnt(mTile, nTile);
//                 block_.InitBlockIndex(index);
//                 for (uint64_t r = 0; r < block_.params_.realRound; ++r) {
//                     if (block_.params_.rowOrder == 0) {
//                         block_.UpdateBasicIndex(r);                // 错位分核
//                     }
//                     if (block_.params_.index < block_.params_.totalTileCnt) {
//                         block_.UpdateBlockParams(mTile, nTile);
//                         block_.template CalcGMOffset<A_TYPE,B_TYPE,C_TYPE,BIAS_TYPE>(
//                             mTile, nTile);
//                         mm_.SetSingleShape(block_.params_.singleCoreM,
//                                            block_.params_.singleCoreN,
//                                            block_.matmulTilingData_->matmulTiling.singleCoreK);
//                         mm_.SetTensorA(aGm_[block_.offset_.offsetA], block_.params_.isTransposeA);
//                         mm_.SetTensorB(bGm_[block_.offset_.offsetB], block_.params_.isTransposeB);
//                         if (block_.matmulTilingData_->matmulTiling.isBias) {
//                             mm_.SetBias(biasGm_[block_.offset_.offsetBias]);
//                         }
//                         mm_.Iterate();                              // 单 base 块
//                         mm_.GetTensorC(cGm_[block_.offset_.offsetC], enAtomic);
//                     }
//                     block_.UpdateBlockIndex();
//                 }
//             }
//         }
//         PipeBarrier<PIPE_ALL>();
//         SetAtomicNone();
//         mm_.SetHF32(false, 0);
//     }
// };
//
