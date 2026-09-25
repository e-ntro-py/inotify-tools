// Same SONAME as the libtool-built C library (libinotifytools.so.0).
fn main() {
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if os != "macos" && os != "ios" && os != "windows" {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-soname,libinotifytools.so.0");
    }

    // Outside Linux inotify is in libc (FreeBSD >= 15) or libinotify;
    // INOTIFYTOOLS_LINK_INOTIFY=0/1 overrides the detection.
    if os != "linux" && os != "android" {
        println!("cargo:rerun-if-env-changed=INOTIFYTOOLS_LINK_INOTIFY");
        let forced = std::env::var("INOTIFYTOOLS_LINK_INOTIFY").ok();
        let native = std::path::Path::new("/usr/include/sys/inotify.h").exists();
        if forced.as_deref() == Some("1") || (forced.is_none() && !native) {
            println!("cargo:rustc-link-search=native=/usr/local/lib");
            println!("cargo:rustc-link-lib=inotify");
        }
    }
    println!("cargo:rerun-if-changed=build.rs");
}
