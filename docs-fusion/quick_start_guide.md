# MathMate-PlotKityCat 融合快速开始指南

## 🎯 5分钟快速启动

### Step 1: 验证环境 (1分钟)

```bash
# 运行环境验证脚本
cd /d/projects/docs
chmod +x verify_fusion_setup.sh
./verify_fusion_setup.sh
```

**预期结果**: 所有关键检查项应该通过

---

### Step 2: 阅读核心文档 (2分钟)

**必读文档** (按优先级):
1. 📋 [融合分析总结](./fusion_analysis_summary.md) - 了解整体方案
2. 📝 [实施检查清单](./fusion_implementation_checklist.md) - 了解详细步骤
3. 📊 [详细分析报告](./fusion_analysis_report.md) - 深入了解技术细节

**快速问题查找**:
- "为什么选择这个方案？" → 查看 `fusion_analysis_summary.md` 的"融合价值评估"部分
- "具体怎么实施？" → 查看 `fusion_implementation_checklist.md` 的相应阶段
- "技术细节是什么？" → 查看 `fusion_analysis_report.md` 的相关章节

---

### Step 3: 启动 Phase 1 开发 (2分钟)

#### 创建融合模块目录结构

```bash
cd /d/projects/MathMate

# 创建融合模块根目录
mkdir -p lib/fusion

# 创建 AI 绘图模块
mkdir -p lib/fusion/ai_drawing/{prompts,services,widgets,models}

# 创建数据模型
mkdir -p lib/fusion/{models,repositories}

# 创建测试目录
mkdir -p test/fusion/ai_drawing
```

#### 创建第一个文件：AI Prompts

```bash
# 创建 AI Prompts 文件
cat > lib/fusion/ai_drawing/prompts/math_prompts.dart << 'EOF'
/// MathMate AI Drawing Prompts
/// 移植自 PlotKityCat 项目
class MathDrawingPrompts {
  /// 基础可视化生成模板
  static const String visualizeTemplate = '''
你是一个专业的数学可视化助手。根据用户的描述，生成 Matplotlib 绘图代码。

用户描述: {description}

要求:
1. 生成清晰、美观的数学图形
2. 使用合适的颜色和线条样式
3. 添加必要的标注和说明
4. 确保代码简洁高效

生成代码:
''';

  /// 代码优化模板
  static const String optimizeTemplate = '''
优化以下 Matplotlib 代码，使其更加美观和高效:

当前代码:
{current_code}

优化要求: {instruction}

优化后的代码:
''';

  /// 错误修复模板
  static const String repairTemplate = '''
修复以下 Matplotlib 代码中的错误:

当前代码:
{current_code}

错误信息:
{error_text}

修复后的代码:
''';
}
EOF
```

---

## 🛠️ Phase 1 MVP 实现 (最小可行产品)

### 目标: 创建第一个 AI 绘图功能

#### Step 1: 创建 AI 服务接口 (15分钟)

```bash
cat > lib/fusion/ai_drawing/services/ai_drawing_service.dart << 'EOF'
import '../prompts/math_prompts.dart';

/// AI 绘图服务
class AIDrawingService {
  /// 通过自然语言生成可视化代码
  Future<String> generateVisualization(String description) async {
    final prompt = MathDrawingPrompts.visualizeTemplate
        .replaceAll('{description}', description);
    
    // TODO: 集成实际的 AI 接口
    // 现在暂时返回模拟代码
    return _simulateAICall(prompt);
  }

  /// 优化现有可视化代码
  Future<String> optimizeCode(String currentCode, String instruction) async {
    final prompt = MathDrawingPrompts.optimizeTemplate
        .replaceAll('{current_code}', currentCode)
        .replaceAll('{instruction}', instruction);
    
    return _simulateAICall(prompt);
  }

  /// 修复代码错误
  Future<String> repairCode(String currentCode, String errorText) async {
    final prompt = MathDrawingPrompts.repairTemplate
        .replaceAll('{current_code}', currentCode)
        .replaceAll('{error_text}', errorText);
    
    return _simulateAICall(prompt);
  }

  /// 模拟 AI 调用 (开发阶段使用)
  String _simulateAICall(String prompt) {
    // 这是一个模拟实现，实际使用时需要替换为真实的 AI 调用
    return '''
import matplotlib.pyplot as plt
import numpy as np

# 示例代码 - 实际使用时由 AI 生成
x = np.linspace(0, 10, 100)
y = np.sin(x)

plt.figure(figsize=(10, 6))
plt.plot(x, y, 'b-', linewidth=2, label='sin(x)')
plt.xlabel('x')
plt.ylabel('y')
plt.title('Sine Wave')
plt.legend()
plt.grid(True)
plt.show()
''';
  }
}
EOF
```

