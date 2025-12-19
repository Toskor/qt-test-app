# Dockerfile for cross-compiling Qt application for Windows on macOS
# Uses MXE (M cross environment) for cross-compilation

FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies required for MXE and building
# Split into multiple steps for better error handling
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    autopoint \
    bash \
    bison \
    bzip2 \
    cmake \
    flex \
    g++ \
    gettext \
    git \
    gperf \
    intltool \
    libgdk-pixbuf2.0-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libltdl-dev \
    libssl-dev \
    libtool-bin \
    libxml-parser-perl \
    lzip \
    make \
    ninja-build \
    openssl \
    p7zip-full \
    patch \
    perl \
    pkg-config \
    python3 \
    python3-mako \
    python-is-python3 \
    ruby \
    sed \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# NOTE: We do NOT install system Qt6 - MXE will build Qt6 for host as dependency
# This ensures MXE builds Qt6 for both host and Windows target correctly
# Installing system Qt6 can confuse MXE and prevent Windows target build

# #region agent log - Hypothesis A: Check system state (no Qt6 should be installed)
RUN mkdir -p /workspace && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:54\",\"message\":\"Checking system Qt6 installation\",\"data\":{\"hypothesisId\":\"A\",\"qmake6_path\":\"$(which qmake6 2>/dev/null || echo 'NOT_FOUND')\",\"qmake_path\":\"$(which qmake 2>/dev/null || echo 'NOT_FOUND')\",\"qt6_cmake_path\":\"$(find /usr/lib -name 'Qt6Config.cmake' 2>/dev/null | head -1 || echo 'NOT_FOUND')\",\"pkg_config_qt6\":\"$(pkg-config --exists Qt6Core && echo 'FOUND' || echo 'NOT_FOUND')\"}}" >> /workspace/debug.log
# #endregion

# Clone MXE
# This step is cached - if MXE directory exists, git clone will be skipped
# Note: Following Habr article recommendation, we should use a specific version for reproducibility
# However, we need latest version for Qt6 support, so we'll clone master but log the commit hash
WORKDIR /opt
RUN git clone https://github.com/mxe/mxe.git && \
    cd mxe && \
    MXE_COMMIT=$(git rev-parse HEAD) && \
    MXE_VERSION=$(git describe --tags --always 2>/dev/null || echo "no-tags") && \
    mkdir -p /workspace && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:77\",\"message\":\"MXE version info\",\"data\":{\"hypothesisId\":\"B\",\"mxe_commit\":\"$MXE_COMMIT\",\"mxe_version\":\"$MXE_VERSION\"}}" >> /workspace/debug.log

# Configure MXE to build only for Windows target
# We use system Qt6 (installed from Ubuntu repos) instead of building host Qt6 via MXE
WORKDIR /opt/mxe
RUN echo "MXE_TARGETS := x86_64-w64-mingw32.static" > settings.mk

# #region agent log - Hypothesis B: Check MXE configuration and Qt6 support
RUN echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:82\",\"message\":\"MXE configuration check\",\"data\":{\"hypothesisId\":\"B\",\"settings_mk_content\":\"$(cat settings.mk 2>/dev/null || echo 'NOT_FOUND')\",\"mxe_targets_env\":\"${MXE_TARGETS:-NOT_SET}\"}}" >> /workspace/debug.log && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:82\",\"message\":\"MXE Qt6 support check\",\"data\":{\"hypothesisId\":\"B\",\"qt6_qtbase_mk\":\"$(find src -name 'qt6-qtbase.mk' 2>/dev/null | head -1 || echo 'NOT_FOUND')\",\"qt6_packages\":\"$(find src -name 'qt6-*.mk' 2>/dev/null | wc -l || echo '0')\",\"qt5_qtbase_mk\":\"$(find src -name 'qtbase.mk' 2>/dev/null | head -1 || echo 'NOT_FOUND')\",\"qt6_qtbase_deps\":\"$(grep -r 'qt6-qtbase.*x86_64-pc-linux-gnu' src 2>/dev/null | head -5 || echo 'NO_DEPS_FOUND')\"}}" >> /workspace/debug.log
# #endregion

