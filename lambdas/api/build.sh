#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$DIR/build"
ZIP_FILE="$DIR/api_lambda.zip"

echo "Cleaning up old zip..."
rm -f "$ZIP_FILE"

# SMART CACHE: Check if build directory already has langchain installed
if [ -d "$BUILD_DIR/langchain" ]; then
    echo "Cache Hit! Skipping pip installation..."
else
    echo "Cache Miss! Cleaning up build directory and installing dependencies..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # We use manylinux2014_aarch64 because we will deploy Lambda as arm64
    pip3 install \
        --platform manylinux2014_aarch64 \
        --target="$BUILD_DIR" \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        --upgrade \
        -r "$DIR/requirements.txt"

    echo "Cleaning up non-deterministic python cache files..."
    cd "$BUILD_DIR"
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.pyc" -delete

    # Normalize timestamps in the pristine dependency directory
    find . -exec touch -t 202001010000.00 {} +
fi

echo "Creating deterministic zip file from pristine dependencies..."
cd "$BUILD_DIR"
find . -type f | LC_ALL=C sort | zip -X -9q "$ZIP_FILE" -@

echo "Injecting source code..."
cd "$DIR"
# Touch the source code so its timestamp is also deterministic
touch -t 202001010000.00 "$DIR/main.py"
zip -X -g "$ZIP_FILE" main.py > /dev/null

# The vector store is shared by both Lambdas, so it lives in lambdas/shared/
# rather than being copied into each. It is injected at the ZIP ROOT, which is
# what makes `import s3_vector_store` resolve at runtime. Only the module goes
# in — the integration test beside it stays out of the artifact.
cd "$DIR/../shared"
touch -t 202001010000.00 s3_vector_store.py
zip -X -g "$ZIP_FILE" s3_vector_store.py > /dev/null

echo "Build complete: $ZIP_FILE"
