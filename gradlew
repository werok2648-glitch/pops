#!/bin/bash
if [ ! -d "gradle" ]; then
    wget -q https://gradle.org
    unzip -q gradle-8.7-bin.zip
    mv gradle-8.7/bin/gradle ./gradlew_real
    rm -rf gradle-8.7-bin.zip gradle-8.7
fi
chmod +x ./build.sh
./build.sh
./gradlew_real build
