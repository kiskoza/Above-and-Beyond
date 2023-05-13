#!/bin/bash

VERSION=$1
[[ -z "$1" ]] && { echo "Version is empty" ; exit 1; }

mkdir -p build/overrides

cp -r config defaultconfigs kubejs openloader resourcepacks shaderpacks worldshape build/overrides/

cp manifest.json build/manifest.json
cp modlist.html build/modlist.html

cd build

zip -r "../Above-and-Beyond-$VERSION.zip" .

cd ..
rm -rd build
