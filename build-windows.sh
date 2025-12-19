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

# Clear previous debug log
rm -f .cursor/debug.log

# Build Docker image if needed
# Platform is specified in docker-compose.yml to avoid ARM64 host issues with MXE
echo -e "${BLUE}Building Docker image (this may take a while on first run)...${NC}"
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# Build image - if it fails, we'll try to extract logs from intermediate layers
if ! docker compose --progress=plain build 2>&1 | tee /tmp/docker-build.log; then
    echo -e "${YELLOW}⚠️  Build failed. Attempting to extract debug logs...${NC}"
    # Try to find the last built image
    LAST_IMAGE=$(docker images --format "{{.ID}}" qt-test-app-builder 2>/dev/null | head -1)
    if [ -n "$LAST_IMAGE" ]; then
        echo "Trying to extract logs from image $LAST_IMAGE..."
        docker run --rm "$LAST_IMAGE" cat /workspace/debug.log 2>/dev/null > .cursor/debug.log || \
        docker run --rm "$LAST_IMAGE" cat /workspace/debug.log.final 2>/dev/null > .cursor/debug.log || \
        echo "Debug log not found in image"
    fi
    # Also try to extract from the last intermediate container
    LAST_CONTAINER=$(docker ps -a --format "{{.ID}}" --filter "ancestor=qt-test-app-builder" | head -1)
    if [ -n "$LAST_CONTAINER" ]; then
        echo "Trying to extract logs from container $LAST_CONTAINER..."
        docker cp "$LAST_CONTAINER:/workspace/debug.log" .cursor/debug.log 2>/dev/null || \
        docker cp "$LAST_CONTAINER:/workspace/debug.log.final" .cursor/debug.log 2>/dev/null || \
        echo "Debug log not found in container"
    fi
    # Try to extract brotli log from failed container
    echo "Attempting to extract brotli build log..."
    docker run --rm "$LAST_IMAGE" cat /opt/mxe/log/brotli_x86_64-w64-mingw32.static 2>/dev/null > .cursor/brotli-build.log || \
    docker run --rm "$LAST_IMAGE" cat /tmp/brotli-build.log 2>/dev/null > .cursor/brotli-build.log || \
    echo "Brotli log not found"
    echo -e "${YELLOW}Debug logs saved to .cursor/debug.log${NC}"
    echo -e "${YELLOW}Brotli log saved to .cursor/brotli-build.log${NC}"
    exit 1
fi

# Extract debug logs from successfully built image
echo -e "${BLUE}Extracting debug logs from image...${NC}"
IMAGE_ID=$(docker compose images -q builder 2>/dev/null | head -1)
if [ -n "$IMAGE_ID" ]; then
    docker run --rm "$IMAGE_ID" cat /workspace/debug.log 2>/dev/null > .cursor/debug.log || \
    docker run --rm "$IMAGE_ID" cat /workspace/debug.log.final 2>/dev/null > .cursor/debug.log || \
    echo "Debug log not found in image"
fi

# Create build directory
mkdir -p build-windows

# Determine windeployqt flags based on build type
if [ "$BUILD_TYPE" = "Debug" ]; then
    DEPLOY_FLAGS="--compiler-runtime --debug"
else
    DEPLOY_FLAGS="--compiler-runtime --release"
fi

