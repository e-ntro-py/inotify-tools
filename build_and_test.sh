#!/bin/sh

set -ex

j=16

os=$(uname -o | sed "s#GNU/##g" | tr '[:upper:]' '[:lower:]')
uname_m=$(uname -m)

# The Makefile needs GNU make.
if [ "$os" = "freebsd" ]; then
  MAKE=gmake
else
  MAKE=make
fi

unit_test() {
  if [ "$os" != "freebsd" ]; then
    printf "\nunit test\n"
    $MAKE cargo-test unit-test unit-test-static
  fi
}

integration_test() {
  printf "\nintegration test\n"
  $MAKE integration-test
}

install_test() {
  printf "\ninstall test\n"
  stage=$(mktemp -d)
  $MAKE install prefix=/usr DESTDIR="$stage"
  test -x "$stage/usr/bin/inotifywait"
  test -L "$stage/usr/bin/fsnotifywait"
  test -e "$stage/usr/lib/libinotifytools.so.0"
  test -e "$stage/usr/include/inotifytools/inotifytools.h"
  $MAKE uninstall prefix=/usr DESTDIR="$stage"
  rm -rf "$stage"
}

tests() {
  unit_test
  integration_test
  install_test
}

clean() {
  $MAKE clean || true
  if [ "$arg1" = "clean" ]; then
    git clean -fdx -e target > /dev/null 2>&1
    git reset --hard
  fi
}

build() {
  $MAKE -j$j "$@"
}

set_gcc() {
  export CC=gcc
  export CXX=g++
}

set_clang() {
  export CC=clang
  export CXX=clang++
}

arg1="$1"

if command -v sudo; then
  pre="sudo"
fi

if command -v apt; then
  $pre apt update || true
  $pre apt install -y clang || true
  $pre apt install -y gcc || true
  $pre apt install -y g++ || true
  $pre apt install -y clang-format || true
  $pre apt install -y doxygen || true
  $pre apt install -y make || true
  $pre apt install -y cargo || true
  $pre apt install -y rustc || true
  $pre apt install -y e2fsprogs || true
  $pre apt install -y git || true
elif command -v apk; then
  apk add build-base bash coreutils clang clang-extra-tools linux-headers \
    cargo rust e2fsprogs git
elif command -v dnf; then
  $pre dnf install -y 'dnf-command(config-manager)'
  $pre dnf config-manager --add-repo "https://mirror.stream.centos.org/9-stream/CRB/$uname_m/os/"
  $pre curl --retry 8 --retry-all-errors -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-Official
  $pre rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official
  $pre dnf install -y --allowerasing gcc-c++ make cargo rust clang doxygen \
    e2fsprogs git diffutils
fi

for i in $(seq 64 -1 11); do
  if command -v "git-clang-format-$i" > /dev/null; then
    CLANG_FMT_VER="clang-format-$i"
    break
  fi
done

if [ -n "$CLANG_FMT_VER" ]; then
  printf "\nclang-format build\n"
  if ! git $CLANG_FMT_VER HEAD^ | grep -q "modif"; then
    printf "\nPlease change style to the format defined in the .clang-format file:\n"
    git diff --name-only
    exit 1
  fi
fi

if cargo fmt --version > /dev/null 2>&1; then
  printf "\nrustfmt check\n"
  cargo fmt --all -- --check
fi

if cargo clippy --version > /dev/null 2>&1; then
  printf "\nclippy\n"
  # Not fatal: newer clippy releases add lints.
  cargo clippy --release --all-targets || true
fi

printf "gcc build\n"
clean
set_gcc
build
tests

printf "\nclang C ABI test\n"
if command -v clang++ > /dev/null && [ "$os" != "freebsd" ]; then
  rm -f libinotifytools/src/test libinotifytools/src/test-static
  $MAKE unit-test unit-test-static CC=clang CXX=clang++
fi

printf "\ndebug build\n"
build PROFILE=dev
$MAKE cargo-test PROFILE=dev

if command -v doxygen > /dev/null; then
  printf "\ndoc build\n"
  ./rh_build.sh
fi

if command -v rustup > /dev/null && command -v arm-linux-gnueabihf-gcc > /dev/null; then
  printf "\narm32 cross build\n"
  rustup target add armv7-unknown-linux-gnueabihf
  CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    build TARGET=armv7-unknown-linux-gnueabihf
fi
