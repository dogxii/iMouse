#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  iMouse 项目初始化脚本
#
#  功能：
#    1. 检查并安装 XcodeGen（如果尚未安装）
#    2. 生成 Xcode 项目文件 (.xcodeproj)
#    3. 打开生成的项目
#
#  使用方法：
#    cd iMouse    # 进入项目根目录（包含 project.yml 的目录）
#    chmod +x setup.sh
#    ./setup.sh
#
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # 无颜色

# 打印带颜色的消息
info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
step()    { echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }

# ─────────────────────────────────────────────────────────────
#  定位项目根目录
# ─────────────────────────────────────────────────────────────

# 脚本所在的目录即为项目根目录（包含 project.yml）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

if [ ! -f "${PROJECT_ROOT}/project.yml" ]; then
    error "未找到 project.yml 文件。请确保从正确的目录运行此脚本。"
    error "预期路径: ${PROJECT_ROOT}/project.yml"
    exit 1
fi

info "项目根目录: ${PROJECT_ROOT}"

# ─────────────────────────────────────────────────────────────
#  Step 1: 检查 Xcode 命令行工具
# ─────────────────────────────────────────────────────────────

step "检查 Xcode 命令行工具"

if ! command -v xcodebuild &> /dev/null; then
    error "未找到 xcodebuild。请先安装 Xcode 命令行工具:"
    error "  xcode-select --install"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -n 1)
success "已检测到 ${XCODE_VERSION}"

# 检查 macOS SDK 版本
SDK_VERSION=$(xcrun --show-sdk-version 2>/dev/null || echo "未知")
info "macOS SDK 版本: ${SDK_VERSION}"

# ─────────────────────────────────────────────────────────────
#  Step 2: 检查并安装 XcodeGen
# ─────────────────────────────────────────────────────────────

step "检查 XcodeGen"

if command -v xcodegen &> /dev/null; then
    XCODEGEN_VERSION=$(xcodegen --version 2>/dev/null || echo "未知版本")
    success "XcodeGen 已安装 (${XCODEGEN_VERSION})"
else
    warning "XcodeGen 未安装，正在安装..."

    # 优先使用 Homebrew 安装
    if command -v brew &> /dev/null; then
        info "通过 Homebrew 安装 XcodeGen..."
        brew install xcodegen

        if command -v xcodegen &> /dev/null; then
            success "XcodeGen 安装成功"
        else
            error "XcodeGen 安装失败，请手动安装:"
            error "  brew install xcodegen"
            error "  或参考: https://github.com/yonaskolb/XcodeGen"
            exit 1
        fi
    else
        # 尝试使用 Mint 安装
        if command -v mint &> /dev/null; then
            info "通过 Mint 安装 XcodeGen..."
            mint install yonaskolb/xcodegen

            if command -v xcodegen &> /dev/null; then
                success "XcodeGen 安装成功"
            else
                error "XcodeGen 安装失败"
                exit 1
            fi
        else
            error "未找到 Homebrew 或 Mint 包管理器。"
            error "请先安装 Homebrew: https://brew.sh"
            error "然后运行: brew install xcodegen"
            exit 1
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
#  Step 3: 验证项目结构
# ─────────────────────────────────────────────────────────────

step "验证项目结构"