# Run build in Docker container
# Use linux/amd64 platform for consistency (platform is set in docker-compose.yml)
echo -e "${BLUE}Running build in Docker container...${NC}"
docker compose run --rm builder /bin/bash -c "
    set -e
    echo '=== Checking Qt6 installation ==='
    echo 'Checking if qt6-qtbase was built successfully:'
    ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase 2>/dev/null && echo 'qt6-qtbase: INSTALLED' || echo 'qt6-qtbase: NOT INSTALLED'
    echo 'Checking if qt6-qttools was built successfully:'
    ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qttools 2>/dev/null && echo 'qt6-qttools: INSTALLED' || echo 'qt6-qttools: NOT INSTALLED'
    echo 'Listing installed packages for Windows target:'
    ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/installed/ | grep qt6 | head -10 || echo 'No qt6 packages found'
    echo 'Checking Qt6 build logs for Windows target:'
    ls -la /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static 2>/dev/null && echo 'Windows Qt6 log exists' || echo 'Windows Qt6 log NOT found'
    echo 'Last 20 lines of Windows Qt6 build log:'
    tail -20 /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static 2>/dev/null || echo 'Log file not found'
    echo 'Listing /opt/mxe/usr/x86_64-w64-mingw32.static/ directory:'
    ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/ 2>/dev/null | head -20 || echo 'Directory not found'
    echo 'Looking for Qt6Config.cmake anywhere in MXE:'
    find /opt/mxe/usr -name 'Qt6Config.cmake' 2>/dev/null | head -5 || echo 'Qt6Config.cmake not found'
    echo 'Looking for qt6 directories:'
    find /opt/mxe/usr -type d -name '*qt6*' 2>/dev/null | head -10 || echo 'No qt6 directories found'
    echo 'Checking Qt6 directory (expected location):'
    ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/ 2>/dev/null || echo 'Qt6 directory not found at expected location'
    echo 'Configuring CMake...'
    # Use MXE wrapper script for cmake (recommended by MXE)
    x86_64-w64-mingw32.static-cmake -B build-windows \
        -G 'Unix Makefiles' \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_PREFIX_PATH=/opt/mxe/usr/x86_64-w64-mingw32.static/qt6 \
        -DQt6_DIR=/opt/mxe/usr/x86_64-w64-mingw32.static/qt6/lib/cmake/Qt6
    
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
    # Find windeployqt.exe - it might be in different locations
    # Note: For static builds, windeployqt may not be needed
    WINDEPLOYQT=''
    if [ -f /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt.exe ] && [ -x /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt.exe ]; then
        WINDEPLOYQT=/opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt.exe
    elif [ -f /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt ] && [ -x /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt ]; then
        WINDEPLOYQT=/opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt
    elif [ -f /opt/mxe/usr/bin/x86_64-w64-mingw32.static-windeployqt ] && [ -x /opt/mxe/usr/bin/x86_64-w64-mingw32.static-windeployqt ]; then
        WINDEPLOYQT=/opt/mxe/usr/bin/x86_64-w64-mingw32.static-windeployqt
    else
        echo 'Searching for windeployqt executable...'
        # Search for executable files only (not .prf or other config files)
        WINDEPLOYQT=\$(find /opt/mxe/usr -name 'windeployqt*' -type f -executable 2>/dev/null | grep -v '\.prf$' | head -1)
    fi
    
    if [ -z \"\$WINDEPLOYQT\" ] || [ ! -f \"\$WINDEPLOYQT\" ]; then
        echo 'Warning: windeployqt not found, skipping deployment'
        echo 'Listing Qt6 bin directory:'
        ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/ 2>/dev/null || echo 'Qt6 bin directory not found'
        echo 'Searching for windeployqt in MXE:'
        find /opt/mxe/usr -name '*windeployqt*' -type f 2>/dev/null || echo 'windeployqt not found'
        echo 'Executable is available at: build-windows/qt-test-app.exe'
        echo 'You may need to manually copy DLLs or use windeployqt on Windows'
    else
        echo \"Using windeployqt: \$WINDEPLOYQT\"
        \"\$WINDEPLOYQT\" \
            ${DEPLOY_FLAGS} \
            --dir build-windows/deploy \
            build-windows/qt-test-app.exe
        
        if [ \$? -ne 0 ]; then
            echo 'Warning: windeployqt failed, but executable should still be available'
        else
            echo 'Qt libraries deployed successfully'
        fi
    fi
    
    echo 'Build completed!'
"

# Check if executable exists (wait a moment for file system sync)
sleep 1

if [ -f "build-windows/qt-test-app.exe" ]; then
    echo -e "${GREEN}✅ Build completed successfully!${NC}"
    echo -e "${GREEN}Windows executable: build-windows/qt-test-app.exe${NC}"
    ls -lh build-windows/qt-test-app.exe
    if [ -d "build-windows/deploy" ]; then
        echo -e "${GREEN}Windows executable and DLLs are in: build-windows/deploy/${NC}"
        ls -lh build-windows/deploy/ | head -10
    else
        echo -e "${BLUE}Note: For static builds, DLLs may not be needed${NC}"
        echo -e "${BLUE}The executable should be self-contained${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Build completed, but executable not found in expected location${NC}"
    echo "Checking build-windows directory contents:"
    ls -la build-windows/ 2>/dev/null || echo "build-windows directory not found"
    echo ""
    echo "Note: If using Docker volumes, the file might be in a Docker volume."
    echo "Try: docker compose run --rm builder ls -la /workspace/build-windows/"
    exit 1
fi

