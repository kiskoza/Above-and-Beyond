#!/bin/bash

# Load APIKEY from a .env file
set -o allexport
source .env
set +o allexport

VERSION=${1:-$(cat manifest.json | jq '.version' | xargs echo)}

[[ -z "$VERSION" ]] && { echo "Version is empty" ; exit 1; }
[[ -z "$APIKEY" ]] && { echo "Version is empty" ; exit 1; }

build_client () {
  mkdir -p build/overrides

  cp -r config defaultconfigs kubejs openloader resourcepacks shaderpacks worldshape build/overrides/

  cp manifest.json build/manifest.json
  cp modlist.html build/modlist.html

  cd build
  zip -r "../Above-and-Beyond-$VERSION.zip" .
  cd ..
  rm -rd build
}

build_server () {
  mkdir -p build

  cp -r config defaultconfigs kubejs openloader worldshape build/

  cp server.properties build/server.properties
  cp server-icon.png build/server-icon.png

  # Download mods
  mkdir -p build/mods
  mkdir -p tmp/cache/mods
  cd build/mods
  download_mods
  cd ../..

  # Cache mods for future builds
  mkdir -p tmp/cache/mods
  cp build/mods/* tmp/cache/mods/

  # Download forge installer
  cd build
  download_forge
  cd ..

  cd build
  zip -r "../Above-and-Beyond-$VERSION-server.zip" .
  cd ..
  rm -rd build
}

download_mods () {
  for ids in $(cat ../../manifest.json | jq '.files[] | "\(.projectID),\(.fileID)"' | xargs echo)
  do
    PROJECT_ID=$(echo $ids | cut -d, -f1)
    FILE_ID=$(echo $ids | cut -d, -f2)

    FILE_META=$(curl -sS \
                     -X GET "https://api.curseforge.com/v1/mods/$PROJECT_ID/files/$FILE_ID" \
                     -H 'Accept: application/json' \
                     -H "x-api-key: $APIKEY")

    DOWNLOAD_URL=$(echo $FILE_META \
                        | jq '.data.downloadUrl' \
                        | xargs echo)

    FILE_NAME=$(echo $FILE_META | jq '.data.fileName' | xargs echo)

    if [ -f "../../tmp/cache/mods/$FILE_NAME" ]; then
      echo -n '.'
      cp "../../tmp/cache/mods/$FILE_NAME" .
    elif [ "$DOWNLOAD_URL" != "null" ]; then
      echo -n 'D'
      wget -q "$DOWNLOAD_URL"
    else
      print -n 'M'
      WEBSITE_URL=$(curl -sS \
                         -X GET "https://api.curseforge.com/v1/mods/$PROJECT_ID" \
                         -H 'Accept: application/json' \
                         -H "x-api-key: $APIKEY" \
                         | jq '.data.links.websiteUrl' \
                         | xargs echo )

      echo "You need to download this mod manually. Go to the website and find the file and put it in the '$(pwd)' folder"
      echo "URL: $WEBSITE_URL"
      echo "File: $FILE_NAME"
      read -p "Press any key to continue " -n 1 -r
    fi
  done
}

download_forge () {
  MC_VERSION=$(cat ../manifest.json | jq '.minecraft.version' | xargs echo)
  FORGE_VERSION=$(cat ../manifest.json | jq '.minecraft.modLoaders[0].id' | xargs echo | cut -d- -f2)

  echo $MC_VERSION
  echo $FORGE_VERSION
  wget -q "https://maven.minecraftforge.net/net/minecraftforge/forge/$MC_VERSION-$FORGE_VERSION/forge-$MC_VERSION-$FORGE_VERSION-installer.jar"
}

build_client
build_server
