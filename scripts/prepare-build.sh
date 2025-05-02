#!/bin/bash

set -e
set -x

ROOT_DIR=$(pwd)
SOURCE_PATH=$(pwd)/sources
PACKAGE_PATH=$(pwd)/packages
BUILD_PATH=$(pwd)/build

function download_release {
    cd $SOURCE_PATH
    local repo=$1
    local release=${2:+tags/$2}
    release=${release:-latest}
    local target_dir=$(basename $repo)
    echo Downloading ${release} release of $repo into $target_dir
    mkdir -p $target_dir
    curl -sL https://api.github.com/repos/${repo}/releases/${release} 
    wget -O ${target_dir}/archive.tar.gz $(wget -q -O - https://api.github.com/repos/${repo}/releases/${release} | jq -r '.tarball_url')
    tar --strip-components=1 -xzf ${target_dir}/archive.tar.gz -C $target_dir
    rm -f ${target_dir}/archive.tar.gz
    cd $ROOT_DIR
}

function download_tarball {
    cd "$SOURCE_PATH" || exit 1
    local repo=$1
    local url=$2
    local target_dir=$(basename "$repo")
    echo "Downloading from $url into $target_dir"
    mkdir -p "$target_dir"

    wget -O "${target_dir}/archive.tar.gz" "$url"
    tar --strip-components=1 -xzf "${target_dir}/archive.tar.gz" -C "$target_dir"
    rm -f "${target_dir}/archive.tar.gz"
    cd "$ROOT_DIR" || exit 1
}

echo "Cleaning build directory..."
rm -rf $PACKAGE_PATH
rm -rf $BUILD_PATH
rm -rf $SOURCE_PATH

mkdir -p $PACKAGE_PATH
mkdir -p $BUILD_PATH
mkdir -p $SOURCE_PATH

# download dependencies
# download_release "audacity/audacity"
# download_release "intel/openvino-plugins-ai-audacity"
# download_release "ggerganov/whisper.cpp" "v1.6.0"
# download_release "openvinotoolkit/openvino_tokenizers" "2024.0.0.0"

download_tarball "audacity/audacity" "https://github.com/audacity/audacity/archive/refs/tags/Audacity-3.7.3.tar.gz"
download_tarball "intel/openvino-plugins-ai-audacity" "https://github.com/intel/openvino-plugins-ai-audacity/archive/refs/tags/v3.7.1-R4.2.tar.gz"
download_tarball "ggerganov/whisper.cpp" "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.6.0.tar.gz"
download_tarball "openvinotoolkit/openvino_tokenizers" "https://github.com/openvinotoolkit/openvino_tokenizers/archive/refs/tags/2024.0.0.0.tar.gz"
