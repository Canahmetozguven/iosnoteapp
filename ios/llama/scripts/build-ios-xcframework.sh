#!/usr/bin/env bash
#
# Build an iOS-only llama.xcframework for SynapsNotes CI.
# Output: ios/llama/build-apple/llama.xcframework
set -euo pipefail

IOS_MIN_OS_VERSION="${IOS_MIN_OS_VERSION:-17.0}"

BUILD_SHARED_LIBS=OFF
LLAMA_BUILD_EXAMPLES=OFF
LLAMA_BUILD_TOOLS=OFF
LLAMA_BUILD_TESTS=OFF
LLAMA_BUILD_SERVER=OFF
GGML_METAL=ON
GGML_METAL_EMBED_LIBRARY=ON
GGML_BLAS_DEFAULT=ON
GGML_METAL_USE_BF16=ON
GGML_OPENMP=OFF

COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"
COMMON_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"

check_required_tool() {
  local tool=$1
  local install_message=$2
  if ! command -v "$tool" &>/dev/null; then
    echo "Error: $tool is required but not found."
    echo "$install_message"
    exit 1
  fi
}

echo "Checking for required tools..."
check_required_tool "cmake" "Install CMake (brew install cmake)"
check_required_tool "xcodebuild" "Install Xcode Command Line Tools (xcode-select --install)"
check_required_tool "libtool" "Install Xcode Command Line Tools (xcode-select --install)"
check_required_tool "dsymutil" "Install Xcode Command Line Tools (xcode-select --install)"

COMMON_CMAKE_ARGS=(
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT="dwarf-with-dsym"
  -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES
  -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO
  -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO
  -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=ggml
  -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
  -DLLAMA_BUILD_EXAMPLES=${LLAMA_BUILD_EXAMPLES}
  -DLLAMA_BUILD_TOOLS=${LLAMA_BUILD_TOOLS}
  -DLLAMA_BUILD_TESTS=${LLAMA_BUILD_TESTS}
  -DLLAMA_BUILD_SERVER=${LLAMA_BUILD_SERVER}
  -DGGML_METAL_EMBED_LIBRARY=${GGML_METAL_EMBED_LIBRARY}
  -DGGML_BLAS_DEFAULT=${GGML_BLAS_DEFAULT}
  -DGGML_METAL=${GGML_METAL}
  -DGGML_METAL_USE_BF16=${GGML_METAL_USE_BF16}
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=${GGML_OPENMP}
  -DLLAMA_OPENSSL=OFF
)

rm -rf build-apple build-ios-sim build-ios-device

