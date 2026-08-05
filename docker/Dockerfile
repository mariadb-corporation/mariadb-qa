# MariaDB QA Framework Container
#
# A ready-to-use MariaDB QA box: the build toolchain, the mariadb-qa framework,
# the testing SQL generators and the testcase reducer. No MariaDB server build
# is included. The engineer clones the sources and builds them in the box.
#
# Build stages, and why they are split:
#   toolchain  Base packages, clang from apt.llvm.org, the box user, and the
#              mariadb-qa clone. Every other stage starts from this one.
#   msan-*     Builds the MSAN instrumented libraries into /MSAN_libs.
#   clang-*    Builds clang from source into /usr/local. This stage is separate
#              because build_clang.sh removes the apt clang packages, while the
#              MSAN builds still need apt clang-20. The final image takes only
#              /usr/local from this stage, so those removals stay behind.
#   final      Copies the results of the optional stages and finishes the box.
#
# Each optional stage is selected by a build argument. "FROM name-${ARG}" picks
# an empty stage when the argument is 0.

ARG UBUNTU_VERSION=24.04
ARG APT_LLVM_VERSION=20
# The MSAN instrumented libraries are off by default: their build runs MSAN test
# binaries, and an MSAN binary turns ASLR off through personality(), which the
# default seccomp profile of a build container blocks. Build them in a running
# box with "qa-upgrade msan", where the control script has turned that profile
# off. A build worker that holds the insecure entitlement can set this to 1
ARG WITH_MSAN_LIBS=0
ARG WITH_CLANG_SOURCE=1
ARG WITH_CLAUDE=1
ARG CLANG_SOURCE_VERSION=22.1.8
ARG BOX_USER=qa
ARG BOX_UID=1000
ARG BOX_GID=1000
ARG MARIADB_QA_REPO=https://github.com/mariadb-corporation/mariadb-qa.git
ARG MARIADB_QA_BRANCH=master

