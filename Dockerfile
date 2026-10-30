# Relay de Gran Santiago: imagen mínima con Godot headless.
# docker build -t gran-santiago-relay server/   &&   docker run -p 8910:8910 gran-santiago-relay
FROM debian:bookworm-slim
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip ca-certificates \
    && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && apt-get purge -y wget unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
WORKDIR /relay
COPY relay_server.gd /relay/server/relay_server.gd
RUN printf 'config_version=5\n\n[application]\n\nconfig/name="Gran Santiago Relay"\n' > /relay/project.godot
ENV PORT=8910
EXPOSE 8910
CMD ["godot", "--headless", "--path", "/relay", "-s", "res://server/relay_server.gd"]
