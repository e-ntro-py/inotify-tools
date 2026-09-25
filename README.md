[![GitHub Build Status](https://github.com/inotify-tools/inotify-tools/actions/workflows/build.yml/badge.svg)](https://github.com/inotify-tools/inotify-tools/actions)
[![Coverity Build Status](https://scan.coverity.com/projects/23295/badge.svg)](https://scan.coverity.com/projects/inotifytools)

inotify-tools
=============

This is a package of some commandline utilities relating to inotify.

The general purpose of this package is to allow inotify's features to be used
from within shell scripts.  Read the man pages for further details.

It consists of:

* `inotifywait` / `fsnotifywait`: wait for (or monitor) filesystem events.
* `inotifywatch` / `fsnotifywatch`: gather filesystem usage statistics.
* `libinotifytools`: a small library, with a C API
  (`<inotifytools/inotifytools.h>`), used by the tools and by other programs.

inotify-tools is written in Rust.  `libinotifytools.so` is a drop-in, ABI
compatible replacement for the historical C library (same symbols, same
SONAME `libinotifytools.so.0`, same headers).

Building
--------

Requirements: Rust (cargo/rustc 1.63 or newer), GNU make, a C compiler (used
to generate the installed headers) and, for `make check`, a C++ compiler.

    make
    make check
    make install              # prefix=/usr/local by default

See [INSTALL](INSTALL) for all options.
