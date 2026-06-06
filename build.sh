#!/bin/bash
set -e

SCHEME="Renamer"
PROJECT="Renamer.xcodeproj"
APP_NAME="Renamer.app"
BUILD_DIR=".build/xcode"

echo "▶ Building $SCHEME (Release)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED|CompileSwift|ProcessInfoPlistFile|CompileAssetCatalog" || true

# 빌드 결과 확인
BUILT_APP=$(find "$BUILD_DIR" -name "$APP_NAME" -type d | head -1)
if [ -z "$BUILT_APP" ]; then
  echo "❌ 빌드 실패: $APP_NAME 를 찾을 수 없습니다"
  exit 1
fi

echo "▶ 코드 서명 중..."
xattr -cr "$BUILT_APP"
codesign --force --deep --sign - "$BUILT_APP"

echo "✅ 완료: $BUILT_APP"
echo ""
echo "설치 방법 (Applications 폴더):"
echo "  cp -r \"$BUILT_APP\" ~/Applications/"
echo "  open ~/Applications/$APP_NAME"
