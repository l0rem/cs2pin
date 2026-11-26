//! cs2pin: tray app that keeps cs2.exe on logical CPUs 2,4,6,8,10,12,14 (one thread per core on
//! cores 1-7, never CPU 0) on 8-core/16-thread CPUs. Same as the Process Lasso rule
//! `DefaultAffinitiesEx=cs2.exe,0,2;4;6;8;10;12;14`. Polls once a second and sets the affinity once per
//! cs2.exe process, like Lasso's default affinity does.
#![windows_subsystem = "windows"]

use std::cell::RefCell;
use std::collections::HashSet;
use std::mem::{size_of, zeroed};
use std::ptr::{null, null_mut};
use std::sync::atomic::{AtomicU32, Ordering};

use windows_sys::core::w;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::Diagnostics::ToolHelp::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Registry::*;
use windows_sys::Win32::System::SystemInformation::*;
use windows_sys::Win32::System::Threading::*;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

/// CPUs 2,4,6,8,10,12,14: the first thread of cores 1-7. Only valid on the CPU layout `supported_cpu` checks.
const PIN: usize = 0x5554;
const WM_TRAY: u32 = WM_APP + 1;
const KEY: *const u16 = w!("Software\\cs2pin");

static TASKBAR_CREATED: AtomicU32 = AtomicU32::new(0);

struct State {
    enabled: bool,
    supported: bool,
    sys_mask: usize,
    shown: bool,
    seen: HashSet<u32>,
    tip: String,
    icons: [HICON; 2], // [off, on]
}

thread_local! {
    static ST: RefCell<State> = RefCell::new(State {
        enabled: true, supported: false, sys_mask: 0, shown: false, seen: HashSet::new(), tip: String::new(),
        icons: [null_mut(); 2],
    });
}

fn main() {
    unsafe {
        CreateMutexW(null(), 0, w!("Local\\cs2pin"));
        if GetLastError() == ERROR_ALREADY_EXISTS {
            return;
        }
        let (mut proc_mask, mut sys_mask) = (0usize, 0usize);
        GetProcessAffinityMask(GetCurrentProcess(), &mut proc_mask, &mut sys_mask);
        ST.with_borrow_mut(|s| {
            s.enabled = load_enabled();
            s.supported = supported_cpu();
            s.sys_mask = sys_mask;
            s.icons = [dot(0x7F7F7F), dot(0x22C55E)];
        });
        TASKBAR_CREATED.store(
            RegisterWindowMessageW(w!("TaskbarCreated")),
            Ordering::Relaxed,
        );

        let hinst = GetModuleHandleW(null());
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wndproc),
            hInstance: hinst,
            lpszClassName: w!("cs2pin"),
            ..zeroed()
        };
        RegisterClassW(&wc);
        // A hidden top-level window (not message-only) so it receives the TaskbarCreated broadcast.
        let hwnd = CreateWindowExW(
            0,
            w!("cs2pin"),
            w!("cs2pin"),
            0,
            0,
            0,
            0,
            0,
            null_mut(),
            null_mut(),
            hinst,
            null(),
        );
        // We run elevated (scheduled task); let the non-elevated Explorer reach us anyway.
        ChangeWindowMessageFilterEx(hwnd, WM_TRAY, MSGFLT_ALLOW, null_mut());
        ChangeWindowMessageFilterEx(
            hwnd,
            TASKBAR_CREATED.load(Ordering::Relaxed),
            MSGFLT_ALLOW,
            null_mut(),
        );
        SetTimer(hwnd, 1, 1000, None);
        tick(hwnd);

        let mut msg: MSG = zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        WM_TIMER => tick(hwnd),
        WM_TRAY if matches!(lp as u32, WM_LBUTTONUP | WM_RBUTTONUP) => menu(hwnd),
        WM_DESTROY => {
            notify(hwnd, NIM_DELETE);
            PostQuitMessage(0);
        }
        m if m != 0 && m == TASKBAR_CREATED.load(Ordering::Relaxed) => {
            // Explorer restarted: the icon is gone, add it again.
            ST.with_borrow_mut(|s| s.shown = false);
            tick(hwnd);
        }
        _ => return DefWindowProcW(hwnd, msg, wp, lp),
    }
    0
}