# ---------------------------------------------------------------------------
# Stage: toolchain
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS toolchain
ARG APT_LLVM_VERSION
ARG WITH_CLAUDE
ARG BOX_USER
ARG BOX_UID
ARG BOX_GID
ARG MARIADB_QA_REPO
ARG MARIADB_QA_BRANCH

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Package set from mariadb-qa/setup_server.sh, updated for Ubuntu 24.04.
# Left out on purpose: host and kernel tools (linux-tools, cpufrequtils, hdparm,
# lshw), Debian packaging extras (devscripts, dh-*), and the retired gcc-9 and
# libasan5 packages. libboost-all-dev is replaced by the three Boost packages a
# Galera build needs. libmysqlclient-dev provides the client library that
# revgen links against.
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake bats bbe bc binutils-dev bison build-essential \
      ca-certificates check chrpath cmake curl debhelper dpkg-dev file g++ \
      gawk gcc gdb git gnupg gnutls-dev groff htop jq less libaio-dev \
      libaio1t64 libasio-dev libboost-dev libboost-filesystem-dev \
      libboost-program-options-dev libbsd-dev libbz2-dev libc++-dev \
      libc++abi-dev libcurl4-openssl-dev libdata-dumper-simple-perl \
      libdbd-mysql-perl libedit-dev libgcrypt20 libgcrypt20-dev libgtest-dev \
      libjemalloc-dev libjudy-dev libkrb5-dev liblz4-dev libmysqlclient-dev \
      libncurses5-dev libnuma-dev libpam0g-dev libpcre2-dev libpmem-dev \
      libreadline-dev libsnappy-dev libssh-dev libssl-dev libsystemd-dev \
      libtool libubsan1 libudev-dev libxml2-dev libxxhash-dev libz-dev \
      libzstd-dev lsb-release lsof lzma lzma-dev make man-db net-tools \
      ninja-build openssl patch perl pkg-config psmisc pwgen python3 \
      python3-pip rr rsync scons screen shellcheck shfmt silversearcher-ag socat \
      strace sudo sysbench tree tzdata unixodbc-dev uuid-dev valgrind vim \
      wget xz-utils zlib1g \
 && rm -rf /var/lib/apt/lists/*

# clang from apt.llvm.org. Ubuntu 24.04 ships clang-18 only, and the MSAN
# scripts need clang-20 exactly: with clang-21 the MSAN server cannot bootstrap
# because InnoDB startup code is flagged (MDEV-38419).
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
      -o /etc/apt/keyrings/llvm.asc \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] http://apt.llvm.org/${VERSION_CODENAME}/ llvm-toolchain-${VERSION_CODENAME}-${APT_LLVM_VERSION} main" \
      > /etc/apt/sources.list.d/llvm-${APT_LLVM_VERSION}.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      clang-${APT_LLVM_VERSION} clang-format-${APT_LLVM_VERSION} \
      libc++-${APT_LLVM_VERSION}-dev libc++abi-${APT_LLVM_VERSION}-dev \
      libclang-rt-${APT_LLVM_VERSION}-dev lld-${APT_LLVM_VERSION} \
      llvm-${APT_LLVM_VERSION} llvm-${APT_LLVM_VERSION}-dev \
      llvm-${APT_LLVM_VERSION}-tools \
 && rm -rf /var/lib/apt/lists/* \
 && for T in clang clang++ clang-format ld.lld llvm-symbolizer llvm-profdata llvm-cov; do \
      ln -sf /usr/bin/${T}-${APT_LLVM_VERSION} /usr/bin/${T}; \
    done \
 && clang --version | head -1

# Claude Code, from the signed Anthropic apt repository. The engineer signs in
# themselves, so the image holds no credentials.
RUN if [ "${WITH_CLAUDE}" = "1" ]; then \
      curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
        -o /etc/apt/keyrings/claude-code.asc \
      && gpg --show-keys /etc/apt/keyrings/claude-code.asc | tr -d ' ' \
         | grep -q '^31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE$' \
      && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
           > /etc/apt/sources.list.d/claude-code.list \
      && apt-get update \
      && apt-get install -y --no-install-recommends claude-code \
      && rm -rf /var/lib/apt/lists/* \
      && claude --version; \
    fi

# The framework runs as a normal user with passwordless sudo, as on a QA server.
# linkit, startup_all and the build scripts all call sudo.
# Ubuntu 24.04 ships an account at id 1000. It goes, so the box user can hold
# that id and match the first account of a normal Linux host
RUN if getent passwd ${BOX_UID} > /dev/null; then \
      userdel -rf "$(getent passwd ${BOX_UID} | cut -d: -f1)" 2> /dev/null; \
    fi \
 && if getent group ${BOX_GID} > /dev/null; then \
      groupdel -f "$(getent group ${BOX_GID} | cut -d: -f1)"; \
    fi \
 && groupadd -g ${BOX_GID} ${BOX_USER} \
 && useradd -m -u ${BOX_UID} -g ${BOX_GID} -s /bin/bash ${BOX_USER} \
 && echo "${BOX_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/box-user \
 && chmod 0440 /etc/sudoers.d/box-user \
 && mkdir -p /test /data \
 && chown ${BOX_USER}:${BOX_USER} /test /data

# No server package is installed, so no /etc/mysql should remain. The move
# matches setup_server.sh and keeps a stray my.cnf out of every test server.
RUN if [ -d /etc/mysql ]; then mv /etc/mysql /etc/mysql.old; fi

USER ${BOX_USER}
WORKDIR /home/${BOX_USER}

# A shallow clone keeps the image small. The tracked content is about 620 MB.
# The clone is the last step of this stage, so the guides and the box scripts of
# the final stage can change without rebuilding anything above.
# A layer cache holds the clone. To take a newer framework into a rebuild, pass
# --build-arg CLONE_DATE=$(date +%F). In a running box, qa-update does the same
ARG CLONE_DATE=unset
RUN echo "clone date argument: ${CLONE_DATE}" \
 && git clone --depth=1 --branch=${MARIADB_QA_BRANCH} ${MARIADB_QA_REPO} \
      /home/${BOX_USER}/mariadb-qa \
 && git -C /home/${BOX_USER}/mariadb-qa log -1 --format='mariadb-qa %h %cd' --date=short

# ---------------------------------------------------------------------------
# Stage: msan-0 (skipped) and msan-1 (build the MSAN instrumented libraries)
# ---------------------------------------------------------------------------
FROM toolchain AS msan-0
RUN sudo install -d -o "$(id -u)" -g "$(id -g)" /MSAN_libs

FROM toolchain AS msan-1
RUN sudo rm -rf /MSAN_libs \
 && ~/mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh \
 && sudo rm -rf /MSAN_libs/build \
 && ls /MSAN_libs

FROM msan-${WITH_MSAN_LIBS} AS msan

# ---------------------------------------------------------------------------
# Stage: clang-0 (skipped) and clang-1 (build clang from source)
# ---------------------------------------------------------------------------
# build_clang.sh installs into /usr/local and points /usr/bin/clang at it. The
# final stage copies /usr/local and remakes those links, and the LLVM source and
# build trees are removed in the same layer, so nothing of the build is carried.
FROM toolchain AS clang-0
RUN true

FROM toolchain AS clang-1
ARG CLANG_SOURCE_VERSION
# build_clang.sh bootstraps with the apt clang, so the build is a clang plus lld
# build. It needs about 18 GB in /test/llvm-build and frees it again
RUN sudo install -d -o "$(id -u)" -g "$(id -g)" /test/llvm-build \
 && ~/mariadb-qa/build_clang.sh ${CLANG_SOURCE_VERSION} \
 && sudo rm -rf /test/llvm-build \
 && /usr/local/bin/clang --version | head -1

FROM clang-${WITH_CLANG_SOURCE} AS clangsel

# ---------------------------------------------------------------------------
# Stage: final
# ---------------------------------------------------------------------------
FROM toolchain AS final
ARG BOX_USER
LABEL org.opencontainers.image.title="MariaDB QA Framework Container"
LABEL org.opencontainers.image.description="MariaDB QA framework, build toolchain, testing SQL generators and testcase reducer"
LABEL org.opencontainers.image.source="https://github.com/mariadb-corporation/mariadb-qa"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"

USER root
COPY --from=msan --chown=${BOX_USER}:${BOX_USER} /MSAN_libs /MSAN_libs
COPY --from=clangsel /usr/local /usr/local
RUN if [ -x /usr/local/bin/clang ]; then \
      for T in clang clang++ ld.lld llvm-symbolizer; do \
        ln -sf /usr/local/bin/${T} /usr/bin/${T}; \
      done; \
      ldconfig; \
    fi \
 && clang --version | head -1

# The box scripts and the guides come last, so a change to either one rebuilds
# only the steps below this line
COPY files/box-setup.sh files/entrypoint.sh files/qa-check.sh \
     files/qa-clonebuild.sh files/qa-guide.sh files/qa-run.sh files/qa-tools.sh \
     files/qa-update.sh files/qa-upgrade.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/box-setup.sh /usr/local/bin/entrypoint.sh \
      /usr/local/bin/qa-*.sh \
 && for T in qa-check qa-clonebuild qa-guide qa-run qa-tools qa-update qa-upgrade; do \
      ln -sf /usr/local/bin/${T}.sh /usr/local/bin/${T}; \
    done \
 && for T in cb cb-san cb-msan cb-tsan cb-val; do \
      ln -sf /usr/local/bin/qa-clonebuild.sh /usr/local/bin/${T}; \
    done
COPY README.md SETUP.md USAGE.md /usr/local/share/mariadb-qa-container/

# The reducer and the revgen testing SQL generator are single translation units
# and build here. The generatorcpp generator links against a MariaDB basedir, so
# it builds with "qa-tools" after the first server build.
USER ${BOX_USER}
RUN box-setup.sh && qa-tools

ENV BOX_USER=${BOX_USER}
USER root
WORKDIR /home/${BOX_USER}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
