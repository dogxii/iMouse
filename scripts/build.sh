#!/bin/bash
#
# build.sh — iMouse 一键构建 & 安装脚本
#
# 用法:
#   chmod +x build.sh   (首次运行前)
#   ./build.sh
#
# 功能:
#   1. Release 构建 iMouse.app（本地开发签名）
#   2. 停止正在运行的 iMouse
#   3. 将 iMouse.app 复制到 /Applications
#   4. 重新启动 iMouse
#

set -e

# ── 配置 ────────────────────────────────────────────────
PROJECT="iMouse.xcodeproj"
SCHEME="iMouse"
CONFIGURATION="Release"
# Team ID：优先读取环境变量 IMOUSE_TEAM_ID，其次使用下方默认值
# 克隆项目后请修改为你自己的 Team ID，或在 shell 中设置：
#   export IMOUSE_TEAM_ID=XXXXXXXXXX
TEAM_ID="${IMOUSE_TEAM_ID:-NR23J92NS8}"
DERIVED_DATA="/tmp/iMouse-build"
APP_NAME="iMouse.app"
INSTALL_DIR="/Applications"
# ────────────────────────────────────────────────────────

# 脚本在 scripts/ 子目录，上一级即为项目根目录（包含 iMouse.xcodeproj）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_OUTPUT="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME"

# 颜色
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║         iMouse Build & Install           ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Project : ${PROJECT_ROOT}/${PROJECT}"
echo -e "  Scheme  : ${SCHEME}  |  Config: ${CONFIGURATION}"
echo -e "  Team    : ${TEAM_ID}"
echo -e "  Output  : ${INSTALL_PATH}"
echo ""

# ── Step 1: 构建 ────────────────────────────────────────
echo -e "${BOLD}▶ [1/4] 构建中...${NC}"

xcodebuild \
  -project "$PROJECT_ROOT/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  -allowProvisioningUpdates \
  2>&1 | grep -E "^(.*error:|.*warning:|Build description|.*BUILD SUCCEEDED|.*BUILD FAILED)" \
       | grep -v "^note:"

if [ ! -d "$BUILD_OUTPUT" ]; then
  echo -e "${RED}❌ 构建失败：未找到产物 $BUILD_OUTPUT${NC}"
  exit 1
fi
echo -e "${GREEN}✅ [1/4] 构建成功${NC}"
echo ""

# ── Step 2: 停止正在运行的 iMouse ───────────────────────
echo -e "${BOLD}▶ [2/4] 停止 iMouse...${NC}"
if pgrep -x "iMouse" > /dev/null 2>&1; then
  pkill -x "iMouse" 2>/dev/null || true
  sleep 1
  echo "  已停止旧进程"
else
  echo "  未在运行，跳过"
fi
echo -e "${GREEN}✅ [2/4] 完成${NC}"
echo ""

# ── Step 3: 安装到 /Applications ────────────────────────
echo -e "${BOLD}▶ [3/4] 安装到 ${INSTALL_DIR}...${NC}"
if [ -d "$INSTALL_PATH" ]; then
  rm -rf "$INSTALL_PATH"
fi
cp -R "$BUILD_OUTPUT" "$INSTALL_PATH"
echo -e "${GREEN}✅ [3/4] 已安装：${INSTALL_PATH}${NC}"
echo ""

# ── Step 4: 启动 iMouse ────────────────────────────────
echo -e "${BOLD}▶ [4/4] 启动 iMouse...${NC}"
open "$INSTALL_PATH"
sleep 1

if pgrep -x "iMouse" > /dev/null 2>&1; then
  echo -e "${GREEN}✅ [4/4] iMouse 已启动${NC}"
else
  echo -e "${YELLOW}⚠️  [4/4] 未能自动检测到进程，请手动打开 ${INSTALL_PATH}${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           🎉 全部完成！                  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
