# syntax=docker/dockerfile:1
#
# Self-hosted GitHub Actions runner image with extra build tooling.
# Base: the official runner image as published by GitHub (user "runner").
# Adds: Eclipse Temurin JDK, python3/zip/unzip, and on-demand Android SDK setup.
#
# The Android SDK is NOT redistributed in the published image (its license does not allow
# redistribution). /usr/local/bin/ensure-android-sdk installs it on first use; the runner calls it
# before every job (ACTIONS_RUNNER_HOOK_JOB_STARTED), and it returns at once when the SDK is there.
# For a private image, build with --build-arg BAKE_ANDROID_SDK=true to install it at build time.

# Required: the upstream runner version to build on, e.g. --build-arg RUNNER_VERSION=2.x.y.
# CI resolves it (.github/scripts/resolve-versions.sh). The default is a valid but non-existent
# tag, so a build without the argument fails with "...:required-build-arg: not found".
ARG RUNNER_VERSION=required-build-arg
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG JDK_MAJOR=21
ARG BAKE_ANDROID_SDK=false

ENV JAVA_HOME=/usr/lib/jvm/temurin-${JDK_MAJOR}-jdk-amd64 \
    ANDROID_HOME=/home/runner/android-sdk \
    ANDROID_SDK_ROOT=/home/runner/android-sdk \
    ANDROID_SDK_PACKAGES="platform-tools platforms/android-37.0 build-tools/36.0.0" \
    ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/ensure-android-sdk
ENV PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Temurin JDK from the Adoptium APT repository (packages signed by Adoptium).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg python3 unzip zip \
 && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
      > /etc/apt/sources.list.d/adoptium.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends "temurin-${JDK_MAJOR}-jdk" \
 && rm -rf /var/lib/apt/lists/* \
 && java -version

COPY --chmod=755 rootfs/usr/local/bin/ /usr/local/bin/

USER runner

# Owned by "runner", so a fresh Docker volume mounted here inherits the ownership.
RUN mkdir -p "${ANDROID_HOME}" \
 && if [ "${BAKE_ANDROID_SDK}" = "true" ]; then ensure-android-sdk; fi
