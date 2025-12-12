#!/bin/bash

# Script for building Qt application for Windows on macOS using Docker

set -e

echo "🚀 Starting Windows build process..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build type (Release or Debug)
BUILD_TYPE=${1:-Release}

echo -e "${BLUE}Build type: ${BUILD_TYPE}${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker is not running. Please start Docker Desktop and try again.${NC}"
    exit 1
fi

# Build Docker image if needed
echo -e "${BLUE}Building Docker image (this may take a while on first run)...${NC}"
docker-compose build --progress=plain

# Create build directory
mkdir -p build-windows

# Determine windeployqt flags based on build type
if [ "$BUILD_TYPE" = "Debug" ]; then
    DEPLOY_FLAGS="--compiler-runtime --debug"
else
    DEPLOY_FLAGS="--compiler-runtime --release"
fi

# Run build in Docker container
echo -e "${BLUE}Running build in Docker container...${NC}"
docker-compose run --rm builder /bin/bash -c "
    set -e
    echo 'Configuring CMake...'
    cmake -B build-windows \
        -G 'Unix Makefiles' \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_TOOLCHAIN_FILE=/usr/lib/mxe/usr/x86_64-w64-mingw32.static/share/cmake/mxe-conf.cmake \
        -DCMAKE_PREFIX_PATH=/usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6
    
    if [ \$? -ne 0 ]; then
        echo 'CMake configuration failed!'
        exit 1
    fi
    
    echo 'Building project...'
    cmake --build build-windows --config ${BUILD_TYPE} -j\$(nproc)
    
    if [ \$? -ne 0 ]; then
        echo 'Build failed!'
        exit 1
    fi
    
    echo 'Checking if executable exists...'
    if [ ! -f build-windows/qt-test-app.exe ]; then
        echo 'Error: Executable not found!'
        exit 1
    fi
    
    echo 'Deploying Qt libraries...'
    /usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt.exe \
        ${DEPLOY_FLAGS} \
        --dir build-windows/deploy \
        build-windows/qt-test-app.exe
    
    if [ \$? -ne 0 ]; then
        echo 'Warning: windeployqt failed, but executable should still be available'
    fi
    
    echo 'Build completed!'
"

if [ -f "build-windows/qt-test-app.exe" ]; then
    echo -e "${GREEN}✅ Build completed successfully!${NC}"
    echo -e "${GREEN}Windows executable: build-windows/qt-test-app.exe${NC}"
    if [ -d "build-windows/deploy" ]; then
        echo -e "${GREEN}Windows executable and DLLs are in: build-windows/deploy/${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Build completed, but executable not found in expected location${NC}"
    exit 1
fi

