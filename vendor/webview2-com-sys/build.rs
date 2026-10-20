use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

// WebView2 SDK 1.0.902.49 is the last static loader verified on Windows 7 SP1
// and Server 2012 R2. Loaders >= 1.0.1054.31 import EventSetInformation, which
// those systems do not provide. The win7/x64/ and win7/x86/ copies are the
// pinned loaders. Verify their SHA256 before the link, because a wrong loader
// produces a binary that fails only at runtime. See
// .github/scripts/prepare-webview2-win7-loader.ps1.
const WIN7_X64_LOADER_SHA256: &str = "aa5c26670f1b18d0fa2a56ac3f1ae30110c332a8bfbd555a7be3e548d1b0da3d";
const WIN7_X64_LOADER_DLL_SHA256: &str = "fdf978ba706578b05967d7f0181f462147864a5aa74f36016a62cb3d3dbe6909";
const WIN7_X86_LOADER_SHA256: &str = "328b573a4d342007078140eb7fa4fb3aeaba804e29dae1361c9733b115580ad2";
const WIN7_X86_LOADER_DLL_SHA256: &str = "49c0650616eadfa63394558cd1d3ed9f64918d5ed38ab3ef32ad0249283df0ef";

fn main() -> Result<()> {
    let arch = target_arch()?;
    let (source, pinned) = loader_source(&arch)?;
    let out_dir = PathBuf::from(env::var("OUT_DIR")?);

    copy_loaders(&source, &out_dir, &arch, pinned)?;
    update_rustc_flags(&out_dir, &arch)?;

    println!("cargo:rustc-link-lib=advapi32");
    Ok(())
}

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Var(#[from] std::env::VarError),
    #[error("{0}")]
    Message(String),
}

pub type Result<T> = std::result::Result<T, Error>;

#[macro_use]
extern crate thiserror;

fn target_arch() -> Result<String> {
    Ok(match env::var("CARGO_CFG_TARGET_ARCH")?.as_str() {
        "x86_64" => "x64".into(),
        "x86" => "x86".into(),
        "aarch64" => "arm64".into(),
        other => return Err(Error::Message(format!("`{other}` is not supported by WebView2"))),
    })
}

// The custom x86_64-win7-windows-msvc and i686-win7-windows-msvc targets link
// the pinned legacy loader. Every other Windows target keeps the upstream
// loader installed by cargo.
fn loader_source(arch: &str) -> Result<(PathBuf, bool)> {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?);
    let target = env::var("TARGET")?;
    if target.ends_with("-win7-windows-msvc") {
        let source = manifest_dir.join("win7").join(arch);
        if !source.is_dir() {
            return Err(Error::Message(format!(
                "the Windows 7 WebView2 loader is only vendored for x64 and x86, not `{arch}`"
            )));
        }
        return Ok((source, true));
    }
    let source = manifest_dir.join(arch);
    if !source.is_dir() {
        return Err(Error::Message(format!("missing WebView2 loaders for `{arch}`: {source:?}")));
    }
    Ok((source, false))
}

fn copy_loaders(source: &Path, out_dir: &Path, arch: &str, pinned: bool) -> Result<()> {
    const LOADER_LIBS: &[&str] = &["WebView2Loader.dll", "WebView2Loader.dll.lib", "WebView2LoaderStatic.lib"];

    let destination = out_dir.join(arch);
    fs::create_dir_all(&destination)?;
    for lib in LOADER_LIBS {
        let from = source.join(lib);
        let to = destination.join(lib);
        if pinned {
            verify_pinned_loader(&from, arch, lib)?;
        }
        fs::copy(&from, &to)?;
        // Cargo rebuilds the crate when a loader changes, so a stale compile
        // cache cannot serve a binary linked against a different loader.
        println!("cargo:rerun-if-changed={}", from.display());
    }
    Ok(())
}

// Pin only the Windows 7 loader. The upstream loaders belong to the crate and
// change with the WebView2 SDK version.
fn verify_pinned_loader(path: &Path, arch: &str, lib: &str) -> Result<()> {
    let expected = match (arch, lib) {
        ("x64", "WebView2LoaderStatic.lib") => WIN7_X64_LOADER_SHA256,
        ("x64", "WebView2Loader.dll") => WIN7_X64_LOADER_DLL_SHA256,
        ("x86", "WebView2LoaderStatic.lib") => WIN7_X86_LOADER_SHA256,
        ("x86", "WebView2Loader.dll") => WIN7_X86_LOADER_DLL_SHA256,
        _ => return Ok(()),
    };

    let mut hasher = Sha256::new();
    hasher.update(fs::read(path)?);
    let actual = format!("{:x}", hasher.finalize());
    if actual != expected {
        return Err(Error::Message(format!(
            "Windows 7 WebView2 loader SHA256 mismatch for {path:?}: expected {expected}, got {actual}"
        )));
    }
    Ok(())
}

fn update_rustc_flags(out_dir: &Path, arch: &str) -> Result<()> {
    let lib_path = out_dir.join(arch);
    if !lib_path.is_dir() {
        return Err(Error::Message(format!("`{arch}` is not supported by WebView2")));
    }
    println!("cargo:rustc-link-search=native={}", lib_path.display());
    Ok(())
}
