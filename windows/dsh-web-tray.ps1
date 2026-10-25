param(
    [switch]$PreviewMenu,
    [string]$PreviewShot = ''
)

$ErrorActionPreference = 'Stop'

$script:Distro     = 'Ubuntu'
$script:WslUser    = 'yanyifan'
$script:WslScript  = '/home/yanyifan/.local/bin/dsh-web'
$script:WslLog     = '/home/yanyifan/.local/state/dsh-web/web.log'
$script:WebUrl     = 'http://127.0.0.1:3080'

$script:AppDir = $PSScriptRoot
if (-not $script:AppDir) { $script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$script:IconOnPath  = Join-Path $script:AppDir 'dsh-web-running.ico'
$script:IconOffPath = Join-Path $script:AppDir 'dsh-web-stopped.ico'
$script:VbsPath     = Join-Path $script:AppDir 'dsh-web-tray.vbs'
$script:ErrorLog    = Join-Path $script:AppDir 'tray-error.log'
$script:TrayStartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web Tray.lnk'
$script:WebStartupLnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web Server.lnk'
$script:AutoStartVbs   = Join-Path $script:AppDir 'dsh-web-autostart.vbs'
$script:FirstRunMarker = Join-Path $script:AppDir '.tray-first-run'
$script:WslExe      = Join-Path $env:SystemRoot 'System32\wsl.exe'

$script:Running = $false
$script:LastStatus = ''
$script:Dpi = 96.0
$script:Scale = 1.0
$script:Light = $true
$script:IconDpi = 0
$script:MenuIconSize = 20
$script:HasMutex = $false

function Write-TrayError([string]$Message) {
    try {
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Message
        Add-Content -LiteralPath $script:ErrorLog -Value $line -Encoding UTF8
    } catch { }
}

function Get-IsLightTheme {
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        return ([int]$v -ne 0)
    } catch {
        return $true
    }
}

