# vendored/ —— 上游原文拷贝的第三方技能

本目录为**上游原文拷贝**（vllm / sglang / Mooncake / evalscope 等上游 SKILL.md
逐字入库），**含 NVIDIA/CUDA 口径，未做昇腾适配** —— 仅供方法取用，**执行口径
一律以本工程 msprof 铁律与 `docs/` 为准**（性能数据只信 `msprof` / `msprof op`）。

- 逐项昇腾相关性评估（vendored 7 / external 21）见 `docs/04 §第三方技能昇腾相关性评估`。
- `external/` 为按域联网同步目录，说明见 `../external/README.md`。
- **请勿修改任何 vendored 技能的 `SKILL.md`**（保持上游原文，便于上游更新时 diff 合并）。
