# UI helpers for the tests; dot-source it. Runs in the signed-in session (one-shot scheduled task).
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Threading; using System.Runtime.InteropServices;
public static class UI {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] struct NII { public int cbSize; public IntPtr hWnd; public int uID; public Guid g; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string name);
  [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll", SetLastError=true)] static extern bool PostMessageW(IntPtr h, int msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetMenuStringW(IntPtr m, int id, StringBuilder s, int n, int flags);
  [DllImport("user32.dll")] static extern int GetMenuState(IntPtr m, int id, int flags);
  [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr m);
  [DllImport("user32.dll")] static extern bool GetMenuItemRect(IntPtr h, IntPtr m, int pos, out RECT r);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern void mouse_event(int f, int x, int y, int d, IntPtr e);
  [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("shell32.dll")] static extern int Shell_NotifyIconGetRect(ref NII id, out RECT r);
  public static void DpiAware() { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
  public static IntPtr App() { return FindWindowW("cs2pin", null); }
  public static string IconRect() { var id = new NII(); id.cbSize = Marshal.SizeOf(id); id.hWnd = App(); id.uID = 1; RECT r;
    int hr = Shell_NotifyIconGetRect(ref id, out r); return hr != 0 ? "hr=0x" + hr.ToString("X") : r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T); }
  // What Explorer sends on a left click (cs2pin uses the classic callback: lParam = mouse message).
  public static string PostClick() { bool ok = PostMessageW(App(), 0x8001, new IntPtr(1), new IntPtr(0x202));
    return ok ? "posted" : "PostMessage failed, error " + Marshal.GetLastWin32Error(); }
  public static IntPtr MenuWindow() { for (int i = 0; i < 30; i++) { var w = FindWindowW("#32768", null);
    if (w != IntPtr.Zero && IsWindowVisible(w)) return w; Thread.Sleep(100); } return IntPtr.Zero; }
  public static IntPtr MenuOf(IntPtr w) { return SendMessageW(w, 0x01E1, IntPtr.Zero, IntPtr.Zero); }
  public static string Items(IntPtr m) { var sb = new StringBuilder(); int n = GetMenuItemCount(m);
    for (int i = 0; i < n; i++) { var s = new StringBuilder(128); GetMenuStringW(m, i, s, 128, 0x400);
      sb.Append("  [" + (((GetMenuState(m, i, 0x400) & 8) != 0) ? "x" : " ") + "] " + s + "\n"); } return sb.ToString(); }
  public static void Click(IntPtr w, IntPtr m, int pos) { RECT r; GetMenuItemRect(w, m, pos, out r); POINT p; GetCursorPos(out p);
    SetCursorPos((r.L + r.R) / 2, (r.T + r.B) / 2); Thread.Sleep(150);
    mouse_event(2, 0, 0, 0, IntPtr.Zero); Thread.Sleep(50); mouse_event(4, 0, 0, 0, IntPtr.Zero); Thread.Sleep(150);
    SetCursorPos(p.X, p.Y); }
  public static void Escape(IntPtr w) { PostMessageW(w, 0x0100, new IntPtr(0x1B), IntPtr.Zero); }
}
"@
[UI]::DpiAware()
