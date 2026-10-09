# Image for building Vinix.
#
# The build prerequisites are a moving target of host packages (clang, LLVM,
# LLD, xorriso, qemu, meson, ...), which is why the README lists a different
# apt/pacman/yum/xbps line per distro. This image is the distro-agnostic answer:
# it has all of them plus both V compilers Vinix needs, already pinned.
#
# Single stage on purpose. V bakes the location of its own stdlib into the
# compiler binary at compile time (`@VMODROOT`, resolved in
# vlib/v/parser/parser.v and read back by vlib/v/pref/pref.v:detect_vroot), so a
# compiler built in a builder stage and copied elsewhere is a compiler that
# cannot find vlib. Building in place costs a few minutes and removes the trap.
#
#   docker build -t vinix .
#   docker run --rm -it -v "$PWD":/src -w /src vinix make -C kernel ...
ARG V_UTIL_VERSION=0.5.2
ARG V_UTIL_SHA256=86caf9e70c3342d48ef19eb4f6c47b709f18c90ae86255520d5c29df6b482e23

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="vlang/vinix"
LABEL org.opencontainers.image.description="Build environment for Vinix, the OS written in V"
LABEL org.opencontainers.image.source="https://github.com/vlang/vinix"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"
LABEL org.opencontainers.image.url="https://github.com/vlang/vinix"

# The package list is the union of the two lists CI uses: the README's
# distro-agnostic prerequisites (clang, llvm, lld, make, findutils, curl, git,
# file, xz, rsync, xorriso, qemu, python3) and the extra tools
# .github/workflows/nightly.yml installs for the full ISO build.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # C toolchain: the kernel is built with clang, and get-v.sh defaults to it
    build-essential clang lld llvm \
    # build system
    make diffutils findutils pkg-config meson ninja-build bison flex \
    # downloads and source control
    curl ca-certificates git unzip \
    # image assembly
    file xz-utils rsync xorriso \
    # scripts and installers
    python3 \
    # testing the result
    qemu-system-x86 qemu-system-arm qemu-utils \
    binutils-aarch64-linux-gnu && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ARG must be declared inside the build stage to be visible after FROM, so these
# two are declared here rather than before the FROM above.
ARG V_UTIL_VERSION
ARG V_UTIL_SHA256

# --- the kernel compiler ------------------------------------------------
# tools/m1-wifi/get-v.sh owns the V pin, and it owns it for a reason: an older
# pin fails every kernel build with "Unknown argument `-target-libc-headers`",
# because the kernel Makefile passes that unconditionally. The script also pins
# its own bootstrap compiler (vlang/vc) so the V pin cannot be built by a
# different, later vc snapshot on a later clean run. Calling the script rather
# than repeating its pin here keeps one source of truth.
COPY tools/m1-wifi/get-v.sh /opt/vinix-tools/get-v.sh
RUN mkdir -p /opt/vinix-tools && \
    sh /opt/vinix-tools/get-v.sh /opt/vinix-tools/v-kernel

# --- the utility compiler ----------------------------------------------
# util-vinix links against the release compiler's libc bindings; the pinned
# kernel compiler is too old for them. This is the same pinned release and
# checksum .github/workflows/check.yml uses - bump the two together.
RUN curl --fail --location --retry 3 \
      "https://github.com/vlang/v/releases/download/${V_UTIL_VERSION}/v_linux.zip" \
      -o /tmp/v_linux.zip && \
    echo "${V_UTIL_SHA256}  /tmp/v_linux.zip" | sha256sum -c - && \
    mkdir -p /opt/vinix-tools/v-util && \
    unzip -q /tmp/v_linux.zip -d /tmp/v-util && \
    mv /tmp/v-util/v/v /opt/vinix-tools/v-util/v && \
    rm -rf /tmp/v-util /tmp/v_linux.zip && \
    /opt/vinix-tools/v-kernel/v version && \
    /opt/vinix-tools/v-util/v version

# The kernel compiler is what `v` on PATH resolves to, so the build's own
# compiler discovery (build-support/find-v.sh, then the README's fallbacks)
# finds a working one without V or VINIX_V_COMPILER being set.
ENV PATH=/opt/vinix-tools/v-kernel:/opt/vinix-tools/v-util:$PATH \
    VEXE=/opt/vinix-tools/v-kernel/v

# Built as root, so run as a normal user: files the build writes into a mounted
# source tree come out owned by the caller instead of by root.
RUN useradd --create-home --uid 1000 builder
# /src is the working directory and has to be writable by that user even when
# nothing is mounted over it - a plain WORKDIR would have made it root-owned.
RUN install -d -o builder -g builder /src
USER builder
ENV HOME=/home/builder

WORKDIR /src

CMD ["bash"]
