#!/bin/bash
# ============================================================================
# بناء OpenSSL من المصدر لـ iOS (arm64 device + arm64/x86_64 simulator)
# شغّله على Mac فيه Xcode command line tools مثبتة.
#
# الاستخدام:
#   chmod +x build_openssl_ios.sh
#   ./build_openssl_ios.sh 3.3.1        # اختياري: رقم نسخة OpenSSL (افتراضي 3.3.1)
#
# الناتج:
#   ./openssl-ios/OpenSSL.xcframework   <-- ده اللي هتسحبه لمشروع Xcode
# ============================================================================
set -euo pipefail

OPENSSL_VERSION="${1:-3.3.1}"
WORK_DIR="$(pwd)/openssl-ios"
SRC_DIR="$WORK_DIR/src"
OUT_DIR="$WORK_DIR/out"
MIN_IOS_VERSION="12.0"

rm -rf "$WORK_DIR"
mkdir -p "$SRC_DIR" "$OUT_DIR"

echo "==> تنزيل OpenSSL $OPENSSL_VERSION"
cd "$SRC_DIR"
curl -LO "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
tar xzf "openssl-${OPENSSL_VERSION}.tar.gz"

build_one() {
  local NAME="$1"          # اسم الفولدر بتاع الناتج
  local TARGET="$2"        # target بتاع Configure (ios64-cross أو iossimulator-xcrun)
  local SDK="$3"           # iphoneos أو iphonesimulator
  local ARCHS="$4"         # arm64 أو "arm64 x86_64"

  echo "==> بناء $NAME (SDK=$SDK ARCHS=$ARCHS)"
  local BUILD_DIR="$SRC_DIR/build_${NAME}"
  rm -rf "$BUILD_DIR"
  cp -r "$SRC_DIR/openssl-${OPENSSL_VERSION}" "$BUILD_DIR"
  cd "$BUILD_DIR"

  export CROSS_TOP="$(xcrun --sdk $SDK --show-sdk-platform-path)/Developer"
  export CROSS_SDK="$(basename "$(xcrun --sdk $SDK --show-sdk-path)")"
  export CC="$(xcrun --sdk $SDK -f clang)"

  # علم min-version لازم يختلف حسب المنصة عشان Xcode يقدر يميّز
  # مكتبة السيميوليتور عن مكتبة الجهاز الحقيقي لما يجمعهم في xcframework
  local MIN_VERSION_FLAG="-mios-version-min=$MIN_IOS_VERSION"
  if [ "$SDK" = "iphonesimulator" ]; then
    MIN_VERSION_FLAG="-mios-simulator-version-min=$MIN_IOS_VERSION"
  fi

  # لو معماريتين (سيميوليتور Intel+Apple Silicon) نبنيهم كل واحدة لوحدها وندمجهم بـ lipo
  local LIBCRYPTO_PARTS=()
  local LIBSSL_PARTS=()
  for ARCH in $ARCHS; do
    local ARCH_BUILD="${BUILD_DIR}_${ARCH}"
    if [ "$ARCH" != "$(echo $ARCHS | awk '{print $1}')" ]; then
      rm -rf "$ARCH_BUILD"; cp -r "$BUILD_DIR" "$ARCH_BUILD"
    else
      ARCH_BUILD="$BUILD_DIR"
    fi
    cd "$ARCH_BUILD"

    # OpenSSL محتاج target مختلف لكل معمارية في السيميوليتور
    # (التارجت العام iossimulator-xcrun بيبني arm64 دايمًا مهما كانت المعمارية المطلوبة)
    local ARCH_TARGET="$TARGET"
    if [ "$SDK" = "iphonesimulator" ]; then
      if [ "$ARCH" = "arm64" ]; then
        ARCH_TARGET="iossimulator-arm64-xcrun"
      elif [ "$ARCH" = "x86_64" ]; then
        ARCH_TARGET="iossimulator-x86_64-xcrun"
      fi
    fi

    ./Configure "$ARCH_TARGET" no-shared no-tests no-asm \
        $MIN_VERSION_FLAG \
        --prefix="$OUT_DIR/${NAME}_${ARCH}"
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw
    LIBCRYPTO_PARTS+=("$OUT_DIR/${NAME}_${ARCH}/lib/libcrypto.a")
    LIBSSL_PARTS+=("$OUT_DIR/${NAME}_${ARCH}/lib/libssl.a")
    cd "$SRC_DIR"
  done

  mkdir -p "$OUT_DIR/$NAME/lib" "$OUT_DIR/$NAME/include"
  lipo -create "${LIBCRYPTO_PARTS[@]}" -output "$OUT_DIR/$NAME/lib/libcrypto.a"
  lipo -create "${LIBSSL_PARTS[@]}" -output "$OUT_DIR/$NAME/lib/libssl.a"
  cp -r "$OUT_DIR/${NAME}_$(echo $ARCHS | awk '{print $1}')/include/"* "$OUT_DIR/$NAME/include/"

  # دمج libcrypto + libssl في مكتبة واحدة (أسهل في الربط)
  libtool -static -o "$OUT_DIR/$NAME/lib/libopenssl.a" \
      "$OUT_DIR/$NAME/lib/libcrypto.a" "$OUT_DIR/$NAME/lib/libssl.a"
}

# 1) جهاز حقيقي iOS (arm64)
build_one "device" "ios64-cross" "iphoneos" "arm64"

# 2) السيميوليتور (arm64 على أبل سيليكون + x86_64 على انتل)
build_one "simulator" "iossimulator-xcrun" "iphonesimulator" "arm64 x86_64"

echo "==> تجميع XCFramework"
cd "$WORK_DIR"
xcodebuild -create-xcframework \
  -library "$OUT_DIR/device/lib/libopenssl.a" -headers "$OUT_DIR/device/include" \
  -library "$OUT_DIR/simulator/lib/libopenssl.a" -headers "$OUT_DIR/simulator/include" \
  -output "$WORK_DIR/OpenSSL.xcframework"

echo ""
echo "✅ تم البناء بنجاح: $WORK_DIR/OpenSSL.xcframework"
echo "اسحبه لمجلد ios/ بتاع مشروع Flutter وضيفه في Xcode (Frameworks, Libraries, and Embedded Content)."
