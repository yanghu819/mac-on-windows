using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace TFD
{
    public class DragApp : Form
    {
        [StructLayout(LayoutKind.Sequential)]
        struct RAWINPUTDEVICE { public ushort usUsagePage; public ushort usUsage; public uint dwFlags; public IntPtr hwndTarget; }

        [StructLayout(LayoutKind.Sequential)]
        struct RAWINPUTHEADER { public uint dwType; public uint dwSize; public IntPtr hDevice; public IntPtr wParam; }

        [StructLayout(LayoutKind.Sequential)]
        struct RAWHID { public uint dwSizeHid; public uint dwCount; }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; }

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] p, uint n, uint sz);
        [DllImport("user32.dll")]
        static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr p, ref uint sz, uint hdr);
        [DllImport("user32.dll")]
        static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")]
        static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")]
        static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
        [DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        const uint RID_INPUT = 0x10000003;
        const uint LEFTDOWN = 0x0002;
        const uint LEFTUP = 0x0004;

        // 可通过 tfd.ini 调整
        double sensitivity = 0.55;   // 触摸板单位 -> 屏幕像素
        double startThreshold = 60;  // 三指移动超过这个距离才开始拖

        NotifyIcon tray;
        bool enabled = true;

        bool armed = false;
        bool dragging = false;
        double startCx, startCy;
        double fracX, fracY;
        Dictionary<uint, double[]> prev = new Dictionary<uint, double[]>();

        string logPath;
        StreamWriter log;

        public DragApp()
        {
            SetProcessDPIAware();

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            logPath = Path.Combine(baseDir, "tfd.log");
            try { log = new StreamWriter(logPath, false); log.AutoFlush = true; } catch { log = null; }

            LoadIni(Path.Combine(baseDir, "tfd.ini"));

            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-30000, -30000);
            Size = new Size(10, 10);

            tray = new NotifyIcon();
            tray.Icon = SystemIcons.Application;
            tray.Text = "三指拖拽（三指按住移动＝拖选）";
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("启用 / 暂停", null, delegate { Toggle(); });
            menu.Items.Add("退出", null, delegate { Quit(); });
            tray.ContextMenuStrip = menu;
            tray.Visible = true;

            RAWINPUTDEVICE dev = new RAWINPUTDEVICE();
            dev.usUsagePage = 0x0D;
            dev.usUsage = 0x05;
            dev.dwFlags = 0x00000100;
            dev.hwndTarget = this.Handle;
            bool ok = RegisterRawInputDevices(new RAWINPUTDEVICE[] { dev }, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));

            Log("started register=" + ok + " sensitivity=" + sensitivity + " threshold=" + startThreshold);
        }

        void LoadIni(string path)
        {
            try
            {
                if (!File.Exists(path)) return;
                foreach (string raw in File.ReadAllLines(path))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;
                    string k = line.Substring(0, eq).Trim().ToLowerInvariant();
                    string v = line.Substring(eq + 1).Trim();
                    double d;
                    if (!double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) continue;
                    if (k == "sensitivity") sensitivity = d;
                    else if (k == "threshold") startThreshold = d;
                }
            }
            catch { }
        }

        void Toggle()
        {
            enabled = !enabled;
            if (!enabled && dragging) EndDrag("paused");
            tray.Text = enabled ? "三指拖拽（已启用）" : "三指拖拽（已暂停）";
            Log("enabled=" + enabled);
        }

        void Quit()
        {
            if (dragging) EndDrag("quit");
            tray.Visible = false;
            Log("exit");
            Application.Exit();
        }

        void Log(string s)
        {
            if (log == null) return;
            try { log.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " " + s); } catch { }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x00FF)
            {
                try { HandleInput(m.LParam); } catch (Exception e) { Log("ERR " + e.Message); }
            }
            base.WndProc(ref m);
        }

        void HandleInput(IntPtr lParam)
        {
            uint size = 0;
            uint hdr = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            GetRawInputData(lParam, RID_INPUT, IntPtr.Zero, ref size, hdr);
            if (size == 0) return;

            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try
            {
                uint read = GetRawInputData(lParam, RID_INPUT, buf, ref size, hdr);
                if (read == 0 || read == 0xFFFFFFFF) return;

                RAWINPUTHEADER h = (RAWINPUTHEADER)Marshal.PtrToStructure(buf, typeof(RAWINPUTHEADER));
                if (h.dwType != 2) return;

                IntPtr p = (IntPtr)((long)buf + hdr);
                RAWHID hid = (RAWHID)Marshal.PtrToStructure(p, typeof(RAWHID));
                if (hid.dwSizeHid != 112) return;

                byte[] data = new byte[112];
                Marshal.Copy((IntPtr)((long)p + Marshal.SizeOf(typeof(RAWHID))), data, 0, 112);
                if (data[0] != 0x05) return;

                Process(data);
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        // Magic Trackpad 2/3 (AmtPtp Mt2 descriptor):
        //   [0] ReportID 0x05
        //   [1 + 21*i] 每个触点: flags(bit0=Confidence,bit1=Tip) | ID(4) | X(2) | Y(2) | W(2) | H(2) | P(2) | 6 bytes vendor
        //   [108] ContactCount  [109..110] MechanicalForce  [111] Button
        void Process(byte[] d)
        {
            Dictionary<uint, double[]> cur = new Dictionary<uint, double[]>();
            double sx = 0, sy = 0;
            int n = 0;

            for (int i = 0; i < 5; i++)
            {
                int o = 1 + i * 21;
                byte flags = d[o];
                if ((flags & 0x02) == 0) continue;
                uint id = (uint)(d[o + 1] | (d[o + 2] << 8) | (d[o + 3] << 16) | (d[o + 4] << 24));
                double x = d[o + 5] | (d[o + 6] << 8);
                double y = d[o + 7] | (d[o + 8] << 8);
                cur[id] = new double[] { x, y };
                sx += x; sy += y; n++;
            }

            if (!enabled)
            {
                if (dragging) EndDrag("disabled");
                prev = cur;
                return;
            }

            if (n == 0)
            {
                if (dragging) EndDrag("all up");
                armed = false;
                prev = cur;
                return;
            }

            double cx = sx / n, cy = sy / n;

            if (dragging)
            {
                MoveByAverageDelta(cur);
                prev = cur;
                return;
            }

            if (n >= 3)
            {
                if (!armed)
                {
                    armed = true;
                    startCx = cx; startCy = cy;
                    Log("armed n=" + n);
                }
                else
                {
                    double dx = cx - startCx, dy = cy - startCy;
                    if (dx * dx + dy * dy > startThreshold * startThreshold)
                    {
                        armed = false;
                        dragging = true;
                        fracX = 0; fracY = 0;
                        mouse_event(LEFTDOWN, 0, 0, 0, IntPtr.Zero);
                        Log("drag start n=" + n);
                    }
                }
            }
            else
            {
                armed = false;
            }

            prev = cur;
        }

        void MoveByAverageDelta(Dictionary<uint, double[]> cur)
        {
            double dx = 0, dy = 0;
            int matched = 0;
            foreach (KeyValuePair<uint, double[]> kv in cur)
            {
                double[] old;
                if (prev.TryGetValue(kv.Key, out old))
                {
                    dx += kv.Value[0] - old[0];
                    dy += kv.Value[1] - old[1];
                    matched++;
                }
            }
            if (matched == 0) return;
            MoveCursor(dx / matched, dy / matched);
        }

        void MoveCursor(double dxUnits, double dyUnits)
        {
            double dx = dxUnits * sensitivity + fracX;
            double dy = dyUnits * sensitivity + fracY;
            int ix = (int)dx;
            int iy = (int)dy;
            fracX = dx - ix;
            fracY = dy - iy;
            if (ix == 0 && iy == 0) return;

            POINT p;
            if (!GetCursorPos(out p)) return;
            SetCursorPos(p.X + ix, p.Y + iy);
        }

        void EndDrag(string why)
        {
            dragging = false;
            armed = false;
            mouse_event(LEFTUP, 0, 0, 0, IntPtr.Zero);
            Log("drag end (" + why + ")");
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.Run(new DragApp());
        }
    }
}
