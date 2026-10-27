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
// MatMul / BatchMatMul 算子 op_host 参考模板
//
// 本文件给出 **两种** 主入口模板：
//   A. plain matmul（无 bias，支持运行时 transpose_a / transpose_b）
//      ── 与 matmul_op_kernel.cpp "模板 A" 配套
//      ── 12-way dispatch：3 dtype × 4 trans 组合 (FF/FT/TF/TT)
//      ── 真实落地参考 ascend-kernel/csrc/ops/matmul/op_host/matmul.cpp
//   B. matmul + bias（trans 编译期固定，3-way dispatch by dtype）
//      ── 与 matmul_op_kernel.cpp "模板 B" 配套
//
// 通用流程（与 references/matmul-tiling.md 一一对应）:
//   1. 输入校验
//   2. 通过 PlatformAscendC 获取硬件参数（AIC 核数、L1/L0 容量）
//   3. 调用 MultiCoreMatmulTiling::GetTiling(TCubeTiling&) 自动算 tiling
//   4. **强制覆写 M/N/Ka/Kb**（不同 CANN 版本对这些字段的填充策略不一致，
//      某些组合会被置 0 → kernel 端读到 0 → 输出全零）
//   5. 派生 mTotalCnt / nTotalCnt / totalBlock 等核间分发参数（singleCoreM/N
//      返回 0 时要兜底）
//   6. 把 TilingHeader 序列化到一个 device 端 uint8 tensor（blocking copy）
//   7. EXEC_KERNEL_CMD 启动 kernel（按 (dtype, transA, transB) 12-way 派发）
//
// 对应 kernel 模板见 matmul_op_kernel.cpp。
// ============================================================

#include "torch_kernel_helper.h"

#include "tiling/platform/platform_ascendc.h"
#include "tiling/matrix/matmul_tiling.h"
#include "tiling/matrix/bmm_tiling.h"  // BatchMatMul 用 MultiCoreMatmulTiling 同 API

// ---- 模板 A：12 个 entry = 3 dtype × 4 trans 组合 (FF/FT/TF/TT) ----
#include "aclrtlaunch_<op_name>_fp16_ff.h"
#include "aclrtlaunch_<op_name>_fp16_ft.h"
#include "aclrtlaunch_<op_name>_fp16_tf.h"
#include "aclrtlaunch_<op_name>_fp16_tt.h"
#include "aclrtlaunch_<op_name>_bf16_ff.h"
#include "aclrtlaunch_<op_name>_bf16_ft.h"
#include "aclrtlaunch_<op_name>_bf16_tf.h"
#include "aclrtlaunch_<op_name>_bf16_tt.h"
#include "aclrtlaunch_<op_name>_fp32_ff.h"
#include "aclrtlaunch_<op_name>_fp32_ft.h"
#include "aclrtlaunch_<op_name>_fp32_tf.h"
#include "aclrtlaunch_<op_name>_fp32_tt.h"

// ---- 模板 B（带 bias 变体，trans 编译期固定）----
// #include "aclrtlaunch_<op_name>_bias_fp16.h"
// #include "aclrtlaunch_<op_name>_bias_bf16.h"
// #include "aclrtlaunch_<op_name>_bias_fp32.h"

#include "../op_kernel/<op_name>_tiling_header.h"

#include <cstring>
#include <algorithm>

