#!/bin/bash
# Cross-compile cs2pin.exe for Windows x64 from macOS or Linux with cargo-xwin (needs LLVM + lld on PATH;
# Homebrew's are picked up automatically). On Windows just run `cargo build --release`.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
export XWIN_ACCEPT_LICENSE=1
cargo xwin build --release --locked --target x86_64-pc-windows-msvc
cp target/x86_64-pc-windows-msvc/release/cs2pin.exe windows/cs2pin.exe
ls -l windows/cs2pin.exe && shasum -a 256 windows/cs2pin.exe
