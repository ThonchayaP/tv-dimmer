$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\tv-dimmer-ui', [ref]$created)
$showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\tv-dimmer-ui-show')
if (-not $created) {
    [void]$showEvt.Set()
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TvGamma
{
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateDC(string driver, string device, string output, IntPtr initData);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool SetDeviceGammaRamp(IntPtr hdc, ushort[] ramp);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string device, uint devNum, ref DISPLAY_DEVICE dd, uint flags);

    public static bool Apply(int pct)
    {
        ushort[] ramp = new ushort[768];
        for (int i = 0; i < 256; i++)
        {
            int v = i * 257 * pct / 100;
            if (v > 65535) v = 65535;
            ramp[i] = (ushort)v;
            ramp[256 + i] = (ushort)v;
            ramp[512 + i] = (ushort)v;
        }

        bool any = false, allOk = true;
        DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
        dd.cb = Marshal.SizeOf(dd);
        for (uint n = 0; EnumDisplayDevices(null, n, ref dd, 0); n++)
        {
            if ((dd.StateFlags & 1) != 0)
            {
                IntPtr hdc = CreateDC(null, dd.DeviceName, null, IntPtr.Zero);
                if (hdc == IntPtr.Zero) hdc = CreateDC(dd.DeviceName, null, null, IntPtr.Zero);
                if (hdc != IntPtr.Zero)
                {
                    any = true;
                    if (!SetDeviceGammaRamp(hdc, ramp)) allOk = false;
                    DeleteDC(hdc);
                }
            }
            dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
        }
        return any && allOk;
    }
}

public class TvHotkeys : System.Windows.Forms.NativeWindow
{
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public Action<int> OnKey;
    public bool Ok;

    public TvHotkeys()
    {
        CreateHandle(new System.Windows.Forms.CreateParams());
        uint mods = 0x1 | 0x2;
        Ok = RegisterHotKey(Handle, 1, mods, 0x22);
        Ok &= RegisterHotKey(Handle, 2, mods, 0x21);
        Ok &= RegisterHotKey(Handle, 3, mods, 0x24);
    }

    protected override void WndProc(ref System.Windows.Forms.Message m)
    {
        if (m.Msg == 0x0312 && OnKey != null) OnKey(m.WParam.ToInt32());
        base.WndProc(ref m);
    }

    public void Release()
    {
        UnregisterHotKey(Handle, 1);
        UnregisterHotKey(Handle, 2);
        UnregisterHotKey(Handle, 3);
        DestroyHandle();
    }
}
'@

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ความสว่างจอ" Width="380" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Topmost="True"
        FontFamily="Leelawadee UI, Segoe UI">
  <Window.Resources>
    <Style x:Key="FillBtn" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Grid Background="Transparent">
              <Border Height="6" CornerRadius="3" Background="#0A84FF" VerticalAlignment="Center"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="EmptyBtn" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Grid Background="Transparent"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Knob" TargetType="Thumb">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Ellipse Width="22" Height="22" Fill="White">
              <Ellipse.Effect>
                <DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.4"/>
              </Ellipse.Effect>
            </Ellipse>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid Height="30">
              <Border Height="6" CornerRadius="3" Background="#3A3A3C" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge" Style="{StaticResource FillBtn}"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge" Style="{StaticResource EmptyBtn}"/>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Style="{StaticResource Knob}"/>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="#2C2C2E"/>
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Opacity" Value="0.8"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CaptionBtn" TargetType="Button">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Foreground" Value="#DDDDDD"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#3A3A3C"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CloseCaptionBtn" TargetType="Button" BasedOn="{StaticResource CaptionBtn}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#C42B1C"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="18" Background="#1C1C1E" BorderBrush="#3A3A3C" BorderThickness="1" Padding="22">
    <StackPanel>
      <Grid>
        <TextBlock Text="ความสว่างจอ" Foreground="#AAAAAA" FontSize="14" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,-10,-12,0">
          <Button x:Name="MinBtn" Content="&#xE921;" Style="{StaticResource CaptionBtn}" ToolTip="ย่อหน้าต่าง"/>
          <Button x:Name="CloseBtn" Content="&#xE8BB;" Style="{StaticResource CloseCaptionBtn}" ToolTip="ปิดหน้าต่าง (ค่าที่ปรับไว้ยังอยู่)"/>
        </StackPanel>
      </Grid>
      <TextBlock x:Name="Pct" Text="100%" Foreground="White" FontSize="44" FontWeight="SemiBold" Margin="0,2,0,8"/>
      <Slider x:Name="Bright" Minimum="20" Maximum="100" Value="100"
              IsMoveToPointEnabled="True" IsSnapToTickEnabled="True" TickFrequency="1"
              SmallChange="5" LargeChange="10"/>
      <TextBlock x:Name="Warn" Foreground="#FF9F0A" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,0"/>
      <Grid Margin="0,14,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="10"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="ResetBtn" Grid.Column="0" Content="รีเซ็ต 100%" Style="{StaticResource Btn}" Background="#0A84FF"/>
        <Button x:Name="QuitBtn" Grid.Column="2" Content="ออกและคืนค่า" Style="{StaticResource Btn}"/>
      </Grid>
      <TextBlock Text="ปุ่มลัด: Ctrl+Alt+PageDown หรี่ลง / PageUp สว่างขึ้น / Home รีเซ็ต" Foreground="#6E6E73" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$root     = $window.FindName('Root')