# Set environment variables for MXE build
ENV PATH="/opt/mxe/usr/bin:${PATH}"
ENV MXE_TARGETS="x86_64-w64-mingw32.static"

# Build base toolchain (gcc, binutils) for Windows target
# Using -j1 JOBS=1 to avoid "Bad file descriptor" errors in Docker
# This step takes 30-60 minutes but is cached in Docker layer
WORKDIR /opt/mxe
RUN make gcc binutils -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static

# Build cmake for Windows target (required for brotli and Qt6)
# Brotli uses CMake, so we need cmake for Windows target
WORKDIR /opt/mxe
RUN make cmake -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static || \
    (echo "CMake build failed, but continuing..." && true)

# Build essential dependencies for Qt6
# These packages are typically required before building Qt6
WORKDIR /opt/mxe
RUN echo "=== Building Qt6 dependencies ===" && \
    make pkgconf -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static || echo "pkgconf build failed, continuing..." && \
    make zlib -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static || echo "zlib build failed, continuing..." && \
    make libpng -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static || echo "libpng build failed, continuing..." && \
    make jpeg -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static || echo "jpeg build failed, continuing..." && \
    echo "=== Dependencies build completed ==="

# Build Qt6 base libraries for Windows target
# IMPORTANT: MXE requires Qt6 for host to be built first as a dependency
# Even though we have system Qt6 installed, MXE needs its own Qt6 for host
# This step takes 1-2 hours but is cached in Docker layer
WORKDIR /opt/mxe

# #region agent log - Hypothesis D: Check environment before build
RUN echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:112\",\"message\":\"Pre-build environment check\",\"data\":{\"hypothesisId\":\"D\",\"PATH\":\"${PATH}\",\"MXE_TARGETS\":\"${MXE_TARGETS}\",\"CMAKE_PREFIX_PATH\":\"${CMAKE_PREFIX_PATH:-NOT_SET}\",\"PKG_CONFIG_PATH\":\"${PKG_CONFIG_PATH:-NOT_SET}\",\"qmake6_available\":\"$(which qmake6 >/dev/null 2>&1 && echo 'YES' || echo 'NO')\"}}" >> /workspace/debug.log
# #endregion

# #region agent log - Hypothesis E: Check MXE make dependencies before build
RUN echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:115\",\"message\":\"MXE make dependencies check\",\"data\":{\"hypothesisId\":\"E\",\"make_qt6_qtbase_deps\":\"$(make -n qt6-qtbase MXE_TARGETS=x86_64-w64-mingw32.static 2>&1 | grep -E 'qt6-qtbase.*x86_64-w64-mingw32.static|build.*qt6' | head -10 | tr '\n' ';' || echo 'NO_WINDOWS_TARGET_IN_DRY_RUN')\"}}" >> /workspace/debug.log
# #endregion

# Build Qt6 base libraries for Windows target
# MXE will automatically build Qt6 for host (x86_64-pc-linux-gnu) as dependency first
# Then it will build Qt6 for Windows target (x86_64-w64-mingw32.static)
# Set CMake variables to disable OpenGL for host Qt6 build (required dependency)
# This prevents OpenGL errors in Docker container without GPU
# MXE uses format: CMAKE_OPTS_qt6-qtbase_x86_64-pc-linux-gnu for host builds

# #region agent log - Hypothesis H: Check state before Qt6 build
RUN mkdir -p /workspace && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:118\",\"message\":\"Pre-build state check\",\"data\":{\"hypothesisId\":\"H\",\"host_qt6_installed\":\"$(test -f /opt/mxe/usr/x86_64-pc-linux-gnu/installed/qt6-qtbase && echo 'YES' || echo 'NO')\",\"windows_qt6_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase && echo 'YES' || echo 'NO')\",\"mxe_log_dir_exists\":\"$(test -d /opt/mxe/log && echo 'YES' || echo 'NO')\",\"existing_logs\":\"$(ls /opt/mxe/log/qt6* 2>/dev/null | wc -l || echo '0')\"}}" >> /workspace/debug.log
# #endregion

