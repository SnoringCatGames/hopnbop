FROM ubuntu:22.04

# Prevent interactive prompts during package installation.
ENV DEBIAN_FRONTEND=noninteractive

# Install minimal runtime dependencies for Godot headless.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libfontconfig1 \
    libgl1 \
    libglib2.0-0 \
    libx11-6 \
    libxcursor1 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /game

# Copy the exported Godot server binary and resource pack.
COPY build/linux/hopnbop_server.x86_64 /game/
COPY build/linux/hopnbop_server.pck /game/

# Copy GameLift GDExtension runtime dependencies.
# The .gdextension [dependencies] section requires these
# shared libraries at runtime for the GameLift SDK.
COPY addons/gamelift/bin/libaws-cpp-sdk-gamelift-server.so \
     /game/lib/
COPY addons/gamelift/bin/libssl.so.3 /game/lib/
COPY addons/gamelift/bin/libcrypto.so.3 /game/lib/

# Set library path so the GDExtension finds its dependencies.
ENV LD_LIBRARY_PATH=/game/lib

# Create log directory for GameLift log upload.
RUN mkdir -p /game/logs

# Make the server binary executable.
RUN chmod +x /game/hopnbop_server.x86_64

# Expose ENet UDP port.
EXPOSE 4433/udp

# Health check: verify the server process is running.
# GameLift also calls the SDK health check independently.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f hopnbop_server || exit 1

# Run the dedicated server in headless mode.
ENTRYPOINT ["/game/hopnbop_server.x86_64", \
            "--server", "--headless"]