setup_framework_structure() {
  local build_dir=$1
  local min_os_version=$2
  local framework_name="llama"

  mkdir -p "${build_dir}/framework/${framework_name}.framework/Headers"
  mkdir -p "${build_dir}/framework/${framework_name}.framework/Modules"

  local header_path="${build_dir}/framework/${framework_name}.framework/Headers/"
  local module_path="${build_dir}/framework/${framework_name}.framework/Modules/"

  cp include/llama.h             "${header_path}"
  cp ggml/include/ggml.h         "${header_path}"
  cp ggml/include/ggml-opt.h     "${header_path}"
  cp ggml/include/ggml-alloc.h   "${header_path}"
  cp ggml/include/ggml-backend.h "${header_path}"
  cp ggml/include/ggml-metal.h   "${header_path}"
  cp ggml/include/ggml-cpu.h     "${header_path}"
  cp ggml/include/ggml-blas.h    "${header_path}"
  cp ggml/include/gguf.h         "${header_path}"

  cat > "${module_path}module.modulemap" <<'EOF'
framework module llama {
    header "llama.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF

  cat > "${build_dir}/framework/${framework_name}.framework/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>llama</string>
    <key>CFBundleIdentifier</key>
    <string>org.ggml.llama</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>llama</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${min_os_version}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>DTPlatformName</key>
    <string>iphoneos</string>
    <key>DTSDKName</key>
    <string>iphoneos${min_os_version}</string>
</dict>
</plist>
EOF
}

combine_static_libraries_to_dylib() {
  local build_dir="$1"
  local release_dir="$2"
  local sdk="$3"
  local archs="$4"
  local min_version_flag="$5"

  local base_dir
  base_dir="$(pwd)"
  local framework_name="llama"
  local output_lib="${build_dir}/framework/${framework_name}.framework/${framework_name}"

  local libs=(
    "${base_dir}/${build_dir}/src/${release_dir}/libllama.a"
    "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml.a"
    "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml-base.a"
    "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml-cpu.a"
    "${base_dir}/${build_dir}/ggml/src/ggml-metal/${release_dir}/libggml-metal.a"
    "${base_dir}/${build_dir}/ggml/src/ggml-blas/${release_dir}/libggml-blas.a"
  )

  local temp_dir="${base_dir}/${build_dir}/temp"
  mkdir -p "${temp_dir}"
  libtool -static -o "${temp_dir}/combined.a" "${libs[@]}" 2>/dev/null

  local arch_flags=""
  for arch in ${archs}; do
    arch_flags+=" -arch ${arch}"
  done

  xcrun -sdk "${sdk}" clang++ -dynamiclib \
    -isysroot "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
    ${arch_flags} \
    ${min_version_flag} \
    -Wl,-force_load,"${temp_dir}/combined.a" \
    -framework Foundation -framework Metal -framework Accelerate \
    -install_name "@rpath/llama.framework/llama" \
    -o "${output_lib}"

  mkdir -p "${base_dir}/${build_dir}/dSYMs"
  xcrun dsymutil "${output_lib}" -o "${base_dir}/${build_dir}/dSYMs/llama.dSYM"

  # Strip debug symbols from the library after generating dSYM
  cp "${output_lib}" "${temp_dir}/binary_to_strip"
  xcrun strip -S "${temp_dir}/binary_to_strip" -o "${temp_dir}/stripped_lib"
  mv "${temp_dir}/stripped_lib" "${output_lib}"

  rm -rf "${temp_dir}"
}

echo "Building for iOS simulator..."
cmake -B build-ios-sim -G Xcode \
  "${COMMON_CMAKE_ARGS[@]}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_OS_VERSION}" \
  -DIOS=ON \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
  -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
  -S .
cmake --build build-ios-sim --config Release -- -quiet

echo "Building for iOS devices..."
cmake -B build-ios-device -G Xcode \
  "${COMMON_CMAKE_ARGS[@]}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_OS_VERSION}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \
  -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
  -S .
cmake --build build-ios-device --config Release -- -quiet

echo "Setting up framework structures..."
setup_framework_structure "build-ios-sim" "${IOS_MIN_OS_VERSION}"
setup_framework_structure "build-ios-device" "${IOS_MIN_OS_VERSION}"

echo "Creating dynamic libraries..."
combine_static_libraries_to_dylib "build-ios-sim" "Release-iphonesimulator" "iphonesimulator" "arm64 x86_64" "-mios-simulator-version-min=${IOS_MIN_OS_VERSION}"
combine_static_libraries_to_dylib "build-ios-device" "Release-iphoneos" "iphoneos" "arm64" "-mios-version-min=${IOS_MIN_OS_VERSION}"

echo "Creating XCFramework..."
mkdir -p build-apple
xcodebuild -create-xcframework \
  -framework "$(pwd)/build-ios-sim/framework/llama.framework" \
  -debug-symbols "$(pwd)/build-ios-sim/dSYMs/llama.dSYM" \
  -framework "$(pwd)/build-ios-device/framework/llama.framework" \
  -debug-symbols "$(pwd)/build-ios-device/dSYMs/llama.dSYM" \
  -output "$(pwd)/build-apple/llama.xcframework"

echo "Done: build-apple/llama.xcframework"