# Build Qt6 for host first (required dependency)
# MXE will build Qt6 for host (x86_64-pc-linux-gnu) as dependency, then for Windows target
RUN set +e && \
    echo "=== Starting Qt6 build for Windows target ===" && \
    echo "This will build Qt6 for host first, then for Windows target..." && \
    make qt6-qtbase -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static \
    CMAKE_OPTS_qt6-qtbase_x86_64-pc-linux-gnu="-DQT_FEATURE_opengl=OFF -DQT_FEATURE_opengles2=OFF -DQT_FEATURE_opengles3=OFF -DQT_FEATURE_opengl_desktop=OFF" \
    CMAKE_OPTS_qt6-qtbase_x86_64-w64-mingw32.static="-DQT_FEATURE_opengl=OFF -DQT_FEATURE_opengles2=OFF -DQT_FEATURE_opengles3=OFF -DQT_FEATURE_opengl_desktop=OFF" \
    2>&1 | tee /tmp/mxe-build.log; \
    BUILD_EXIT_CODE=$? && \
    echo "Build exit code: $BUILD_EXIT_CODE" >> /tmp/mxe-build.log && \
    mkdir -p /workspace && \
    echo "=== Checking build results ===" && \
    echo "Host Qt6 installed: $(test -f /opt/mxe/usr/x86_64-pc-linux-gnu/installed/qt6-qtbase && echo 'YES' || echo 'NO')" && \
    echo "Windows Qt6 installed: $(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase && echo 'YES' || echo 'NO')" && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:127\",\"message\":\"After Qt6 build\",\"data\":{\"build_exit_code\":\"$BUILD_EXIT_CODE\",\"host_qt6_installed\":\"$(test -f /opt/mxe/usr/x86_64-pc-linux-gnu/installed/qt6-qtbase && echo 'YES' || echo 'NO')\",\"windows_qt6_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase && echo 'YES' || echo 'NO')\"}}" >> /workspace/debug.log && \
    if [ $BUILD_EXIT_CODE -ne 0 ]; then \
        echo "=== Build failed with exit code $BUILD_EXIT_CODE ===" && \
        echo "=== Last 100 lines of build log ===" && \
        tail -100 /tmp/mxe-build.log || echo "Build log not found" && \
        echo "=== Checking for Qt6 Windows build log ===" && \
        if [ -f /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static ]; then \
            echo "=== Last 100 lines of Windows Qt6 log ===" && \
            tail -100 /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static; \
        else \
            echo "Windows Qt6 log not found"; \
        fi && \
        echo "=== Checking for Qt6 Host build log ===" && \
        if [ -f /opt/mxe/log/qt6-qtbase_x86_64-pc-linux-gnu ]; then \
            echo "=== Last 100 lines of Host Qt6 log ===" && \
            tail -100 /opt/mxe/log/qt6-qtbase_x86_64-pc-linux-gnu; \
        else \
            echo "Host Qt6 log not found"; \
        fi && \
        echo "=== Listing all log files ===" && \
        ls -la /opt/mxe/log/ 2>/dev/null | head -30 || echo "Log directory not found"; \
    fi && \
    set -e