namespace ascend_kernel {

namespace {

// ============================================================
// TilingHeader 填充：调用 CANN 标准 MultiCoreMatmulTiling
// ============================================================
//
// MultiCoreMatmulTiling::GetTiling(TCubeTiling&) 会根据 SoC 自动决定：
//   - baseM / baseN / baseK    （cube 一次发射的块大小）
//   - singleCoreM / singleCoreN / singleCoreK （单核处理大小）
//   - depthA1 / depthB1, stepM/N/Ka/Kb   （L1 双缓冲深度与 base 块步长）
//   - dbL0A / dbL0B / dbL0C    （L0 双缓冲）
//   - usedCoreNum             （实际使用核数，≤ coreNum）
//   - shareL1Size / shareL0CSize / shareUbSize
//
// CANN 版本差异（必须做防御）：
//   * **M / N / Ka / Kb 字段在某些组合下被置 0**：例如 SetBias(true) 但实际未用、
//     或 SetMadType(NORMAL) 与 cubeDtype=FLOAT 组合，不同 CANN（8.0/8.1/9.0）
//     表现不同。返回后必须强制覆写为请求值，否则 kernel 端读到 0、blockIdx
//     推导出错、输出全零。
//   * **singleCoreM / singleCoreN 可能返回 0**：极小 shape (M*N < base*base)
//     或 SetDim(coreNum) 大于 mTotalCnt 时；派生 mTotalCnt = ceil(M, 0) → 除零。
//     必须用 `header.cubeTiling.singleCoreM > 0 ? ... : M` 兜底。
//   * **usedCoreNum 与 SetDim 不一致**：tilingApi 内部按 L1/L0 容量裁核；host
//     侧 blockDim 必须以返回值 mTotalCnt*nTotalCnt 为上界，不能用 SetDim 的值。
//   * SetBias(false) 时 BIAS_TYPE 仍然要正确设置（kernel 端 MatmulImpl 第 4
//     模板参数不能省，cube 内部按 isBias 标志判定是否真 SetBias）。
//   * MultiCoreMatmulTiling 不计算 L2 切分，需要 host 自己计算 mTileBlock/nTileBlock。
//
// ============================================================
void Fill<OpName>TilingHeader(int64_t M, int64_t N, int64_t K,
                              matmul_tiling::DataType cubeDtype,
                              int64_t coreNum,
                              bool transA, bool transB,
                              bool hasBias,
                              <OpName>::TilingHeader &header)
{
    auto *platform = platform_ascendc::PlatformAscendCManager::GetInstance();
    TORCH_CHECK(platform != nullptr, "<op_name>: PlatformAscendCManager::GetInstance() returned nullptr");

    matmul_tiling::MultiCoreMatmulTiling tilingApi(*platform);

    tilingApi.SetDim(static_cast<int32_t>(coreNum));
    tilingApi.SetAType(matmul_tiling::TPosition::GM, matmul_tiling::CubeFormat::ND, cubeDtype, transA);
    tilingApi.SetBType(matmul_tiling::TPosition::GM, matmul_tiling::CubeFormat::ND, cubeDtype, transB);
    tilingApi.SetCType(matmul_tiling::TPosition::GM, matmul_tiling::CubeFormat::ND, cubeDtype);
    tilingApi.SetBiasType(matmul_tiling::TPosition::GM, matmul_tiling::CubeFormat::ND,
                          matmul_tiling::DataType::DT_FLOAT);
    tilingApi.SetBias(hasBias);

    // CubeMathType=4 (KEEP_FLOAT_DTYPE): 显式 NORMAL madType，让 host tiling
    // 按"FP32 cube 全精度路径（4-way FP16-high/low decomp）"分配 L1/L0 buffer，
    // 而不是 HF32 单 pass 路径。配合 kernel 端 SetHF32(false, 0) 一起使用，
    // 才能保证 FP32 输入达到 SKILL precision-eval 的严格阈值 (Threshold=2^-13)。
    //
    // 若性能优先且接受 ~10-bit mantissa，可改为 SetMadType(MatrixMadType::HF32)。
    tilingApi.SetMadType(matmul_tiling::MatrixMadType::NORMAL);

    tilingApi.SetShape(static_cast<int32_t>(M), static_cast<int32_t>(N), static_cast<int32_t>(K));
    tilingApi.SetOrgShape(static_cast<int32_t>(M), static_cast<int32_t>(N), static_cast<int32_t>(K));

    int64_t ret = tilingApi.GetTiling(header.cubeTiling);
    TORCH_CHECK(ret == 0, "<op_name>: MultiCoreMatmulTiling::GetTiling failed, "
                          "M=", M, " N=", N, " K=", K);

    // 强制覆写：不同 CANN 版本字段填充策略有差异，确保 M/N/Ka/Kb 与请求一致。
    header.cubeTiling.M  = static_cast<int32_t>(M);
    header.cubeTiling.N  = static_cast<int32_t>(N);
    header.cubeTiling.Ka = static_cast<int32_t>(K);
    header.cubeTiling.Kb = static_cast<int32_t>(K);

    // 派生核间分发计数（kernel 端 blockIdx → (mIdx, nIdx) 的依据）
    const int32_t singleCoreM =
        header.cubeTiling.singleCoreM > 0 ? header.cubeTiling.singleCoreM : static_cast<int32_t>(M);
    const int32_t singleCoreN =
        header.cubeTiling.singleCoreN > 0 ? header.cubeTiling.singleCoreN : static_cast<int32_t>(N);

    header.mTotalCnt  = static_cast<int32_t>((M + singleCoreM - 1) / singleCoreM);
    header.nTotalCnt  = static_cast<int32_t>((N + singleCoreN - 1) / singleCoreN);
    header.totalBlock = header.mTotalCnt * header.nTotalCnt;
    header.reserved   = 0;

    // 大算子：在此处补充计算 L2 级 tiling
    //   header.mTileCntL2 / nTileCntL2 / mTileBlock / nTileBlock / calOrder
    //   计算原则：
    //     - 估算 L2 容量：l2Size = ascendcPlatform->GetL2CacheSize();
    //     - mTileBlock × nTileBlock × (baseM*baseK + baseN*baseK) * dtypeSize ≤ l2Size / 2
    //     - 当 N >> M 时 calOrder = COL_FIRST = 2，否则 ROW_FIRST = 1
    //   小算子可全部置 1（即不切 L2）。
}

// ============================================================
// TilingHeader → device tensor
// ============================================================
//
// 关键点：
//   1. 在 CPU 上拼好 uint8 buffer，再 to(device) — 避免直接构造 NPU 内存写入失败
//   2. **必须** non_blocking=false：kernel 启动前 tiling 数据必须在 device 上就位
// ============================================================
at::Tensor Build<OpName>TilingDeviceTensor(const <OpName>::TilingHeader &header,
                                            const at::Tensor &device_like)
{
    auto cpu_buf = at::empty({static_cast<int64_t>(sizeof(<OpName>::TilingHeader))},
                             at::TensorOptions().dtype(at::kByte).device(at::kCPU));
    std::memcpy(cpu_buf.data_ptr(), &header, sizeof(<OpName>::TilingHeader));
    return cpu_buf.to(device_like.device(), /*non_blocking=*/false, /*copy=*/true);
}

}  // namespace

// ============================================================
// 模板 A：plain matmul 主入口（无 bias，12-way dispatch）
// ============================================================
at::Tensor <op_name>(const at::Tensor &a, const at::Tensor &b,
                     bool transpose_a = false, bool transpose_b = false)
{
    // ---- 1. 输入校验 ----
    TORCH_CHECK(a.dim() == 2, "<op_name>: 'a' must be 2D, got dim=", a.dim());
    TORCH_CHECK(b.dim() == 2, "<op_name>: 'b' must be 2D, got dim=", b.dim());
    TORCH_CHECK(a.scalar_type() == b.scalar_type(),
                "<op_name>: 'a' and 'b' must have same dtype, got a=",
                a.scalar_type(), " b=", b.scalar_type());
    TORCH_CHECK(a.scalar_type() == at::kHalf || a.scalar_type() == at::kBFloat16
                || a.scalar_type() == at::kFloat,
                "<op_name>: only float16/bfloat16/float32 are supported, got ",
                a.scalar_type());
    TORCH_CHECK(a.device() == b.device(), "<op_name>: 'a' and 'b' must be on the same device");
    TORCH_CHECK(a.is_contiguous(), "<op_name>: 'a' must be contiguous");
    TORCH_CHECK(b.is_contiguous(), "<op_name>: 'b' must be contiguous");

    // ---- 2. 按 trans 标志推导 (M, N, K) ----
    //   transA=false: a=[M,K], transA=true: a=[K,M]
    //   transB=false: b=[K,N], transB=true: b=[N,K]
    //   错误的用例数据会让 Ka != Kb，提示信息要把 trans 标志一起 dump 出来
    //   方便快速定位（实际项目里高频出现）。
    const int64_t M  = transpose_a ? a.size(1) : a.size(0);
    const int64_t Ka = transpose_a ? a.size(0) : a.size(1);
    const int64_t Kb = transpose_b ? b.size(1) : b.size(0);
    const int64_t N  = transpose_b ? b.size(0) : b.size(1);
    TORCH_CHECK(Ka == Kb,
                "<op_name>: K dim mismatch, Ka=", Ka, " Kb=", Kb,
                " (a.shape=", a.sizes(), " b.shape=", b.sizes(),
                " transpose_a=", transpose_a, " transpose_b=", transpose_b, ")");
    TORCH_CHECK(M > 0 && N > 0 && Ka > 0,
                "<op_name>: M, N, K must all be positive, got M=", M, " N=", N, " K=", Ka);

    // ---- 3. 输出 tensor ----
    at::Tensor c = at::empty({M, N}, a.options());

    // ---- 4. 硬件参数 ----
    auto *platform = platform_ascendc::PlatformAscendCManager::GetInstance();
    TORCH_CHECK(platform != nullptr, "<op_name>: failed to get PlatformAscendCManager");
    const int64_t aicCoreNum = static_cast<int64_t>(platform->GetCoreNumAic());
    TORCH_CHECK(aicCoreNum > 0, "<op_name>: GetCoreNumAic returned ", aicCoreNum);

    matmul_tiling::DataType cubeDtype;
    switch (a.scalar_type()) {
        case at::kHalf:     cubeDtype = matmul_tiling::DataType::DT_FLOAT16; break;
        case at::kBFloat16: cubeDtype = matmul_tiling::DataType::DT_BF16;    break;
        case at::kFloat:    cubeDtype = matmul_tiling::DataType::DT_FLOAT;   break;
        default:            TORCH_CHECK(false, "<op_name>: unsupported dtype");
    }

    // ---- 5. Tiling 计算（含 CANN 版本差异防御，详见 Fill<OpName>TilingHeader）----
    <OpName>::TilingHeader header{};
    Fill<OpName>TilingHeader(M, N, Ka, cubeDtype, aicCoreNum,
                              transpose_a, transpose_b, /*hasBias=*/false, header);

    // ---- 6. Tiling header → device tensor（non_blocking=false）----
    at::Tensor tiling_tensor = Build<OpName>TilingDeviceTensor(header, a);

    // ---- 7. blockDim ----
    uint32_t blockDim = static_cast<uint32_t>(
        std::min<int64_t>(aicCoreNum, static_cast<int64_t>(header.totalBlock)));
    if (blockDim == 0) blockDim = 1;  // 防御性：M*N*K > 0 时不可能为 0

    // ---- 8. 12-way dispatch: (dtype, transA, transB) ----
    // 参考 ascend-kernel/csrc/ops/matmul/op_host/matmul.cpp 的真实落地实现。
    // 不要在 kernel 内做运行时 trans 分支：MatmulType<...IS_TRANS> 是 constexpr，
    // 必须每种 (transA, transB) 组合各编译一份 kernel。
    if (a.scalar_type() == at::kHalf) {
        if      (!transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_fp16_ff, blockDim, a, b, c, tiling_tensor);
        else if (!transpose_a &&  transpose_b) EXEC_KERNEL_CMD(<op_name>_fp16_ft, blockDim, a, b, c, tiling_tensor);
        else if ( transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_fp16_tf, blockDim, a, b, c, tiling_tensor);
        else                                    EXEC_KERNEL_CMD(<op_name>_fp16_tt, blockDim, a, b, c, tiling_tensor);
    } else if (a.scalar_type() == at::kBFloat16) {
        if      (!transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_bf16_ff, blockDim, a, b, c, tiling_tensor);
        else if (!transpose_a &&  transpose_b) EXEC_KERNEL_CMD(<op_name>_bf16_ft, blockDim, a, b, c, tiling_tensor);
        else if ( transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_bf16_tf, blockDim, a, b, c, tiling_tensor);
        else                                    EXEC_KERNEL_CMD(<op_name>_bf16_tt, blockDim, a, b, c, tiling_tensor);
    } else {  // at::kFloat
        if      (!transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_fp32_ff, blockDim, a, b, c, tiling_tensor);
        else if (!transpose_a &&  transpose_b) EXEC_KERNEL_CMD(<op_name>_fp32_ft, blockDim, a, b, c, tiling_tensor);
        else if ( transpose_a && !transpose_b) EXEC_KERNEL_CMD(<op_name>_fp32_tf, blockDim, a, b, c, tiling_tensor);
        else                                    EXEC_KERNEL_CMD(<op_name>_fp32_tt, blockDim, a, b, c, tiling_tensor);
    }

    return c;
}

// ============================================================
// 模板 B：matmul + bias 主入口（trans 编译期固定，3-way dispatch by dtype）
//
// 用法：仅当 trans_a/trans_b 在算子设计阶段已固定（如总是 transB=true 的 BMM 反向）
// 且需要 bias 时使用。否则优先用模板 A。
// ============================================================
at::Tensor <op_name>_with_bias(const at::Tensor &a, const at::Tensor &b,
                               const c10::optional<at::Tensor> &bias = c10::nullopt,
                               bool trans_a = false, bool trans_b = false)
{
    TORCH_CHECK(a.dim() == 2 && b.dim() == 2,
                "<op_name>_with_bias: a, b must be 2D");
    TORCH_CHECK(a.scalar_type() == b.scalar_type(),
                "<op_name>_with_bias: a/b dtype mismatch");
    TORCH_CHECK(a.is_contiguous() && b.is_contiguous(),
                "<op_name>_with_bias: a, b must be contiguous");

    const int64_t M  = trans_a ? a.size(1) : a.size(0);
    const int64_t Ka = trans_a ? a.size(0) : a.size(1);
    const int64_t Kb = trans_b ? b.size(1) : b.size(0);
    const int64_t N  = trans_b ? b.size(0) : b.size(1);
    TORCH_CHECK(Ka == Kb, "<op_name>_with_bias: K mismatch");

    if (bias.has_value()) {
        TORCH_CHECK(bias->dim() == 1 && bias->size(0) == N,
                    "<op_name>_with_bias: bias must be 1D with size N=", N);
        TORCH_CHECK(bias->scalar_type() == at::kFloat,
                    "<op_name>_with_bias: bias must be float32 (cube 内部累加精度)");
    }

    at::Tensor c = at::empty({M, N}, a.options());

    auto *platform = platform_ascendc::PlatformAscendCManager::GetInstance();
    const int64_t aicCoreNum = static_cast<int64_t>(platform->GetCoreNumAic());

    matmul_tiling::DataType cubeDtype;
    switch (a.scalar_type()) {
        case at::kHalf:     cubeDtype = matmul_tiling::DataType::DT_FLOAT16; break;
        case at::kBFloat16: cubeDtype = matmul_tiling::DataType::DT_BF16;    break;
        case at::kFloat:    cubeDtype = matmul_tiling::DataType::DT_FLOAT;   break;
        default:            TORCH_CHECK(false, "<op_name>_with_bias: unsupported dtype");
    }

    <OpName>::TilingHeader header{};
    Fill<OpName>TilingHeader(M, N, Ka, cubeDtype, aicCoreNum,
                              trans_a, trans_b, bias.has_value(), header);
    at::Tensor tiling_tensor = Build<OpName>TilingDeviceTensor(header, a);

    uint32_t blockDim = static_cast<uint32_t>(
        std::min<int64_t>(aicCoreNum, static_cast<int64_t>(header.totalBlock)));
    if (blockDim == 0) blockDim = 1;

    at::Tensor bias_tensor = bias.has_value()
        ? bias.value()
        : at::empty({0}, at::TensorOptions().dtype(at::kFloat).device(a.device()));

    // 3-way dispatch by dtype（trans 编译期固定，不需要 4 组合分发）
    // if (a.scalar_type() == at::kHalf) {
    //     EXEC_KERNEL_CMD(<op_name>_bias_fp16, blockDim, a, b, bias_tensor, c, tiling_tensor);
    // } else if (a.scalar_type() == at::kBFloat16) {
    //     EXEC_KERNEL_CMD(<op_name>_bias_bf16, blockDim, a, b, bias_tensor, c, tiling_tensor);
    // } else {
    //     EXEC_KERNEL_CMD(<op_name>_bias_fp32, blockDim, a, b, bias_tensor, c, tiling_tensor);
    // }

    return c;
}

// ============================================================
// BatchMatMul 主入口（可选）
// ============================================================
//
// 与 MatMul 主要差异：
//   1. 解析 batch 维度（最多 4 维）
//   2. 支持 batch 广播：batchA / batchB / max(batchA, batchB)
//   3. 当 batchB == 1 && !trans_a 时，把 batchA 合并进 M 维度（性能优化）
//   4. tiling 结构升级为 BatchMatmulTilingData（叠加 MultiBatchInfo）
//   5. 核间分配 = batchUsedCoreNum × tile-per-batch
// ============================================================
at::Tensor batch_<op_name>(const at::Tensor &a, const at::Tensor &b,
                           const c10::optional<at::Tensor> &bias = c10::nullopt,
                           bool trans_a = false, bool trans_b = false)
{
    // ---- 1. 校验 ----
    TORCH_CHECK(a.dim() >= 2 && a.dim() <= 6, "batch_<op_name>: a dim 2~6, got ", a.dim());
    TORCH_CHECK(b.dim() >= 2 && b.dim() <= 6, "batch_<op_name>: b dim 2~6, got ", b.dim());
    TORCH_CHECK(a.scalar_type() == b.scalar_type(),
                "batch_<op_name>: a/b dtype mismatch");

    // ---- 2. Batch 维度展开 ----
    int64_t batchA = 1, batchB = 1;
    for (int i = 0; i < a.dim() - 2; ++i) batchA *= a.size(i);
    for (int i = 0; i < b.dim() - 2; ++i) batchB *= b.size(i);
    int64_t batchC = std::max(batchA, batchB);

    int64_t M  = trans_a ? a.size(a.dim() - 1) : a.size(a.dim() - 2);
    int64_t Ka = trans_a ? a.size(a.dim() - 2) : a.size(a.dim() - 1);
    int64_t Kb = trans_b ? b.size(b.dim() - 1) : b.size(b.dim() - 2);
    int64_t N  = trans_b ? b.size(b.dim() - 2) : b.size(b.dim() - 1);
    TORCH_CHECK(Ka == Kb, "batch_<op_name>: K mismatch");

    // ---- 3. Batch 合并优化（B 不带 batch 时合并到 M）----
    if (batchB == 1 && !trans_a) {
        M *= batchA;
        batchA = 1;
        batchC = 1;
    }

    // ---- 4. 输出 ----
    std::vector<int64_t> output_shape;
    if (batchC > 1) output_shape.push_back(batchC);
    output_shape.push_back(M);
    output_shape.push_back(N);
    at::Tensor c = at::empty(output_shape, a.options());

    // ---- 5. Tiling（BatchMatmulTilingData = MatmulTilingData + MultiBatchInfo）----
    //   填充 tiling.matmulTiling 与 MatMul 完全一致（FillMatmulTilingHeader）
    //   再填充 multiBatchInfo:
    //     batchUsedCoreNum = min(batchC, coreNum)
    //     iterBatch        = ceil(batchC, batchUsedCoreNum * loopTimes)
    //     loopTimes        = ceil(batchC, iterBatch * batchUsedCoreNum)
    //     biasWithBatch    = bias.has_value() && bias->dim() > 1
    //     batchTileBlock   = batchA / batchC, etc.

    // ---- 6. 启动 batch kernel ----
    //   uint32_t blockDim = batchUsedCoreNum;
    //   EXEC_KERNEL_CMD(batch_<op_name>_<dtype>, blockDim, a, b, bias_tensor, c, tiling_tensor);

    return c;
}

}  // namespace ascend_kernel