# --- DPI awareness: must run before WinForms creates any window ------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DshDpi
{
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
}
public static class DshDwm
{
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
'@

try { [void][DshDpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { }
try { [void][DshDpi]::SetProcessDpiAwareness(2) } catch { }
try { [void][DshDpi]::SetProcessDPIAware() } catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }

try {
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:Dpi = [double]$g.DpiX
    $g.Dispose()
} catch { }
try {
    $hmon = [DshDpi]::MonitorFromWindow([IntPtr]::Zero, 1)
    [uint32]$dx = 0
    [uint32]$dy = 0
    $hr = [DshDpi]::GetDpiForMonitor($hmon, 0, [ref]$dx, [ref]$dy)
    if ($hr -eq 0 -and $dx -gt 0) { $script:Dpi = [Math]::Max($script:Dpi, [double]$dx) }
} catch { }
if ($script:Dpi -le 0) { $script:Dpi = 96.0 }
$script:Scale = $script:Dpi / 96.0
$script:MenuIconSize = [int][Math]::Round(20 * $script:Scale)
$script:Light = Get-IsLightTheme

# --- renderer ---------------------------------------------------------------
$script:RendererSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

public class DshMenuColorTable : ProfessionalColorTable
{
    private readonly bool light;
    public DshMenuColorTable(bool light) { this.light = light; }
    public override Color ToolStripDropDownBackground { get { return light ? Color.FromArgb(255, 255, 255) : Color.FromArgb(30, 32, 36); } }
    public override Color ImageMarginGradientBegin { get { return ToolStripDropDownBackground; } }
    public override Color ImageMarginGradientMiddle { get { return ToolStripDropDownBackground; } }
    public override Color ImageMarginGradientEnd { get { return ToolStripDropDownBackground; } }
    public override Color MenuBorder { get { return light ? Color.FromArgb(227, 232, 239) : Color.FromArgb(51, 54, 60); } }
    public override Color MenuItemBorder { get { return Color.Transparent; } }
    public override Color MenuItemSelected { get { return light ? Color.FromArgb(243, 246, 255) : Color.FromArgb(42, 45, 51); } }
    public override Color MenuItemSelectedGradientBegin { get { return MenuItemSelected; } }
    public override Color MenuItemSelectedGradientEnd { get { return MenuItemSelected; } }
    public override Color SeparatorDark { get { return light ? Color.FromArgb(232, 236, 242) : Color.FromArgb(52, 55, 61); } }
    public override Color SeparatorLight { get { return SeparatorDark; } }
}

public class DshMenuRenderer : ToolStripProfessionalRenderer
{
    public bool Light { get; set; }

    public DshMenuRenderer(bool light) : base(new DshMenuColorTable(light))
    {
        Light = light;
        RoundedEdges = false;
    }

    public Color Bg { get { return Light ? Color.FromArgb(255, 255, 255) : Color.FromArgb(30, 32, 36); } }
    public Color BorderColor { get { return Light ? Color.FromArgb(227, 232, 239) : Color.FromArgb(51, 54, 60); } }
    public Color TextColor { get { return Light ? Color.FromArgb(31, 41, 55) : Color.FromArgb(232, 234, 237); } }
    public Color MutedColor { get { return Light ? Color.FromArgb(107, 114, 128) : Color.FromArgb(154, 160, 166); } }
    public Color AccentColor { get { return Light ? Color.FromArgb(77, 107, 254) : Color.FromArgb(138, 180, 248); } }
    public Color HoverColor { get { return Light ? Color.FromArgb(243, 246, 255) : Color.FromArgb(42, 45, 51); } }
    public Color SeparatorColor { get { return Light ? Color.FromArgb(232, 236, 242) : Color.FromArgb(52, 55, 61); } }
    public Color HeaderTop { get { return Light ? Color.FromArgb(243, 246, 255) : Color.FromArgb(39, 43, 54); } }
    public Color HeaderBottom { get { return Bg; } }

    private static GraphicsPath RoundRect(RectangleF r, float radius)
    {
        float d = radius * 2f;
        GraphicsPath p = new GraphicsPath();
        if (d <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush b = new SolidBrush(Bg))
        {
            e.Graphics.FillRectangle(b, 0, 0, e.ToolStrip.Width, e.ToolStrip.Height);
        }
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        using (GraphicsPath p = RoundRect(r, 10f))
        using (Pen pen = new Pen(BorderColor, 1f))
        {
            e.Graphics.DrawPath(pen, p);
        }
    }

    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        ToolStripItem item = e.Item;
        string tag = item.Tag as string;
        if (tag == "header")
        {
            Rectangle r = new Rectangle(0, 0, item.Width, item.Height + 1);
            using (LinearGradientBrush b = new LinearGradientBrush(r, HeaderTop, HeaderBottom, 90f))
            {
                e.Graphics.FillRectangle(b, r);
            }
            return;
        }
        if (tag == "status") { return; }
        if (item.Selected && item.Enabled)
        {
            Rectangle r = new Rectangle(4, 1, item.Width - 8, item.Height - 2);
            using (GraphicsPath p = RoundRect(r, 6f))
            using (SolidBrush b = new SolidBrush(HoverColor))
            {
                e.Graphics.FillPath(b, p);
            }
            Rectangle bar = new Rectangle(4, 5, 3, item.Height - 10);
            using (GraphicsPath p2 = RoundRect(bar, 1.5f))
            using (SolidBrush b2 = new SolidBrush(AccentColor))
            {
                e.Graphics.FillPath(b2, p2);
            }
        }
    }

    private Color TextColorFor(ToolStripItem item)
    {
        string tag = item.Tag as string;
        if (tag == "header") { return AccentColor; }
        if (tag == "status") { return MutedColor; }
        if (!item.Enabled) { return MutedColor; }
        if (item.ForeColor != Color.Empty) { return item.ForeColor; }
        return TextColor;
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        Color color = TextColorFor(e.Item);
        Rectangle content = e.Item.ContentRectangle;
        int x = e.TextRectangle.X;
        int w = e.TextRectangle.Width;
        if (w <= 0) { w = e.Item.Width - x - 2; }
        Size proposed = new Size(w, int.MaxValue);
        Size textSize = TextRenderer.MeasureText(e.Graphics, e.Text, e.Item.Font, proposed,
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
        int y = content.Top + (content.Height - textSize.Height) / 2;
        Rectangle textRect = new Rectangle(x, y, w, textSize.Height);
        TextRenderer.DrawText(e.Graphics, e.Text, e.Item.Font, textRect, color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        int y = e.Item.Height / 2;
        using (Pen pen = new Pen(SeparatorColor))
        {
            e.Graphics.DrawLine(pen, 12, y, e.Item.Width - 12, y);
        }
    }

    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        Rectangle content = e.Item.ContentRectangle;
        int s = Math.Min(e.ImageRectangle.Width, e.ImageRectangle.Height);
        if (s <= 0) { s = 18; }
        int lift = (int)Math.Round(e.Item.Font.Size * e.Graphics.DpiX / 72.0 * 0.13);
        int bx = e.ImageRectangle.X + (e.ImageRectangle.Width - s) / 2;
        int by = content.Top + (content.Height - s) / 2 + lift;
        Rectangle box = new Rectangle(bx, by, s, s);
        box.Inflate(-1, -1);
        using (GraphicsPath p = RoundRect(box, 4f))
        using (SolidBrush b = new SolidBrush(AccentColor))
        {
            e.Graphics.FillPath(b, p);
        }
        using (Pen pen = new Pen(Color.White, Math.Max(1.6f, s / 10f)))
        {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            pen.LineJoin = LineJoin.Round;
            float x = box.X + box.Width * 0.22f;
            float y = box.Y + box.Height * 0.52f;
            e.Graphics.DrawLines(pen, new PointF[]
            {
                new PointF(x, y),
                new PointF(box.X + box.Width * 0.42f, box.Y + box.Height * 0.70f),
                new PointF(box.X + box.Width * 0.78f, box.Y + box.Height * 0.30f)
            });
        }
    }

    protected override void OnRenderItemImage(ToolStripItemImageRenderEventArgs e)
    {
        string tag = e.Item.Tag as string;
        bool isAutostart = (tag == "trayautostart" || tag == "webautostart" || tag == "autostart");
        if (isAutostart && e.Item is ToolStripMenuItem && ((ToolStripMenuItem)e.Item).Checked)
        {
            return;
        }
        if (e.Image == null) { return; }
        Rectangle content = e.Item.ContentRectangle;
        int lift = (int)Math.Round(e.Item.Font.Size * e.Graphics.DpiX / 72.0 * 0.13);
        int x = e.ImageRectangle.X + (e.ImageRectangle.Width - e.Image.Width) / 2;
        int y = content.Top + (content.Height - e.Image.Height) / 2 + lift;
        bool keepColor = (tag == "header" || tag == "status");
        if (!e.Item.Enabled && !keepColor)
        {
            ControlPaint.DrawImageDisabled(e.Graphics, e.Image, x, y, Bg);
        }
        else
        {
            e.Graphics.DrawImage(e.Image, new Rectangle(x, y, e.Image.Width, e.Image.Height));
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $script:RendererSource -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing')
} catch {
    Write-TrayError ('renderer compile failed: ' + ($_ | Out-String))
    throw
}

if (-not $PreviewMenu) {
    $script:mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, 'Local\DSHWebTray'
    if (-not $script:mutex.WaitOne(0)) { exit 0 }
    $script:HasMutex = $true
}

# --- helpers ----------------------------------------------------------------
function Invoke-DshWeb([string]$Action) {
    $out = & $script:WslExe -d $script:Distro -u $script:WslUser -- $script:WslScript $Action 2>&1
    $code = $LASTEXITCODE
    $text = (($out | ForEach-Object { "$_" }) -join "`n").Trim()
    return [pscustomobject]@{ Text = $text; Code = $code }
}

function New-Pad([int]$Left, [int]$Top, [int]$Right, [int]$Bottom) {
    return (New-Object -TypeName System.Windows.Forms.Padding -ArgumentList @($Left, $Top, $Right, $Bottom))
}

function Set-ItemImage($Item, $Image) {
    if ($null -eq $Item) { return }
    $old = $Item.Image
    $Item.Image = $Image
    if ($old -and -not [object]::ReferenceEquals($old, $Image)) {
        try { $old.Dispose() } catch { }
    }
}

function Get-IconBitmap([string]$Path, [int]$Size) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $ico = New-Object -TypeName System.Drawing.Icon -ArgumentList @($Path, $Size, $Size)
    try { return $ico.ToBitmap() } finally { $ico.Dispose() }
}

function New-GlyphBitmap([int]$Glyph, [System.Drawing.Color]$Color, [int]$Size) {
    $bmp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList @($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $font = $null
    $brush = $null
    $fmt = $null
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $font = New-Object -TypeName System.Drawing.Font -ArgumentList @('Segoe MDL2 Assets', [float]($Size * 0.80), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList @($Color)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object -TypeName System.Drawing.RectangleF -ArgumentList @(0, 0, $Size, $Size)
        $g.DrawString([string][char]$Glyph, $font, $brush, $rect, $fmt)
    } catch {
        $bmp.Dispose()
        throw
    } finally {
        if ($fmt) { $fmt.Dispose() }
        if ($brush) { $brush.Dispose() }
        if ($font) { $font.Dispose() }
        $g.Dispose()
    }
    return $bmp
}

function New-DotBitmap([int]$Size, [System.Drawing.Color]$Color) {
    $bmp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList @($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $brush = $null
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $d = [int]($Size * 0.44)
        $x = [int](($Size - $d) / 2)
        $brush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList @($Color)
        $g.FillEllipse($brush, $x, $x, $d, $d)
    } finally {
        if ($brush) { $brush.Dispose() }
        $g.Dispose()
    }
    return $bmp
}

function Get-Palette {
    if ($script:Light) {
        return @{
            Bg     = [System.Drawing.Color]::FromArgb(255, 255, 255)
            Text   = [System.Drawing.Color]::FromArgb(31, 41, 55)
            Muted  = [System.Drawing.Color]::FromArgb(107, 114, 128)
            Accent = [System.Drawing.Color]::FromArgb(77, 107, 254)
            Icon   = [System.Drawing.Color]::FromArgb(91, 107, 133)
            Green  = [System.Drawing.Color]::FromArgb(22, 163, 74)
            Danger = [System.Drawing.Color]::FromArgb(229, 72, 77)
            DotOn  = [System.Drawing.Color]::FromArgb(34, 197, 94)
            DotOff = [System.Drawing.Color]::FromArgb(148, 163, 184)
        }
    }
    return @{
        Bg     = [System.Drawing.Color]::FromArgb(30, 32, 36)
        Text   = [System.Drawing.Color]::FromArgb(232, 234, 237)
        Muted  = [System.Drawing.Color]::FromArgb(154, 160, 166)
        Accent = [System.Drawing.Color]::FromArgb(138, 180, 248)
        Icon   = [System.Drawing.Color]::FromArgb(180, 190, 205)
        Green  = [System.Drawing.Color]::FromArgb(74, 222, 128)
        Danger = [System.Drawing.Color]::FromArgb(255, 138, 138)
        DotOn  = [System.Drawing.Color]::FromArgb(74, 222, 128)
        DotOff = [System.Drawing.Color]::FromArgb(148, 163, 184)
    }
}

function Update-TrayIcon {
    if ($script:IconDpi -eq [int]$script:Dpi -and $script:IconOn -and $script:IconOff) { return }
    $want = [int][Math]::Round(16 * $script:Dpi / 96.0)
    if ($want -lt 16) { $want = 16 }
    $sizes = @(16, 20, 24, 28, 32, 40, 48, 64, 128)
    $best = $sizes[0]
    foreach ($s in $sizes) {
        if ([Math]::Abs($s - $want) -lt [Math]::Abs($best - $want)) { $best = $s }
    }
    try {
        $newOn = New-Object -TypeName System.Drawing.Icon -ArgumentList @($script:IconOnPath, $best, $best)
        $newOff = New-Object -TypeName System.Drawing.Icon -ArgumentList @($script:IconOffPath, $best, $best)
    } catch {
        Write-TrayError ('icon load failed: ' + ($_ | Out-String))
        return
    }
    $oldOn = $script:IconOn
    $oldOff = $script:IconOff
    $script:IconOn = $newOn
    $script:IconOff = $newOff
    $script:IconDpi = [int]$script:Dpi
    if ($script:ni) {
        $script:ni.Icon = if ($script:Running) { $newOn } else { $newOff }
    }
    if ($oldOn) { try { $oldOn.Dispose() } catch { } }
    if ($oldOff) { try { $oldOff.Dispose() } catch { } }
}

function Apply-MenuTheme {
    $script:Light = Get-IsLightTheme
    $p = Get-Palette
    $script:menu.Renderer = New-Object -TypeName DshMenuRenderer -ArgumentList @($script:Light)
    $script:menu.BackColor = $p.Bg
    $script:menu.ForeColor = $p.Text
    $script:miHeader.ForeColor = $p.Accent
    $script:miStatus.ForeColor = $p.Muted
    $script:miOpen.ForeColor = $p.Accent
    $script:miStart.ForeColor = $p.Text
    $script:miStop.ForeColor = $p.Text
    $script:miRestart.ForeColor = $p.Text
    $script:miLog.ForeColor = $p.Text
    $script:miTrayAutostart.ForeColor = $p.Text
    $script:miWebAutostart.ForeColor = $p.Text
    $script:miExit.ForeColor = $p.Muted

    Set-ItemImage $script:miHeader (Get-IconBitmap $script:IconOnPath $script:MenuIconSize)
    Set-ItemImage $script:miStatus (New-DotBitmap $script:MenuIconSize $p.DotOff)
    Set-ItemImage $script:miOpen (New-GlyphBitmap 0xE774 $p.Accent $script:MenuIconSize)
    Set-ItemImage $script:miStart (New-GlyphBitmap 0xE768 $p.Green $script:MenuIconSize)
    Set-ItemImage $script:miStop (New-GlyphBitmap 0xE71A $p.Danger $script:MenuIconSize)
    Set-ItemImage $script:miRestart (New-GlyphBitmap 0xE72C $p.Accent $script:MenuIconSize)
    Set-ItemImage $script:miLog (New-GlyphBitmap 0xE8A5 $p.Icon $script:MenuIconSize)
    Set-ItemImage $script:miTrayAutostart (New-GlyphBitmap 0xE7E8 $p.Icon $script:MenuIconSize)
    Set-ItemImage $script:miWebAutostart (New-GlyphBitmap 0xE768 $p.Green $script:MenuIconSize)
    Set-ItemImage $script:miExit (New-GlyphBitmap 0xE8BB $p.Muted $script:MenuIconSize)
}

function Update-Ui {
    Update-TrayIcon
    $p = Get-Palette
    if ($script:Running) {
        $script:ni.Icon = $script:IconOn
        $script:ni.Text = 'DSH Web · 运行中'
        $script:miStatus.Text = '运行中 · 127.0.0.1:3080'
        $script:miOpen.Text = '打开 Web UI'
        $dot = $p.DotOn
    } else {
        $script:ni.Icon = $script:IconOff
        $script:ni.Text = 'DSH Web · 已停止'
        $script:miStatus.Text = '已停止 · 127.0.0.1:3080'
        $script:miOpen.Text = '启动并打开 Web UI'
        $dot = $p.DotOff
    }
    $script:miStart.Enabled = -not $script:Running
    $script:miStop.Enabled = $script:Running
    $script:miRestart.Enabled = $script:Running
    $script:miTrayAutostart.Checked = Test-Path -LiteralPath $script:TrayStartupLnk
    $script:miWebAutostart.Checked = Test-Path -LiteralPath $script:WebStartupLnk
    Set-ItemImage $script:miStatus (New-DotBitmap $script:MenuIconSize $dot)
}

function Refresh-State {
    try {
        $r = Invoke-DshWeb 'status'
        $script:Running = ($r.Code -eq 0 -and $r.Text -match '^running')
        $script:LastStatus = $r.Text
    } catch {
        $script:Running = $false
        Write-TrayError ($_ | Out-String)
    }
    Update-Ui
    return $script:Running
}

function Show-Balloon([string]$Text, [string]$Kind) {
    try {
        if (-not $script:ni -or -not $script:ni.Visible) { return }
        if (-not $Text) { $Text = '操作完成' }
        if ($Text.Length -gt 250) { $Text = $Text.Substring(0, 250) }
        $script:ni.BalloonTipTitle = 'DSH Web'
        $script:ni.BalloonTipText = $Text
        switch ($Kind) {
            'Warning' { $script:ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning }
            'Error'   { $script:ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error }
            default   { $script:ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $script:ni.ShowBalloonTip(4000)
    } catch { Write-TrayError ($_ | Out-String) }
}

function Do-Action([string]$Action) {
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $r = Invoke-DshWeb $Action
        if ($r.Code -ne 0) {
            Show-Balloon $r.Text 'Warning'
        } else {
            switch ($Action) {
                'start'   { Show-Balloon ('已启动：' + $script:WebUrl) 'Info' }
                'stop'    { Show-Balloon 'DSH Web 已停止' 'Info' }
                'restart' { Show-Balloon ('已重启：' + $script:WebUrl) 'Info' }
            }
        }
        [void](Refresh-State)
    } catch {
        Write-TrayError ($_ | Out-String)
        Show-Balloon ('操作失败：' + $_.Exception.Message) 'Error'
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
}

function Open-Web {
    if (-not $script:Running) {
        Do-Action 'start'
        if (-not $script:Running) { return }
    }
    try {
        Start-Process $script:WebUrl
    } catch {
        Write-TrayError ($_ | Out-String)
        Show-Balloon ('无法打开浏览器：' + $_.Exception.Message) 'Error'
    }
}

function Open-Log {
    try {
        $tmp = Join-Path $env:TEMP 'dsh-web.log'
        $out = & $script:WslExe -d $script:Distro -u $script:WslUser -- /usr/bin/tail -n 300 $script:WslLog 2>&1
        ($out | ForEach-Object { "$_" }) | Set-Content -LiteralPath $tmp -Encoding UTF8
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $tmp + '"')
    } catch {
        Write-TrayError ($_ | Out-String)
        Show-Balloon ('无法打开日志：' + $_.Exception.Message) 'Error'
    }
}

function New-StartupShortcut([string]$Path, [string]$Arguments, [string]$Description) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($Path)
    $sc.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $script:AppDir
    $sc.IconLocation = $script:IconOnPath + ',0'
    $sc.Description = $Description
    $sc.Save()
}

function Set-TrayAutostart([bool]$Enable) {
    try {
        if ($Enable) {
            New-StartupShortcut $script:TrayStartupLnk ('"' + $script:VbsPath + '"') 'DSH Web tray controller'
            Show-Balloon '托盘已设置为登录时自动启动' 'Info'
        } else {
            Remove-Item -LiteralPath $script:TrayStartupLnk -Force -ErrorAction SilentlyContinue
            Show-Balloon '已取消托盘开机自启' 'Info'
        }
    } catch {
        Write-TrayError ($_ | Out-String)
        Show-Balloon ('设置托盘自启失败：' + $_.Exception.Message) 'Error'
    }
    Update-Ui
}

function Set-WebAutostart([bool]$Enable) {
    try {
        if ($Enable) {
            if (-not (Test-Path -LiteralPath $script:AutoStartVbs)) {
                throw ('缺少文件：' + $script:AutoStartVbs)
            }
            New-StartupShortcut $script:WebStartupLnk ('"' + $script:AutoStartVbs + '"') 'Start dsh web at logon'
            Show-Balloon 'dsh web 已设置为登录时自动启动' 'Info'
        } else {
            Remove-Item -LiteralPath $script:WebStartupLnk -Force -ErrorAction SilentlyContinue
            Show-Balloon '已取消 dsh web 开机自启' 'Info'
        }
    } catch {
        Write-TrayError ($_ | Out-String)
        Show-Balloon ('设置 dsh web 自启失败：' + $_.Exception.Message) 'Error'
    }
    Update-Ui
}

function Build-Menu {
    $script:menu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:menu.Font = $script:BaseFont
    $script:menu.Padding = New-Pad 0 0 0 0
    $script:menu.ShowImageMargin = $true
    $script:menu.ShowCheckMargin = $false
    $script:menu.DropShadowEnabled = $true
    $script:menu.ImageScalingSize = New-Object -TypeName System.Drawing.Size -ArgumentList @($script:MenuIconSize, $script:MenuIconSize)

    $itemPad = New-Pad 0 ([int](7 * $script:Scale)) ([int](12 * $script:Scale)) ([int](7 * $script:Scale))

    $script:miHeader = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miHeader.Text = 'DSH Web'
    $script:miHeader.Tag = 'header'
    $script:miHeader.Enabled = $false
    $script:miHeader.Font = $script:HeaderFont
    $script:miHeader.Padding = New-Pad 0 ([int](12 * $script:Scale)) ([int](12 * $script:Scale)) ([int](2 * $script:Scale))

    $script:miStatus = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miStatus.Text = '已停止 · 127.0.0.1:3080'
    $script:miStatus.Tag = 'status'
    $script:miStatus.Enabled = $false
    $script:miStatus.Font = $script:StatusFont
    $script:miStatus.Padding = New-Pad 0 0 ([int](12 * $script:Scale)) ([int](8 * $script:Scale))

    $script:miOpen = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miOpen.Text = '打开 Web UI'
    $script:miOpen.Tag = 'open'
    $script:miOpen.Font = $script:OpenFont
    $script:miOpen.Padding = $itemPad
    $script:miOpen.Add_Click({ try { Open-Web } catch { Write-TrayError ($_ | Out-String) } })

    $script:miStart = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miStart.Text = '启动'
    $script:miStart.Tag = 'start'
    $script:miStart.Padding = $itemPad
    $script:miStart.Add_Click({ try { Do-Action 'start' } catch { Write-TrayError ($_ | Out-String) } })

    $script:miStop = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miStop.Text = '停止'
    $script:miStop.Tag = 'stop'
    $script:miStop.Padding = $itemPad
    $script:miStop.Add_Click({ try { Do-Action 'stop' } catch { Write-TrayError ($_ | Out-String) } })

    $script:miRestart = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miRestart.Text = '重启'
    $script:miRestart.Tag = 'restart'
    $script:miRestart.Padding = $itemPad
    $script:miRestart.Add_Click({ try { Do-Action 'restart' } catch { Write-TrayError ($_ | Out-String) } })

    $script:miLog = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miLog.Text = '查看日志'
    $script:miLog.Tag = 'log'
    $script:miLog.Padding = $itemPad
    $script:miLog.Add_Click({ try { Open-Log } catch { Write-TrayError ($_ | Out-String) } })

    $script:miTrayAutostart = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miTrayAutostart.Text = '托盘开机自启'
    $script:miTrayAutostart.Tag = 'trayautostart'
    $script:miTrayAutostart.CheckOnClick = $false
    $script:miTrayAutostart.Padding = $itemPad
    $script:miTrayAutostart.Add_Click({
        try { Set-TrayAutostart (-not $script:miTrayAutostart.Checked) } catch { Write-TrayError ($_ | Out-String) }
    })

    $script:miWebAutostart = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miWebAutostart.Text = 'dsh web 开机自启'
    $script:miWebAutostart.Tag = 'webautostart'
    $script:miWebAutostart.CheckOnClick = $false
    $script:miWebAutostart.Padding = $itemPad
    $script:miWebAutostart.Add_Click({
        try { Set-WebAutostart (-not $script:miWebAutostart.Checked) } catch { Write-TrayError ($_ | Out-String) }
    })

    $script:miExit = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:miExit.Text = '退出托盘'
    $script:miExit.Tag = 'exit'
    $script:miExit.Padding = $itemPad
    $script:miExit.Add_Click({
        try {
            $script:ni.Visible = $false
            [System.Windows.Forms.Application]::Exit()
        } catch { Write-TrayError ($_ | Out-String) }
    })

    [void]$script:menu.Items.Add($script:miHeader)
    [void]$script:menu.Items.Add($script:miStatus)
    [void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:menu.Items.Add($script:miOpen)
    [void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:menu.Items.Add($script:miStart)
    [void]$script:menu.Items.Add($script:miStop)
    [void]$script:menu.Items.Add($script:miRestart)
    [void]$script:menu.Items.Add($script:miLog)
    [void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:menu.Items.Add($script:miTrayAutostart)
    [void]$script:menu.Items.Add($script:miWebAutostart)
    [void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:menu.Items.Add($script:miExit)

    $script:menu.MinimumSize = New-Object -TypeName System.Drawing.Size -ArgumentList @([int](260 * $script:Scale), 0)

    $script:menu.Add_Opening({
        try {
            if ((Get-IsLightTheme) -ne $script:Light) { Apply-MenuTheme }
            if (-not $script:Running) { [void](Refresh-State) } else { Update-Ui }
        } catch { Write-TrayError ($_ | Out-String) }
    })

    $script:menu.Add_HandleCreated({
        try {
            $v = 2
            [void][DshDwm]::DwmSetWindowAttribute($script:menu.Handle, 33, [ref]$v, 4)
        } catch { }
    })
}

# --- main -------------------------------------------------------------------
try {
    $script:BaseFont = New-Object -TypeName System.Drawing.Font -ArgumentList @('Microsoft YaHei UI', [float]9.5)
    $script:HeaderFont = New-Object -TypeName System.Drawing.Font -ArgumentList @('Microsoft YaHei UI', [float]11.5, [System.Drawing.FontStyle]::Bold)
    $script:OpenFont = New-Object -TypeName System.Drawing.Font -ArgumentList @('Microsoft YaHei UI', [float]10.0, [System.Drawing.FontStyle]::Bold)
    $script:StatusFont = New-Object -TypeName System.Drawing.Font -ArgumentList @('Microsoft YaHei UI', [float]8.5)

    Build-Menu
    Apply-MenuTheme

    $script:ni = New-Object System.Windows.Forms.NotifyIcon
    $script:ni.ContextMenuStrip = $script:menu
    $script:ni.Visible = $true
    if ($PreviewMenu) { $script:ni.Visible = $false }

    Update-Ui
    [void](Refresh-State)

    if (-not $PreviewMenu -and -not (Test-Path -LiteralPath $script:FirstRunMarker)) {
        try { Set-Content -LiteralPath $script:FirstRunMarker -Value (Get-Date -Format s) -Encoding ASCII } catch { }
        $script:firstRunTimer = New-Object System.Windows.Forms.Timer
        $script:firstRunTimer.Interval = 1200
        $script:firstRunTimer.Add_Tick({
            try {
                $script:firstRunTimer.Stop()
                Show-Balloon '托盘已启动。右键此图标可启动/停止/重启 DSH Web。若看不到图标，请从任务栏 ^ 溢出区把它拖到任务栏。' 'Info'
            } catch { Write-TrayError ($_ | Out-String) }
        })
        $script:firstRunTimer.Start()
    }

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 10000
    $script:timer.Add_Tick({
        try {
            if ($script:Running) { [void](Refresh-State) }
        } catch { Write-TrayError ($_ | Out-String) }
    })
    $script:timer.Start()

    if ($PreviewMenu) {
        $script:previewBackdrop = New-Object System.Windows.Forms.Form
        $script:previewBackdrop.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $script:previewBackdrop.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $script:previewBackdrop.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 0, 0
        $script:previewBackdrop.Size = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
        $script:previewBackdrop.BackColor = [System.Drawing.Color]::FromArgb(233, 238, 246)
        $script:previewBackdrop.ShowInTaskbar = $false
        $script:previewBackdrop.Show()
        $shotPath = $PreviewShot
        if (-not $shotPath) { $shotPath = Join-Path $script:AppDir 'menu-preview.png' }
        $script:previewTimer = New-Object System.Windows.Forms.Timer
        $script:previewTimer.Interval = 1200
        $script:previewTimer.Add_Tick({
            try {
                $script:previewTimer.Stop()
                $script:menu.Show(120, 120)
                try { $script:miOpen.Select() } catch { }
                $script:previewShotTimer = New-Object System.Windows.Forms.Timer
                $script:previewShotTimer.Interval = 900
                $script:previewShotTimer.Add_Tick({
                    try {
                        $script:previewShotTimer.Stop()
                        $bmp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList @(420, 620)
                        $g = [System.Drawing.Graphics]::FromImage($bmp)
                        try {
                            $g.CopyFromScreen(100, 100, 0, 0, $bmp.Size)
                            $bmp.Save($shotPath, [System.Drawing.Imaging.ImageFormat]::Png)
                        } finally {
                            $g.Dispose()
                            $bmp.Dispose()
                        }
                        [System.Windows.Forms.Application]::Exit()
                    } catch {
                        Write-TrayError ($_ | Out-String)
                        [System.Windows.Forms.Application]::Exit()
                    }
                })
                $script:previewShotTimer.Start()
            } catch {
                Write-TrayError ($_ | Out-String)
                [System.Windows.Forms.Application]::Exit()
            }
        })
        $script:previewTimer.Start()
    }

    [System.Windows.Forms.Application]::Run()
} catch {
    Write-TrayError ($_ | Out-String)
} finally {
    try { if ($script:timer) { $script:timer.Stop(); $script:timer.Dispose() } } catch { }
    try { if ($script:firstRunTimer) { $script:firstRunTimer.Stop(); $script:firstRunTimer.Dispose() } } catch { }
    try { if ($script:previewTimer) { $script:previewTimer.Stop(); $script:previewTimer.Dispose() } } catch { }
    try { if ($script:previewShotTimer) { $script:previewShotTimer.Stop(); $script:previewShotTimer.Dispose() } } catch { }
    try { if ($script:previewBackdrop) { $script:previewBackdrop.Close(); $script:previewBackdrop.Dispose() } } catch { }
    try { if ($script:ni) { $script:ni.Visible = $false; $script:ni.Dispose() } } catch { }
    try {
        if ($script:menu) {
            foreach ($item in $script:menu.Items) {
                if ($item.Image) { try { $item.Image.Dispose() } catch { } }
            }
            $script:menu.Dispose()
        }
    } catch { }
    try { if ($script:BaseFont) { $script:BaseFont.Dispose() } } catch { }
    try { if ($script:HeaderFont) { $script:HeaderFont.Dispose() } } catch { }
    try { if ($script:OpenFont) { $script:OpenFont.Dispose() } } catch { }
    try { if ($script:StatusFont) { $script:StatusFont.Dispose() } } catch { }
    try { if ($script:IconOn) { $script:IconOn.Dispose() } } catch { }
    try { if ($script:IconOff) { $script:IconOff.Dispose() } } catch { }
    try { if ($script:HasMutex -and $script:mutex) { $script:mutex.ReleaseMutex() } } catch { }
    try { if ($script:mutex) { $script:mutex.Dispose() } } catch { }
}