# Verify that Qt6 for Windows was successfully installed
# If not installed, show detailed diagnostics but don't fail yet
RUN echo "=== Verifying Qt6 installation ===" && \
    if [ ! -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase ]; then \
        echo "ERROR: qt6-qtbase for Windows was not installed!" && \
        echo "=== Detailed diagnostics ===" && \
        echo "=== Last 100 lines of build log ===" && \
        tail -100 /tmp/mxe-build.log 2>/dev/null || echo "Build log not found" && \
        echo "" && \
        echo "=== Windows Qt6 log ===" && \
        if [ -f /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static ]; then \
            tail -200 /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static; \
        else \
            echo "Windows Qt6 log not found at /opt/mxe/log/qt6-qtbase_x86_64-w64-mingw32.static"; \
        fi && \
        echo "" && \
        echo "=== Host Qt6 log ===" && \
        if [ -f /opt/mxe/log/qt6-qtbase_x86_64-pc-linux-gnu ]; then \
            tail -200 /opt/mxe/log/qt6-qtbase_x86_64-pc-linux-gnu; \
        else \
            echo "Host Qt6 log not found"; \
        fi && \
        echo "" && \
        echo "=== All log files in /opt/mxe/log ===" && \
        ls -la /opt/mxe/log/ 2>/dev/null | head -50 || echo "Log directory not found" && \
        echo "" && \
        echo "=== Searching for qt6 logs ===" && \
        find /opt/mxe/log -name '*qt6*' -type f 2>/dev/null | head -20 || echo "No qt6 logs found" && \
        echo "" && \
        echo "=== Checking Windows target directory ===" && \
        ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/ 2>/dev/null | head -30 || echo "Windows target directory not found" && \
        echo "" && \
        echo "=== Checking installed packages ===" && \
        ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/installed/ 2>/dev/null | head -30 || echo "Installed directory not found" && \
        echo "" && \
        echo "=== Checking if host Qt6 was built ===" && \
        ls -la /opt/mxe/usr/x86_64-pc-linux-gnu/installed/qt6-qtbase 2>/dev/null && echo "Host Qt6 is installed" || echo "Host Qt6 is NOT installed" && \
        echo "" && \
        echo "=== Checking MXE version and configuration ===" && \
        cd /opt/mxe && git log -1 --oneline 2>/dev/null || echo "Cannot get MXE version" && \
        cat /opt/mxe/settings.mk 2>/dev/null || echo "Cannot read settings.mk" && \
        exit 1; \
    else \
        echo "SUCCESS: qt6-qtbase for Windows is installed"; \
        echo "Checking Qt6 installation directory..." && \
        ls -la /opt/mxe/usr/x86_64-w64-mingw32.static/qt6/ 2>/dev/null | head -20 || echo "Qt6 directory not found at expected location"; \
    fi

# Build Qt6 tools (including windeployqt) for Windows target only
# This step is cached separately - if qt6-qtbase is already built, only tools will be rebuilt
# Note: brotli may fail with parallel build, so we build it separately first if needed
WORKDIR /opt/mxe

# #region agent log - Hypothesis F: Check brotli build status before qt6-qttools
RUN echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:132\",\"message\":\"Checking brotli build status\",\"data\":{\"hypothesisId\":\"F\",\"brotli_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/brotli && echo 'YES' || echo 'NO')\",\"brotli_log_exists\":\"$(test -f /opt/mxe/log/brotli_x86_64-w64-mingw32.static && echo 'YES' || echo 'NO')\"}}" >> /workspace/debug.log
# #endregion

# Try to build brotli separately first (may fail with parallel build)
# If brotli is already built, this will be skipped
RUN set +e && \
    make brotli -j1 JOBS=1 MXE_TARGETS=x86_64-w64-mingw32.static 2>&1 | tee /tmp/brotli-build.log; \
    BROTLI_EXIT_CODE=$? && \
    mkdir -p /workspace && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:177\",\"message\":\"Brotli build result\",\"data\":{\"hypothesisId\":\"J\",\"brotli_exit_code\":\"$BROTLI_EXIT_CODE\",\"brotli_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/brotli && echo 'YES' || echo 'NO')\",\"brotli_log_exists\":\"$(test -f /opt/mxe/log/brotli_x86_64-w64-mingw32.static && echo 'YES' || echo 'NO')\",\"brotli_log_size\":\"$(test -f /opt/mxe/log/brotli_x86_64-w64-mingw32.static && wc -l < /opt/mxe/log/brotli_x86_64-w64-mingw32.static || echo '0')\"}}" >> /workspace/debug.log && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:177\",\"message\":\"Brotli build log tail\",\"data\":{\"hypothesisId\":\"J\",\"last_100_lines\":\"$(tail -100 /opt/mxe/log/brotli_x86_64-w64-mingw32.static 2>/dev/null | sed 's/"/\\"/g' | tr '\n' ';' || echo 'LOG_NOT_FOUND')\"}}" >> /workspace/debug.log && \
    echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:177\",\"message\":\"Brotli build output tail\",\"data\":{\"hypothesisId\":\"J\",\"last_50_lines\":\"$(tail -50 /tmp/brotli-build.log 2>/dev/null | sed 's/"/\\"/g' | tr '\n' ';' || echo 'OUTPUT_NOT_FOUND')\"}}" >> /workspace/debug.log && \
    if [ $BROTLI_EXIT_CODE -ne 0 ]; then \
        echo "Brotli build failed with exit code $BROTLI_EXIT_CODE" && \
        echo "=== Brotli build log (last 100 lines) ===" && \
        tail -100 /opt/mxe/log/brotli_x86_64-w64-mingw32.static 2>/dev/null || echo "Brotli log not found" && \
        echo "=== Brotli build output (last 50 lines) ===" && \
        tail -50 /tmp/brotli-build.log 2>/dev/null || echo "Brotli output not found" && \
        echo "=== Checking brotli source directory ===" && \
        ls -la /opt/mxe/tmp-brotli-x86_64-w64-mingw32.static/ 2>/dev/null | head -20 || echo "Brotli source directory not found" && \
        exit 1; \
    fi && \
    set -e

