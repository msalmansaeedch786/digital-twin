#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$DIR/build"
ZIP_FILE="$DIR/api_lambda.zip"

echo "Cleaning up..."
rm -rf "$BUILD_DIR" "$ZIP_FILE"
mkdir -p "$BUILD_DIR"

echo "Installing dependencies..."
# We use manylinux2014_aarch64 because we will deploy Lambda as arm64
pip3 install \
    --platform manylinux2014_aarch64 \
    --target="$BUILD_DIR" \
    --implementation cp \
    --python-version 3.12 \
    --only-binary=:all: \
    --upgrade \
    -r "$DIR/requirements.txt"

echo "Copying function code..."
cp "$DIR/main.py" "$BUILD_DIR/"

echo "Creating deterministic zip file..."
cd "$BUILD_DIR"
# Normalize all file modification times to Jan 1, 2020 to ensure reproducible zip hashes
find . -exec touch -t 202001010000.00 {} +
zip -X -r9q "$ZIP_FILE" .

echo "Build complete: $ZIP_FILE"
