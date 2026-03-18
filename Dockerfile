FROM ubuntu:24.04 AS sdk-builder

# Build the GameLift Server SDK shared library with
# GAMELIFT_USE_STD=1 to match the GDExtension's ABI.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v5.2.0 --depth 1 \
    https://github.com/amazon-gamelift/amazon-gamelift-servers-cpp-server-sdk.git \
    /sdk

WORKDIR /sdk

# Patch CMake version requirements for compatibility.
RUN find . -name 'CMakeLists.txt' -print0 \
    | xargs -0 sed -i -E \
    's/cmake_minimum_required\(VERSION ([0-9]+(\.[0-9]+)?)\)/cmake_minimum_required(VERSION 3.5...3.30)/gI'

RUN mkdir -p cmake-build && cd cmake-build && \
    cmake -G "Unix Makefiles" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGAMELIFT_USE_STD=1 \
        -DBUILD_SHARED_LIBS=ON \
        -DRUN_UNIT_TESTS=OFF \
        -DCMAKE_INSTALL_PREFIX=/sdk/cmake-build/prefix \
        .. && \
    cmake --build . -j$(nproc)

# -----------------------------------------------

FROM ubuntu:24.04

# Prevent interactive prompts during package installation.
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies for Godot headless, nginx
# (TLS termination for WSS), jq (JSON parsing), and
# unzip (AWS CLI installer).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    libfontconfig1 \
    libgl1 \
    libglib2.0-0 \
    libx11-6 \
    libxcursor1 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    libnginx-mod-stream \
    nginx \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (used at startup to fetch the TLS
# certificate from Secrets Manager).
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o "/tmp/awscli.zip" && \
    unzip -q /tmp/awscli.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscli.zip /tmp/aws

WORKDIR /game

# Copy the exported Godot server binary and resource pack.
COPY build/linux/hopnbop_server.x86_64 /game/
COPY build/linux/hopnbop_server.pck /game/

# Copy GameLift GDExtension manifest and extension binary.
COPY addons/gamelift/gamelift.gdextension \
     /game/addons/gamelift/
COPY addons/gamelift/bin/libgamelift.linux.template_release.x86_64.so \
     /game/addons/gamelift/bin/

# Copy the SDK shared library built in the builder stage
# (compiled with GAMELIFT_USE_STD=1 to match GDExtension ABI).
COPY --from=sdk-builder \
     /sdk/cmake-build/prefix/lib/libaws-cpp-sdk-gamelift-server.so \
     /game/addons/gamelift/bin/

# Copy OpenSSL libraries from the builder stage
# (same Ubuntu version ensures ABI compatibility).
COPY --from=sdk-builder /usr/lib/x86_64-linux-gnu/libssl.so.3 \
     /game/addons/gamelift/bin/
COPY --from=sdk-builder /usr/lib/x86_64-linux-gnu/libcrypto.so.3 \
     /game/addons/gamelift/bin/

# Set library path so shared libraries are found at runtime.
ENV LD_LIBRARY_PATH=/game/addons/gamelift/bin

# Create log directory for GameLift log upload.
RUN mkdir -p /game/logs

# Make the server binary executable.
RUN chmod +x /game/hopnbop_server.x86_64

# Copy nginx config for WSS TLS termination and the
# entrypoint script that fetches the cert at startup.
COPY gamelift-deploy/nginx.conf /etc/nginx/nginx.conf
COPY gamelift-deploy/entrypoint.sh /game/entrypoint.sh
RUN chmod +x /game/entrypoint.sh

# Expose ENet UDP port and nginx WSS TCP port.
EXPOSE 4433/udp
EXPOSE 4434/tcp

# Health check: verify the server process is running.
# GameLift also calls the SDK health check independently.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f hopnbop_server || exit 1

# Entrypoint fetches the TLS cert from Secrets Manager,
# starts nginx, then runs the Godot server in the
# foreground.
ENTRYPOINT ["/game/entrypoint.sh"]
