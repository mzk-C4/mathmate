#!/bin/bash
# MathMate-PlotKityCat 融合技术验证脚本

echo "🔍 MathMate-PlotKityCat 融合技术验证"
echo "======================================"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查结果存储
PASSED=0
FAILED=0
WARNINGS=0

# 检查函数
check_item() {
    local name=$1
    local command=$2
    local critical=$3

    echo -n "检查 $name... "
    if eval $command > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 通过${NC}"
        ((PASSED++))
        return 0
    else
        if [ "$critical" = "true" ]; then
            echo -e "${RED}✗ 失败 (关键)${NC}"
            ((FAILED++))
        else
            echo -e "${YELLOW}⚠ 警告 (非关键)${NC}"
            ((WARNINGS++))
        fi
        return 1
    fi
}

echo "📍 环境检查"
echo "----------"

# 基础环境检查
check_item "当前工作目录" "[ -d '/d/projects' ]" true
check_item "MathMate 项目存在" "[ -d '/d/projects/MathMate' ]" true
check_item "PlotKityCat 项目存在" "[ -d '/d/projects/add/PlotKityCat' ]" true
check_item "文档目录存在" "[ -d '/d/projects/docs' ]" false

echo ""
echo "🔧 开发工具检查"
echo "--------------"

# Flutter 环境检查
check_item "Flutter 安装" "which flutter" true
check_item "Flutter 版本" "flutter --version" true
check_item "Dart 安装" "which dart" true

echo ""
echo "📦 依赖项目检查"
echo "---------------"

# 检查关键文件是否存在
check_item "MathMate pubspec.yaml" "[ -f '/d/projects/MathMate/pubspec.yaml' ]" true
check_item "PlotKityCat README" "[ -f '/d/projects/add/PlotKityCat/README.md' ]" false
check_item "PlotKityCat Go 模块" "[ -f '/d/projects/add/PlotKityCat/go.mod' ]" false
check_item "PlotKityCat 前端配置" "[ -f '/d/projects/add/PlotKityCat/frontend/package.json' ]" false

echo ""
echo "🚀 运行环境检查"
echo "--------------"

# 检查 Flutter 状态
cd /d/projects/MathMate
check_item "Flutter 依赖状态" "flutter pub deps" true
check_item "Flutter 构建状态" "flutter build --help" false

echo ""
echo "🐍 Python 环境检查 (用于 Matplotlib)"
echo "------------------------------------"

# Python 环境检查 (用于服务端渲染)
check_item "Python 3 安装" "which python3" false
check_item "pip 安装" "which pip" false

if command -v python3 &> /dev/null; then
    echo "Python 版本: $(python3 --version)"

    # 检查关键 Python 包
    echo "检查 Python 包:"
    check_item "Matplotlib" "python3 -c 'import matplotlib'" false
    check_item "NumPy" "python3 -c 'import numpy'" false
else
    echo -e "${YELLOW}Python 未安装，服务端渲染功能需要 Python 环境${NC}"
fi

echo ""
echo "📊 资源检查"
echo "----------"

# 检查磁盘空间
check_item "磁盘空间 (>2GB)" "df -h . | tail -1 | awk '{print \$4}' | grep -E 'G|[0-9]{3,}M'" false

# 检查内存 (简化检查)
check_item "内存信息" "free -h" false

echo ""
echo "🔗 网络检查"
echo "----------"

# 网络连接检查
check_item "网络连接" "ping -c 1 github.com" false
check_item "GitHub 访问" "curl -s --head https://github.com" false

echo ""
echo "📁 项目结构检查"
echo "--------------"

# MathMate 结构检查
check_item "MathMate lib 目录" "[ -d '/d/projects/MathMate/lib' ]" true
check_item "MathMate services 目录" "[ -d '/d/projects/MathMate/lib/services' ]" false
check_item "MathMate pages 目录" "[ -d '/d/projects/MathMate/lib/pages' ]" false

# PlotKityCat 结构检查
check_item "PlotKityCat Go 源码" "[ -d '/d/projects/add/PlotKityCat/internal' ]" false
check_item "PlotKityCat 前端源码" "[ -d '/d/projects/add/PlotKityCat/frontend/src' ]" false
check_item "PlotKityCat AI 模块" "[ -d '/d/projects/add/PlotKityCat/internal/ai' ]" false

echo ""
echo "📄 文档检查"
echo "----------"

# 检查分析文档是否存在
check_item "融合分析报告" "[ -f '/d/projects/docs/fusion_analysis_report.md' ]" false
check_item "融合分析总结" "[ -f '/d/projects/docs/fusion_analysis_summary.md' ]" false
check_item "实施检查清单" "[ -f '/d/projects/docs/fusion_implementation_checklist.md' ]" false

echo ""
echo "======================================"
echo "📊 检查结果汇总"
echo "======================================"
echo -e "${GREEN}✓ 通过: $PASSED${NC}"
echo -e "${RED}✗ 失败: $FAILED${NC}"
echo -e "${YELLOW}⚠ 警告: $WARNINGS${NC}"
echo ""

# 给出建议
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 所有关键检查项都通过！可以开始融合工作。${NC}"
else
    echo -e "${RED}⚠️  有 $FAILED 个关键检查项失败，请先解决这些问题。${NC}"
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}💡 有 $WARNINGS 个警告项，建议关注但不影响开始。${NC}"
fi

echo ""
echo "🚀 下一步操作建议:"
echo "1. 阅读 /d/projects/docs/fusion_analysis_summary.md"
echo "2. 查看 /d/projects/docs/fusion_implementation_checklist.md"
echo "3. 开始 Phase 1: AI绘图能力集成"

echo ""
echo "✨ 验证完成！"
echo "======================================"