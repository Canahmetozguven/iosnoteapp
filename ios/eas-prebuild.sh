#!/bin/bash
set -e

PROJECT_NAME="SynapsNotes-iOS"
PROJECT_FILE="ios/${PROJECT_NAME}.xcodeproj"

echo "EAS Prebuild: Starting..."

# Check if ios/llama exists
if [ ! -d "ios/llama" ]; then
  echo "Error: ios/llama directory not found!"
  ls -R ios
  exit 1
fi

# Install dependencies
echo "Installing dependencies..."
brew install cmake xcodegen

# Build llama.cpp
echo "Building llama.cpp framework..."
cd ios/llama
if [ ! -f "scripts/build-ios-xcframework.sh" ]; then
  echo "Error: scripts/build-ios-xcframework.sh not found in ios/llama"
  ls -la
  exit 1
fi
chmod +x scripts/build-ios-xcframework.sh
./scripts/build-ios-xcframework.sh
cd ../..

# Move framework
echo "Moving framework..."
mkdir -p ios/Frameworks
rm -rf ios/Frameworks/llama.xcframework
if [ -d "ios/llama/build-apple/llama.xcframework" ]; then
  cp -R ios/llama/build-apple/llama.xcframework ios/Frameworks/
  ls -la ios/Frameworks/llama.xcframework >/dev/null
else
  echo "Error: llama.xcframework build failed or not found"
  exit 1
fi

# Generate Project
echo "Generating Xcode project..."
cd ios
if [ -d "${PROJECT_NAME}.xcodeproj" ]; then
    echo "Removing old project..."
    rm -rf "${PROJECT_NAME}.xcodeproj"
fi
xcodegen
cd ..

if [ ! -d "${PROJECT_FILE}" ]; then
  echo "Error: ${PROJECT_FILE} was not generated"
  exit 1
fi

echo "Validated generated project: ${PROJECT_FILE}"
echo "EAS Prebuild: Completed successfully."
