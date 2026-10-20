[CmdletBinding()]
param(
  [ValidateSet("x64", "x86")]
  [string]$Architecture = "x64",
  [string]$RuntimeDirectory = (Join-Path $PSScriptRoot "..\..\src-tauri\webview2-fixed-runtime"),
  [string]$LoaderPath = (Join-Path ([System.IO.Path]::GetTempPath()) "dbx-win7-webview2-loader-probe\WebView2Loader.dll"),
  [string]$ExpectedVersion = "109.0.1518.78"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimeDirectory = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$runtimeExecutable = Join-Path $runtimeDirectory "msedgewebview2.exe"
if (!(Test-Path -LiteralPath $runtimeExecutable -PathType Leaf)) {
  throw "WebView2 fixed runtime executable does not exist: $runtimeExecutable"
}

$loaderPath = (Resolve-Path -LiteralPath $LoaderPath).Path

# The DllImport probe runs in-process, so an x86 fixed runtime must be probed
# with the x86 WebView2Loader.dll from SDK 1.0.902.49 inside 32-bit PowerShell.
# Refuse loudly instead of falling back to the wrong architecture.
function Get-PeMachine {
  param([Parameter(Mandatory = $true)][string]$Path)
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $reader = New-Object System.IO.BinaryReader($stream)
    if ($reader.ReadUInt16() -ne 0x5A4D) {
      throw "File is not a PE image: $Path"
    }
    $null = $reader.BaseStream.Seek(0x3C, [System.IO.SeekOrigin]::Begin)
    $peOffset = $reader.ReadUInt32()
    $null = $reader.BaseStream.Seek($peOffset + 4, [System.IO.SeekOrigin]::Begin)
    $reader.ReadUInt16()
  } finally {
    $stream.Dispose()
  }
}

if ($Architecture -eq "x86") {
  if ([System.IntPtr]::Size -ne 4) {
    throw "The x86 WebView2 runtime probe must run in 32-bit PowerShell: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
  }
  $loaderMachine = Get-PeMachine -Path $loaderPath
  if ($loaderMachine -ne 0x014C) {
    throw "x86 probe needs the x86 WebView2Loader.dll from SDK 1.0.902.49 via -LoaderPath; $loaderPath is machine 0x$($loaderMachine.ToString('X4'))."
  }
  $runtimeMachine = Get-PeMachine -Path $runtimeExecutable
  if ($runtimeMachine -ne 0x014C) {
    throw "Expected an x86 fixed runtime but $runtimeExecutable is machine 0x$($runtimeMachine.ToString('X4'))."
  }
}

$escapedLoaderPath = $loaderPath.Replace('"', '""')
$source = @"
using System;
using System.Runtime.InteropServices;

public static class DbxWebView2LoaderProbe
{
    [DllImport(@"$escapedLoaderPath", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern int GetAvailableCoreWebView2BrowserVersionString(
        string browserExecutableFolder,
        out IntPtr versionInfo);
}
"@

Add-Type -TypeDefinition $source -Language CSharp
$versionPointer = [IntPtr]::Zero
$result = [DbxWebView2LoaderProbe]::GetAvailableCoreWebView2BrowserVersionString(
  $runtimeDirectory,
  [ref]$versionPointer
)
if ($result -ne 0) {
  throw "WebView2 loader failed to recognize fixed runtime at $runtimeDirectory (HRESULT 0x$($result.ToString('X8')))."
}
if ($versionPointer -eq [IntPtr]::Zero) {
  throw "WebView2 loader returned an empty version pointer for $runtimeDirectory."
}

try {
  $version = [Runtime.InteropServices.Marshal]::PtrToStringUni($versionPointer)
}
finally {
  [Runtime.InteropServices.Marshal]::FreeCoTaskMem($versionPointer)
}

if ([string]::IsNullOrWhiteSpace($version) -or !$version.StartsWith($ExpectedVersion)) {
  throw "Expected WebView2 fixed runtime $ExpectedVersion, detected '$version'."
}

Write-Host "WebView2 fixed runtime probe passed: loader=$loaderPath runtime=$runtimeDirectory version=$version"