/// Once a second: pin new cs2.exe processes and keep the tray icon/tooltip current.
fn tick(hwnd: HWND) {
    let (enabled, supported) = ST.with_borrow(|s| (s.enabled, s.supported));
    let tip = if !enabled {
        "cs2pin: off".to_string()
    } else if !supported {
        "cs2pin: not pinning, made for 8-core/16-thread CPUs (SMT on)".to_string()
    } else {
        let pids = cs2_pids();
        let new: Vec<u32> = ST.with_borrow_mut(|s| {
            s.seen.retain(|p| pids.contains(p));
            pids.iter().copied().filter(|p| s.seen.insert(*p)).collect()
        });
        let mut tip = ST.with_borrow(|s| s.tip.clone());
        for pid in new {
            tip = match set_affinity(pid, PIN) {
                Ok(()) => "cs2pin: on, cs2 on CPUs 2,4,6,8,10,12,14".to_string(),
                Err(e) => {
                    ST.with_borrow_mut(|s| s.seen.remove(&pid)); // try again next second
                    format!("cs2pin: on, couldn't pin cs2 (error {e})")
                }
            };
        }
        if pids.is_empty() {
            tip = "cs2pin: on, waiting for cs2".to_string();
        }
        tip
    };
    let (changed, shown) = ST.with_borrow_mut(|s| {
        let changed = s.tip != tip;
        s.tip = tip;
        (changed, s.shown)
    });
    if !shown {
        // At logon the taskbar may not be ready yet; keep trying.
        let ok = notify(hwnd, NIM_ADD);
        ST.with_borrow_mut(|s| s.shown = ok);
    } else if changed {
        notify(hwnd, NIM_MODIFY);
    }
}

fn menu(hwnd: HWND) {
    let enabled = ST.with_borrow(|s| s.enabled);
    unsafe {
        let m = CreatePopupMenu();
        AppendMenuW(
            m,
            MF_STRING | if enabled { MF_CHECKED } else { MF_UNCHECKED },
            1,
            w!("Keep CS2 off CPU 0"),
        );
        AppendMenuW(m, MF_STRING, 2, w!("Exit"));
        let mut pt: POINT = zeroed();
        GetCursorPos(&mut pt);
        SetForegroundWindow(hwnd); // otherwise the menu doesn't close when clicking elsewhere
        let cmd = TrackPopupMenu(
            m,
            TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
            pt.x,
            pt.y,
            0,
            hwnd,
            null(),
        );
        DestroyMenu(m);
        match cmd {
            1 => toggle(hwnd),
            2 => {
                DestroyWindow(hwnd);
            }
            _ => {}
        }
    }
}

fn toggle(hwnd: HWND) {
    let (enabled, supported, sys_mask) = ST.with_borrow_mut(|s| {
        s.enabled = !s.enabled;
        s.seen.clear();
        (s.enabled, s.supported, s.sys_mask)
    });
    save_enabled(enabled);
    if !enabled && supported {
        // Off means cs2 gets every CPU again, right away.
        for pid in cs2_pids() {
            let _ = set_affinity(pid, sys_mask);
        }
    }
    ST.with_borrow_mut(|s| s.tip.clear()); // force an icon + tooltip update
    tick(hwnd);
}

/// True when PIN is right for this machine: 8 cores of the same kind (no P/E-core mix), each with two
/// threads numbered 2k and 2k+1, all in processor group 0. That is how Windows numbers e.g. a Ryzen 7
/// 9800X3D/7800X3D with SMT on.
fn supported_cpu() -> bool {
    let mut len = 0u32;
    unsafe { GetLogicalProcessorInformationEx(RelationProcessorCore, null_mut(), &mut len) };
    let mut buf = vec![0u64; (len as usize).div_ceil(8)]; // u64s keep the records aligned
    if unsafe {
        GetLogicalProcessorInformationEx(RelationProcessorCore, buf.as_mut_ptr().cast(), &mut len)
    } == 0
    {
        return false;
    }
    let (mut cores, mut classes, mut off) = (Vec::new(), HashSet::new(), 0usize);
    while off < len as usize {
        // SAFETY: Windows fills `len` bytes with back-to-back records, each `Size` bytes long.
        let rec = unsafe {
            &*(buf.as_ptr().cast::<u8>().add(off) as *const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)
        };
        let core = unsafe { &rec.Anonymous.Processor };
        let g = core.GroupMask[0];
        cores.push((g.Group, g.Mask));
        classes.insert(core.EfficiencyClass);
        off += rec.Size as usize;
    }
    cores.sort_unstable();
    cores.len() == 8
        && classes.len() == 1
        && cores
            .iter()
            .enumerate()
            .all(|(k, &c)| c == (0, 0b11 << (2 * k)))
}

