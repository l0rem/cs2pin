# cs2pin

A tiny Windows tray app that keeps Counter-Strike 2 off CPU 0. It pins `cs2.exe` to one thread per core on
cores 1–7 (logical CPUs 2, 4, 6, 8, 10, 12, 14) and does nothing else. It replaces the one Process Lasso rule
that does this, so you don't need Process Lasso installed (or updating) just for that.

It's a single 220 KB exe in Rust for Windows 10/11 (x64), with no installer program, service, config file,
updater, network access or telemetry. A short PowerShell script sets up the autostart.

## What it does

- Once a second it looks for `cs2.exe`. When a new one starts, it sets its CPU affinity once, the same way
  Process Lasso's "default CPU affinity" rule does (`cs2.exe,0,2;4;6;8;10;12;14`). If you change the affinity
  yourself afterwards, cs2pin leaves it alone until the game restarts.
- Tray icon: a green dot when it's on, a grey one when it's off. Click it (left or right) for a menu with
  **Keep CS2 off CPU 0** (on/off, remembered across restarts) and **Exit**. Turning it off gives a running cs2
  all CPUs back straight away. **Exit** just quits; a running cs2 keeps its affinity until it restarts. Hover
  over the icon to see what it's doing.
- It only pins on **8-core / 16-thread CPUs with SMT on** where every core is the same kind, such as the Ryzen 7
  9800X3D, 7800X3D, 9700X and 7700X. On anything else (other core counts, SMT off, Intel CPUs with P- and
  E-cores) it doesn't touch cs2 and the tooltip says why, because those CPU numbers would point at the wrong
  cores.

## Why

Windows tends to run more interrupts and background work on CPU 0, and CS2 is sensitive to frame-time spikes.
Measured on a Ryzen 7 9800X3D with an RTX 4080 Super (Dust2 FPS benchmark map, 111 s camera flight, PresentMon,
3 passes each):

| CS2 affinity | avg fps | 1% low |
|---|---|---|
| all 16 threads (Windows default) | 772 | 262 |
| threads 2–15 (only core 0 excluded) | 816 | 295 |
| **2, 4, 6, 8, 10, 12, 14 (what cs2pin sets)** | **830** | **310** |

The first two rows were measured on one day, the last one the next day against a same-day re-run of the
middle row (815 / 297). Other CPUs, game builds and setups will differ. Try it and compare your own numbers.

## Install

1. From [Releases](https://github.com/l0rem/cs2pin/releases), download `cs2pin.exe` and `install.ps1` into the
   same folder.
2. Open PowerShell **as administrator** in that folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

It copies the exe to `C:\Program Files\cs2pin`, adds a scheduled task `cs2pin` that starts it when you log
in, starts it now, and makes the tray icon always visible on the taskbar. The task runs it with admin rights
(without a UAC prompt) so it can change cs2's affinity no matter how the game was started; Process Lasso's
service runs elevated for the same reason. Because it runs elevated, the exe lives in Program Files, where
only admins can change it. The exe isn't code-signed.

To check it worked, start CS2 and run `check.ps1` (also in Releases). It should print `affinity 0x5554`.

If you use Process Lasso, remove its cs2 rule (or Process Lasso) so the two don't both manage cs2.

## Uninstall

Run `uninstall.ps1` (from Releases) as administrator. It stops cs2pin and removes the task, the exe and its
one registry value (`HKCU\Software\cs2pin`). A running cs2 keeps its current affinity until it restarts.

## Anti-cheat

cs2pin calls one documented Windows API on cs2 (`SetProcessAffinityMask`), the same thing Task Manager's
"Set affinity" and Process Lasso do. It doesn't read or write game memory, inject anything or hook anything.
That said, neither Valve nor FACEIT has said anything about tools like this, so use it at your own risk. If an
anti-cheat blocks it, the tooltip shows "couldn't pin cs2 (error …)".

## Resource use

One thread that wakes once a second, takes a process list snapshot and goes back to sleep. Measured with
`Get-Process` on Windows 11 25H2 (Ryzen 7 9800X3D) over 9 minutes with CS2 closed:

| | |
|---|---|
| CPU time | 1.3 s in 9 minutes: about 2.5 ms per check, 0.25% of one thread |
| Private bytes | 1.4 MB |
| Working set | 7.5 MB |
| Handles | 126 (mostly shell32's, loaded for the tray icon) |

## Build

On Windows with [Rust](https://rustup.rs) (MSVC toolchain):

```sh
cargo build --release     # → target/release/cs2pin.exe
```

From macOS or Linux, `./build.sh` cross-compiles with [cargo-xwin](https://github.com/rust-cross/cargo-xwin)
(needs LLVM and lld) into `windows/cs2pin.exe`. Tagged releases are built by
[the workflow](.github/workflows/build.yml), which also publishes the SHA-256. `test/` has the PowerShell
end-to-end test (see [AGENTS.md](AGENTS.md)).

## License

MIT
