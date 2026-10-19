# actions-runner-android

A GitHub Actions self-hosted runner image for Android builds and device tests, based on the
official [`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner)
image.

```
ghcr.io/blafry/actions-runner-android:latest
```

## What's inside

| Component | Details |
|---|---|
| Base | The official runner image (Ubuntu 24.04, user `runner` uid 1001, Docker CLI, runner container hooks) |
| JDK | Eclipse Temurin 21 from the Adoptium APT repository (`JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64`) |
| Tools | `python3`, `zip`, `unzip`, `curl`, `jq`, `git` |
| Android SDK | **Installed on first use** by `ensure-android-sdk` (see below) into `ANDROID_HOME=/home/runner/android-sdk` |

`PATH` includes the JDK, `cmdline-tools/latest/bin` and `platform-tools` (adb).

### Why the Android SDK is installed on first use

The Android SDK License Agreement does not allow redistributing the SDK, so the published image
doesn't contain it. Instead, the runner runs `/usr/local/bin/ensure-android-sdk` before every job
(`ACTIONS_RUNNER_HOOK_JOB_STARTED`):

- On the first job it downloads the command-line tools (SHA-1 verified) and installs
  `ANDROID_SDK_PACKAGES` with the Android CLI. That takes about 20-60 seconds.
- On later jobs it returns immediately, as long as `ANDROID_HOME` is on a **persistent volume**.

Installing the SDK this way accepts the
[Android SDK Terms of Service](https://developer.android.com/studio/terms) on behalf of whoever
runs the runner. To bake the SDK into a **private** image instead, build it yourself with
`--build-arg BAKE_ANDROID_SDK=true`.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `ANDROID_HOME` / `ANDROID_SDK_ROOT` | `/home/runner/android-sdk` | SDK location; mount a volume here |
| `ANDROID_SDK_PACKAGES` | `platform-tools platforms/android-37.0 build-tools/36.0.0` | Packages to keep installed (Android CLI syntax) |
| `ANDROID_SDK_SKIP` | unset | `1` skips the SDK setup (runners that never build Android) |
| `CMDLINE_TOOLS_ZIP`, `CMDLINE_TOOLS_SHA1` | pinned | Command-line tools archive and checksum |

## Usage

### Docker

```bash
docker volume create android-sdk
docker run -d --name runner \
  -v android-sdk:/home/runner/android-sdk \
  -v gradle-cache:/home/runner/.gradle \
  ghcr.io/blafry/actions-runner-android:latest \
  bash -c './config.sh --url https://github.com/<owner>/<repo> --token <registration-token> --unattended --ephemeral && ./run.sh'
```

### actions-runner-controller (Kubernetes)

Runner scale set values:

```yaml
template:
  spec:
    securityContext:
      fsGroup: 1001            # lets the runner write to the mounted volumes
    containers:
      - name: runner
        image: ghcr.io/blafry/actions-runner-android:latest
        command: ["/home/runner/run.sh"]
        resources:
          requests: { cpu: "2", memory: 6Gi }
          limits: { cpu: "4", memory: 8Gi }
        volumeMounts:
          - { name: android-sdk, mountPath: /home/runner/android-sdk }
          - { name: gradle, mountPath: /home/runner/.gradle }
    volumes:
      - name: android-sdk
        persistentVolumeClaim: { claimName: android-sdk }
      - name: gradle
        persistentVolumeClaim: { claimName: gradle-cache }
```

### Device tests

Instrumented tests need a device:

- **adb over Wi-Fi** (simplest in containers): `adb connect <device-ip>:5555` at the start of the
  job, after enabling wireless debugging on the device once.
- **USB**: pass the device into the container (`--device /dev/bus/usb` with Docker, a hostPath
  mount and a node selector on Kubernetes) and accept the debugging prompt on the device. Persist
  `/home/runner/.android` so the adb key survives restarts.

Emulators need `/dev/kvm` and a lot more resources; they are not the focus of this image.

## Sizing

Typical Gradle Android builds with unit tests:

| | vCPU | RAM | Disk |
|---|---|---|---|
| Minimum | 2 | 6 GB | 20 GB |
| Recommended | 4 | 8 GB | 30 GB |
| Large projects | 8 | 16 GB | 50 GB |

On small runners, limit Gradle in `~/.gradle/gradle.properties`, e.g.
`org.gradle.jvmargs=-Xmx2g`, `kotlin.daemon.jvmargs=-Xmx1536m`, `org.gradle.workers.max=2`.

## Tags and updates

| Tag | Meaning |
|---|---|
| `latest` | Newest build |
| `<runner version>` (e.g. `2.338.0`) | Newest build on that upstream runner version |
| `<runner version>-<YYYYMMDD>` | A specific build |

The image is rebuilt:

- weekly, when GitHub publishes a new upstream runner image (checked by digest);
- on every change to the image on `master`;
- on demand (`workflow_dispatch`, with an optional forced rebuild).

Every build is smoke-tested before it is published (runner user, JDK, SDK setup, adb).

## License

The files in this repository are under the [MIT License](LICENSE). The base image and the
software installed into containers keep their own licenses (GitHub Actions runner: MIT; Eclipse
Temurin: GPLv2 with Classpath Exception; Android SDK: Android SDK License Agreement, accepted by
whoever runs `ensure-android-sdk`).
