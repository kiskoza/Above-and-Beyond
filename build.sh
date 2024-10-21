#!/usr/bin/bash

# Fail if any error happens unhandled
set -e

# Get project root based on build.sh directory
PROJECT_ROOT=$(dirname "$(readlink -f "$0")")
pushd "${PROJECT_ROOT}" &>/dev/null

# Load variables from a .env file
if [[ -f .env ]]; then
    set -o allexport
    source .env
    set +o allexport
fi

build_client () {
    mkdir -p $BUILD_DIR/overrides

    cp --target-dir $BUILD_DIR \
       manifest.json modlist.html

    cp --target-dir $BUILD_DIR/overrides \
       -r config defaultconfigs kubejs openloader worldshape

    pushd $BUILD_DIR &>/dev/null
    zip -q -r "Above-and-Beyond-$VERSION.zip" .
    popd &>/dev/null
    mv "$BUILD_DIR/Above-and-Beyond-$VERSION.zip" .

    rm -rf $BUILD_DIR

    echo "Client pack is ready: Above-and-Beyond-$VERSION.zip"
}

build_server () {
    mkdir -p $BUILD_DIR

    cp --target-dir $BUILD_DIR \
       server.properties server-icon.png

    cp --target-dir $BUILD_DIR \
       -r config defaultconfigs kubejs openloader worldshape

    # Download mods
    download_mods

    # Cache mods for future builds
    mkdir -p $MOD_CACHE_DIR
    cp $BUILD_DIR/mods/* $MOD_CACHE_DIR

    # Download forge installer
    download_forge

    pushd ${BUILD_DIR} &>/dev/null
    zip -q -r "Above-and-Beyond-$VERSION-server.zip" .
    popd &>/dev/null
    mv "$BUILD_DIR/Above-and-Beyond-$VERSION-server.zip" .

    rm -rf $BUILD_DIR
    echo "Server pack is ready: Above-and-Beyond-$VERSION-server.zip"
}

download_mods () {
    echo "Downloading mods to $BUILD_DIR/mods"
    mkdir -p "${BUILD_DIR}"/mods

    for ids in $(jq -r '.files[] | "\(.projectID),\(.fileID)"' manifest.json); do
        local project_id
        project_id=$(cut -d, -f1 <<< "${ids}")

        local file_id
        file_id=$(cut -d, -f2 <<< "${ids}")

        local file_meta
        file_meta=$(curl -sS \
                         -X GET "https://api.curseforge.com/v1/mods/$project_id/files/$file_id" \
                         -H 'Accept: application/json' \
                         -H "x-api-key: $APIKEY")

        local download_url
        download_url=$(jq -r '.data.downloadUrl' <<< "${file_meta}")

        local file_name
        file_name=$(jq -r '.data.fileName' <<< "${file_meta}")

        if [ -f "${MOD_CACHE_DIR}/$file_name" ]; then
            echo -n '.'
            cp "${MOD_CACHE_DIR}/$file_name" "${BUILD_DIR}"/mods
        elif [ "$download_url" != "null" ]; then
            echo -n 'D'
            wget -q "$download_url" -P "${BUILD_DIR}"/mods
        else
            echo -n 'M'
            local website_url
            website_url=$(curl -sS \
                               -X GET "https://api.curseforge.com/v1/mods/$project_id" \
                               -H 'Accept: application/json' \
                               -H "x-api-key: $APIKEY" \
                            | jq -r '.data.links.websiteUrl'
                         )
            echo ""
            echo "You need to download this mod manually."
            echo "Go to the website and find the file and put it in the following directory:"
            echo " ${BUILD_DIR}/mods "
            echo "URL: $website_url"
            echo "File: $file_name"
            read -p "Press any key to continue when you are ready" -n 1 -r
        fi
    done
    echo ""
}

download_forge () {
    echo "Downloading Forge to ${BUILD_DIR}"

    local mc_version
    mc_version=$(jq -r '.minecraft.version' manifest.json)

    local forge_version
    forge_version=$(jq -r '.minecraft.modLoaders[0].id' manifest.json | cut -d- -f2)

    echo "Minecraft version: $mc_version"
    echo "Forge version: $forge_version"
    wget -q "https://maven.minecraftforge.net/net/minecraftforge/forge/$mc_version-$forge_version/forge-$mc_version-$forge_version-installer.jar" -P "${BUILD_DIR}"
}

usage () {
    echo "Above and Beyond builder"
    echo ""
    echo "Usage: $0 [--apikey <k>] [--version <v>|-v <v>] [--skip-server|--skip-client] [--help|-h]"
    echo "            --apikey       sets the CurseForge API key (default is in the .env file)"
    echo "            --version      sets the package version (default is in the manifest.json)"
    echo "            --skip-server  skips the server build (default)"
    echo "            --skip-client  skips the client build"
    echo "            --help         show this message"
    echo ""
}

BUILD_DIR=build
MOD_CACHE_DIR=tmp/cache/mods

BUILD_SERVER=yes
BUILD_CLIENT=yes

VERSION=$(jq -r '.version' manifest.json)

while [ $# -gt 0 ]
do
  case "$1" in
    --apikey)
      shift
      APIKEY="$1"
      shift
      ;;

    --version | -v)
      shift
      VERSION="$1"
      shift
      ;;

    --skip-server)
      shift
      BUILD_SERVER=no
      ;;

    --skip-client)
      shift
      BUILD_CLIENT=no
      ;;

    --help | -h | *)
      usage
      exit 255
      ;;
  esac
done

[[ -z "$APIKEY"  ]] && { echo "API key not found!"; exit 1; }
[[ -z "$VERSION" ]] && { echo "Version is empty";   exit 1; }

if [ "$BUILD_CLIENT" = "yes" ]; then
  build_client
fi

if [ "$BUILD_SERVER" = "yes" ]; then
  build_server
fi
