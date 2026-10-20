[CmdletBinding()]
param(
  [ValidateSet("x64", "x86")][string]$Architecture = "x64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The Windows 7 / Server 2012 R2 bundle links the static loader from WebView2 SDK
# 1.0.902.49. Loaders >= 1.0.1054.31 import EventSetInformation, which Win7 and
# Server 2012 R2 do not provide, and fail with "Could not find the WebView2
# Runtime". The loader lives in vendor/webview2-com-sys/win7/<architecture>/ and
# Cargo links it through the [patch.crates-io] entry. This script verifies the
# loader and stages the loader DLL for the runtime probe. It does not modify the
# Cargo registry, so compile caches stay correct.
$sdkVersion = "1.0.902.49"
switch ($Architecture) {
  "x64" {
    $loaderSha256 = "aa5c26670f1b18d0fa2a56ac3f1ae30110c332a8bfbd555a7be3e548d1b0da3d"
    $loaderDllSha256 = "fdf978ba706578b05967d7f0181f462147864a5aa74f36016a62cb3d3dbe6909"
  }
  "x86" {
    $loaderSha256 = "328b573a4d342007078140eb7fa4fb3aeaba804e29dae1361c9733b115580ad2"
    $loaderDllSha256 = "49c0650616eadfa63394558cd1d3ed9f64918d5ed38ab3ef32ad0249283df0ef"
  }
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$loaderDirectory = Join-Path $repositoryRoot "vendor/webview2-com-sys/win7/$Architecture"
$loaderPath = Join-Path $loaderDirectory "WebView2LoaderStatic.lib"
$loaderDllPath = Join-Path $loaderDirectory "WebView2Loader.dll"

function Assert-FileHash {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected
  )
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Vendored Windows 7 WebView2 loader is missing: $Path"
  }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) {
    throw "Unexpected Windows 7 WebView2 loader SHA256 for ${Path}: $actual"
  }
}

Assert-FileHash -Path $loaderPath -Expected $loaderSha256
Assert-FileHash -Path $loaderDllPath -Expected $loaderDllSha256

$probeDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "dbx-win7-webview2-loader-probe"
New-Item -ItemType Directory -Path $probeDirectory -Force | Out-Null
$probeLoader = Join-Path $probeDirectory "WebView2Loader.dll"
Copy-Item -LiteralPath $loaderDllPath -Destination $probeLoader -Force

Write-Host "Verified vendored WebView2 SDK $sdkVersion static loader: $loaderPath"
Write-Host "Staged WebView2 SDK $sdkVersion loader probe DLL: $probeLoader"
