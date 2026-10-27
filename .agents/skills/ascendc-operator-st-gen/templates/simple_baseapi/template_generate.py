#!/usr/bin/python
# -*- coding: utf-8 -*-
# 模板：用例生成器 — 替换 {{GENERATE}} / 联动 shape 逻辑

from atk.case_generator.generator.generate_types import GENERATOR_REGISTRY
from atk.case_generator.generator.base_generator import CaseGenerator
from atk.configs.case_config import CaseConfig


@GENERATOR_REGISTRY.register("{{GENERATE}}")
class {{OP_NAME}}Generator(CaseGenerator):
    def after_case_config(self, case_config: CaseConfig) -> CaseConfig:
        # TODO: 按算子文档约束联动 inputs 的 shape / dtype / range_values
        return case_config