#### Step 2: 创建基础 UI 页面 (15分钟)

```bash
cat > lib/pages/ai_drawing_page.dart << 'EOF'
import 'package:flutter/material.dart';
import '../fusion/ai_drawing/services/ai_drawing_service.dart';

class AIDrawingPage extends StatefulWidget {
  const AIDrawingPage({Key? key}) : super(key: key);

  @override
  _AIDrawingPageState createState() => _AIDrawingPageState();
}

class _AIDrawingPageState extends State<AIDrawingPage> {
  final TextEditingController _descriptionController = TextEditingController();
  final AIDrawingService _aiService = AIDrawingService();
  
  String _generatedCode = '';
  bool _isGenerating = false;
  String? _errorMessage;

  Future<void> _generateVisualization() async {
    if (_descriptionController.text.isEmpty) {
      setState(() => _errorMessage = '请输入描述');
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedCode = '';
    });

    try {
      final code = await _aiService.generateVisualization(
        _descriptionController.text,
      );
      setState(() => _generatedCode = code);
    } catch (e) {
      setState(() => _errorMessage = '生成失败: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 绘图'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 输入区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '描述你想要的数学图形...\n例如: 绘制一个正弦函数图像，x范围从0到2π',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isGenerating ? null : _generateVisualization,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue[700],
                      ),
                      child: Text(
                        _isGenerating ? '生成中...' : '生成图形',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 错误信息
            if (_errorMessage != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red[900]),
                  ),
                ),
              ),
            
            // 生成的代码
            if (_generatedCode.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '生成的代码',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              // TODO: 实现复制功能
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _generatedCode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
}
EOF
```

#### Step 3: 添加路由入口 (5分钟)

```bash
# 在 MathMate 的主路由文件中添加新页面
# 假设主文件是 lib/main.dart，在其中添加路由
```

---

## 🧪 测试 MVP (10分钟)

### 运行应用测试

```bash
cd /d/projects/MathMate

# 确保依赖是最新的
flutter pub get

# 运行应用
flutter run
```

### 功能测试清单

- [ ] 应用正常启动
- [ ] 可以找到 AI 绘图入口
- [ ] 点击进入 AI 绘图页面
- [ ] 输入描述文本
- [ ] 点击"生成图形"按钮
- [ ] 显示"生成中..."状态
- [ ] 显示生成的代码
- [ ] 代码格式正确

---

## 🎯 下一步行动计划

### 立即行动 (本周内)
1. ✅ 完成环境验证
2. ✅ 阅读3个核心文档
3. ✅ 创建 Phase 1 MVP
4. ⬜ 集成真实 AI 接口
5. ⬜ 添加基础测试

### 短期目标 (2周内)
1. ⬜ 完善 AI Prompt 系统
2. ⬜ 实现代码优化功能
3. ⬜ 添加错误处理
4. ⬜ 编写单元测试
5. ⬜ 进行用户测试

### 中期目标 (4周内)
1. ⬜ 实现服务端渲染
2. ⬜ 添加图片显示功能
3. ⬜ 完善用户体验
4. ⬜ 性能优化
5. ⬜ 准备 Phase 2

---

## 🔥 快速问题解决

### 常见问题

**Q: 应用启动报错？**
```bash
A: 检查 Flutter 版本和依赖
flutter --version
flutter clean
flutter pub get
```

**Q: 找不到新创建的页面？**
```bash
A: 检查路由配置，确保正确导入和注册新页面
```

**Q: AI 调用失败？**
```bash
A: 当前使用模拟实现，需要集成真实的 AI 接口
参考 MathMate 现有的 AI 服务实现
```

---

## 📞 获取帮助

**文档资源**:
- [融合分析总结](./fusion_analysis_summary.md) - 快速了解方案
- [实施检查清单](./fusion_implementation_checklist.md) - 详细步骤
- [详细分析报告](./fusion_analysis_report.md) - 深入技术细节

**技术支持**:
- GitHub Issues: [项目Issues页面]
- 开发讨论: [团队讨论频道]

---

## 🎉 恭喜！

如果你已经完成了 MVP 的创建，恭喜你迈出了融合的第一步！

**现在的状态**:
- ✅ 环境已经验证
- ✅ 核心文档已经阅读
- ✅ 第一个功能已经创建
- ✅ 下一步计划已经明确

**继续前进**:
1. 集成真实的 AI 服务
2. 完善错误处理
3. 添加测试覆盖
4. 准备进入 Phase 2

**记住**: 这是一个迭代过程，先让功能跑起来，再逐步完善！

---

**快速开始指南版本**: 1.0  
**最后更新**: 2026年7月2日  
**预计完成时间**: 5分钟环境验证 + 30分钟MVP开发