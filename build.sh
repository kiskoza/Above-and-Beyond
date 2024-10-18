#!/usr/bin/bash

PROJECT_ROOT=$(dirname "$(readlink -f "$0")")
BUILD_DIR="${PROJECT_ROOT}"/build
MOD_CACHE_DIR="${PROJECT_ROOT}"/tmp/cache/mods

# Load APIKEY from a .env file
if [[ ! -f ${PROJECT_ROOT}/.env ]]; then
    echo ".env file missing! Cannot load API key!"
    exit 1
fi
set -o allexport
source "${PROJECT_ROOT}"/.env
set +o allexport

[[ -z "$APIKEY" ]] && { echo "API key not found!" ; exit 1; }

MANIFEST_JSON="${PROJECT_ROOT}"/manifest.json

VERSION=$(jq '.version' < "${MANIFEST_JSON}" -r)
[[ -z "$VERSION" ]] && { echo "Version is empty" ; exit 1; }

build_client () {
    mkdir -p "${BUILD_DIR}"/overrides
    
    TARGETS="config defaultconfigs kubejs openloader resourcepacks shaderpacks worldshape"
    for T in $TARGETS; do 
        cp -r "${PROJECT_ROOT}/$T" "${BUILD_DIR}"/overrides
    done

    cp "${MANIFEST_JSON}" "${BUILD_DIR}"/manifest.json
    cp "${PROJECT_ROOT}"/modlist.html "${BUILD_DIR}"/modlist.html

    pushd ${BUILD_DIR} &>/dev/null || exit 1
    zip -r "${PROJECT_ROOT}/Above-and-Beyond-$VERSION.zip" .
    popd &>/dev/null || exit 1

    rm -rf "${BUILD_DIR}"
}

build_server () {
    mkdir -p "${BUILD_DIR}"
    
    TARGETS="config defaultconfigs kubejs openloader worldshape"
    for T in $TARGETS; do 
        cp -r "${PROJECT_ROOT}/${T}" "${BUILD_DIR}"
    done
    
    cp "${PROJECT_ROOT}"/server.properties "${BUILD_DIR}"/server.properties
    cp "${PROJECT_ROOT}"/server-icon.png   "${BUILD_DIR}"/server-icon.png

    # Download mods
    download_mods
    
    # Cache mods for future builds
    mkdir -p "${MOD_CACHE_DIR}"
    cp "${BUILD_DIR}"/mods/* "${MOD_CACHE_DIR}"
    
    # Download forge installer
    download_forge
    echo "Generating server pack: ${PROJECT_ROOT}/Above-and-Beyond-$VERSION-server.zip"

    pushd ${BUILD_DIR} &>/dev/null || exit 1
    zip -r "${PROJECT_ROOT}/Above-and-Beyond-$VERSION-server.zip" .
    popd &>/dev/null || exit 1

    rm -rd "${BUILD_DIR}"
}

download_mods () {
    echo "Downloading mods to ${BUILD_DIR}/mods"
    mkdir -p "${BUILD_DIR}"/mods
  
    for ids in $(jq '.files[] | "\(.projectID),\(.fileID)"' < "${MANIFEST_JSON}" -r); do
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
    MC_VERSION=$(jq '.minecraft.version' < "${MANIFEST_JSON}" -r)
    FORGE_VERSION=$(jq '.minecraft.modLoaders[0].id' < "${MANIFEST_JSON}" -r | cut -d- -f2)
    
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
    echo "No argumetns given!"
    print_help
fi

for ARG in "$@"; do
    case $ARG in
        "server")
            echo "Building server pack"
            build_server
            ;;
        "client")
            echo "Buildind client pack"
            build_client
            ;;
        "help")
            print_help
            ;;
        *)
            echo "Incorrect argument!"
            print_help
            exit 1
            ;;
    esac
done
