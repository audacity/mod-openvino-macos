#!/bin/bash

set -e

ROOT_DIR=$(pwd)
STAGING_PATH="$ROOT_DIR/staging"

process_file() {
    local rel_path="$1"
    local arm_file="$ARM_DIR/$rel_path"
    local x86_file="$X86_DIR/$rel_path"
    local out_file="$UNIVERSAL_DIR/$rel_path"

    echo processing $1

    mkdir -p "$(dirname "$out_file")"

    if [ -f "$arm_file" ] && [ -f "$x86_file" ]; then
        # Merge matching binaries
        if file "$arm_file" | grep -q 'Mach-O'; then
            lipo -create -output "$out_file" "$arm_file" "$x86_file"
            echo "Created universal binary: $rel_path"
        else
            cp "$arm_file" "$out_file"
            echo "Copied from ARM (non-binary): $rel_path"
        fi
    elif [ -f "$arm_file" ]; then
        cp "$arm_file" "$out_file"
        echo "Copied from ARM only: $rel_path"
    elif [ -f "$x86_file" ]; then
        cp "$x86_file" "$out_file"
        echo "Copied from x86 only: $rel_path"
    fi

    # Copy symlinks
    if [ -L "$arm_file" ]; then
        link_target=$(readlink "$arm_file")
        ln -sf "$link_target" "$out_file"
        echo "Copied symlink from ARM: $rel_path -> $link_target"
    elif [ -L "$x86_file" ]; then
        link_target=$(readlink "$x86_file")
        ln -sf "$link_target" "$out_file"
        echo "Copied symlink from x86: $rel_path -> $link_target"
    fi
}

echo "Extracting PKGs"
cd universal || exit 1

pkgutil --expand-full mod-openvino-arm64/Audacity-OpenVINO*.pkg openvino-module-arm64
pkgutil --expand-full mod-openvino-x86/Audacity-OpenVINO*.pkg openvino-module-x86

ARM_DIR="openvino-module-arm64/"
X86_DIR="openvino-module-x86/"
UNIVERSAL_DIR="openvino-module-universal/"

mkdir -p "$UNIVERSAL_DIR"
mkdir -p "$STAGING_PATH"

all_files=$(
  (
    (cd "$ARM_DIR" && find . \( -type f -o -type l \))
    (cd "$X86_DIR" && find . \( -type f -o -type l \))
  ) | sort -u
)

while read -r rel_path; do
    rel_path="${rel_path#./}"
    process_file "$rel_path"
done <<< "$all_files"

version=$(sed -nE 's/.*version="([0-9]+\.[0-9]+\.[0-9]+[^"]*)".*/\1/p' $ARM_DIR/openvino-module.pkg/PackageInfo)

echo "Creating universal PKG"
mv openvino-module-universal/openvino-module.pkg openvino-module-universal/openvino-module.dir
mkdir -p openvino-module-universal/packages
pkgbuild \
    --root openvino-module-universal/openvino-module.dir/Payload \
    --scripts openvino-module-universal/openvino-module.dir/Scripts \
    --install-location / \
    --identifier org.audacityteam.audacity \
    --version "$version" \
    openvino-module-universal/packages/openvino-module.pkg


productbuild  --distribution openvino-module-universal/Distribution \
  --resources openvino-module-universal/Resources \
  --package-path ./openvino-module-universal/packages \
  $STAGING_PATH/Audacity-OpenVINO-${version}.pkg
