#!/bin/bash

set -e
set -x
set -o pipefail

brew install opencl-clhpp-headers
brew install libomp

MODULE_VERSION="3.7.1-R4.2"
ROOT_DIR=$(pwd)
SOURCE_PATH=$(pwd)/sources
PACKAGE_PATH=$(pwd)/packages
BUILD_PATH=$(pwd)/build
STAGING_PATH=$(pwd)/staging

echo "Applying patches..."

for repo in $(ls $SOURCE_PATH); do
    patch_dir=${ROOT_DIR}/patches/$repo
    if [ -d "$patch_dir" ]; then
        echo "Applying patches to $repo"
        for patch in $patch_dir/*.patch; do
            if [ -f "$patch" ]; then
                echo "Applying patch $patch"
                patch -d $SOURCE_PATH/$repo < $patch
            fi
        done
    else
        echo "No patches found for $repo"
    fi
done

cp -r $SOURCE_PATH/openvino-plugins-ai-audacity/mod-openvino $SOURCE_PATH/audacity/modules

cd $PACKAGE_PATH
wget https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.0/macos/m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64.tgz
tar xvf m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64.tgz
source m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64/setupvars.sh

wget https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.2.2.zip
unzip libtorch-macos-arm64-2.2.2.zip
export LIBTORCH_ROOTDIR=$PACKAGE_PATH/libtorch

mkdir -p $BUILD_PATH/whisper
cd $BUILD_PATH/whisper
cmake $SOURCE_PATH/whisper.cpp -DWHISPER_OPENVINO=ON -DMACOS_ARCHITECTURE=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DWHISPER_NO_ACCELERATE=ON
make -j`sysctl -n hw.ncpu`

cmake --install . --config Release --prefix $PACKAGE_PATH/whisper
export WHISPERCPP_ROOTDIR=$PACKAGE_PATH/whisper
export LD_LIBRARY_PATH=${WHISPERCPP_ROOTDIR}/lib:$LD_LIBRARY_PATH

mkdir -p $BUILD_PATH/openvino_tokenizers
cd $BUILD_PATH/openvino_tokenizers
cmake $SOURCE_PATH/openvino_tokenizers -DMACOS_ARCHITECTURE=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
make -j`sysctl -n hw.ncpu`

cmake --install . --config Release --prefix $PACKAGE_PATH/openvino_tokenizers

mkdir -p $BUILD_PATH/audacity
cd $BUILD_PATH/audacity

cmake -G "Unix Makefiles" \
    -D CMAKE_CXX_FLAGS="-I/opt/homebrew/opt/opencl-clhpp-headers/include" \
    -DMACOS_ARCHITECTURE=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0\
    $SOURCE_PATH/audacity -DCMAKE_BUILD_TYPE=Release

make -j`sysctl -n hw.ncpu`

mkdir -p $STAGING_PATH
cd $STAGING_PATH
MODULE_PATH="$STAGING_PATH/dist/Library/Application Support/audacity/modules"

mkdir -p "$MODULE_PATH/libs"

cp -p $BUILD_PATH/audacity/Release/Audacity.app/Contents/modules/mod-openvino.so \
    "$MODULE_PATH"

cp -p $PACKAGE_PATH/m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64/runtime/lib/arm64/Release/*.so \
    "$MODULE_PATH/libs"
cp -p $PACKAGE_PATH/m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64/runtime/lib/arm64/Release/*.dylib \
    "$MODULE_PATH/libs"
cp -p $PACKAGE_PATH/m_openvino_toolkit_macos_11_0_2024.0.0.14509.34caeefd078_arm64/runtime/3rdparty/tbb/lib/*.dylib \
    "$MODULE_PATH/libs"

cp -p $PACKAGE_PATH/libtorch/lib/libc10.dylib \
    "$MODULE_PATH/libs"
cp -p $PACKAGE_PATH/libtorch/lib/libtorch.dylib \
    "$MODULE_PATH/libs"
cp -p $PACKAGE_PATH/libtorch/lib/libtorch_cpu.dylib \
    "$MODULE_PATH/libs"

cp -P $PACKAGE_PATH/whisper/lib/*.dylib \
    "$MODULE_PATH/libs"

cp -P $PACKAGE_PATH/openvino_tokenizers/lib/*.dylib \
    "$MODULE_PATH/libs/"

cp /opt/homebrew/opt/libomp/lib/libomp.dylib \
    "$MODULE_PATH/libs/"

chmod -R ug+w "$MODULE_PATH"

xattr -cr "$MODULE_PATH"

# Fix loading paths
cd "$MODULE_PATH"
for lib in *.so *.dylib; do
    [ -e "$lib" ] || continue

    echo "Processing $lib..."

    deps=$(otool -L "$lib" | awk 'NR>1 {print $1}' | grep '@loader_path/../Frameworks/')

    for dep in $deps; do
        
        dep_filename=$(basename "$dep")

        # If we have this file in the libs directory, use it
        if [[ -f "./libs/$dep_filename" ]]; then
            new_dep="@rpath/$dep_filename"
            echo "  Updating dependency: $dep → $new_dep"
            install_name_tool -change "$dep" "$new_dep" "$lib"
        else
            # If the file does not exist load it from the Audacity/Frameworks directory
        	new_dep="@executable_path/../Frameworks/$dep_filename"
			echo "  Updating dependency: $dep → $new_dep"
			install_name_tool -change "$dep" "$new_dep" "$lib"
        fi
    done

    install_name_tool -add_rpath @loader_path/libs "$lib"
done

cd $ROOT_DIR
cp -r installer/* "$STAGING_PATH"

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
  clean build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"

# codesign --verbose --timestamp --identifier "org.audacityteam.resourcedownloader" --sign "${APPLE_CODESIGN_IDENTITY}" "$APP_PATH"

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

# productsign --sign "${APPLE_CODESIGN_IDENTITY}" packages/openvino-module.pkg packages/openvino-module.pkg

productbuild  --distribution distribution.xml \
  --resources Resources \
  --package-path ./packages \
  ./Audacity-OpenVINO.pkg 

# productsign --sign "${APPLE_CODESIGN_IDENTITY}" final.pkg final.pkg

echo "Done."
