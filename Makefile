# Builds with cargo, then generates headers and man pages, installs with the
# historical autotools layout and runs the C ABI and sharness tests.
#
#   make; make check; make install prefix=/usr libdir=/usr/lib64 DESTDIR=...
#
# Variables: prefix exec_prefix bindir libdir includedir datarootdir mandir
# docdir DESTDIR CARGO CARGOFLAGS PROFILE TARGET CARGO_TARGET_DIR
# ENABLE_SHARED ENABLE_STATIC ALL_STATIC CC CXX CFLAGS CXXFLAGS LDFLAGS
# (see INSTALL).

VERSION := $(shell packaging/version.sh)

prefix ?= /usr/local
exec_prefix ?= $(prefix)
bindir ?= $(exec_prefix)/bin
libdir ?= $(exec_prefix)/lib
includedir ?= $(prefix)/include
datarootdir ?= $(prefix)/share
mandir ?= $(datarootdir)/man
docdir ?= $(datarootdir)/doc/inotify-tools
DESTDIR ?=

CARGO ?= cargo
CARGOFLAGS ?=
PROFILE ?= release
TARGET ?=
CARGO_TARGET_DIR ?= target
ENABLE_SHARED ?= 1
ENABLE_STATIC ?= 1
ALL_STATIC ?= 0

INSTALL ?= install
INSTALL_PROGRAM ?= $(INSTALL) -m 755
INSTALL_DATA ?= $(INSTALL) -m 644
LN_S ?= ln -sf
DOXYGEN ?= doxygen
SHELL_PATH ?= /bin/bash

# libtool -version-info 4:1:4 of the original library.
SONAME := libinotifytools.so.0
SOFILE := libinotifytools.so.0.4.1

ifeq ($(PROFILE),dev)
PROFILE_DIR := debug
else
PROFILE_DIR := $(PROFILE)
endif

CARGO_BUILD_FLAGS := --profile $(PROFILE) $(CARGOFLAGS)
ifneq ($(TARGET),)
CARGO_BUILD_FLAGS += --target $(TARGET)
OUT := $(CARGO_TARGET_DIR)/$(TARGET)/$(PROFILE_DIR)
else
OUT := $(CARGO_TARGET_DIR)/$(PROFILE_DIR)
endif
export CARGO_TARGET_DIR

# ALL_STATIC tools get their own target dir, so the static and the normal
# build do not keep invalidating each other.
ifeq ($(ALL_STATIC),1)
STATIC_TARGET_DIR := $(CARGO_TARGET_DIR)/static
TOOLS_OUT := $(patsubst $(CARGO_TARGET_DIR)/%,$(STATIC_TARGET_DIR)/%,$(OUT))
else
TOOLS_OUT := $(OUT)
endif

MAN_DATE ?= $(shell date -u -r ChangeLog +'%Y-%m-%d' 2>/dev/null || date -u +'%Y-%m-%d')

HDRDIR := libinotifytools/src/inotifytools
GEN_HEADERS := $(HDRDIR)/inotify.h $(HDRDIR)/fanotify.h
HEADERS := $(HDRDIR)/inotifytools.h $(HDRDIR)/inotify-nosys.h $(HDRDIR)/inotify.h \
	$(HDRDIR)/fanotify-dfid-name.h $(HDRDIR)/fanotify.h
MANPAGES := man/inotifywait.1 man/inotifywatch.1 man/fsnotifywait.1 man/fsnotifywatch.1
TOOLS := inotifywait inotifywatch
# The tests in t/ run ../../src/<tool>.
TEST_LINKS := src/inotifywait src/inotifywatch src/fsnotifywait src/fsnotifywatch

# Needed to link the static library into C (rustc --print native-static-libs).
STATIC_LIBS ?= -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc

.PHONY: FORCE all build headers man check unit-test unit-test-static cargo-test \
	integration-test install install-strip install-doc uninstall clean \
	distclean doc dist

all: build headers man $(TEST_LINKS)

