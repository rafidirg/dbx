import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const win7StaticSha256 = {
  x64: "aa5c26670f1b18d0fa2a56ac3f1ae30110c332a8bfbd555a7be3e548d1b0da3d",
  x86: "328b573a4d342007078140eb7fa4fb3aeaba804e29dae1361c9733b115580ad2",
};
const win7DllSha256 = {
  x64: "fdf978ba706578b05967d7f0181f462147864a5aa74f36016a62cb3d3dbe6909",
  x86: "49c0650616eadfa63394558cd1d3ed9f64918d5ed38ab3ef32ad0249283df0ef",
};

function sha256(url) {
  return createHash("sha256").update(readFileSync(url)).digest("hex");
}

// A replaced loader once shipped a binary that failed on Server 2012 R2. Pin the
// committed bytes so a PR cannot swap them without an explicit hash update.
test("the vendored Windows 7 WebView2 loaders match the pinned SHA256", () => {
  for (const arch of ["x64", "x86"]) {
    assert.equal(sha256(new URL(`vendor/webview2-com-sys/win7/${arch}/WebView2LoaderStatic.lib`, root)), win7StaticSha256[arch], arch);
    assert.equal(sha256(new URL(`vendor/webview2-com-sys/win7/${arch}/WebView2Loader.dll`, root)), win7DllSha256[arch], arch);
  }
});