REQUIRED_FILES=(
    "project.yml"
    "Shared/SelectionContext.swift"
    "Shared/ContextAction.swift"
    "Shared/AppSettings.swift"
    "iMouse/iMouseApp.swift"
    "iMouse/UI/SettingsView.swift"
    "iMouse/Core/Actions/NewFileAction.swift"
    "iMouse/Core/Actions/NewGhosttyWindowAction.swift"
    "iMouse/Core/Actions/CopyPathAction.swift"
    "iMouse/Core/Actions/CopyNameAction.swift"
    "iMouse/Core/Actions/AirDropAction.swift"
    "iMouse/Core/Actions/ConvertImageAction.swift"
    "iMouse/Core/Actions/ResizeImageAction.swift"
    "iMouse/Info.plist"
    "iMouse/iMouse.entitlements"
    "FinderSync/FinderSync.swift"
    "FinderSync/Info.plist"
    "FinderSync/FinderSync.entitlements"
    "iMouse/Resources/en.lproj/Localizable.strings"
    "iMouse/Resources/zh-Hans.lproj/Localizable.strings"
    "FinderSync/Resources/en.lproj/Localizable.strings"
    "FinderSync/Resources/zh-Hans.lproj/Localizable.strings"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${PROJECT_ROOT}/${file}" ]; then
        MISSING_FILES+=("${file}")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    error "以下必需文件缺失:"
    for file in "${MISSING_FILES[@]}"; do
        echo -e "  ${RED}✗${NC} ${file}"
    done
    error "请确保所有源代码文件已正确创建。"
    exit 1
fi

success "所有必需文件已就位 (${#REQUIRED_FILES[@]} 个文件)"

# ─────────────────────────────────────────────────────────────
#  Step 4: 生成 Xcode 项目
# ─────────────────────────────────────────────────────────────

step "生成 Xcode 项目"

cd "${PROJECT_ROOT}"
info "工作目录: $(pwd)"
info "运行: xcodegen generate"

if xcodegen generate; then
    success "Xcode 项目生成成功！"
else
    error "Xcode 项目生成失败。请检查 project.yml 配置。"
    error "尝试运行以下命令查看详细错误:"
    error "  cd ${PROJECT_ROOT} && xcodegen generate --use-cache"
    exit 1
fi

# 检查生成的 .xcodeproj 是否存在
XCODEPROJ="${PROJECT_ROOT}/iMouse.xcodeproj"
if [ ! -d "${XCODEPROJ}" ]; then
    error "Xcode 项目文件未找到: ${XCODEPROJ}"
    exit 1
fi

success "项目文件: ${XCODEPROJ}"

# ─────────────────────────────────────────────────────────────
#  Step 5: 打印后续步骤
# ─────────────────────────────────────────────────────────────

step "完成！"

echo ""
echo -e "${GREEN}${BOLD}iMouse 项目已准备就绪！${NC}"
echo ""
echo -e "  ${BOLD}项目文件:${NC} ${XCODEPROJ}"
echo ""
echo -e "${CYAN}${BOLD}下一步操作:${NC}"
echo ""
echo -e "  ${BOLD}1.${NC} 打开项目:"
echo -e "     ${YELLOW}open ${XCODEPROJ}${NC}"
echo ""
echo -e "  ${BOLD}2.${NC} 在 Xcode 中配置签名:"
echo -e "     - 选择你的开发团队 (Team)"
echo -e "     - 确认 Bundle Identifier:"
echo -e "       • 主 App: ${CYAN}com.dogxi.iMouse${NC}"
echo -e "       • 扩展:   ${CYAN}com.dogxi.iMouse.FinderSync${NC}"
echo ""
echo -e "  ${BOLD}3.${NC} 配置 App Group:"
echo -e "     - 在两个 target 的 Signing & Capabilities 中"
echo -e "       添加 App Group: ${CYAN}group.com.dogxi.iMouse${NC}"
echo ""
echo -e "  ${BOLD}4.${NC} 构建并运行 (⌘R):"
echo -e "     - 选择 ${CYAN}iMouse${NC} scheme"
echo -e "     - 构建成功后，应用将在菜单栏中出现"
echo ""
echo -e "  ${BOLD}5.${NC} 启用 Finder Sync 扩展:"
echo -e "     - 打开「系统设置 → 隐私与安全 → 扩展 → 已添加的扩展」"
echo -e "     - 找到 ${CYAN}iMouse${NC} 并启用"
echo -e "     - 或运行: ${YELLOW}pluginkit -e use -i com.dogxi.iMouse.FinderSync${NC}"
echo ""
echo -e "  ${BOLD}6.${NC} 调试 Finder Sync 扩展 (可选):"
echo -e "     - 在 Xcode 中选择 ${CYAN}FinderSync${NC} scheme"
echo -e "     - 运行时选择 ${CYAN}Finder.app${NC} 作为宿主应用"
echo -e "     - 在 Finder 中右键点击文件即可触发断点"
echo ""
echo -e "${YELLOW}${BOLD}⚠️  重要提示:${NC}"
echo ""
echo -e "  • 本项目${BOLD}未启用 App Sandbox${NC}，因为 Finder Sync 扩展需要："
echo -e "    - 读写文件系统（新建文件、转换/缩放图片）"
echo -e "    - 启动外部进程（Ghostty 终端）"
echo -e "    - 通过 NSSharingService 调用 AirDrop"
echo ""
echo -e "  • 如果需要上架 Mac App Store，需要启用沙盒并使用"
echo -e "    XPC Service 来处理特权操作。详见项目 README。"
echo ""
echo -e "  • 首次构建后，Finder Sync 扩展可能需要重启 Finder 才能生效:"
echo -e "    ${YELLOW}killall Finder${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
#  可选：自动打开项目
# ─────────────────────────────────────────────────────────────

echo -e -n "${BOLD}是否立即打开 Xcode 项目？[Y/n] ${NC}"
read -r OPEN_PROJECT

if [[ -z "${OPEN_PROJECT}" || "${OPEN_PROJECT}" =~ ^[Yy]$ ]]; then
    info "正在打开 Xcode 项目..."
    open "${XCODEPROJ}"
    success "已打开 Xcode！"
else
    info "你可以稍后运行以下命令打开项目:"
    echo -e "  ${YELLOW}open ${XCODEPROJ}${NC}"
fi

echo ""
success "祝你使用愉快！🖱️✨"
