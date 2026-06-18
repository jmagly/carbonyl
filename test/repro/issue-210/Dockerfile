# GPU-less runtime image for reproducing upstream #181 / issue #210
# ("blank after ~1s in a docker container").
#
# Deliberately a clean debian:bullseye-slim with NO GPU drivers, exercising the
# software-rendering (SwiftShader) fallback path that the bug report describes.
#
# Library set: the project's top-level Dockerfile installs only
# libasound2/libexpat1/libfontconfig1/libnss3, which is NOT enough to load the
# prebuilt binary (see issue #224). The full load-time set is below.
FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libasound2 libexpat1 libfontconfig1 libnss3 \
      libx11-6 libdbus-1-3 libgbm1 \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# The carbonyl binary + its adjacent libcarbonyl.so and bundled SwiftShader
# (libvk_swiftshader.so, libvulkan.so.1, vk_swiftshader_icd.json) are bind-mounted
# at /carbonyl by run.sh — they are not copied into the image.
