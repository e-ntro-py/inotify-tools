//! libc bindings the `libc` crate lacks.  Using the platform's own regex and
//! getopt_long keeps behaviour and messages identical to the C tools.

use libc::{c_char, c_int, c_void, size_t};

/// `struct inotify_event` (the name follows the fixed-size header).
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct inotify_event {
    pub wd: c_int,
    pub mask: u32,
    pub cookie: u32,
    pub len: u32,
}

/// Storage for a `regex_t`, treated as opaque (large enough and suitably
/// aligned for glibc, musl and the BSDs).
#[repr(C, align(16))]
pub struct regex_t {
    _opaque: [u8; 256],
}

impl regex_t {
    pub fn zeroed() -> Self {
        regex_t { _opaque: [0; 256] }
    }
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub use libc::{inotify_add_watch, inotify_init, inotify_rm_watch};

// Other systems provide the inotify API in libc (e.g. FreeBSD >= 15) or in
// libinotify (see build.rs).
#[cfg(not(any(target_os = "linux", target_os = "android")))]
extern "C" {
    pub fn inotify_init() -> c_int;
    pub fn inotify_add_watch(fd: c_int, pathname: *const c_char, mask: u32) -> c_int;
    pub fn inotify_rm_watch(fd: c_int, wd: c_int) -> c_int;
}

/// `struct option` from `<getopt.h>`.
#[repr(C)]
pub struct option {
    pub name: *const c_char,
    pub has_arg: c_int,
    pub flag: *mut c_int,
    pub val: c_int,
}

pub const NO_ARGUMENT: c_int = 0;
pub const REQUIRED_ARGUMENT: c_int = 1;

// <regex.h> flags (identical on glibc and musl).
pub const REG_EXTENDED: c_int = 1;
pub const REG_ICASE: c_int = 2;
pub const REG_NOSUB: c_int = 8;

extern "C" {
    pub fn getopt_long(
        argc: c_int,
        argv: *const *mut c_char,
        optstring: *const c_char,
        longopts: *const option,
        longindex: *mut c_int,
    ) -> c_int;
    pub static mut optarg: *mut c_char;
    pub static mut optind: c_int;

    pub fn regcomp(preg: *mut regex_t, pattern: *const c_char, cflags: c_int) -> c_int;
    pub fn regexec(
        preg: *const regex_t,
        string: *const c_char,
        nmatch: size_t,
        pmatch: *mut c_void,
        eflags: c_int,
    ) -> c_int;
    pub fn regfree(preg: *mut regex_t);

    pub fn daemon(nochdir: c_int, noclose: c_int) -> c_int;
}

#[cfg(target_os = "linux")]
extern "C" {
    pub fn name_to_handle_at(
        dirfd: c_int,
        pathname: *const c_char,
        handle: *mut c_void,
        mount_id: *mut c_int,
        flags: c_int,
    ) -> c_int;
    pub fn open_by_handle_at(mount_fd: c_int, handle: *mut c_void, flags: c_int) -> c_int;
}
