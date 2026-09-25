// The version printed by --help: packaging/version.sh's (series + commit count).
use std::process::Command;

fn main() {
    let version = Command::new("sh")
        .arg("../packaging/version.sh")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| format!("{}.0", include_str!("../VERSION").trim()));
    println!("cargo:rustc-env=INOTIFY_TOOLS_VERSION={}", version);
    println!("cargo:rerun-if-changed=../VERSION");
    println!("cargo:rerun-if-changed=../packaging/version.sh");
    // The commit count changes whenever HEAD moves.
    if let Ok(o) = Command::new("git").args(["rev-parse", "--git-path", "logs/HEAD"]).output() {
        if o.status.success() {
            println!("cargo:rerun-if-changed={}", String::from_utf8_lossy(&o.stdout).trim());
        }
    }
}