build:
ifeq ($(ALL_STATIC),1)
	RUSTFLAGS="$$RUSTFLAGS -C target-feature=+crt-static" CARGO_TARGET_DIR=$(STATIC_TARGET_DIR) \
		$(CARGO) build $(CARGO_BUILD_FLAGS) -p inotify-tools --bins
	$(CARGO) build $(CARGO_BUILD_FLAGS) -p inotifytools --lib
else
	$(CARGO) build $(CARGO_BUILD_FLAGS)
endif

headers: $(GEN_HEADERS)

# Like the old configure checks: use the system headers if they work.
$(HDRDIR)/inotify.h: $(HDRDIR)/inotify.h.in
	@if printf '#include <sys/inotify.h>\nint main(void) { return (-1 == inotify_init()); }\n' | \
		$(CC) $(CFLAGS) -x c -c -o /dev/null - >/dev/null 2>&1; then \
		def='#define SYS_INOTIFY_H_EXISTS_AND_WORKS 1'; \
	else \
		def='/* #undef SYS_INOTIFY_H_EXISTS_AND_WORKS */'; \
	fi; \
	{ echo "/* $@.  Generated from inotify.h.in by make.  */"; \
	  sed "s|^#undef SYS_INOTIFY_H_EXISTS_AND_WORKS\$$|$$def|" $<; } > $@.tmp && mv $@.tmp $@
	@echo "  GEN      $@"

$(HDRDIR)/fanotify.h: $(HDRDIR)/fanotify.h.in
	@if printf '#include <sys/fanotify.h>\nint main(void) { return (-1 == fanotify_init(FAN_REPORT_DFID_NAME, 0)); }\n' | \
		$(CC) $(CFLAGS) -x c -c -o /dev/null - >/dev/null 2>&1; then \
		def='#define SYS_FANOTIFY_H_EXISTS_AND_WORKS 1'; \
	else \
		def='/* #undef SYS_FANOTIFY_H_EXISTS_AND_WORKS */'; \
	fi; \
	{ echo "/* $@.  Generated from fanotify.h.in by make.  */"; \
	  sed "s|^#undef SYS_FANOTIFY_H_EXISTS_AND_WORKS\$$|$$def|" $<; } > $@.tmp && mv $@.tmp $@
	@echo "  GEN      $@"

man: $(MANPAGES)

# Rewritten only when the version changes, so the man pages follow it.
.version: FORCE
	@echo $(VERSION) | cmp -s - $@ || echo $(VERSION) > $@

man/%.1: man/%.1.in .version
	sed -e 's|@MAN_DATE@|$(MAN_DATE)|g' -e 's|@MAN_PACKAGE_VERSION@|$(VERSION)|g' $< > $@

$(TEST_LINKS): | build
src/inotifywait src/inotifywatch:
	$(LN_S) $(abspath $(TOOLS_OUT))/$(notdir $@) $@
src/fsnotifywait: | src/inotifywait
	$(LN_S) inotifywait $@
src/fsnotifywatch: | src/inotifywatch
	$(LN_S) inotifywatch $@

# ---------------------------------------------------------------- tests

check: all cargo-test unit-test unit-test-static integration-test

cargo-test:
	$(CARGO) test $(CARGO_BUILD_FLAGS)

# Uninstalled library with its SONAME link, so the C tests never pick up an
# installed copy.
TESTLIBDIR := libinotifytools/src/.libs

$(TESTLIBDIR): build
	mkdir -p $@
	$(LN_S) $(abspath $(OUT))/libinotifytools.so $@/libinotifytools.so
	$(LN_S) $(abspath $(OUT))/libinotifytools.so $@/$(SONAME)

# The original C++ unit test, against the shared and the static library.
libinotifytools/src/test: libinotifytools/src/test.cpp $(HEADERS) $(TESTLIBDIR)
	$(CXX) $(CXXFLAGS) -std=c++17 -Wall -Ilibinotifytools/src -o $@ $< \
		-L$(TESTLIBDIR) -linotifytools -Wl,-rpath,$(abspath $(TESTLIBDIR)) $(LDFLAGS)

libinotifytools/src/test-static: libinotifytools/src/test.cpp $(HEADERS) build
	$(CXX) $(CXXFLAGS) -std=c++17 -Wall -Ilibinotifytools/src -o $@ $< \
		$(OUT)/libinotifytools.a $(STATIC_LIBS) $(LDFLAGS)

