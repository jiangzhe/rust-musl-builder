# use centos 7
FROM centos:centos7

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=nightly
ARG MUSL_VERS=1.1.16
ARG OPENSSL_VERS=1.0.2l

# Make sure we have basic dev tools for building C libraries.  Our goal
# here is to support the musl-libc builds and Cargo builds needed for a
# large selection of the most popular crates.
#
# We also set up a `rust` user by default, in whose account we'll install
# the Rust toolchain.  This user has sudo privileges if you need to install
# any more software.
RUN yum -y install curl-devel openssl-devel git-devel file sudo perl gcc make && \
    yum clean all && rm -rf /var/cache/yum

RUN curl -O https://www.musl-libc.org/releases/musl-${MUSL_VERS}.tar.gz && \
    tar -zxf musl-${MUSL_VERS}.tar.gz && \
    cd musl-${MUSL_VERS} && \
    ./configure && make && make install && \
    cd .. && rm -rf musl-${MUSL_VERS} musl-${MUSL_VERS}.tar.gz

RUN groupadd sudo && \
    useradd rust --user-group --create-home --shell /bin/bash --groups sudo

# Allow sudo without a password.
ADD sudoers /etc/sudoers.d/nopasswd

# Run all further code as user `rust`, and create our working directories
# as the appropriate user.
USER rust

# set up path to rust and gcc-musl
ENV PATH=$PATH:/home/rust/.cargo/bin:/usr/local/musl/bin 
# comment the proxy settings as the automatic build do not need to 
# break GFW through proxy
#    http_proxy=socks5://192.168.111.1:1080 \
#    https_proxy=socks5://192.168.111.1:1080

RUN mkdir -p /home/rust/libs /home/rust/src

# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.

RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain $TOOLCHAIN && \
    rustup target add x86_64-unknown-linux-musl
ADD cargo-config.toml /home/rust/.cargo/config

# We'll build our libraries in subdirectories of /home/rust/libs.  Please
# clean up when you're done.
WORKDIR /home/rust/libs

# Build a static library version of OpenSSL using musl-libc.  This is
# needed by the popular Rust `hyper` crate.
RUN curl -O https://www.openssl.org/source/openssl-${OPENSSL_VERS}.tar.gz && \
    tar xvzf openssl-${OPENSSL_VERS}.tar.gz && cd openssl-${OPENSSL_VERS} && \
    env CC=musl-gcc ./config --prefix=/usr/local/musl && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ && \
    make && sudo make install && \
    cd .. && rm -rf openssl-${OPENSSL_VERS}.tar.gz openssl-$OPENSSL_VERS}
ENV OPENSSL_DIR=/usr/local/musl/ \
    OPENSSL_INCLUDE_DIR=/usr/local/musl/include/ \
    DEP_OPENSSL_INCLUDE=/usr/local/musl/include/ \
    OPENSSL_LIB_DIR=/usr/local/musl/lib/ \
    OPENSSL_STATIC=1

# (Please feel free to submit pull requests for musl-libc builds of other C
# libraries needed by the most popular and common Rust crates, to avoid
# everybody needing to build them manually.)

# prefetch cache for popular Rust libs
RUN cd /tmp && \
    cargo new foo --bin && \
    cd foo && \
    echo 'iron = "*"' >> Cargo.toml && \
    cargo fetch --quiet && \
    cd .. && \
    rm -rf foo

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /home/rust/src