# Build Qt6 tools - brotli should be built by now or will be built as dependency
RUN make qt6-qttools -j2 JOBS=2 MXE_TARGETS=x86_64-w64-mingw32.static 2>&1 | tee /tmp/qt6-qttools-build.log

# Verify that Qt6 tools for Windows were successfully installed
RUN if [ ! -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qttools ]; then \
    echo "ERROR: qt6-qttools for Windows was not installed!" && \
    echo "=== Last 50 lines of qt6-qttools build log ===" && \
    tail -50 /tmp/qt6-qttools-build.log 2>/dev/null || echo "Build log not found" && \
    echo "=== Brotli log ===" && \
    tail -100 /opt/mxe/log/brotli_x86_64-w64-mingw32.static 2>/dev/null || echo "Brotli log not found" && \
    exit 1; \
    else \
    echo "SUCCESS: qt6-qttools for Windows is installed"; \
    fi

# Set additional environment variables for CMake
# Qt6 in MXE is installed in qt6 directory, but Qt6Config.cmake is in lib/cmake/Qt6
# CMAKE_PREFIX_PATH should point to the qt6 directory root
ENV CMAKE_PREFIX_PATH="/opt/mxe/usr/x86_64-w64-mingw32.static/qt6"
ENV PKG_CONFIG_PATH="/opt/mxe/usr/x86_64-w64-mingw32.static/lib/pkgconfig"
ENV Qt6_DIR="/opt/mxe/usr/x86_64-w64-mingw32.static/qt6/lib/cmake/Qt6"

# #region agent log - Hypothesis G: Verify Qt6 installation paths after build
RUN echo "{\"timestamp\":$(date +%s000),\"location\":\"Dockerfile:161\",\"message\":\"Verifying Qt6 installation after build\",\"data\":{\"hypothesisId\":\"G\",\"qt6_qtbase_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qtbase && echo 'YES' || echo 'NO')\",\"qt6_qttools_installed\":\"$(test -f /opt/mxe/usr/x86_64-w64-mingw32.static/installed/qt6-qttools && echo 'YES' || echo 'NO')\",\"qt6_dir_exists\":\"$(test -d /opt/mxe/usr/x86_64-w64-mingw32.static/qt6 && echo 'YES' || echo 'NO')\",\"qt6config_cmake\":\"$(find /opt/mxe/usr/x86_64-w64-mingw32.static/qt6 -name 'Qt6Config.cmake' 2>/dev/null | head -1 || echo 'NOT_FOUND')\",\"qt6_dirs\":\"$(find /opt/mxe/usr -type d -name '*qt6*' 2>/dev/null | head -5 | tr '\n' ' ' || echo 'NONE')\",\"mxe_usr_contents\":\"$(ls /opt/mxe/usr/x86_64-w64-mingw32.static/ 2>/dev/null | head -10 | tr '\n' ' ' || echo 'NOT_FOUND')\"}}" >> /workspace/debug.log
# #endregion

# Set working directory
WORKDIR /workspace

# Copy debug log to workspace for easy access
RUN cp /workspace/debug.log /workspace/debug.log.final 2>/dev/null || true

# Default command - can be overridden
CMD ["/bin/bash"]

