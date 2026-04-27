# 蓝心模型参数优化方案

## 一、参数优化建议

### 1. 核心生成参数

| 参数名称 | 建议值 | 说明 | 性能影响 |
|---------|--------|------|----------|
| `max_new_tokens` | 100-300 | 限制生成文本长度，减少推理时间 | 显著提升速度 |
| `temperature` | 0.3-0.7 | 降低随机性，减少搜索空间 | 中度提升速度 |
| `do_sample` | False | 使用贪婪解码，减少计算开销 | 显著提升速度 |
| `top_p` | 0.7-0.9 | 限制采样范围，减少计算量 | 中度提升速度 |
| `num_beams` | 1-3 | 减少 beam search 的宽度 | 显著提升速度 |
| `repetition_penalty` | 1.0-1.1 | 适度惩罚重复，避免无限循环 | 轻微提升速度 |
| `eos_token_id` | 适当设置 | 及时停止生成，避免冗余输出 | 轻微提升速度 |

### 2. 批处理参数

| 参数名称 | 建议值 | 说明 | 性能影响 |
|---------|--------|------|----------|
| `batch_size` | 8-32 | 根据显存大小调整 | 提升吞吐量 |
| `max_batch_size` | 64-128 | 最大批处理大小 | 提升并发能力 |
| `max_seq_len` | 512-1024 | 限制输入序列长度 | 显著提升速度 |

### 3. 内存优化参数

| 参数名称 | 建议值 | 说明 | 性能影响 |
|---------|--------|------|----------|
| `device_map` | "auto" | 自动分配设备 | 优化内存使用 |
| `torch_dtype` | torch.bfloat16 | 使用半精度计算 | 显著提升速度 |
| `load_in_8bit` | True | 8位量化加载 | 减少内存使用 |
| `load_in_4bit` | True | 4位量化加载 | 显著减少内存使用 |

## 二、参数组合测试

### 1. 速度优先配置

```python
# 速度优先的参数配置
gen_kwargs = {
    "max_new_tokens": 200,
    "do_sample": False,  # 贪婪解码
    "temperature": 0.0,  # 确定性输出
    "top_p": 1.0,       # 不限制采样
    "num_beams": 1,      # 不使用beam search
    "repetition_penalty": 1.0,
    "eos_token_id": tokenizer.eos_token_id
}
```

### 2. 平衡配置

```python
# 速度与质量平衡的参数配置
gen_kwargs = {
    "max_new_tokens": 300,
    "do_sample": True,
    "temperature": 0.7,
    "top_p": 0.9,
    "num_beams": 2,
    "repetition_penalty": 1.1,
    "eos_token_id": tokenizer.eos_token_id
}
```

### 3. 质量优先配置

```python
# 质量优先的参数配置
gen_kwargs = {
    "max_new_tokens": 512,
    "do_sample": True,
    "temperature": 1.0,
    "top_p": 0.95,
    "num_beams": 3,
    "repetition_penalty": 1.1,
    "eos_token_id": tokenizer.eos_token_id
}
```

## 三、测试策略

### 1. 基准测试
- 选择100个代表性问题作为测试集
- 测量不同参数组合的响应时间
- 评估回答质量

### 2. 性能指标
- **响应时间**：从输入到输出的总时间
- **吞吐量**：单位时间内处理的请求数
- **内存使用**：峰值内存消耗
- **质量评分**：人工评估回答质量（1-5分）

### 3. 测试脚本示例

```python
import time
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

# 加载模型
tokenizer = AutoTokenizer.from_pretrained("vivo-ai/BlueLM-7B-Chat", trust_remote_code=True, use_fast=False)
model = AutoModelForCausalLM.from_pretrained("vivo-ai/BlueLM-7B-Chat", device_map="cuda:0", torch_dtype=torch.bfloat16, trust_remote_code=True)
model = model.eval()

# 测试问题
test_questions = [
    "1+1=?",
    "什么是人工智能？",
    "如何解一元二次方程？",
    "解释量子计算的基本原理",
    "如何提高英语水平？"
]

# 测试不同参数组合
param_combinations = [
    {"name": "速度优先", "max_new_tokens": 200, "do_sample": False, "temperature": 0.0, "num_beams": 1},
    {"name": "平衡配置", "max_new_tokens": 300, "do_sample": True, "temperature": 0.7, "num_beams": 2},
    {"name": "质量优先", "max_new_tokens": 512, "do_sample": True, "temperature": 1.0, "num_beams": 3},
]

for params in param_combinations:
    print(f"\n测试配置: {params['name']}")
    total_time = 0
    
    for question in test_questions:
        start_time = time.time()
        
        # 构建输入
        prompt = f"[|Human|]:{question}[|AI|]:"
        inputs = tokenizer(prompt, return_tensors="pt")
        inputs = inputs.to(model.device)
        
        # 生成回答
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=params["max_new_tokens"],
                do_sample=params["do_sample"],
                temperature=params["temperature"],
                num_beams=params["num_beams"],
                repetition_penalty=1.1,
                eos_token_id=tokenizer.eos_token_id
            )
        
        end_time = time.time()
        response_time = end_time - start_time
        total_time += response_time
        
        # 解码输出
        answer = tokenizer.decode(outputs.cpu()[0], skip_special_tokens=True)
        print(f"问题: {question}")
        print(f"回答: {answer[:100]}...")
        print(f"响应时间: {response_time:.2f}秒")
    
    avg_time = total_time / len(test_questions)
    print(f"\n平均响应时间: {avg_time:.2f}秒")
```

## 四、实施建议

### 1. 分阶段优化
1. **第一阶段**：测试不同 `max_new_tokens` 和 `temperature` 的组合
2. **第二阶段**：调整 `do_sample` 和 `num_beams` 参数
3. **第三阶段**：优化批处理和内存参数

### 2. 环境适配
- **GPU环境**：使用半精度计算，适当增加批处理大小
- **CPU环境**：使用量化模型，减少批处理大小
- **内存受限**：使用4位量化，限制输入输出长度

### 3. 监控与调整
- 实时监控模型性能
- 根据实际负载调整参数
- 定期重新评估参数配置

## 五、预期效果

通过参数优化，预计可以：
- 响应速度提升30-50%
- 内存使用减少40-60%
- 吞吐量提升2-3倍
- 保持回答质量稳定