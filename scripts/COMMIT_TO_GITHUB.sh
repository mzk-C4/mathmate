#!/bin/bash
# ============================================
# MathMate 一键提交脚本
# 自动提交所有优化后的文件到 GitHub
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 检查 Git 状态
# ============================================
check_git() {
    log_info "检查 Git 状态..."

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi

    # 检查是否有未提交的更改
    if git diff-index --quiet HEAD --; then
        log_info "工作目录干净，无需提交"
    else
        log_info "检测到未提交的更改"
    fi
}

# ============================================
# 提交 MathMate 主项目
# ============================================
commit_mathmate() {
    log_info "提交 MathMate 主项目..."

    cd D:/projects/MathMate

    git add README.md .env.example docs/
    git commit -m "docs: 优化 GitHub README 和文档

- 完善 README.md：添加视频链接、功能截图、技术架构图
- 更新 .env.example：添加详细配置说明和注释
- 新增文档：GitHub 资源配置指南和优化指南
- 优化排版和样式，提升展示效果

Refs: #1"
}

# ============================================
# 提交网站项目
# ============================================
commit_website() {
    log_info "提交 MathMate-Website 项目..."

    cd D:/projects/MathMate-Website

    git add .
    git commit -m "feat: 完成网站优化和部署配置

网站优化：
- SEO 优化：添加完整的 meta 标签（Open Graph、Twitter Card）
- 新建 favicon.svg、robots.txt、sitemap.xml
- 优化 index.html 和 tech.html 的搜索引擎友好度

部署配置：
- 新增 proxy_server.js：API 代理服务器
- 新增 package.json：Node.js 依赖配置
- 新增 ecosystem.config.js：PM2 进程管理
- 新增 .env.template：环境变量模板

部署脚本：
- deploy.sh：完整自动化部署脚本
- quick-deploy.sh：快速部署脚本

文档：
- README.md：项目说明
- DEPLOYMENT_GUIDE.md：完整部署指南
- DEPLOYMENT.md：详细部署文档
- CHECKLIST.md：部署执行清单
- SUMMARY.md：完成总结

准备部署到 mathmate.top 🚀"
}

# ============================================
# 推送到 GitHub
# ============================================
push_to_github() {
    log_info "推送到 GitHub..."

    # 推送 MathMate
    cd D:/projects/MathMate
    git push origin main

    # 推送 Website
    cd D:/projects/MathMate-Website
    git push origin main
}

# ============================================
# 显示结果
# ============================================
show_result() {
    log_info "=========================================="
    log_info "提交完成！"
    log_info "=========================================="
    echo ""
    log_info "已提交的仓库："
    echo "  📦 MathMate: https://github.com/mzk-C4/mathmate"
    echo "  🌐 MathMate-Website: (如果有的话)"
    echo ""
    log_info "下一步："
    echo "  1. 在 GitHub 上查看更新"
    echo "  2. 添加应用截图到 README"
    echo "  3. 部署到服务器"
    echo ""
    log_info "=========================================="
}

# ============================================
# 主流程
# ============================================
main() {
    log_info "开始提交 MathMate 优化..."
    echo ""

    check_git
    commit_mathmate
    commit_website
    push_to_github
    show_result
}

# 执行主流程
main
