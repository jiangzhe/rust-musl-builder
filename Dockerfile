# Use Debian 16.04 as the base for our Rust musl toolchain, because of
# https://github.com/rust-lang/rust/issues/34978 (as of Rust 1.11).
FROM centos:centos7

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=stable

# Make sure we have basic dev tools for building C libraries.  Our goal
# here is to support the musl-libc builds and Cargo builds needed for a
# large selection of the most popular crates.
#
# We also set up a `rust` user by default, in whose account we'll install
# the Rust toolchain.  This user has sudo privileges if you need to install
# any more software.
RUN yum -y install curl-devel openssl-devel git-devel file sudo perl gcc make && \
    yum clean all && rm -rf /var/cache/yum

RUN curl -O https://www.musl-libc.org/releases/musl-1.1.16.tar.gz && \
    tar -zxf musl-1.1.16.tar.gz && \
    cd musl-1.1.16 && \
    ./configure && make && make install && \
    cd .. && rm -rf musl-1.1.16 musl-1.1.16.tar.gz

RUN groupadd sudo && \
    useradd rust --user-group --create-home --shell /bin/bash --groups sudo

# Allow sudo without a password.
ADD sudoers /etc/sudoers.d/nopasswd

# Run all further code as user `rust`, and create our working directories
# as the appropriate user.
USER rust
ENV PATH=$PATH:/home/rust/.cargo/bin:/usr/local/musl/bin 
# comment the proxy settings as the automatic build do not need to 
# break GFW through proxy
#    http_proxy=socks5://192.168.88.1:1080 \
#    https_proxy=socks5://192.168.88.1:1080

RUN mkdir -p /home/rust/libs /home/rust/src

# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
#ENV PATH=/home/rust/.cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
RUN VERS=1.0.2l && \
    curl -O https://www.openssl.org/source/openssl-$VERS.tar.gz && \
    tar xvzf openssl-$VERS.tar.gz && cd openssl-$VERS && \
    env CC=musl-gcc ./config --prefix=/usr/local/musl && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ && \
    make && sudo make install && \
    cd .. && rm -rf openssl-$VERS.tar.gz openssl-$VERS
ENV OPENSSL_DIR=/usr/local/musl/ \
    OPENSSL_INCLUDE_DIR=/usr/local/musl/include/ \
    DEP_OPENSSL_INCLUDE=/usr/local/musl/include/ \
    OPENSSL_LIB_DIR=/usr/local/musl/lib/ \
    OPENSSL_STATIC=1

# (Please feel free to submit pull requests for musl-libc builds of other C
# libraries needed by the most popular and common Rust crates, to avoid
# everybody needing to build them manually.)

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /home/rust/src
