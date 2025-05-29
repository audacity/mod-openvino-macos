#!/bin/bash

set -e
set -x
set -o pipefail

ARCH="$1"

if [[ "$ARCH" == "arm64" ]]; then
  MACOS_DEPLOYMENT_TARGET="11.0"
  OV_ARCH_NAME="arm64"
  OPENVINO_URL="https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.0/macos/m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64.tgz"
  OPENVINO_FOLDER="m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64"
  LIBTORCH_URL="https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.2.2.zip"
  LIBOMP_LIB_DIR="/opt/homebrew/opt/libomp/lib/"
elif [[ "$ARCH" == "x86_64" ]]; then
  MACOS_DEPLOYMENT_TARGET="10.15"
  OV_ARCH_NAME="intel64"
  OPENVINO_URL="https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.0/macos/m_openvino_toolkit_macos_10_15_2024.0.0.14509.34caeefd078_x86_64.tgz"
  OPENVINO_FOLDER="m_openvino_toolkit_macos_10_15_2024.0.0.14509.34caeefd078_x86_64"
  LIBTORCH_URL="https://download.pytorch.org/libtorch/cpu/libtorch-macos-x86_64-2.2.2.zip"
  LIBOMP_LIB_DIR="/usr/local/opt/libomp/lib/"
  echo "Install x86 brew"
  arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  arch -x86_64 /usr/local/bin/brew install libomp  
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

brew install opencl-clhpp-headers
brew install libomp

MODULE_VERSION="3.7.1-R4.2"
ROOT_DIR=$(pwd)
SOURCE_PATH="$ROOT_DIR/sources"
PACKAGE_PATH="$ROOT_DIR/packages"
BUILD_PATH="$ROOT_DIR/build"
STAGING_PATH="$ROOT_DIR/staging"

OPENCL_INCLUDE_DIR="/opt/homebrew/opt/opencl-clhpp-headers/include"

echo "Applying patches..."

for repo in $(ls "$SOURCE_PATH"); do
    patch_dir="${ROOT_DIR}/patches/$repo"
    if [ -d "$patch_dir" ]; then
        echo "Applying patches to $repo"
        for patch in $patch_dir/*.patch; do
            if [ -f "$patch" ]; then
                echo "Applying patch $patch"
                patch -d "$SOURCE_PATH/$repo" < "$patch"
            fi
        done
    else
        echo "No patches found for $repo"
    fi
done

cp -r "$SOURCE_PATH/openvino-plugins-ai-audacity/mod-openvino" "$SOURCE_PATH/audacity/modules"

cd "$PACKAGE_PATH"
wget "$OPENVINO_URL"
tar xvf "$(basename "$OPENVINO_URL")"
source "$OPENVINO_FOLDER/setupvars.sh"

wget "$LIBTORCH_URL"
unzip "$(basename "$LIBTORCH_URL")"
export LIBTORCH_ROOTDIR="$PACKAGE_PATH/libtorch"

mkdir -p "$BUILD_PATH/whisper"
cd "$BUILD_PATH/whisper"
cmake "$SOURCE_PATH/whisper.cpp" -DWHISPER_OPENVINO=ON -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET -DWHISPER_NO_ACCELERATE=ON
make -j"$(sysctl -n hw.ncpu)"

cmake --install . --config Release --prefix "$PACKAGE_PATH/whisper"
export WHISPERCPP_ROOTDIR="$PACKAGE_PATH/whisper"
export LD_LIBRARY_PATH="${WHISPERCPP_ROOTDIR}/lib:$LD_LIBRARY_PATH"

mkdir -p "$BUILD_PATH/openvino_tokenizers"
cd "$BUILD_PATH/openvino_tokenizers"
cmake "$SOURCE_PATH/openvino_tokenizers" -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET
make -j"$(sysctl -n hw.ncpu)"

cmake --install . --config Release --prefix "$PACKAGE_PATH/openvino_tokenizers"

mkdir -p "$BUILD_PATH/audacity"
cd "$BUILD_PATH/audacity"
cmake -G "Unix Makefiles" \
    -D CMAKE_CXX_FLAGS="-I${OPENCL_INCLUDE_DIR}" \
    -DCMAKE_OSX_ARCHITECTURES=$ARCH \
    -DMACOS_ARCHITECTURE=$ARCH \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET \
    "$SOURCE_PATH/audacity" -DCMAKE_BUILD_TYPE=Release

make -j"$(sysctl -n hw.ncpu)"

mkdir -p "$STAGING_PATH"
cd "$STAGING_PATH"
MODULE_PATH="$STAGING_PATH/dist/Library/Application Support/audacity/modules"
mkdir -p "$MODULE_PATH/libs"

cp -P "$BUILD_PATH/audacity/Release/Audacity.app/Contents/modules/mod-openvino.so" "$MODULE_PATH"

cp -P "$PACKAGE_PATH/$OPENVINO_FOLDER/runtime/lib/$OV_ARCH_NAME/Release/"*.{so,dylib} "$MODULE_PATH/libs"
cp -P "$PACKAGE_PATH/$OPENVINO_FOLDER/runtime/3rdparty/tbb/lib/"*.dylib "$MODULE_PATH/libs"

cp -P "$PACKAGE_PATH/libtorch/lib/"*.dylib "$MODULE_PATH/libs"
cp -P "$PACKAGE_PATH/whisper/lib/"*.dylib "$MODULE_PATH/libs"
cp -P "$PACKAGE_PATH/openvino_tokenizers/lib/"*.dylib "$MODULE_PATH/libs"
cp "${LIBOMP_LIB_DIR}/libomp.dylib" "$MODULE_PATH/libs/"

chmod -R ug+w "$MODULE_PATH"
xattr -cr "$MODULE_PATH"

cd "$MODULE_PATH"
for lib in *.so *.dylib; do
    [ -e "$lib" ] || continue
    echo "Processing $lib..."
    deps=$(otool -L "$lib" | awk 'NR>1 {print $1}' | grep '@loader_path/../Frameworks/')
    for dep in $deps; do
        dep_filename=$(basename "$dep")
        if [[ -f "./libs/$dep_filename" ]]; then
            new_dep="@rpath/$dep_filename"
        else
            new_dep="@executable_path/../Frameworks/$dep_filename"
        fi
        echo "  Updating dependency: $dep → $new_dep"
        install_name_tool -change "$dep" "$new_dep" "$lib"
    done
    install_name_tool -add_rpath @loader_path/libs "$lib"
done

cd "$ROOT_DIR"
cp -r installer/* staging

sudo xcode-select -s /Applications/Xcode_16.2.app

PROJECT="tools/ResourceDownloader/ResourceDownloader.xcodeproj"
SCHEME="ResourceDownloader"
CONFIG="Release"
BUILD_DIR="build"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  -arch "$ARCH" \
  clean build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"
cp -R "$APP_PATH" "$STAGING_PATH/Scripts"

cd "$STAGING_PATH"
mkdir -p packages

pkgbuild \
  --root dist \
  --scripts Scripts \
  --install-location / \
  --identifier org.audacityteam.audacity \
  --version "$MODULE_VERSION" \
  packages/openvino-module.pkg

productbuild  --distribution distribution.xml \
  --resources Resources \
  --package-path ./packages \
  ./Audacity-OpenVINO-${MODULE_VERSION}-${ARCH}.pkg

echo "Done."
