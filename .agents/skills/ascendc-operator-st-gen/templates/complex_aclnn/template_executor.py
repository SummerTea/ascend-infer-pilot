#!/usr/bin/python
# -*- coding: utf-8 -*-
# 模板：CPU golden + NPU AclnnBaseApi（含 -cp 补丁占位）

import ctypes
import os
import sys

import torch

from atk.configs.dataset_config import InputDataset
from atk.configs.results_config import OutputData, TaskResult
from atk.tasks.api_execute import register
from atk.tasks.api_execute.base_api import BaseApi
from atk.tasks.api_execute.aclnn_base_api import AclnnBaseApi

# TODO: 若用 pytest golden，把 tests/pytest 加入 path
# _PYTEST_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../pytest"))
# sys.path.insert(0, _PYTEST_DIR)

# aclnn GetWorkspaceSize 须为 nullptr 的下标（按 docs 填写）
_ACLNN_NULLPTR_INPUT_IDX = ()  # 例: (3, 8, 9, 10)


def _get_golden_case(kwargs, task_result):
    """TODO: 返回含 cpu_output、input 的 case dict。"""
    raise NotImplementedError


def _sync_case_to_kwargs(kwargs, case):
    """TODO: 用 golden 覆盖 input_data.kwargs。"""
    pass


def _patch_aclnn_input_args(input_args, kwargs):
    """TODO: -cp 签名校验，如 softmax_scale -> ctypes.c_double。"""
    pass


@register("{{REGISTER_CPU}}")
class {{OP_NAME}}GoldenApi(BaseApi):
    def init_by_input_data(self, input_data: InputDataset):
        self._case = _get_golden_case(input_data.kwargs, self.task_result)
        _sync_case_to_kwargs(input_data.kwargs, self._case)

    def __call__(self, input_data: InputDataset, with_output: bool = False):
        out = self._case["cpu_output"]
        return out


@register("{{REGISTER_NPU}}")
class {{OP_NAME}}NpuApi(AclnnBaseApi):
    def _apply_aclnn_nullptr_inputs(self, input_args):
        from atk.tasks.backends.lib_interface.acl_wrapper import AclTensor
        null_ptr = ctypes.cast(ctypes.c_void_p(None), ctypes.POINTER(AclTensor))
        for idx in _ACLNN_NULLPTR_INPUT_IDX:
            if idx < len(input_args):
                input_args[idx] = null_ptr

    def init_by_input_data(self, input_data: InputDataset):
        case = _get_golden_case(input_data.kwargs, self.task_result)
        _sync_case_to_kwargs(input_data.kwargs, case)
        self._kwargs = input_data.kwargs
        pyaclnn = self.device == "pyaclnn"
        if pyaclnn:
            for k, v in list(input_data.kwargs.items()):
                if isinstance(v, torch.Tensor) and not v.is_npu:
                    input_data.kwargs[k] = v.npu()
        input_args, output_packages = super().init_by_input_data(input_data)
        if pyaclnn:
            self._apply_aclnn_nullptr_inputs(input_args)
            _patch_aclnn_input_args(input_args, self._kwargs)
            self.input_args = input_args
        return input_args, output_packages

    def __call__(self):
        if self.device == "pyaclnn" and getattr(self, "input_args", None):
            self._apply_aclnn_nullptr_inputs(self.input_args)
            _patch_aclnn_input_args(self.input_args, self._kwargs)
        return super().__call__()

    def after_call(self, output_packages):
        # TODO: 与 pytest/custom 一致的前向；或 super().after_call
        outputs = [self.acl_tensor_to_torch(x).cpu() for x in output_packages]
        return outputs[0]
