#!/usr/bin/bash

# Get project root based on build.sh directory
PROJECT_ROOT=$(dirname "$(readlink -f "$0")")
pushd ${PROJECT_ROOT} &>/dev/null

BUILD_DIR=build
MOD_CACHE_DIR=/tmp/cache/mods

# Load APIKEY from a .env file
set -o allexport
source .env
set +o allexport

VERSION=$(jq '.version' < "${MANIFEST_JSON}" -r)

[[ -z "$APIKEY"  ]] && { echo "API key not found!"; exit 1; }
[[ -z "$VERSION" ]] && { echo "Version is empty";   exit 1; }

build_client () {
    mkdir -p "${BUILD_DIR}"/overrides
    
    TARGETS="config defaultconfigs kubejs openloader resourcepacks shaderpacks worldshape"
    for T in $TARGETS; do 
        cp -r "$T" "${BUILD_DIR}"/overrides
    done

    cp manifest.json "${BUILD_DIR}"/manifest.json
    cp modlist.html  "${BUILD_DIR}"/modlist.html

    pushd ${BUILD_DIR} &>/dev/null
    zip -r "../Above-and-Beyond-$VERSION.zip" .
    popd &>/dev/null

    rm -rf "${BUILD_DIR}"
}

build_server () {
    mkdir -p "${BUILD_DIR}"
    
    TARGETS="config defaultconfigs kubejs openloader worldshape"
    for T in $TARGETS; do 
        cp -r "${T}" "${BUILD_DIR}"
    done
    
    cp server.properties "${BUILD_DIR}"/server.properties
    cp server-icon.png   "${BUILD_DIR}"/server-icon.png

    # Download mods
    download_mods
    
    # Cache mods for future builds
    mkdir -p "${MOD_CACHE_DIR}"
    cp "${BUILD_DIR}"/mods/* "${MOD_CACHE_DIR}"
    
    # Download forge installer
    download_forge
    echo "Generating server pack: Above-and-Beyond-$VERSION-server.zip"

    pushd ${BUILD_DIR} &>/dev/null
    zip -r "../Above-and-Beyond-$VERSION-server.zip" .
    popd &>/dev/null

    rm -rd "${BUILD_DIR}"
}

download_mods () {
    echo "Downloading mods to ${BUILD_DIR}/mods"
    mkdir -p "${BUILD_DIR}"/mods
  
    for ids in $(jq '.files[] | "\(.projectID),\(.fileID)"' < manifest.json -r); do
        PROJECT_ID=$(cut -d, -f1 <<< "${ids}")
        FILE_ID=$(cut -d, -f2 <<< "${ids}")

        FILE_META=$(curl -sS \
                         -X GET "https://api.curseforge.com/v1/mods/$PROJECT_ID/files/$FILE_ID" \
                         -H 'Accept: application/json' \
                         -H "x-api-key: $APIKEY")

        DOWNLOAD_URL=$(jq '.data.downloadUrl' -r <<< "${FILE_META}")
        FILE_NAME=$(jq '.data.fileName' -r <<< "${FILE_META}")

        if [ -f "${MOD_CACHE_DIR}/$FILE_NAME" ]; then
            echo -n '.'
            cp "${MOD_CACHE_DIR}/$FILE_NAME" "${BUILD_DIR}"/mods
        elif [ "$DOWNLOAD_URL" != "null" ]; then
            echo -n 'D'
            wget -q "$DOWNLOAD_URL" -P "${BUILD_DIR}"/mods
        else
            echo -n 'M'
            WEBSITE_URL=$(curl -sS \
                               -X GET "https://api.curseforge.com/v1/mods/$PROJECT_ID" \
                               -H 'Accept: application/json' \
                               -H "x-api-key: $APIKEY" \
                              | jq '.data.links.websiteUrl' -r
                       )
            echo ""
            echo "You need to download this mod manually."
            echo "Go to the website and find the file and put it in the following directory:"
            echo " ${BUILD_DIR}/mods "
            echo "URL: $WEBSITE_URL"
            echo "File: $FILE_NAME"
            echo "After that you can continue."
            read -p "Press any key to continue " -n 1 -r
        fi
    done
    echo ""
}

download_forge () {
    echo "Downloading Forge to ${BUILD_DIR}"
    MC_VERSION=$(jq '.minecraft.version' < manifest.json -r)
    FORGE_VERSION=$(jq '.minecraft.modLoaders[0].id' < manifest.json -r | cut -d- -f2)
    
    echo "Minecraft version: $MC_VERSION"
    echo "Forge version: $FORGE_VERSION"
    wget -q "https://maven.minecraftforge.net/net/minecraftforge/forge/$MC_VERSION-$FORGE_VERSION/forge-$MC_VERSION-$FORGE_VERSION-installer.jar" -P "${BUILD_DIR}"
}

print_help () {
    echo "Above and beyond builder" 
    echo "Give arguments to build the server or the client pack!"
    echo "Usage:"
    echo " ./build.sh server -- builds the server pack"
    echo " ./build.sh client -- builds the client pack"
    echo " ./build.sh help   -- builds the client pack"
    echo "(you can build both by using both arguments)"
}

if [[ -z "$*" ]]; then
    echo "Building whole pack"
    build_client
    build_server
fi

for ARG in "$@"; do
    case $ARG in
        "--server")
            echo "Building server pack"
            build_server
            ;;
        "--client")
            echo "Buildind client pack"
            build_client
            ;;
        "--help")
            print_help
            ;;
        *)
            echo "Incorrect argument!"
            print_help
            popd &>/dev/null
            exit 1
            ;;
    esac
done

popd &>/dev/null

