// SH2-CoopMod launcher - authored by MarySue.
// Host or join a session, pick the game folder, change co-op tweaks and characters, pick a theme.
// Also carries the mod's messages between the two PCs over UDP, and the host's save to a player
// who joins from the game's main menu over TCP (same port number).
//
// Build: tools\build_dist.ps1 (uses the C# compiler that ships with Windows, so C# 5 syntax only).
// Screenshots for the README: CoopLauncher.exe --screenshots <folder> [--scale 1.25]
// Testing: CoopLauncher.exe --session <host|join>,<peer ip>[,<port>] starts a session at once, off
// screen, without touching the saved settings; --save-into <folder> puts a fetched save and a
// launcher.log there instead of in the game's save folder.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace SH2CoopMod
{
    static class Native
    {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Native.SetProcessDPIAware();
            string shotDir = null;
            float forcedScale = 0f;
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (args[i] == "--screenshots") shotDir = args[i + 1];
                if (args[i] == "--scale") float.TryParse(args[i + 1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out forcedScale);
                if (args[i] == "--session") MainForm.TestSession = args[i + 1];
                if (args[i] == "--save-into") MainForm.TestSaveDir = args[i + 1];
            }
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Theme.Scale = g.DpiX / 96f;
            if (forcedScale > 0.5f) Theme.Scale = forcedScale;

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (shotDir != null) { MainForm.TakeScreenshots(shotDir); return; }
            Application.Run(new MainForm(false));
        }
    }

    // ------------------------------------------------------------------ theme

    class Palette
    {
        public string Key, Name;
        public Color Bg, Side, Card, Border, Text, Muted, Accent, OnAccent, Input;
        public Palette(string key, string name, int bg, int side, int card, int border, int text, int muted, int accent, int onAccent, int input)
        {
            Key = key; Name = name;
            Bg = C(bg); Side = C(side); Card = C(card); Border = C(border); Text = C(text); Muted = C(muted);
            Accent = C(accent); OnAccent = C(onAccent); Input = C(input);
        }
        static Color C(int rgb) { return Color.FromArgb(255, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
    }

    interface IThemed { void ApplyTheme(); }

    static class Theme
    {
        public static float Scale = 1f;
        public static readonly Palette[] All =
        {
            new Palette("fog",   "Fog",   0x14171A, 0x0F1113, 0x1C2024, 0x2C323A, 0xE6E8EA, 0x8A929B, 0x7FB2C8, 0x0B1114, 0x111417),
            new Palette("rust",  "Rust",  0x171311, 0x110E0C, 0x201A17, 0x3A2E27, 0xEDE6E1, 0x9C8F86, 0xD9703C, 0x1A0D06, 0x130F0D),
            new Palette("moss",  "Moss",  0x121613, 0x0D100E, 0x1A201B, 0x2B352D, 0xE3E9E4, 0x88958A, 0x8FC27A, 0x0B1408, 0x0F1310),
            new Palette("paper", "Paper", 0xF3F1EC, 0xE8E5DE, 0xFFFFFF, 0xD8D3C8, 0x22201C, 0x6F6A60, 0xB4472B, 0xFFFFFF, 0xFAF9F6),
        };
        public static Palette Cur = All[0];
        public static readonly Color Good = Color.FromArgb(95, 191, 122);
        public static readonly Color Warn = Color.FromArgb(217, 164, 65);
        public static readonly Color Bad = Color.FromArgb(217, 96, 79);

        public static int D(int v) { return (int)Math.Round(v * Scale); }
        public static float Df(float v) { return v * Scale; }

        static readonly Dictionary<string, Font> fonts = new Dictionary<string, Font>();
        public static Font F(float px, bool bold) { return Get(bold ? "Segoe UI Semibold" : "Segoe UI", px); }
        public static Font Mono(float px) { return Get("Consolas", px); }
        static Font Get(string family, float px)
        {
            string key = family + "|" + px.ToString(System.Globalization.CultureInfo.InvariantCulture);
            Font f;
            if (!fonts.TryGetValue(key, out f))
            {
                f = new Font(family, px * Scale, FontStyle.Regular, GraphicsUnit.Pixel);
                fonts[key] = f;
            }
            return f;
        }

        public static Palette Find(string key)
        {
            foreach (Palette p in All) if (p.Key == key) return p;
            return All[0];
        }

        public static Color Mix(Color a, Color b, float t)
        {
            return Color.FromArgb(255, (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = rad * 2f;
            if (d > r.Height) d = r.Height;
            if (d > r.Width) d = r.Width;
            if (d < 1f) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void FillRound(Graphics g, RectangleF r, float rad, Color fill, Color border, float borderWidth)
        {
            using (GraphicsPath path = Round(r, rad))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, path);
                if (borderWidth > 0f) using (Pen pen = new Pen(border, borderWidth)) g.DrawPath(pen, path);
            }
        }

        // The app's mark: two figures side by side - you and the other player.
        public static void DrawMark(Graphics g, RectangleF r, Color front, Color back)
        {
            float s = r.Height;
            Figure(g, r.X + s * 0.40f, r.Y, s, back);
            Figure(g, r.X, r.Y + s * 0.06f, s * 0.94f, front);
        }
        static void Figure(Graphics g, float x, float y, float s, Color c)
        {
            using (SolidBrush b = new SolidBrush(c))
            {
                float head = s * 0.34f, bodyW = s * 0.60f, bodyH = s * 0.52f;
                g.FillEllipse(b, x + (bodyW - head) / 2f, y, head, head);
                using (GraphicsPath p = Round(new RectangleF(x, y + s - bodyH, bodyW, bodyH + s * 0.3f), bodyW * 0.42f))
                {
                    Region old = g.Clip;
                    g.SetClip(new RectangleF(x - 1, y, bodyW + 2, s), CombineMode.Intersect);
                    g.FillPath(b, p);
                    g.Clip = old;
                }
            }
        }
    }

    // ------------------------------------------------------------------ controls

    enum Role { Text, Muted, Accent, Good, Warn, Bad }

    class Lbl : Label, IThemed
    {
        Role role;
        public Lbl(string text, Role role, float px, bool bold)
        {
            this.role = role;
            Text = text; AutoSize = true; BackColor = Color.Transparent; UseMnemonic = false;
            Font = Theme.F(px, bold);
            ApplyTheme();
        }
        public void SetRole(Role r) { role = r; ApplyTheme(); }
        public void ApplyTheme()
        {
            Palette p = Theme.Cur;
            ForeColor = role == Role.Muted ? p.Muted : role == Role.Accent ? p.Accent : role == Role.Good ? Theme.Good
                : role == Role.Warn ? Theme.Warn : role == Role.Bad ? Theme.Bad : p.Text;
        }
    }

    class Card : Panel, IThemed
    {
        public Card(string title)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            if (title != null)
            {
                Lbl t = new Lbl(title.ToUpperInvariant(), Role.Muted, 10.5f, true);
                t.Location = new Point(Theme.D(16), Theme.D(13));
                Controls.Add(t);
            }
            ApplyTheme();
        }
        public void ApplyTheme() { BackColor = Theme.Cur.Card; Invalidate(); }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Cur.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Theme.FillRound(g, new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f), Theme.Df(10), Theme.Cur.Card, Theme.Cur.Border, 1f);
        }
        protected override void OnPaint(PaintEventArgs e) { }
    }

    class Toggle : Control, IThemed
    {
        bool chk;
        public event EventHandler CheckedChanged;
        public Toggle()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Size = new Size(Theme.D(40), Theme.D(22));
            Cursor = Cursors.Hand;
        }
        public bool Checked
        {
            get { return chk; }
            set { if (chk == value) return; chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        }
        public void ApplyTheme() { Invalidate(); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); if (Enabled) Checked = !Checked; }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette p = Theme.Cur;
            Color bg = Parent != null ? Parent.BackColor : p.Bg;
            g.Clear(bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color track = chk ? p.Accent : p.Border;
            Color knob = chk ? p.OnAccent : p.Muted;
            if (!Enabled) { track = Theme.Mix(track, bg, 0.6f); knob = Theme.Mix(knob, bg, 0.5f); }
            Theme.FillRound(g, new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f), Height / 2f, track, track, 0f);
            float d = Height - Theme.Df(6);
            float x = chk ? Width - Theme.Df(3) - d : Theme.Df(3);
            using (SolidBrush b = new SolidBrush(knob)) g.FillEllipse(b, x, (Height - d) / 2f, d, d);
        }
    }

    enum Kind { Primary, Outline, Nav, Chip, Tile, Min, Close }

    class Btn : Control, IThemed
    {
        public Kind Kind;
        public string Monogram = "";
        bool sel, hover, down;
        public Btn(string text, Kind kind)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Kind = kind; Text = text; Cursor = Cursors.Hand;
        }
        public bool Selected { get { return sel; } set { if (sel != value) { sel = value; Invalidate(); } } }
        public void ApplyTheme() { Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette p = Theme.Cur;
            Color bg = Parent != null ? Parent.BackColor : p.Bg;
            g.Clear(bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
            bool hot = hover && Enabled;
            Rectangle textRect = new Rectangle(0, 0, Width, Height);
            TextFormatFlags flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis;
            Color textColor = p.Text;
            Font font = Theme.F(13f, false);

            switch (Kind)
            {
                case Kind.Primary:
                {
                    Color fill = !Enabled ? Theme.Mix(p.Accent, bg, 0.65f) : down ? Theme.Mix(p.Accent, Color.Black, 0.14f) : hot ? Theme.Mix(p.Accent, Color.White, 0.14f) : p.Accent;
                    Theme.FillRound(g, r, Theme.Df(8), fill, fill, 0f);
                    textColor = Enabled ? p.OnAccent : Theme.Mix(p.OnAccent, fill, 0.4f);
                    font = Theme.F(14f, true);
                    break;
                }
                case Kind.Outline:
                {
                    Color fill = Theme.Mix(bg, p.Text, down ? 0.14f : hot ? 0.09f : 0.04f);
                    Theme.FillRound(g, r, Theme.Df(8), fill, p.Border, 1f);
                    textColor = Enabled ? p.Text : Theme.Mix(p.Muted, bg, 0.4f);
                    break;
                }
                case Kind.Nav:
                {
                    if (sel)
                    {
                        Theme.FillRound(g, r, Theme.Df(8), Theme.Mix(bg, p.Text, 0.08f), bg, 0f);
                        Theme.FillRound(g, new RectangleF(Theme.Df(1), Height / 2f - Theme.Df(8), Theme.Df(3), Theme.Df(16)), Theme.Df(1.5f), p.Accent, p.Accent, 0f);
                        font = Theme.F(13.5f, true);
                    }
                    else
                    {
                        if (hot) Theme.FillRound(g, r, Theme.Df(8), Theme.Mix(bg, p.Text, 0.04f), bg, 0f);
                        textColor = hot ? p.Text : p.Muted;
                        font = Theme.F(13.5f, false);
                    }
                    textRect = new Rectangle(Theme.D(18), 0, Width - Theme.D(18), Height);
                    flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
                    break;
                }
                case Kind.Chip:
                case Kind.Tile:
                {
                    if (sel) Theme.FillRound(g, r, Theme.Df(8), Theme.Mix(bg, p.Accent, 0.16f), p.Accent, Theme.Df(1.5f));
                    else Theme.FillRound(g, r, Theme.Df(8), hot ? Theme.Mix(p.Input, p.Text, 0.05f) : p.Input, p.Border, 1f);
                    textColor = sel || hot ? p.Text : p.Muted;
                    font = Theme.F(13f, sel);
                    if (Kind == Kind.Tile)
                    {
                        float d = Theme.Df(40);
                        RectangleF c = new RectangleF((Width - d) / 2f, Theme.Df(14), d, d);
                        using (SolidBrush b = new SolidBrush(sel ? p.Accent : Theme.Mix(p.Input, p.Text, 0.12f))) g.FillEllipse(b, c);
                        TextRenderer.DrawText(g, Monogram, Theme.F(17f, true), Rectangle.Round(c), sel ? p.OnAccent : p.Text, flags);
                        textRect = new Rectangle(0, Height - Theme.D(34), Width, Theme.D(22));
                    }
                    break;
                }
                case Kind.Min:
                case Kind.Close:
                {
                    Color glyph = p.Muted;
                    if (hot)
                    {
                        Theme.FillRound(g, r, Theme.Df(6), Kind == Kind.Close ? Theme.Bad : Theme.Mix(bg, p.Text, 0.10f), bg, 0f);
                        glyph = Kind == Kind.Close ? Color.White : p.Text;
                    }
                    float cx = Width / 2f, cy = Height / 2f, s = Theme.Df(5);
                    using (Pen pen = new Pen(glyph, Theme.Df(1.3f)))
                    {
                        if (Kind == Kind.Min) g.DrawLine(pen, cx - s, cy, cx + s, cy);
                        else { g.DrawLine(pen, cx - s, cy - s, cx + s, cy + s); g.DrawLine(pen, cx - s, cy + s, cx + s, cy - s); }
                    }
                    return;
                }
            }
            TextRenderer.DrawText(g, Text, font, textRect, textColor, flags);
        }
    }

    class Slider : Control, IThemed
    {
        public int Min = 0, Max = 100, Step = 1;
        int val;
        bool drag;
        public event EventHandler ValueChanged;
        public Slider()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Height = Theme.D(22); Cursor = Cursors.Hand;
        }
        public int Value
        {
            get { return val; }
            set
            {
                int v = Math.Max(Min, Math.Min(Max, value));
                v = Min + (int)Math.Round((v - Min) / (double)Step) * Step;
                if (v > Max) v = Max;
                if (v == val) return;
                val = v; Invalidate();
                if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
            }
        }
        public void ApplyTheme() { Invalidate(); }
        float X0 { get { return Theme.Df(9); } }
        float X1 { get { return Width - Theme.Df(9); } }
        void SetFromX(int x) { if (!Enabled) return; Value = Min + (int)Math.Round((x - X0) / (X1 - X0) * (Max - Min)); }
        protected override void OnMouseDown(MouseEventArgs e) { drag = true; SetFromX(e.X); base.OnMouseDown(e); }
        protected override void OnMouseMove(MouseEventArgs e) { if (drag) SetFromX(e.X); base.OnMouseMove(e); }
        protected override void OnMouseUp(MouseEventArgs e) { drag = false; base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette p = Theme.Cur;
            Color bg = Parent != null ? Parent.BackColor : p.Bg;
            g.Clear(bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float cy = Height / 2f, th = Theme.Df(4);
            float t = Max > Min ? (val - Min) / (float)(Max - Min) : 0f;
            float x = X0 + t * (X1 - X0);
            Color accent = Enabled ? p.Accent : Theme.Mix(p.Accent, bg, 0.6f);
            Theme.FillRound(g, new RectangleF(X0, cy - th / 2f, X1 - X0, th), th / 2f, p.Border, p.Border, 0f);
            if (x > X0 + 1f) Theme.FillRound(g, new RectangleF(X0, cy - th / 2f, x - X0, th), th / 2f, accent, accent, 0f);
            float d = Theme.Df(14);
            using (SolidBrush b = new SolidBrush(Enabled ? p.Text : Theme.Mix(p.Text, bg, 0.5f))) g.FillEllipse(b, x - d / 2f, cy - d / 2f, d, d);
            using (Pen pen = new Pen(bg, Theme.Df(2))) g.DrawEllipse(pen, x - d / 2f, cy - d / 2f, d, d);
        }
    }

    class InputBox : Control, IThemed
    {
        public readonly TextBox Box = new TextBox();
        public event EventHandler Changed;
        public InputBox()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Box.BorderStyle = BorderStyle.None;
            Box.Font = Theme.F(13f, false);
            Controls.Add(Box);
            Height = Theme.D(32);
            Box.GotFocus += delegate { Invalidate(); };
            Box.LostFocus += delegate { Invalidate(); };
            Box.TextChanged += delegate { if (Changed != null) Changed(this, EventArgs.Empty); };
            Cursor = Cursors.IBeam;
            ApplyTheme();
        }
        public string Value { get { return Box.Text; } set { Box.Text = value; } }
        public void ApplyTheme() { Box.BackColor = Theme.Cur.Input; Box.ForeColor = Theme.Cur.Text; Invalidate(); }
        protected override void OnClick(EventArgs e) { Box.Focus(); base.OnClick(e); }
        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Box.SetBounds(Theme.D(10), (Height - Box.PreferredHeight) / 2, Math.Max(10, Width - Theme.D(20)), Box.PreferredHeight);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette p = Theme.Cur;
            g.Clear(Parent != null ? Parent.BackColor : p.Bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Theme.FillRound(g, new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f), Theme.Df(7), p.Input, Box.Focused ? p.Accent : p.Border, 1f);
        }
    }

    class LogBox : TextBox, IThemed
    {
        public LogBox()
        {
            Multiline = true; ReadOnly = true; BorderStyle = BorderStyle.None; ScrollBars = ScrollBars.None;
            Font = Theme.Mono(12f); TabStop = false;
            ApplyTheme();
        }
        public void ApplyTheme() { BackColor = Theme.Cur.Card; ForeColor = Theme.Cur.Muted; }
    }

    class MarkBox : Control, IThemed
    {
        public MarkBox() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true); }
        public void ApplyTheme() { Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette p = Theme.Cur;
            Color bg = Parent != null ? Parent.BackColor : p.Bg;
            g.Clear(bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Theme.DrawMark(g, new RectangleF(0, 0, Width, Height), p.Accent, Theme.Mix(bg, p.Accent, 0.38f));
        }
    }

    // A small preview of a palette, used to pick the theme.
    class ThemeTile : Control, IThemed
    {
        public readonly Palette P;
        bool sel, hover;
        public ThemeTile(Palette p)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            P = p; Cursor = Cursors.Hand;
        }
        public bool Selected { get { return sel; } set { if (sel != value) { sel = value; Invalidate(); } } }
        public void ApplyTheme() { Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Palette cur = Theme.Cur;
            Color bg = Parent != null ? Parent.BackColor : cur.Bg;
            g.Clear(bg);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float nameH = Theme.Df(30);
            RectangleF outer = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
            Theme.FillRound(g, outer, Theme.Df(9), cur.Input, sel ? cur.Accent : hover ? cur.Muted : cur.Border, sel ? Theme.Df(1.8f) : 1f);
            // miniature window in this tile's own palette
            RectangleF w = new RectangleF(Theme.Df(9), Theme.Df(9), Width - Theme.Df(18), Height - nameH - Theme.Df(12));
            Theme.FillRound(g, w, Theme.Df(5), P.Bg, P.Border, 1f);
            Theme.FillRound(g, new RectangleF(w.X + 1, w.Y + 1, w.Width * 0.26f, w.Height - 2), Theme.Df(4), P.Side, P.Side, 0f);
            float cx = w.X + w.Width * 0.32f, cw = w.Width * 0.62f;
            Theme.FillRound(g, new RectangleF(cx, w.Y + w.Height * 0.14f, cw, w.Height * 0.30f), Theme.Df(3), P.Card, P.Border, 1f);
            Theme.FillRound(g, new RectangleF(cx, w.Y + w.Height * 0.54f, cw, w.Height * 0.18f), Theme.Df(3), P.Card, P.Border, 1f);
            Theme.FillRound(g, new RectangleF(cx, w.Y + w.Height * 0.78f, cw * 0.45f, w.Height * 0.13f), Theme.Df(3), P.Accent, P.Accent, 0f);
            Theme.FillRound(g, new RectangleF(w.X + w.Width * 0.05f, w.Y + w.Height * 0.16f, w.Width * 0.16f, Theme.Df(4)), Theme.Df(2), P.Accent, P.Accent, 0f);
            Theme.FillRound(g, new RectangleF(w.X + w.Width * 0.05f, w.Y + w.Height * 0.34f, w.Width * 0.13f, Theme.Df(3)), Theme.Df(1.5f), P.Muted, P.Muted, 0f);
            Theme.FillRound(g, new RectangleF(w.X + w.Width * 0.05f, w.Y + w.Height * 0.46f, w.Width * 0.15f, Theme.Df(3)), Theme.Df(1.5f), P.Muted, P.Muted, 0f);
            TextRenderer.DrawText(g, P.Name, Theme.F(13f, sel), new Rectangle(0, Height - (int)nameH, Width, (int)nameH - Theme.D(2)),
                sel ? cur.Text : cur.Muted, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    // ------------------------------------------------------------------ main window

    class MainForm : Form
    {
        const string Version = "0.16";
        const string Author = "MarySue";
        const string RepoUrl = "https://github.com/MarySueXLsD/Silent-Hill-2-Remake-Cooperative-Plugin";
        const string DefaultGame = @"C:\Program Files (x86)\SILENT HILL 2 REMAKE";

        static readonly string[] ModelKeys = { "james", "maria", "angela", "mary" };
        static readonly string[] ModelNames = { "James", "Maria", "Angela", "Mary" };
        static readonly string[] PageNames = { "Session", "Tweaks", "World", "Characters", "Appearance", "About" };
        static readonly string[] ToggleKeys = { "share_inventory", "host_inventory_wins", "share_ammo", "share_healing", "share_documents",
            "share_key_items", "show_other_player", "show_held_items", "sync_flashlight", "flashlight_shadows", "show_my_model_to_me",
            "sync_doors", "other_player_collision", "friendly_fire", "sync_cutscenes", "sync_enemies", "sync_puzzles", "sync_pushables",
            "sync_saves" };
        static readonly string[] ToggleDefaults = { "1", "1", "1", "1", "1", "1", "1", "1", "1", "0", "1", "1", "0", "0", "1", "1", "1", "1", "1" };
        static readonly int[] SendRates = { 30, 15, 10 };

        readonly bool demo;
        bool loading = true;

        Panel side;
        Panel[] pages;
        Btn[] nav;
        Lbl pageTitle, sideStatus;
        int page;

        InputBox gameBox, ipBox, portBox, nameBox;
        Lbl gameStatus, modStatus, netStatus, addrLabel;
        Btn installBtn, hostBtn, joinBtn, startBtn, stopBtn;
        Toggle launchGame, onTop;
        LogBox logBox;
        Card connCard;
        readonly List<Btn> addrChips = new List<Btn>();

        readonly Dictionary<string, Toggle> tg = new Dictionary<string, Toggle>();
        readonly Dictionary<string, Slider> sl = new Dictionary<string, Slider>();
        readonly Dictionary<string, Lbl> slValue = new Dictionary<string, Lbl>();
        readonly Dictionary<string, string> slUnit = new Dictionary<string, string>();
        Btn[] rateChips, myTiles, otherTiles;
        ThemeTile[] themeTiles;
        int sendRate = 30, myModel = 0, otherModel = 0;

        System.Windows.Forms.Timer uiTimer;
        Thread relayThread;
        volatile bool relayRun;
        int sentCount, recvCount;
        long lastRecvTicks;
        TcpListener saveListener;
        volatile bool fetching;

        public static string TestSession, TestSaveDir;   // see the top of this file

        static int D(int v) { return Theme.D(v); }

        protected override bool ShowWithoutActivation { get { return TestSession != null; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= 0x20000;   // drop shadow
                cp.Style |= 0x20000;        // minimise from the taskbar
                return cp;
            }
        }

        public MainForm(bool demo)
        {
            this.demo = demo;
            Text = "SH2-CoopMod";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(D(940), D(760));
            DoubleBuffered = true;
            Font = Theme.F(13f, false);
            using (Bitmap bmp = new Bitmap(64, 64))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    Theme.DrawMark(g, new RectangleF(6, 8, 52, 48), Color.FromArgb(127, 178, 200), Color.FromArgb(70, 100, 114));
                }
                Icon = Icon.FromHandle(bmp.GetHicon());
            }

            Dictionary<string, string> ini = demo ? new Dictionary<string, string>() : ReadIni();
            Theme.Cur = Theme.Find(Get(ini, "theme", "fog"));

            BuildSidebar();
            BuildTitleBar();
            pages = new Panel[PageNames.Length];
            for (int i = 0; i < pages.Length; i++)
            {
                Panel p = new Panel();
                p.SetBounds(D(234), D(64), D(682), D(676));
                p.Visible = false;
                Controls.Add(p);
                pages[i] = p;
            }
            BuildSessionPage(pages[0]);
            BuildTweaksPage(pages[1]);
            BuildWorldPage(pages[2]);
            BuildCharactersPage(pages[3]);
            BuildAppearancePage(pages[4]);
            BuildAboutPage(pages[5]);

            LoadSettings(ini);
            if (!demo && TestSession != null)
            {
                string[] t = TestSession.Split(',');
                SetRole(t[0] == "join");
                if (t.Length > 1) ipBox.Value = t[1];
                if (t.Length > 2) portBox.Value = t[2];
                launchGame.Checked = false;
                StartPosition = FormStartPosition.Manual;
                Location = new Point(-30000, -30000);
                ShowInTaskbar = false;
                Shown += delegate { StartSession(); };
            }
            loading = false;
            ApplyThemeAll();
            UpdateEnabled();
            RefreshGameStatus();
            ShowAddresses(demo ? new string[] { "26.84.12.7  Radmin VPN", "192.168.1.20  Ethernet" } : DescribeAddresses());
            ShowPage(0);
            if (demo) FillDemo();

            uiTimer = new System.Windows.Forms.Timer();
            uiTimer.Interval = 1000;
            uiTimer.Tick += delegate { if (!this.demo) UpdateNetStatus(); };
            uiTimer.Start();
            FormClosing += delegate { StopSession(); };
        }

        // ------------------------------------------------------------ chrome

        void HookDrag(Control c)
        {
            c.MouseDown += delegate(object s, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                Native.ReleaseCapture();
                Native.SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero);   // act as if the title bar was grabbed
            };
        }

        void BuildSidebar()
        {
            side = new Panel();
            side.SetBounds(0, 0, D(210), ClientSize.Height);
            Controls.Add(side);
            HookDrag(side);

            MarkBox mark = new MarkBox(); mark.SetBounds(D(22), D(26), D(40), D(32)); side.Controls.Add(mark); HookDrag(mark);
            Lbl name = new Lbl("SH2-CoopMod", Role.Text, 18f, true); name.Location = new Point(D(70), D(22)); side.Controls.Add(name); HookDrag(name);
            Lbl sub = new Lbl("co-op launcher", Role.Muted, 11.5f, false); sub.Location = new Point(D(71), D(46)); side.Controls.Add(sub); HookDrag(sub);

            nav = new Btn[PageNames.Length];
            for (int i = 0; i < nav.Length; i++)
            {
                int index = i;
                Btn b = new Btn(PageNames[i], Kind.Nav);
                b.SetBounds(D(14), D(96 + i * 44), D(182), D(38));
                b.Click += delegate { ShowPage(index); };
                side.Controls.Add(b);
                nav[i] = b;
            }

            sideStatus = new Lbl("\u25CF  Not running", Role.Muted, 12f, false);
            sideStatus.Location = new Point(D(22), ClientSize.Height - D(78));
            side.Controls.Add(sideStatus);
            Lbl by = new Lbl("by " + Author, Role.Muted, 11.5f, false); by.Location = new Point(D(22), ClientSize.Height - D(40)); side.Controls.Add(by);
            Lbl ver = new Lbl("v" + Version, Role.Muted, 11.5f, false); ver.Location = new Point(D(160), ClientSize.Height - D(40)); side.Controls.Add(ver);
        }

        void BuildTitleBar()
        {
            HookDrag(this);
            pageTitle = new Lbl("", Role.Text, 21f, true);
            pageTitle.Location = new Point(D(232), D(18));
            Controls.Add(pageTitle);
            HookDrag(pageTitle);
            Btn close = new Btn("", Kind.Close); close.SetBounds(ClientSize.Width - D(46), D(12), D(34), D(28)); close.Click += delegate { Close(); }; Controls.Add(close);
            Btn min = new Btn("", Kind.Min); min.SetBounds(ClientSize.Width - D(84), D(12), D(34), D(28)); min.Click += delegate { WindowState = FormWindowState.Minimized; }; Controls.Add(min);
        }

        void ShowPage(int index)
        {
            page = index;
            for (int i = 0; i < pages.Length; i++) { pages[i].Visible = i == index; nav[i].Selected = i == index; }
            pageTitle.Text = PageNames[index];
        }

        void ApplyThemeAll()
        {
            BackColor = Theme.Cur.Bg;
            side.BackColor = Theme.Cur.Side;
            foreach (Panel p in pages) p.BackColor = Theme.Cur.Bg;
            ApplyThemeTo(this);
            if (themeTiles != null) foreach (ThemeTile t in themeTiles) t.Selected = t.P == Theme.Cur;
            Invalidate(true);
        }
        static void ApplyThemeTo(Control root)
        {
            foreach (Control c in root.Controls)
            {
                IThemed t = c as IThemed;
                if (t != null) t.ApplyTheme();
                ApplyThemeTo(c);
            }
        }

        // ------------------------------------------------------------ small builders

        static Lbl Put(Control parent, string text, Role role, float px, bool bold, int x, int y)
        {
            Lbl l = new Lbl(text, role, px, bold);
            l.Location = new Point(D(x), D(y));
            parent.Controls.Add(l);
            return l;
        }
        static Lbl PutWrapped(Control parent, string text, Role role, float px, int x, int y, int w, int h)
        {
            Lbl l = new Lbl(text, role, px, false);
            l.AutoSize = false;
            l.SetBounds(D(x), D(y), D(w), D(h));
            parent.Controls.Add(l);
            return l;
        }
        static Card PutCard(Control parent, string title, int x, int y, int w, int h)
        {
            Card c = new Card(title);
            c.SetBounds(D(x), D(y), D(w), D(h));
            parent.Controls.Add(c);
            return c;
        }
        static Btn PutBtn(Control parent, string text, Kind kind, int x, int y, int w, int h)
        {
            Btn b = new Btn(text, kind);
            b.SetBounds(D(x), D(y), D(w), D(h));
            parent.Controls.Add(b);
            return b;
        }
        static InputBox PutInput(Control parent, int x, int y, int w)
        {
            InputBox b = new InputBox();
            b.SetBounds(D(x), D(y), D(w), D(32));
            parent.Controls.Add(b);
            return b;
        }

        // A setting with a switch on the right. `key` is the mod's config key, or null.
        Toggle PutToggle(Control parent, string key, int x, int y, int w, string title, string desc)
        {
            Put(parent, title, Role.Text, 13f, false, x, y);
            if (desc != null) Put(parent, desc, Role.Muted, 11.5f, false, x, y + 19);
            Toggle t = new Toggle();
            t.Location = new Point(D(x + w) - t.Width, D(y + (desc != null ? 8 : -1)));
            parent.Controls.Add(t);
            if (key != null) tg[key] = t;
            t.CheckedChanged += OnSettingChanged;
            return t;
        }

        Slider PutSlider(Control parent, string key, int x, int y, int w, string title, int min, int max, int step, string unit)
        {
            Put(parent, title, Role.Text, 13f, false, x, y);
            Lbl v = new Lbl("", Role.Accent, 12.5f, true);
            v.AutoSize = false; v.TextAlign = ContentAlignment.TopRight;
            v.SetBounds(D(x + w - 90), D(y), D(90), D(18));
            parent.Controls.Add(v);
            Slider s = new Slider();
            s.Min = min; s.Max = max; s.Step = step;
            s.SetBounds(D(x - 6), D(y + 22), D(w + 12), D(22));
            parent.Controls.Add(s);
            sl[key] = s; slValue[key] = v; slUnit[key] = unit;
            s.ValueChanged += delegate { v.Text = s.Value + unit; OnSettingChanged(s, EventArgs.Empty); };
            return s;
        }

        void OnSettingChanged(object sender, EventArgs e)
        {
            if (loading) return;
            UpdateEnabled();
            SaveAll();
        }

        void UpdateEnabled()
        {
            bool inv = tg["share_inventory"].Checked;
            foreach (string k in new string[] { "host_inventory_wins", "share_ammo", "share_healing", "share_documents", "share_key_items" }) tg[k].Enabled = inv;
            bool other = tg["show_other_player"].Checked;
            tg["show_held_items"].Enabled = other; sl["other_player_scale"].Enabled = other;
            tg["other_player_collision"].Enabled = other;
            sl["ff_hit_damage"].Enabled = tg["friendly_fire"].Checked;
            bool fl = tg["sync_flashlight"].Checked;
            tg["flashlight_shadows"].Enabled = fl; sl["flashlight_brightness"].Enabled = fl;
            tg["show_my_model_to_me"].Enabled = myModel != 0;
            TopMost = onTop.Checked;
        }

        // ------------------------------------------------------------ pages

        void BuildSessionPage(Panel p)
        {
            Card game = PutCard(p, "Game", 0, 0, 682, 122);
            gameBox = PutInput(game, 16, 38, 536);
            Btn browse = PutBtn(game, "Browse\u2026", Kind.Outline, 562, 38, 104, 32);
            gameStatus = Put(game, "", Role.Muted, 12.5f, false, 16, 86);
            modStatus = Put(game, "", Role.Muted, 12.5f, false, 150, 86);
            installBtn = PutBtn(game, "Install / update mod", Kind.Outline, 506, 80, 160, 30);

            connCard = PutCard(p, "Connection", 0, 134, 682, 178);
            hostBtn = PutBtn(connCard, "Host", Kind.Chip, 16, 38, 110, 32);
            joinBtn = PutBtn(connCard, "Join", Kind.Chip, 132, 38, 110, 32);
            Put(connCard, "The host's world and inventory are the authority.", Role.Muted, 12f, false, 258, 46);
            Put(connCard, "Other player's IP", Role.Muted, 11.5f, false, 16, 82);
            ipBox = PutInput(connCard, 16, 100, 200);
            Put(connCard, "Port", Role.Muted, 11.5f, false, 228, 82);
            portBox = PutInput(connCard, 228, 100, 90);
            Put(connCard, "Your name", Role.Muted, 11.5f, false, 330, 82);
            nameBox = PutInput(connCard, 330, 100, 170);
            addrLabel = Put(connCard, "Your addresses (click to copy):", Role.Muted, 11.5f, false, 16, 146);

            startBtn = PutBtn(p, "Start session", Kind.Primary, 0, 324, 170, 44);
            stopBtn = PutBtn(p, "Stop", Kind.Outline, 180, 324, 90, 44);
            stopBtn.Enabled = false;
            Put(p, "Start the game too", Role.Text, 13f, false, 338, 337);
            launchGame = new Toggle(); launchGame.Location = new Point(D(290), D(335)); p.Controls.Add(launchGame);
            launchGame.CheckedChanged += OnSettingChanged;

            Btn regroup = PutBtn(p, "Go to other player (F7)", Kind.Outline, 494, 324, 186, 44);
            regroup.Click += delegate
            {
                // The mod picks this file up within a second and moves the player in game.
                try { Directory.CreateDirectory(IpcDir); File.WriteAllText(Path.Combine(IpcDir, "command.txt"), "regroup"); Log("Asked the game to move you to the other player."); }
                catch (Exception ex) { Log("Could not send that to the game: " + ex.Message); }
            };

            Card log = PutCard(p, "Log", 0, 380, 682, 296);
            netStatus = new Lbl("Not running", Role.Muted, 12f, false);
            netStatus.AutoSize = false; netStatus.TextAlign = ContentAlignment.TopRight;
            netStatus.SetBounds(D(226), D(12), D(440), D(18));
            log.Controls.Add(netStatus);
            logBox = new LogBox();
            logBox.SetBounds(D(16), D(38), D(650), D(246));
            log.Controls.Add(logBox);

            browse.Click += delegate
            {
                using (FolderBrowserDialog d = new FolderBrowserDialog())
                {
                    d.Description = "Select the game folder (the one that contains SHProto.exe)";
                    if (Directory.Exists(gameBox.Value)) d.SelectedPath = gameBox.Value;
                    if (d.ShowDialog(this) == DialogResult.OK) gameBox.Value = d.SelectedPath;
                }
            };
            gameBox.Changed += delegate { RefreshGameStatus(); OnSettingChanged(null, EventArgs.Empty); };
            ipBox.Changed += OnSettingChanged; portBox.Changed += OnSettingChanged; nameBox.Changed += OnSettingChanged;
            hostBtn.Click += delegate { SetRole(false); OnSettingChanged(null, EventArgs.Empty); };
            joinBtn.Click += delegate { SetRole(true); OnSettingChanged(null, EventArgs.Empty); };
            installBtn.Click += delegate { InstallMod(); };
            startBtn.Click += delegate { StartSession(); };
            stopBtn.Click += delegate { StopSession(); Log("Session stopped."); };
        }

        void SetRole(bool join) { hostBtn.Selected = !join; joinBtn.Selected = join; }

        void BuildTweaksPage(Panel p)
        {
            Card inv = PutCard(p, "Inventory", 0, 0, 335, 284);
            PutToggle(inv, "share_inventory", 16, 40, 303, "Shared inventory", "Pickups and item use apply to both players");
            PutToggle(inv, "host_inventory_wins", 16, 86, 303, "Host's inventory wins on connect", "Replaces the joiner's items when you connect");
            Put(inv, "WHAT IS SHARED", Role.Muted, 10f, true, 16, 136);
            PutToggle(inv, "share_ammo", 16, 158, 303, "Ammunition", null);
            PutToggle(inv, "share_healing", 16, 188, 303, "Healing items", null);
            PutToggle(inv, "share_documents", 16, 218, 303, "Maps, notes and photos", null);
            PutToggle(inv, "share_key_items", 16, 248, 303, "Weapons, keys and puzzle items", null);

            Card net = PutCard(p, "Network", 0, 296, 335, 204);
            Put(net, "Updates sent per second", Role.Text, 13f, false, 16, 44);
            rateChips = new Btn[SendRates.Length];
            for (int i = 0; i < SendRates.Length; i++)
            {
                int rate = SendRates[i];
                Btn c = PutBtn(net, rate.ToString(), Kind.Chip, 185 + i * 46, 38, 42, 28);
                c.Click += delegate { sendRate = rate; RefreshChoices(); OnSettingChanged(null, EventArgs.Empty); };
                rateChips[i] = c;
            }
            PutSlider(net, "interp_delay_ms", 16, 86, 303, "Smoothing delay", 0, 300, 10, " ms");
            PutSlider(net, "peer_timeout_s", 16, 142, 303, "Hide other player after silence", 1, 10, 1, " s");

            Card other = PutCard(p, "Other player", 347, 0, 335, 242);
            PutToggle(other, "show_other_player", 16, 40, 303, "Show the other player", "Draw their body in my world");
            PutToggle(other, "show_held_items", 16, 86, 303, "Held items", "Weapon, flashlight and radio on their body");
            PutToggle(other, "other_player_collision", 16, 132, 303, "Collision", "Their body blocks me, and enemies too");
            PutSlider(other, "other_player_scale", 16, 182, 303, "Size", 50, 150, 5, " %");

            Card flash = PutCard(p, "Flashlight", 347, 254, 335, 196);
            PutToggle(flash, "sync_flashlight", 16, 40, 303, "Their flashlight lights my world", "A real beam, aimed where they aim");
            PutToggle(flash, "flashlight_shadows", 16, 86, 303, "Beam casts shadows", "Looks better, costs performance");
            PutSlider(flash, "flashlight_brightness", 16, 136, 303, "Beam brightness", 25, 300, 25, " %");

        }

        // Everything about the shared world: what both games keep in step.
        void BuildWorldPage(Panel p)
        {
            Card world = PutCard(p, "Shared world", 0, 0, 335, 286);
            PutToggle(world, "sync_puzzles", 16, 40, 303, "Puzzles", "Solved by one of us, solved for both");
            PutToggle(world, "sync_doors", 16, 86, 303, "Doors", "Open, close and unlock for both players");
            PutToggle(world, "sync_pushables", 16, 132, 303, "Pushable objects", "Furniture one of us pushes moves for both");
            PutToggle(world, "sync_cutscenes", 16, 178, 303, "Cutscenes", "Watch together, then regroup at the host");
            PutToggle(world, "sync_saves", 16, 224, 303, "Save and load together", "Joiner saves and loads when the host does");

            Card combat = PutCard(p, "Combat", 347, 0, 335, 214);
            PutToggle(combat, "sync_enemies", 16, 40, 303, "Shared enemies", "Same health and targets; they hunt both of us");
            PutToggle(combat, "friendly_fire", 16, 86, 303, "Friendly fire", "My attacks hurt them; a shot counts double");
            PutSlider(combat, "ff_hit_damage", 16, 136, 303, "Damage per melee hit", 5, 30, 1, " hp");

            Card note = PutCard(p, null, 347, 226, 335, 136);
            PutWrapped(note, "These apply straight away, also mid-game, and both players should use the same choices.",
                Role.Muted, 12f, 16, 16, 303, 40);
            PutWrapped(note, "Health is never shared. If you get separated, press F7 in game or use Go to other player on the Session page.",
                Role.Muted, 12f, 16, 64, 303, 60);
        }

        void BuildCharactersPage(Panel p)
        {
            Card mine = PutCard(p, "My character", 0, 0, 682, 226);
            Put(mine, "What the other player sees me as.", Role.Muted, 12f, false, 16, 36);
            myTiles = new Btn[ModelNames.Length];
            for (int i = 0; i < ModelNames.Length; i++)
            {
                int index = i;
                Btn t = PutBtn(mine, ModelNames[i], Kind.Tile, 16 + i * 130, 62, 120, 98);
                t.Monogram = ModelNames[i].Substring(0, 1);
                t.Click += delegate { myModel = index; RefreshChoices(); OnSettingChanged(null, EventArgs.Empty); };
                myTiles[i] = t;
            }
            PutToggle(mine, "show_my_model_to_me", 16, 174, 650, "See myself as this character too", "Replaces James on my own screen as well");

            Card theirs = PutCard(p, "Other player on my screen", 0, 238, 682, 178);
            Put(theirs, "Overrides what they picked, on my screen only.", Role.Muted, 12f, false, 16, 36);
            otherTiles = new Btn[ModelNames.Length + 1];
            for (int i = 0; i < otherTiles.Length; i++)
            {
                int index = i;
                Btn t = PutBtn(theirs, i == 0 ? "Their choice" : ModelNames[i - 1], Kind.Tile, 16 + i * 109, 62, 101, 98);
                t.Monogram = i == 0 ? "\u2194" : ModelNames[i - 1].Substring(0, 1);
                t.Click += delegate { otherModel = index; RefreshChoices(); OnSettingChanged(null, EventArgs.Empty); };
                otherTiles[i] = t;
            }

            Card tip = PutCard(p, "Two ways to set it up", 0, 428, 682, 150);
            PutWrapped(tip, "Host is James, guest is someone else: the guest picks a character under My character.",
                Role.Text, 12.5f, 16, 40, 650, 20);
            PutWrapped(tip, "Everyone sees themselves as James and the partner as someone else: both players pick a look under Other player on my screen, and leave My character on James.",
                Role.Text, 12.5f, 16, 64, 650, 38);
            PutWrapped(tip, "Models are loaded from your own game files. Poses on other characters are approximate.",
                Role.Muted, 11.5f, 16, 114, 650, 20);
        }

        void BuildAppearancePage(Panel p)
        {
            Card themes = PutCard(p, "Theme", 0, 0, 682, 196);
            themeTiles = new ThemeTile[Theme.All.Length];
            for (int i = 0; i < Theme.All.Length; i++)
            {
                Palette pal = Theme.All[i];
                ThemeTile t = new ThemeTile(pal);
                t.SetBounds(D(16 + i * 164), D(42), D(154), D(138));
                t.Click += delegate { Theme.Cur = pal; ApplyThemeAll(); OnSettingChanged(null, EventArgs.Empty); };
                themes.Controls.Add(t);
                themeTiles[i] = t;
            }
            Card win = PutCard(p, "Window", 0, 208, 682, 96);
            onTop = PutToggle(win, null, 16, 40, 650, "Keep the launcher on top", "Handy for changing tweaks while the game is in windowed mode");
        }

        void BuildAboutPage(Panel p)
        {
            Card c = PutCard(p, null, 0, 0, 682, 286);
            MarkBox mark = new MarkBox(); mark.SetBounds(D(24), D(26), D(74), D(58)); c.Controls.Add(mark);
            Put(c, "SH2-CoopMod", Role.Text, 28f, true, 112, 22);
            Put(c, "Version " + Version + "  \u00B7  co-op mod and launcher", Role.Muted, 12.5f, false, 114, 62);
            Put(c, "Authored by " + Author, Role.Accent, 16f, true, 24, 108);
            PutWrapped(c, "Co-op mod for Silent Hill 2 (2024). Play the whole game together: you see each other, share one inventory, fight the same enemies, and puzzles, doors and cutscenes move on for both. Works over Radmin VPN, Hamachi or LAN.",
                Role.Text, 13f, 24, 142, 634, 64);
            Btn repo = PutBtn(c, "Open GitHub page", Kind.Outline, 24, 226, 170, 36);
            Btn folder = PutBtn(c, "Open mod folder", Kind.Outline, 204, 226, 160, 36);
            repo.Click += delegate { try { Process.Start(RepoUrl); } catch { } };
            folder.Click += delegate { try { if (Directory.Exists(ModDir)) Process.Start(ModDir); } catch { } };

            Card d = PutCard(p, null, 0, 298, 682, 84);
            PutWrapped(d, "Unofficial fan project. Not affiliated with or endorsed by the game's developer or publisher. You need your own copy of the game; this project contains no game files.",
                Role.Muted, 12f, 16, 18, 650, 52);
        }

        void RefreshChoices()
        {
            for (int i = 0; i < rateChips.Length; i++) rateChips[i].Selected = SendRates[i] == sendRate;
            for (int i = 0; i < myTiles.Length; i++) myTiles[i].Selected = i == myModel;
            for (int i = 0; i < otherTiles.Length; i++) otherTiles[i].Selected = i == otherModel;
        }

        void FillDemo()
        {
            gameStatus.Text = "\u25CF  Game found"; gameStatus.SetRole(Role.Good);
            modStatus.Text = "\u25CF  Mod installed"; modStatus.SetRole(Role.Good);
            ipBox.Value = "26.91.33.150"; nameBox.Value = "Player";
            netStatus.Text = "Connected   (sent 30/s, received 30/s)"; netStatus.SetRole(Role.Good);
            sideStatus.Text = "\u25CF  Connected"; sideStatus.SetRole(Role.Good);
            startBtn.Enabled = false; stopBtn.Enabled = true;
            logBox.Text = "21:04:11  Hosting for 26.91.33.150 on port 47777.\r\n21:04:11  If Windows Firewall asks, allow this app on private networks.\r\n21:04:11  Load your save. The other player joins from their main menu.\r\n21:05:02  The other player is joining from their main menu. Saving the game for them.\r\n21:05:02  Save sent (275 KB).";
        }

        // ------------------------------------------------------------ log, paths

        void Log(string s)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { try { BeginInvoke(new Action<string>(Log), s); } catch { } return; }
            if (TestSaveDir != null) { try { File.AppendAllText(Path.Combine(TestSaveDir, "launcher.log"), s + "\r\n"); } catch { } }
            logBox.AppendText((logBox.TextLength > 0 ? "\r\n" : "") + DateTime.Now.ToString("HH:mm:ss") + "  " + s);
        }

        string GamePath { get { return gameBox.Value.Trim(); } }
        string Win64Dir { get { return Path.Combine(GamePath, @"SHProto\Binaries\Win64"); } }
        string ModDir { get { return Path.Combine(Win64Dir, @"ue4ss\Mods\SH2-CoopMod"); } }
        string IpcDir { get { return Path.Combine(ModDir, "ipc"); } }
        string PayloadDir { get { return Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "game_files"); } }
        bool GameFound { get { try { return File.Exists(Path.Combine(GamePath, "SHProto.exe")); } catch { return false; } } }
        bool ModInstalled { get { return File.Exists(Path.Combine(ModDir, @"Scripts\core.lua")) && File.Exists(Path.Combine(Win64Dir, "dwmapi.dll")); } }
        static bool IsLink(string dir) { return Directory.Exists(dir) && (new DirectoryInfo(dir).Attributes & FileAttributes.ReparsePoint) != 0; }
        static bool GameRunning { get { return Process.GetProcessesByName("SHProto-Win64-Shipping").Length > 0; } }

        void RefreshGameStatus()
        {
            if (demo) return;
            if (!GameFound)
            {
                gameStatus.Text = "\u25CF  SHProto.exe not found in this folder"; gameStatus.SetRole(Role.Bad);
                modStatus.Text = ""; installBtn.Enabled = false;
                return;
            }
            gameStatus.Text = "\u25CF  Game found"; gameStatus.SetRole(Role.Good);
            bool payload = Directory.Exists(PayloadDir);
            if (IsLink(ModDir)) { modStatus.Text = "\u25CF  Mod installed (development link)"; modStatus.SetRole(Role.Good); installBtn.Enabled = false; }
            else if (ModInstalled) { modStatus.Text = "\u25CF  Mod installed"; modStatus.SetRole(Role.Good); installBtn.Enabled = payload; }
            else { modStatus.Text = payload ? "\u25CF  Mod not installed" : "\u25CF  Mod not installed (game_files folder missing)"; modStatus.SetRole(Role.Warn); installBtn.Enabled = payload; }
        }

        // ------------------------------------------------------------ settings

        string IniPath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SH2-CoopMod");
                Directory.CreateDirectory(dir);
                return Path.Combine(dir, "launcher.ini");
            }
        }

        Dictionary<string, string> ReadIni()
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            try
            {
                foreach (string line in File.ReadAllLines(IniPath))
                {
                    int i = line.IndexOf('=');
                    if (i > 0) d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
                }
            }
            catch { }
            return d;
        }
        static string Get(Dictionary<string, string> d, string key, string def) { string v; return d.TryGetValue(key, out v) ? v : def; }
        static int GetInt(Dictionary<string, string> d, string key, int def) { int v; return int.TryParse(Get(d, key, ""), out v) ? v : def; }

        void LoadSettings(Dictionary<string, string> d)
        {
            gameBox.Value = Get(d, "game_path", DefaultGame);
            SetRole(Get(d, "role", "host") == "join");
            ipBox.Value = Get(d, "peer_ip", "");
            portBox.Value = GetInt(d, "port", 47777).ToString();
            nameBox.Value = Get(d, "player_name", demo ? "Player" : Environment.UserName);
            launchGame.Checked = Get(d, "launch_game", "1") == "1";
            onTop.Checked = Get(d, "always_on_top", "0") == "1";
            for (int i = 0; i < ToggleKeys.Length; i++) tg[ToggleKeys[i]].Checked = Get(d, ToggleKeys[i], ToggleDefaults[i]) == "1";
            sl["other_player_scale"].Value = GetInt(d, "other_player_scale", 100);
            sl["flashlight_brightness"].Value = GetInt(d, "flashlight_brightness", 100);
            sl["interp_delay_ms"].Value = GetInt(d, "interp_delay_ms", 100);
            sl["peer_timeout_s"].Value = GetInt(d, "peer_timeout_s", 3);
            sl["ff_hit_damage"].Value = GetInt(d, "ff_hit_damage", 10);
            foreach (string k in sl.Keys) slValue[k].Text = sl[k].Value + slUnit[k];
            sendRate = GetInt(d, "send_rate_hz", 30);
            if (Array.IndexOf(SendRates, sendRate) < 0) sendRate = 30;
            myModel = Math.Max(0, Array.IndexOf(ModelKeys, Get(d, "my_model", "james")));
            otherModel = Array.IndexOf(ModelKeys, Get(d, "other_model", "auto")) + 1;
            RefreshChoices();
        }

        int PortValue { get { int v; return int.TryParse(portBox.Value.Trim(), out v) && v >= 1024 && v <= 65535 ? v : 47777; } }

        // What the mod reads (config.txt in the mod folder).
        string ModConfigText()
        {
            StringBuilder sb = new StringBuilder();
            foreach (string k in ToggleKeys) sb.AppendLine(k + "=" + (tg[k].Checked ? "1" : "0"));
            foreach (string k in sl.Keys) sb.AppendLine(k + "=" + sl[k].Value);
            sb.AppendLine("send_rate_hz=" + sendRate);
            sb.AppendLine("my_model=" + ModelKeys[myModel]);
            sb.AppendLine("other_model=" + (otherModel <= 0 ? "auto" : ModelKeys[otherModel - 1]));
            string name = nameBox.Value.Trim().Replace("=", "").Replace("\r", "").Replace("\n", "");
            sb.AppendLine("player_name=" + (name.Length == 0 ? "Player" : name));
            return sb.ToString();
        }

        void SaveAll()
        {
            if (loading || demo || TestSession != null) return;
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("game_path=" + GamePath);
                sb.AppendLine("role=" + (joinBtn.Selected ? "join" : "host"));
                sb.AppendLine("peer_ip=" + ipBox.Value.Trim());
                sb.AppendLine("port=" + PortValue);
                sb.AppendLine("launch_game=" + (launchGame.Checked ? "1" : "0"));
                sb.AppendLine("always_on_top=" + (onTop.Checked ? "1" : "0"));
                sb.AppendLine("theme=" + Theme.Cur.Key);
                sb.Append(ModConfigText());
                File.WriteAllText(IniPath, sb.ToString());
            }
            catch { }
            WriteModConfig(false);
        }

        bool WriteModConfig(bool report)
        {
            if (demo || !GameFound || !Directory.Exists(ModDir)) return false;
            try
            {
                File.WriteAllText(Path.Combine(ModDir, "config.txt"), ModConfigText());
                return true;
            }
            catch (Exception ex)
            {
                if (report) Log("Could not write the mod's settings: " + ex.Message);
                return false;
            }
        }

        // ------------------------------------------------------------ network info

        static string[] DescribeAddresses()
        {
            List<string> parts = new List<string>();
            try
            {
                foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    foreach (UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                    {
                        if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                        string ip = ua.Address.ToString();
                        if (ip.StartsWith("169.254.")) continue;
                        string label = ni.Name;
                        string lower = (ni.Name + " " + ni.Description).ToLowerInvariant();
                        bool vpn = true;
                        if (lower.Contains("radmin") || ip.StartsWith("26.")) label = "Radmin VPN";
                        else if (lower.Contains("hamachi") || ip.StartsWith("25.")) label = "Hamachi";
                        else vpn = false;
                        if (label.Length > 14) label = label.Substring(0, 14);
                        string text = ip + "  " + label;
                        if (vpn) parts.Insert(0, text); else parts.Add(text);
                    }
                }
            }
            catch { }
            return parts.ToArray();
        }

        void ShowAddresses(string[] list)
        {
            foreach (Btn b in addrChips) { connCard.Controls.Remove(b); b.Dispose(); }
            addrChips.Clear();
            int x = addrLabel.Right + D(10);
            int limit = connCard.Width - D(16);
            foreach (string text in list)
            {
                string ip = text.Split(' ')[0];
                Btn b = new Btn(text, Kind.Outline);
                int w = TextRenderer.MeasureText(text, Theme.F(13f, false)).Width + D(22);
                if (x + w > limit) break;
                b.SetBounds(x, D(138), w, D(28));
                b.Click += delegate { try { Clipboard.SetText(ip); Log("Copied " + ip + " to the clipboard."); } catch { } };
                connCard.Controls.Add(b);
                addrChips.Add(b);
                x += w + D(8);
            }
            if (list.Length == 0) addrLabel.Text = "No network addresses found.";
        }

        // ------------------------------------------------------------ install

        bool OfferElevation(string what)
        {
            DialogResult r = MessageBox.Show(this, what + "\n\nWindows protects this folder. Restart the launcher as administrator?",
                "SH2-CoopMod", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return false;
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath);
                psi.UseShellExecute = true; psi.Verb = "runas";
                Process.Start(psi);
                StopSession();
                Close();
            }
            catch { }
            return true;
        }

        static void CopyDir(string src, string dst)
        {
            if (IsLink(dst)) return;   // never copy over a development link
            Directory.CreateDirectory(dst);
            foreach (string f in Directory.GetFiles(src)) File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), true);
            foreach (string d in Directory.GetDirectories(src)) CopyDir(d, Path.Combine(dst, Path.GetFileName(d)));
        }

        void InstallMod()
        {
            if (!GameFound || !Directory.Exists(PayloadDir)) return;
            if (GameRunning) { MessageBox.Show(this, "Close the game before installing or updating the mod.", "SH2-CoopMod"); return; }
            try
            {
                CopyDir(PayloadDir, Win64Dir);
                Directory.CreateDirectory(IpcDir);
                Log("Mod files copied into " + Win64Dir);
            }
            catch (UnauthorizedAccessException) { OfferElevation("The mod could not be copied into the game folder."); }
            catch (Exception ex) { Log("Install failed: " + ex.Message); }
            RefreshGameStatus();
            WriteModConfig(false);
        }

        // ------------------------------------------------------------ session

        void StartSession()
        {
            if (!GameFound) { ShowPage(0); MessageBox.Show(this, "Choose the game folder first.", "SH2-CoopMod"); return; }
            if (!ModInstalled) { MessageBox.Show(this, "Install the mod first.", "SH2-CoopMod"); return; }
            IPAddress peer;
            if (!IPAddress.TryParse(ipBox.Value.Trim(), out peer) || peer.AddressFamily != AddressFamily.InterNetwork)
            {
                MessageBox.Show(this, "Enter the other player's IP address (for Radmin VPN it starts with 26.).", "SH2-CoopMod");
                return;
            }
            bool join = joinBtn.Selected;
            try
            {
                Directory.CreateDirectory(IpcDir);
                File.WriteAllText(Path.Combine(IpcDir, "role.txt"), join ? "join" : "host");
                foreach (string stale in new string[] { "in.txt", "request.txt", "save_ready.txt", "coopsave_done.txt" })
                {
                    string path = Path.Combine(IpcDir, stale);
                    if (File.Exists(path)) File.Delete(path);
                }
            }
            catch (UnauthorizedAccessException) { OfferElevation("The launcher cannot write to the mod folder inside the game."); return; }
            catch (Exception ex) { Log("Cannot prepare the mod folder: " + ex.Message); return; }
            WriteModConfig(true);

            int port = PortValue;
            UdpClient udp;
            try { udp = new UdpClient(port); }
            catch (Exception ex) { Log("Cannot open UDP port " + port + ": " + ex.Message + " (is another launcher or relay running?)"); return; }

            sentCount = 0; recvCount = 0; lastRecvTicks = 0;
            relayRun = true;
            IPEndPoint peerEp = new IPEndPoint(peer, port);
            string ipc = IpcDir;
            relayThread = new Thread(delegate() { RelayLoop(udp, peerEp, ipc); });
            relayThread.IsBackground = true;
            relayThread.Start();
            startBtn.Enabled = false; stopBtn.Enabled = true;
            Log((join ? "Joining " : "Hosting for ") + peer + " on port " + port + ".");
            Log("If Windows Firewall asks, allow this app on private networks.");

            // The host hands its save to a player who joins from the game's main menu.
            if (!join || IPAddress.IsLoopback(peer))
            {
                try
                {
                    TcpListener tcp = new TcpListener(IPAddress.Any, port);
                    tcp.Start();
                    saveListener = tcp;
                    Thread st = new Thread(delegate() { SaveServerLoop(tcp, peer, ipc); });
                    st.IsBackground = true;
                    st.Start();
                }
                catch (Exception ex) { Log("Cannot open TCP port " + port + " (" + ex.Message + "). The other player cannot join from the main menu."); }
            }
            Log(join ? "When the host is in the game, choose \"Join co-op\" in the game's main menu."
                     : "Load your save. The other player joins from their main menu.");

            if (launchGame.Checked && !GameRunning)
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(GamePath, "SHProto.exe"));
                    psi.WorkingDirectory = GamePath; psi.UseShellExecute = true;
                    Process.Start(psi);
                    Log("Game started.");
                }
                catch (Exception ex) { Log("Could not start the game: " + ex.Message); }
            }
        }

        void StopSession()
        {
            relayRun = false;
            TcpListener l = saveListener; saveListener = null;
            if (l != null) { try { l.Stop(); } catch { } }
            Thread t = relayThread; relayThread = null;
            if (t != null) t.Join(1000);
            if (!IsDisposed && startBtn != null) { startBtn.Enabled = true; stopBtn.Enabled = false; }
        }

        // Carries the mod's out.txt to the other PC and the other PC's packets into in.txt.
        void RelayLoop(UdpClient udp, IPEndPoint peer, string ipc)
        {
            string outFile = Path.Combine(ipc, "out.txt");
            string inFile = Path.Combine(ipc, "in.txt");
            string requestFile = Path.Combine(ipc, "request.txt");
            string lastSent = "";
            Encoding enc = Encoding.ASCII;
            int loops = 0;
            try
            {
                while (relayRun)
                {
                    // The mod's "Join co-op" menu entry asks for the host's save by dropping this file.
                    if (++loops % 10 == 0 && !fetching && File.Exists(requestFile))
                    {
                        bool taken = false;
                        try { File.Delete(requestFile); taken = true; }
                        catch (IOException) { }
                        catch (UnauthorizedAccessException) { }
                        if (taken)
                        {
                            fetching = true;
                            ThreadPool.QueueUserWorkItem(delegate { FetchSave(peer, ipc); });
                        }
                    }

                    try
                    {
                        string text;
                        using (FileStream fs = new FileStream(outFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                        using (StreamReader sr = new StreamReader(fs, enc)) text = sr.ReadToEnd();
                        if (text.Length > 2 && text.Length < 60000 && text.StartsWith("S ") && text != lastSent)
                        {
                            byte[] bytes = enc.GetBytes(text);
                            udp.Send(bytes, bytes.Length, peer);
                            lastSent = text;
                            Interlocked.Increment(ref sentCount);
                        }
                    }
                    catch (IOException) { }
                    catch (SocketException) { }

                    string latest = null;
                    while (udp.Available > 0)
                    {
                        try
                        {
                            IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                            byte[] data = udp.Receive(ref from);
                            if (from.Address.Equals(peer.Address))
                            {
                                latest = enc.GetString(data);
                                Interlocked.Increment(ref recvCount);
                                Interlocked.Exchange(ref lastRecvTicks, DateTime.UtcNow.Ticks);
                            }
                        }
                        catch (SocketException) { break; }
                    }
                    if (latest != null && latest.StartsWith("S ") && latest.Length < 60000)
                    {
                        try { File.WriteAllText(inFile, latest, enc); } catch (IOException) { }
                    }
                    Thread.Sleep(10);
                }
            }
            catch (Exception ex) { Log("Relay stopped: " + ex.Message); }
            finally { try { udp.Close(); } catch { } }
        }

        // ------------------------------------------------------------ joining from the main menu
        //
        // The joiner's mod drops request.txt -> this launcher asks the host's launcher over TCP ->
        // that one tells its game to save (command.txt "coopsave", answered by coopsave_done.txt)
        // and sends the file back -> it lands in the joiner's co-op slot -> save_ready.txt tells
        // the joiner's mod to load it.

        const int CoopSlot = 9;                          // the mod uses the same number; never one of the player's own slots
        const int MaxSaveBytes = 64 * 1024 * 1024;

        // The game keeps saves in a folder named after the account; take the one in use.
        static string FindSaveDir()
        {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"SilentHill2\Saved\SaveGames");
            if (!Directory.Exists(root)) return null;
            string best = null;
            DateTime bestTime = DateTime.MinValue;
            foreach (string d in Directory.GetDirectories(root))
            {
                foreach (string f in Directory.GetFiles(d, "*.sav"))
                {
                    DateTime t = File.GetLastWriteTimeUtc(f);
                    if (t > bestTime) { bestTime = t; best = d; }
                }
            }
            return best;
        }

        static string ReadLine(Stream s, int max)
        {
            StringBuilder sb = new StringBuilder();
            while (sb.Length < max)
            {
                int b = s.ReadByte();
                if (b < 0 || b == '\n') break;
                if (b != '\r') sb.Append((char)b);
            }
            return sb.ToString();
        }

        // Host: answer the joiner's launcher, and nobody else.
        void SaveServerLoop(TcpListener tcp, IPAddress peer, string ipc)
        {
            while (relayRun)
            {
                TcpClient c;
                try { c = tcp.AcceptTcpClient(); }
                catch { break; }   // the session was stopped
                try
                {
                    using (c)
                    {
                        if (!((IPEndPoint)c.Client.RemoteEndPoint).Address.Equals(peer)) continue;
                        c.ReceiveTimeout = 5000; c.SendTimeout = 30000;
                        NetworkStream ns = c.GetStream();
                        if (ReadLine(ns, 32) != "GETSAVE") continue;
                        Log("The other player is joining from their main menu. Saving the game for them.");
                        byte[] data;
                        string err = MakeSaveForPeer(ipc, out data);
                        byte[] head = Encoding.ASCII.GetBytes(err == null ? "OK " + data.Length + "\n" : "ERR " + err + "\n");
                        ns.Write(head, 0, head.Length);
                        if (err == null) { ns.Write(data, 0, data.Length); Log("Save sent (" + (data.Length / 1024) + " KB)."); }
                        else Log("No save sent: " + err);
                    }
                }
                catch (Exception ex) { Log("Could not send the save: " + ex.Message); }
            }
        }

        // Host: have the game write a fresh save into the co-op slot and read it. Returns what went wrong, or null.
        string MakeSaveForPeer(string ipc, out byte[] data)
        {
            data = null;
            if (!GameRunning) return "the host's game is not running";
            string done = Path.Combine(ipc, "coopsave_done.txt");
            string command = Path.Combine(ipc, "command.txt");
            try { File.Delete(done); } catch (IOException) { }
            DateTime asked = DateTime.UtcNow;
            File.WriteAllText(command, "coopsave");

            string slotText = "";
            for (int i = 0; i < 150 && relayRun && slotText.Length == 0; i++)   // the mod looks three times a second
            {
                Thread.Sleep(100);
                try { if (File.Exists(done)) slotText = File.ReadAllText(done).Trim(); } catch (IOException) { }
            }
            int slot;
            if (slotText.Length == 0)
            {
                try { File.Delete(command); } catch (IOException) { }
                return "the host is not in the game";
            }
            if (!int.TryParse(slotText, out slot) || slot < 0 || slot > 99) return "the host's mod gave a bad answer";

            string dir = FindSaveDir();
            if (dir == null) return "the host's save folder was not found";
            string file = Path.Combine(dir, "SaveGameData_" + slot + ".sav");
            long size = -1;
            bool settled = false;
            for (int i = 0; i < 50 && !settled; i++)   // fresh, and no longer growing
            {
                FileInfo fi = new FileInfo(file);
                if (fi.Exists && fi.Length > 0 && fi.LastWriteTimeUtc >= asked.AddSeconds(-2))
                {
                    if (fi.Length == size) settled = true;
                    size = fi.Length;
                }
                if (!settled) Thread.Sleep(100);
            }
            if (!settled) return "the host's game could not save just now, try again in a moment";
            if (size > MaxSaveBytes) return "the save is too large";
            using (FileStream fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                byte[] buf = new byte[(int)fs.Length];
                int got = 0;
                while (got < buf.Length)
                {
                    int n = fs.Read(buf, got, buf.Length - got);
                    if (n <= 0) break;
                    got += n;
                }
                if (got != buf.Length) return "the save could not be read";
                data = buf;
            }
            return null;
        }

        // Joiner: get the host's save, put it into the co-op slot, tell the mod.
        void FetchSave(IPEndPoint peer, string ipc)
        {
            string answer;
            try
            {
                Log("Asking the host for their save...");
                byte[] data;
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect(peer.Address, peer.Port, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(6000)) throw new Exception("the host's launcher did not answer (is it running, and is its firewall open?)");
                    c.EndConnect(ar);
                    c.ReceiveTimeout = 30000; c.SendTimeout = 5000;
                    NetworkStream ns = c.GetStream();
                    byte[] ask = Encoding.ASCII.GetBytes("GETSAVE\n");
                    ns.Write(ask, 0, ask.Length);
                    string head = ReadLine(ns, 200);
                    if (head.StartsWith("ERR ")) throw new Exception(head.Substring(4));
                    int len;
                    if (!head.StartsWith("OK ") || !int.TryParse(head.Substring(3), out len) || len <= 0 || len > MaxSaveBytes)
                        throw new Exception("the host's launcher gave a bad answer (is it the same version?)");
                    data = new byte[len];
                    int got = 0;
                    while (got < len)
                    {
                        int n = ns.Read(data, got, len - got);
                        if (n <= 0) throw new Exception("the connection dropped while the save was coming in");
                        got += n;
                    }
                }
                string dir = TestSaveDir != null ? TestSaveDir : FindSaveDir();
                if (dir == null) throw new Exception("this PC's save folder was not found (start the game once first)");
                File.WriteAllBytes(Path.Combine(dir, "SaveGameData_" + CoopSlot + ".sav"), data);
                answer = "ok " + CoopSlot;
                Log("Host's save received (" + (data.Length / 1024) + " KB). The game is loading it.");
            }
            catch (Exception ex)
            {
                answer = "err " + ex.Message;
                Log("Could not get the host's save: " + ex.Message);
            }
            try { File.WriteAllText(Path.Combine(ipc, "save_ready.txt"), answer); } catch { }
            fetching = false;
        }

        void UpdateNetStatus()
        {
            if (relayThread == null)
            {
                netStatus.Text = "Not running"; netStatus.SetRole(Role.Muted);
                sideStatus.Text = "\u25CF  Not running"; sideStatus.SetRole(Role.Muted);
                return;
            }
            int s = Interlocked.Exchange(ref sentCount, 0);
            int r = Interlocked.Exchange(ref recvCount, 0);
            long last = Interlocked.Read(ref lastRecvTicks);
            string state; Role role;
            if (last != 0 && (DateTime.UtcNow.Ticks - last) < TimeSpan.TicksPerSecond * 3) { state = "Connected"; role = Role.Good; }
            else if (!GameRunning) { state = "Waiting for the game"; role = Role.Warn; }
            else if (s == 0) { state = "Game running, load a save"; role = Role.Warn; }
            else { state = "No answer from the other player"; role = Role.Bad; }
            netStatus.Text = state + "   (sent " + s + "/s, received " + r + "/s)"; netStatus.SetRole(role);
            sideStatus.Text = "\u25CF  " + state; sideStatus.SetRole(role);
        }

        // ------------------------------------------------------------ README screenshots

        public static void TakeScreenshots(string dir)
        {
            Directory.CreateDirectory(dir);
            MainForm f = new MainForm(true);
            f.StartPosition = FormStartPosition.Manual;
            f.Location = new Point(-30000, -30000);
            f.ShowInTaskbar = false;
            f.Show();
            Application.DoEvents();
            f.Shot(dir, "session", 0, "fog");
            f.Shot(dir, "tweaks", 1, "fog");
            f.Shot(dir, "world", 2, "fog");
            f.Shot(dir, "characters", 3, "fog");
            f.Shot(dir, "appearance", 4, "fog");
            f.Shot(dir, "about", 5, "fog");
            f.Shot(dir, "session-rust", 0, "rust");
            f.Shot(dir, "tweaks-moss", 1, "moss");
            f.Shot(dir, "characters-paper", 3, "paper");
            f.Close();
        }

        void Shot(string dir, string name, int pageIndex, string theme)
        {
            Theme.Cur = Theme.Find(theme);
            ApplyThemeAll();
            ShowPage(pageIndex);
            if (pageIndex == 3) { myModel = 1; otherModel = 0; RefreshChoices(); UpdateEnabled(); }
            Application.DoEvents();
            using (Bitmap bmp = new Bitmap(Width, Height))
            {
                DrawToBitmap(bmp, new Rectangle(0, 0, Width, Height));
                bmp.Save(Path.Combine(dir, name + ".png"), ImageFormat.Png);
            }
        }
    }
}
