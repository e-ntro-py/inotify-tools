//! Output through C stdio, so it interleaves with C callers' output and keeps
//! the original buffering behaviour.

use std::ffi::{CStr, CString};

use libc::{c_int, FILE};

#[cfg(not(any(
    target_os = "freebsd",
    target_os = "dragonfly",
    target_os = "macos",
    target_os = "ios"
)))]
extern "C" {
    #[link_name = "stdin"]
    static mut C_STDIN: *mut FILE;
    #[link_name = "stdout"]
    static mut C_STDOUT: *mut FILE;
    #[link_name = "stderr"]
    static mut C_STDERR: *mut FILE;
}

// On the BSDs and macOS, stdin/stdout/stderr are macros for these.
#[cfg(any(target_os = "freebsd", target_os = "dragonfly", target_os = "macos", target_os = "ios"))]
extern "C" {
    #[link_name = "__stdinp"]
    static mut C_STDIN: *mut FILE;
    #[link_name = "__stdoutp"]
    static mut C_STDOUT: *mut FILE;
    #[link_name = "__stderrp"]
    static mut C_STDERR: *mut FILE;
}

/// The C library's `stdin` stream.
pub fn c_stdin() -> *mut FILE {
    unsafe { C_STDIN }
}

/// The C library's `stdout` stream.
pub fn c_stdout() -> *mut FILE {
    unsafe { C_STDOUT }
}

/// The C library's `stderr` stream.
pub fn c_stderr() -> *mut FILE {
    unsafe { C_STDERR }
}

/// `fwrite()` raw bytes to a C stream.
///
/// # Safety
/// `f` must be NULL or a valid, open C `FILE` stream.
pub unsafe fn write_to(f: *mut FILE, b: &[u8]) {
    if !b.is_empty() && !f.is_null() {
        libc::fwrite(b.as_ptr().cast(), 1, b.len(), f);
    }
}

/// Write raw bytes to C `stdout`.
pub fn out(b: &[u8]) {
    unsafe { write_to(c_stdout(), b) };
}

/// Write raw bytes to C `stderr`.
pub fn err(b: &[u8]) {
    unsafe { write_to(c_stderr(), b) };
}

/// `fflush(NULL)`
pub fn flush_all() {
    unsafe {
        libc::fflush(std::ptr::null_mut());
    }
}

/// Current `errno`.
pub fn errno() -> c_int {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

/// Set `errno`.
pub fn set_errno(e: c_int) {
    unsafe {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        {
            *libc::__errno_location() = e;
        }
        #[cfg(any(target_os = "freebsd", target_os = "dragonfly", target_os = "macos"))]
        {
            *libc::__error() = e;
        }
    }
}

/// `strerror(e)`, exactly as the C library formats it.
pub fn strerror(e: c_int) -> Vec<u8> {
    unsafe {
        let p = libc::strerror(e);
        if p.is_null() {
            return Vec::new();
        }
        CStr::from_ptr(p).to_bytes().to_vec()
    }
}

/// Build a `CString` from bytes, truncating at the first NUL like a C
/// string copy would.
pub fn cstring(b: &[u8]) -> CString {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    CString::new(&b[..end]).expect("no interior NUL")
}

/// Something that can be appended to a byte message.  Paths are arbitrary
/// bytes (not necessarily UTF-8), so messages are assembled as bytes.
pub trait Piece {
    fn put(&self, v: &mut Vec<u8>);
}

impl Piece for str {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self.as_bytes());
    }
}
impl Piece for String {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self.as_bytes());
    }
}
impl Piece for [u8] {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self);
    }
}
impl<const N: usize> Piece for [u8; N] {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self);
    }
}
impl Piece for Vec<u8> {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self);
    }
}
impl Piece for CStr {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self.to_bytes());
    }
}
impl Piece for CString {
    fn put(&self, v: &mut Vec<u8>) {
        v.extend_from_slice(self.to_bytes());
    }
}
impl<T: Piece + ?Sized> Piece for &T {
    fn put(&self, v: &mut Vec<u8>) {
        (**self).put(v);
    }
}
macro_rules! piece_display {
    ($($t:ty),*) => {$(
        impl Piece for $t {
            fn put(&self, v: &mut Vec<u8>) {
                v.extend_from_slice(self.to_string().as_bytes());
            }
        }
    )*};
}
piece_display!(i32, u32, i64, u64, isize, usize, u16, u8, char);

/// Concatenate [`Piece`]s into a `Vec<u8>`.
#[macro_export]
macro_rules! cat {
    ($($e:expr),* $(,)?) => {{
        #[allow(unused_mut)]
        let mut v: Vec<u8> = Vec::new();
        $( $crate::cio::Piece::put(&$e, &mut v); )*
        v
    }};
}

/// Print concatenated [`Piece`]s to C `stdout`.
#[macro_export]
macro_rules! cprint {
    ($($e:expr),* $(,)?) => { $crate::cio::out(&$crate::cat!($($e),*)) };
}

/// Print concatenated [`Piece`]s to C `stderr`.
#[macro_export]
macro_rules! ceprint {
    ($($e:expr),* $(,)?) => { $crate::cio::err(&$crate::cat!($($e),*)) };
}
