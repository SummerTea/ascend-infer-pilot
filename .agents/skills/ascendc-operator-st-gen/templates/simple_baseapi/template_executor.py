#!/usr/bin/python
# -*- coding: utf-8 -*-
# 模板：简单自定义执行器（BaseApi，CPU/pyaclnn 共用）

import torch

from atk.configs.dataset_config import InputDataset
from atk.tasks.api_execute import register
from atk.tasks.api_execute.base_api import BaseApi


def _forward_cpu_or_npu(input_data: InputDataset):
    """TODO: 实现标杆/算子逻辑，从 input_data.kwargs 取参。"""
    raise NotImplementedError("implement forward for {{OP_NAME}}")


@register("{{REGISTER_SIMPLE}}")
class {{OP_NAME}}Api(BaseApi):
    def init_by_input_data(self, input_data: InputDataset):
        if self.device == "pyaclnn":
            # TODO: 需要上 NPU 的 tensor
            # input_data.kwargs["input0"] = input_data.kwargs["input0"].npu()
            query_dtype = input_data.kwargs.get("queryIn", torch.tensor(0)).dtype
            if self.task_result.output_info_list:
                self.task_result.output_info_list[0].dtype = str(query_dtype)

    def __call__(self, input_data: InputDataset, with_output: bool = False):
        return _forward_cpu_or_npu(input_data)
