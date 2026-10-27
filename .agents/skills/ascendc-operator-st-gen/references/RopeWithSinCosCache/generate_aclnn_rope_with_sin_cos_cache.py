import random
from typing import Union, List

from atk.case_generator.generator.generate_types import GENERATOR_REGISTRY
from atk.case_generator.generator.base_generator import CaseGenerator
from atk.configs.case_config import InputCaseConfig, CaseConfig
from functools import reduce


@GENERATOR_REGISTRY.register("generate_aclnn_rope_with_sin_cos_cache")
class aclnnRopeWithSinCosCacheGenerator(CaseGenerator):
    def after_case_config(self, case_config: CaseConfig) -> CaseConfig:
        mrope =True
        hunyuan =False
        if len(case_config.inputs[0].shape) == 1:
            num_tokens = case_config.inputs[0].shape[0]
            mrope = False
        elif len(case_config.inputs[0].shape) == 2:
            num_tokens = case_config.inputs[0].shape[1]
            if hunyuan:
                case_config.inputs[0].shape[0] = 4
            else:
                case_config.inputs[0].shape[0] = 3
            mrope = True
        
        if mrope:
            if hunyuan:
                headSize = 128
            else:
                # headSize随mrope变动修改
                headSize = 128
            rotary_dim = headSize
        else:
            headSize = random.randint(1,128)
            headSize = ((headSize + 32 - 1) // 32) * 32
        
            rotary_dim = random.randint(1,128)
            if case_config.inputs[1].dtype == 'fp32':
                rotary_dim = ((rotary_dim + 32 - 1) // 32) * 32
            else:
                rotary_dim = ((rotary_dim + 16 - 1) // 16) * 16
            if rotary_dim > headSize:
                rotary_dim = headSize

        if random.random() < 0.7:
            numQHeads = random.randint(1, 32)
            numKHeads = random.randint(1, 32)
        else:
            numQHeads = random.randint(32, 128)
            numKHeads = random.randint(32, 128)

        numQHeads = random.randint(32, 128)
        numKHeads = random.randint(32, 128)

        maxSeqLen = random.randint(1,num_tokens*2)
        
        case_config.inputs[0].range_values = [-1, maxSeqLen]

        case_config.inputs[1].shape[0] = num_tokens
        case_config.inputs[1].shape[1] = numQHeads * headSize

        case_config.inputs[2].shape[0] = num_tokens
        case_config.inputs[2].shape[1] = numKHeads * headSize
        case_config.inputs[2].dtype = case_config.inputs[1].dtype

        case_config.inputs[3].shape[0] = maxSeqLen
        case_config.inputs[3].shape[1] = headSize
        case_config.inputs[3].dtype = case_config.inputs[1].dtype

        # 这里适配rope和mrope
        if mrope:
            if hunyuan:
                values = random.choice([[[16], [16], [16], [16]], [[16], [16], [16], [16]]])
                case_config.inputs[4][3].range_values = values[3]
            else:
                values = random.choice([[[16], [24], [24]], [[24], [20], [20]]])
            case_config.inputs[4][0].range_values = values[0]
            case_config.inputs[4][1].range_values = values[1]
            case_config.inputs[4][2].range_values = values[2]
        else:
            case_config.inputs[4][0].range_values=[0]
            case_config.inputs[4][1].range_values=[0]
            case_config.inputs[4][2].range_values=[0]

        case_config.inputs[5].range_values = [headSize]

        return case_config  