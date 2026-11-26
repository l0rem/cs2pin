# cs2pin

Windows tray app that keeps `cs2.exe` on logical CPUs 2,4,6,8,10,12,14 (mask `0x5554`, one thread per core on
cores 1-7, never CPU 0). It replaces the Process Lasso rule `DefaultAffinitiesEx=cs2.exe,0,2;4;6;8;10;12;14`.

- Scope is fixed: the pin, a tray icon, an on/off toggle (`HKCU\Software\cs2pin\Enabled`), exit. No config file,
  other rules, updater or network. Keep it that way.
- One file, `src/main.rs`, `windows-sys` only. Every second it lists processes and sets the affinity once per new
  cs2.exe PID. Turning it off resets running cs2 to all CPUs. `supported_cpu()` only allows CPUs where the mask is
  right (8 same-class cores × 2 threads numbered 2k/2k+1); keep that check if the mask ever changes.
- Build: `cargo build --release` on Windows, or `./build.sh` on macOS/Linux (cargo-xwin, MSVC target, static CRT)
  → `windows/cs2pin.exe`. Before committing: `cargo fmt` and `cargo clippy --release` with no warnings (CI checks).
- Install: `windows/install.ps1` from an elevated PowerShell (exe to `C:\Program Files\cs2pin`, never a user-writable
  folder because the logon task `cs2pin` runs it elevated; tray icon promoted via `HKCU\Control Panel\NotifyIconSettings`).
  `uninstall.ps1` removes everything, `check.ps1` prints cs2's current affinity.
- Test on a real Windows desktop with the real cs2 closed: copy `test/*.ps1` to a folder and run `run.ps1` from an
  elevated PowerShell (ssh works). It starts a stand-in cs2.exe (a ping.exe copy in
  `%LOCALAPPDATA%\cs2pin-standin`; some setups block exes in `%TEMP%`) non-elevated in the desktop session and
  checks: pinned to `0x5554`, toggle off → `0xFFFF`, on → `0x5554`, a new cs2 gets pinned. The menu is opened from
  a non-elevated process (like Explorer) and clicked with a real mouse click, so the cursor moves briefly. It
  leaves cs2pin enabled. Delete the folders afterwards.
- Releases: push a `v*` tag; the workflow builds on Windows and attaches the exe, its `.sha256` and the scripts.