fn cs2_pids() -> Vec<u32> {
    let mut pids = Vec::new();
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap == INVALID_HANDLE_VALUE {
            return pids;
        }
        let mut e: PROCESSENTRY32W = zeroed();
        e.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        let mut ok = Process32FirstW(snap, &mut e);
        while ok != 0 {
            let len = e
                .szExeFile
                .iter()
                .position(|&c| c == 0)
                .unwrap_or(e.szExeFile.len());
            if String::from_utf16_lossy(&e.szExeFile[..len]).eq_ignore_ascii_case("cs2.exe") {
                pids.push(e.th32ProcessID);
            }
            ok = Process32NextW(snap, &mut e);
        }
        CloseHandle(snap);
    }
    pids
}

fn set_affinity(pid: u32, mask: usize) -> Result<(), u32> {
    unsafe {
        let h = OpenProcess(PROCESS_SET_INFORMATION, 0, pid);
        if h.is_null() {
            return Err(GetLastError());
        }
        let ok = SetProcessAffinityMask(h, mask);
        let err = GetLastError();
        CloseHandle(h);
        if ok != 0 {
            Ok(())
        } else {
            Err(err)
        }
    }
}

fn notify(hwnd: HWND, msg: u32) -> bool {
    let (icon, tip) = ST.with_borrow(|s| (s.icons[s.enabled as usize], s.tip.clone()));
    unsafe {
        let mut nid: NOTIFYICONDATAW = zeroed();
        nid.cbSize = size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        nid.uCallbackMessage = WM_TRAY;
        nid.hIcon = icon;
        for (d, c) in nid.szTip.iter_mut().zip(tip.encode_utf16().take(127)) {
            *d = c;
        }
        Shell_NotifyIconW(msg, &nid) != 0
    }
}

/// A filled circle in the given 0xRRGGBB colour, at the small-icon size.
fn dot(rgb: u32) -> HICON {
    let s = unsafe { GetSystemMetrics(SM_CXSMICON) }.max(16);
    let (c, r) = (s as f32 / 2.0, s as f32 / 2.0 - 1.5);
    let mut px = Vec::with_capacity((s * s) as usize);
    for y in 0..s {
        for x in 0..s {
            let d = ((x as f32 + 0.5 - c).powi(2) + (y as f32 + 0.5 - c).powi(2)).sqrt();
            let a = ((r - d + 0.5).clamp(0.0, 1.0) * 255.0) as u32;
            px.push(a << 24 | rgb);
        }
    }
    let and = vec![0u8; (s * s) as usize]; // ignored when the colour bitmap has alpha; oversized on purpose
    unsafe {
        CreateIcon(
            null_mut(),
            s,
            s,
            1,
            32,
            and.as_ptr(),
            px.as_ptr() as *const u8,
        )
    }
}

fn load_enabled() -> bool {
    let (mut v, mut n) = (1u32, 4u32);
    unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            KEY,
            w!("Enabled"),
            RRF_RT_REG_DWORD,
            null_mut(),
            &mut v as *mut u32 as _,
            &mut n,
        );
    }
    v != 0
}

fn save_enabled(on: bool) {
    let v = on as u32;
    unsafe {
        RegSetKeyValueW(
            HKEY_CURRENT_USER,
            KEY,
            w!("Enabled"),
            REG_DWORD,
            &v as *const u32 as _,
            4,
        );
    }
}