unit-test: libinotifytools/src/test
	LD_LIBRARY_PATH=$(abspath $(TESTLIBDIR)) ./libinotifytools/src/test

unit-test-static: libinotifytools/src/test-static
	./libinotifytools/src/test-static

integration-test: all
	$(MAKE) -C t SHELL_PATH=$(SHELL_PATH)

# -------------------------------------------------------------- install

install: all
	$(INSTALL) -d $(DESTDIR)$(bindir)
	for t in $(TOOLS); do $(INSTALL_PROGRAM) $(TOOLS_OUT)/$$t $(DESTDIR)$(bindir)/$$t || exit 1; done
	cd $(DESTDIR)$(bindir) && $(LN_S) inotifywait fsnotifywait && $(LN_S) inotifywatch fsnotifywatch
	$(INSTALL) -d $(DESTDIR)$(libdir)
ifeq ($(ENABLE_SHARED),1)
	$(INSTALL_PROGRAM) $(OUT)/libinotifytools.so $(DESTDIR)$(libdir)/$(SOFILE)
	cd $(DESTDIR)$(libdir) && $(LN_S) $(SOFILE) $(SONAME) && $(LN_S) $(SOFILE) libinotifytools.so
endif
ifeq ($(ENABLE_STATIC),1)
	$(INSTALL_DATA) $(OUT)/libinotifytools.a $(DESTDIR)$(libdir)/libinotifytools.a
endif
	$(INSTALL) -d $(DESTDIR)$(includedir)/inotifytools
	$(INSTALL_DATA) $(HEADERS) $(DESTDIR)$(includedir)/inotifytools/
	$(INSTALL) -d $(DESTDIR)$(mandir)/man1
	$(INSTALL_DATA) $(MANPAGES) $(DESTDIR)$(mandir)/man1/

install-strip:
	$(MAKE) install INSTALL_PROGRAM="$(INSTALL_PROGRAM) -s"

uninstall:
	rm -f $(addprefix $(DESTDIR)$(bindir)/,$(TOOLS) fsnotifywait fsnotifywatch)
	rm -f $(DESTDIR)$(libdir)/$(SOFILE) $(DESTDIR)$(libdir)/$(SONAME) \
		$(DESTDIR)$(libdir)/libinotifytools.so $(DESTDIR)$(libdir)/libinotifytools.a
	rm -f $(addprefix $(DESTDIR)$(includedir)/inotifytools/,$(notdir $(HEADERS)))
	-rmdir $(DESTDIR)$(includedir)/inotifytools 2>/dev/null
	rm -f $(addprefix $(DESTDIR)$(mandir)/man1/,$(notdir $(MANPAGES)))
	rm -rf $(DESTDIR)$(docdir)/libinotifytools

# ------------------------------------------------------------------ docs

# C API documentation (from the public header) with doxygen.
doc:
	cd libinotifytools/src && $(DOXYGEN)

install-doc: doc
	$(INSTALL) -d $(DESTDIR)$(docdir)/libinotifytools
	cp -R libinotifytools/src/doc/html/. $(DESTDIR)$(docdir)/libinotifytools/

# ----------------------------------------------------------------- misc

# Release tarball, with the full version stamped into its VERSION file.
dist:
	packaging/version.sh --strict >/dev/null
	rm -rf inotify-tools-$(VERSION)
	git archive --format=tar --prefix=inotify-tools-$(VERSION)/ HEAD | tar xf -
	git log --pretty=format:'%s' > inotify-tools-$(VERSION)/ChangeLog
	echo $(VERSION) > inotify-tools-$(VERSION)/VERSION
	tar czf inotify-tools-$(VERSION).tar.gz inotify-tools-$(VERSION)
	rm -rf inotify-tools-$(VERSION)

clean:
	-$(CARGO) clean
	rm -f $(GEN_HEADERS) $(MANPAGES) $(TEST_LINKS) .version
	rm -f libinotifytools/src/test libinotifytools/src/test-static
	rm -rf $(TESTLIBDIR)
	rm -rf libinotifytools/src/doc
	-$(MAKE) -C t clean

distclean: clean
