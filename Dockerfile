# Dockerfile for cross-compiling Qt application for Windows on macOS
# Uses MXE (M cross environment) for cross-compilation

FROM mxe/mxe-x86-64-w64-mingw32.static:latest

# Install additional dependencies
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables for MXE
ENV PATH="/usr/lib/mxe/usr/bin:${PATH}"
ENV CMAKE_PREFIX_PATH="/usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6"
ENV PKG_CONFIG_PATH="/usr/lib/mxe/usr/x86_64-w64-mingw32.static/lib/pkgconfig"
ENV MXE_TARGETS="x86_64-w64-mingw32.static"

# Install Qt6 components via MXE
# Note: This may take a long time (30+ minutes) on first build
RUN make qt6base qt6tools -j$(nproc) JOBS=$(nproc) MXE_TARGETS=x86_64-w64-mingw32.static

# Set working directory
WORKDIR /workspace

# Default command - can be overridden
CMD ["/bin/bash"]

