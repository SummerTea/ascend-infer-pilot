#!/usr/bin/python
# -*- coding: utf-8 -*-

from atk.case_generator.generator.generate_types import GENERATOR_REGISTRY
from atk.case_generator.generator.base_generator import CaseGenerator
from atk.configs.case_config import CaseConfig


@GENERATOR_REGISTRY.register("{{GENERATE}}")
class {{OP_NAME}}Generator(CaseGenerator):
    def after_case_config(self, case_config: CaseConfig) -> CaseConfig:
        # TODO: case_id==0 可锚定 pytest paramset 首用例
        return case_config