$pct      = $window.FindName('Pct')
$slider   = $window.FindName('Bright')
$warn     = $window.FindName('Warn')
$resetBtn = $window.FindName('ResetBtn')
$quitBtn  = $window.FindName('QuitBtn')
$closeBtn = $window.FindName('CloseBtn')
$minBtn   = $window.FindName('MinBtn')

$script:level = 100
$script:syncing = $false
$script:quitting = $false

function Set-Level([int]$v) {
    $v = [Math]::Max(20, [Math]::Min(100, $v))
    if ([TvGamma]::Apply($v)) {
        $script:level = $v
        $warn.Text = ''
    } else {
        [void][TvGamma]::Apply($script:level)
        $warn.Text = "Windows ไม่ยอมให้หรี่ถึง $v% ให้รีสตาร์ทเครื่อง 1 ครั้งแล้วลองใหม่"
    }
    $pct.Text = "$($script:level)%"
    if ([int]$slider.Value -ne $script:level) {
        $script:syncing = $true
        $slider.Value = $script:level
        $script:syncing = $false
    }
}

$slider.Add_ValueChanged({
    if (-not $script:syncing) { Set-Level ([int][Math]::Round($slider.Value)) }
})
$resetBtn.Add_Click({ Set-Level 100 })
$closeBtn.Add_Click({ $window.Hide() })
$minBtn.Add_Click({ $window.WindowState = 'Minimized' })
$quitBtn.Add_Click({
    Set-Level 100
    $script:quitting = $true
    $window.Close()
})
$root.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Hide() } })
$window.Add_Closing({
    if (-not $script:quitting) {
        $_.Cancel = $true
        $window.Hide()
    }
})

$hotkeys = New-Object TvHotkeys
$hotkeys.OnKey = [Action[int]]{
    param($id)
    if ($id -eq 1) { Set-Level ($script:level - 10) }
    elseif ($id -eq 2) { Set-Level ($script:level + 10) }
    elseif ($id -eq 3) { Set-Level 100 }
}
if (-not $hotkeys.Ok) { $warn.Text = 'ปุ่มลัดบางปุ่มถูกโปรแกรมอื่นใช้อยู่ ใช้แถบเลื่อนแทนได้' }

$keeper = New-Object System.Windows.Threading.DispatcherTimer
$keeper.Interval = [TimeSpan]::FromSeconds(3)
$keeper.Add_Tick({ if ($script:level -lt 100) { [void][TvGamma]::Apply($script:level) } })
$keeper.Start()

$watcher = New-Object System.Windows.Threading.DispatcherTimer
$watcher.Interval = [TimeSpan]::FromMilliseconds(300)
$watcher.Add_Tick({
    if ($showEvt.WaitOne(0)) {
        $window.Show()
        $window.WindowState = 'Normal'
        $window.Activate()
    }
})
$watcher.Start()

$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$window.Add_Closed({
    $keeper.Stop()
    $watcher.Stop()
    $hotkeys.Release()
    $app.Shutdown()
})

[void][TvGamma]::Apply(100)
$app.Run($window) | Out-Null
$mutex.ReleaseMutex()
