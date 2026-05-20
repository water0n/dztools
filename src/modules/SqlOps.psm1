if ($PSVersionTable.PSVersion.Major -lt 5) { throw "Se requiere PowerShell 5.0 o superior." }
#SqlOps.psm1 - Módulo de operaciones SQL Server
function Show-AttachDialog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$ModulesPath,
    [Parameter(Mandatory = $false)][scriptblock]$OnAttachCompleted
  )
  $script:AttachRunning = $false
  $script:AttachDone = $false
  Write-DzDebug "`t[DEBUG][Show-AttachDialog] INICIO"
  Write-DzDebug "`t[DEBUG][Show-AttachDialog] Server='$Server' User='$User'"
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName System.Windows.Forms
  $theme = Get-DzUiTheme
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Adjuntar base de datos"
        Width="800" Height="720"
        MinWidth="800" MinHeight="720"
        MaxWidth="800" MaxHeight="720"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="GroupBox">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style x:Key="TextBoxStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Foreground" Value="{DynamicResource AccentSecondary}"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DangerButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentMagenta}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="12" Margin="10" SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" CornerRadius="12,12,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentPrimary}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="📎 Adjuntar Base de Datos (Attach)" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" FontSize="12"/>
            <TextBlock Text="Selecciona MDF/LDF y configura opciones antes de ejecutar." Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnCloseX" Style="{StaticResource IconButtonStyle}" Content="✕" ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="12,12,12,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="Archivo MDF (datos):" Margin="0,0,0,6"/>
          <Grid Grid.Row="1" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="txtMdfPath" Grid.Column="0" Style="{StaticResource TextBoxStyle}"/>
            <Button x:Name="btnBrowseMdf" Grid.Column="1" Content="Examinar..." Width="120" Margin="10,0,0,0" Style="{StaticResource SecondaryButtonStyle}"/>
          </Grid>
          <TextBlock Grid.Row="2" Text="Archivo LDF (log):" Margin="0,0,0,6"/>
          <Grid Grid.Row="3" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="txtLdfPath" Grid.Column="0" Style="{StaticResource TextBoxStyle}"/>
            <Button x:Name="btnBrowseLdf" Grid.Column="1" Content="Examinar..." Width="120" Margin="10,0,0,0" Style="{StaticResource SecondaryButtonStyle}"/>
          </Grid>
          <StackPanel Grid.Row="4" Margin="0,0,0,12">
            <CheckBox x:Name="chkRebuildLog" Content="Reconstruir archivo de log si no existe" Margin="0,0,0,8"/>
            <CheckBox x:Name="chkReadOnly" Content="Adjuntar como solo lectura"/>
          </StackPanel>
          <TextBlock Grid.Row="5" Text="Nombre de la base de datos (Attach As):" Margin="0,0,0,6"/>
          <TextBox x:Name="txtDbName" Grid.Row="6" Style="{StaticResource TextBoxStyle}" Margin="0,0,0,12"/>
          <TextBlock Grid.Row="7" Text="Owner (opcional):" Margin="0,0,0,6"/>
          <TextBox x:Name="txtOwner" Grid.Row="8" Style="{StaticResource TextBoxStyle}"/>
        </Grid>
      </Border>
      <Border Grid.Row="2" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="10" Margin="12,0,12,12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="Progreso" FontWeight="SemiBold" Margin="0,0,0,6"/>
              <ProgressBar x:Name="pbAttach" Height="20" Minimum="0" Maximum="100" Value="0"/>
              <TextBlock x:Name="txtProgress" Text="Esperando..." Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource AccentMuted}"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="1" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="8" Margin="0,0,0,10">
            <TextBox x:Name="txtLog" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Height="110" TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" BorderThickness="0" Background="Transparent"/>
          </Border>
          <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Enter: Adjuntar   |   Esc: Cerrar" Foreground="{DynamicResource AccentMuted}" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="btnAttach" Content="Adjuntar" Width="140" Margin="0,0,10,0" Style="{StaticResource DangerButtonStyle}"/>
              <Button x:Name="btnClose" Content="Cerrar" Width="120" Style="{StaticResource SecondaryButtonStyle}"/>
            </StackPanel>
          </Grid>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@

  $ui = $null
  $window = $null
  $c = $null
  try {
    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $window = $ui.Window
    $c = $ui.Controls
    try { Set-DzWpfThemeResources -Window $window -Theme $theme } catch { Write-DzDebug "`t[DEBUG][Show-RestoreDialog] No se pudo aplicar tema: $($_.Exception.Message)" }
    if (-not $window) { Write-DzDebug "`t[DEBUG][Show-AttachDialog] ERROR: window=NULL"; throw "No se pudo crear la ventana (XAML)." }
    try { Set-WpfDialogOwner -Dialog $window } catch {}
    try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
    $window.WindowStartupLocation = "Manual"
    $window.Add_Loaded({
        try {
          $owner = $window.Owner
          if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
          $ob = $owner.RestoreBounds
          $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
          $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $window.Left = [double]$left
          $window.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $window.DragMove() } catch {}
        }
      })
  } catch {
    Write-DzDebug "`t[DEBUG][Show-AttachDialog] ERROR creando ventana: $($_.Exception.Message)"
    throw "No se pudo crear la ventana (XAML). $($_.Exception.Message)"
  }
  $txtMdfPath = $window.FindName("txtMdfPath")
  $btnBrowseMdf = $window.FindName("btnBrowseMdf")
  $txtLdfPath = $window.FindName("txtLdfPath")
  $btnBrowseLdf = $window.FindName("btnBrowseLdf")
  $chkRebuildLog = $window.FindName("chkRebuildLog")
  $chkReadOnly = $window.FindName("chkReadOnly")
  $txtDbName = $window.FindName("txtDbName")
  $txtOwner = $window.FindName("txtOwner")
  $pbAttach = $window.FindName("pbAttach")
  $txtProgress = $window.FindName("txtProgress")
  $txtLog = $window.FindName("txtLog")
  $btnAttach = $window.FindName("btnAttach")
  $btnClose = $window.FindName("btnClose")
  $btnCloseX = $window.FindName("btnCloseX")
  if (-not $txtMdfPath -or -not $btnBrowseMdf -or -not $txtLdfPath -or -not $btnBrowseLdf -or -not $chkRebuildLog -or -not $chkReadOnly -or -not $txtDbName -or -not $txtOwner -or -not $pbAttach -or -not $txtProgress -or -not $txtLog -or -not $btnAttach -or -not $btnClose -or -not $btnCloseX) { Write-DzDebug "`t[DEBUG][Show-AttachDialog] ERROR: controles NULL"; throw "Controles WPF incompletos (FindName devolvió NULL)." }
  $logQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $progressQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
  function Paint-Progress { param([int]$Percent, [string]$Message) $pbAttach.Value = $Percent; $txtProgress.Text = $Message }
  function Add-Log { param([string]$Message) $logQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)) }
  function New-SafeCredential { param([string]$Username, [string]$PlainPassword) $secure = New-Object System.Security.SecureString; foreach ($ch in $PlainPassword.ToCharArray()) { $secure.AppendChar($ch) }; $secure.MakeReadOnly(); New-Object System.Management.Automation.PSCredential($Username, $secure) }
  function Set-LogControlsState { param([bool]$Enabled) $txtLdfPath.IsEnabled = $Enabled; $btnBrowseLdf.IsEnabled = $Enabled }
  Set-LogControlsState -Enabled $true
  $chkRebuildLog.Add_Checked({ Set-LogControlsState -Enabled $false })
  $chkRebuildLog.Add_Unchecked({ Set-LogControlsState -Enabled $true })
  function Start-AttachWorkAsync {
    param(
      [string]$Server,
      [string]$AttachQuery,
      [System.Management.Automation.PSCredential]$Credential,
      [System.Collections.Concurrent.ConcurrentQueue[string]]$LogQueue,
      [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue,
      [Parameter(Mandatory)][string]$UtilitiesModulePath,
      [Parameter(Mandatory)][string]$DatabaseModulePath
    )
    $worker = {
      param($Server, $AttachQuery, $Credential, $LogQueue, $ProgressQueue, $UtilitiesModulePath, $DatabaseModulePath)
      function EnqLog([string]$m) { $LogQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m)) }
      function EnqProg([int]$p, [string]$m) { $ProgressQueue.Enqueue(@{Percent = $p; Message = $m }) }
      try {
        if (-not (Test-Path -LiteralPath $DatabaseModulePath)) { throw "No se encontró el módulo requerido: $DatabaseModulePath" }
        Import-Module $UtilitiesModulePath -Force -DisableNameChecking -ErrorAction Stop
        Import-Module $DatabaseModulePath -Force -DisableNameChecking -ErrorAction Stop
        EnqProg 10 "Conectando a SQL Server..."
        EnqLog "Ejecutando ATTACH..."
        $r = Invoke-SqlQuery -Server $Server -Database "master" -Query $AttachQuery -Credential $Credential
        if (-not $r.Success) {
          EnqProg 0 "❌ Error en adjuntar"
          EnqLog ("❌ Error de SQL: {0}" -f $r.ErrorMessage)
          EnqLog "ERROR_RESULT|$($r.ErrorMessage)"
          EnqLog "__DONE__"
          return
        }
        EnqProg 100 "Adjuntar completado."
        EnqLog "✅ Base de datos adjuntada"
        EnqLog "SUCCESS_RESULT|Base de datos adjuntada exitosamente"
        EnqLog "__DONE__"
      } catch {
        EnqProg 0 "Error"
        EnqLog ("❌ Error inesperado (worker): {0}" -f $_.Exception.Message)
        EnqLog "ERROR_RESULT|$($_.Exception.Message)"
        EnqLog "__DONE__"
      }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($worker).AddArgument($Server).AddArgument($AttachQuery).AddArgument($Credential).AddArgument($LogQueue).AddArgument($ProgressQueue).AddArgument($UtilitiesModulePath).AddArgument($DatabaseModulePath)
    $null = $ps.BeginInvoke()
  }
  $logTimer = [System.Windows.Threading.DispatcherTimer]::new()
  $logTimer.Interval = [TimeSpan]::FromMilliseconds(200)
  $logTimer.Add_Tick({
      try {
        $count = 0
        $doneThisTick = $false
        $finalResult = $null
        while ($count -lt 50) {
          $line = $null
          if (-not $logQueue.TryDequeue([ref]$line)) { break }
          if ($line -like "*SUCCESS_RESULT|*") { $finalResult = @{ Success = $true; Message = $line -replace '^.*SUCCESS_RESULT\|', '' } }
          if ($line -like "*ERROR_RESULT|*") { $finalResult = @{ Success = $false; Message = $line -replace '^.*ERROR_RESULT\|', '' } }
          if ($line -notmatch '(SUCCESS_RESULT|ERROR_RESULT)') { $txtLog.Text = "$line`n" + $txtLog.Text }
          if ($line -like "*__DONE__*") {
            $doneThisTick = $true
            $script:AttachRunning = $false
            $btnAttach.IsEnabled = $true
            $btnAttach.Content = "Adjuntar"
            $tmp = $null
            while ($progressQueue.TryDequeue([ref]$tmp)) { }
            Paint-Progress -Percent 100 -Message "Completado"
            $script:AttachDone = $true
            if ($finalResult) {
              $window.Dispatcher.Invoke([action] {
                  if ($finalResult.Success) {
                    Ui-Info "Base de datos '$($txtDbName.Text)' adjuntada con éxito.`n`n$($finalResult.Message)" "✓ Adjuntar exitoso" $window
                    if ($OnAttachCompleted) { try { & $OnAttachCompleted $txtDbName.Text } catch { Write-DzDebug "`t[DEBUG][Show-AttachDialog] Error OnAttachCompleted: $($_.Exception.Message)" } }
                  } else {
                    Write-DzDebug "`t[DEBUG][Adjuntar] Adjuntar falló: $($finalResult.Message)"
                    Ui-Error "No se pudo adjuntar la base de datos:`n`n$($finalResult.Message)" "✗ Error al adjuntar" $window
                  }
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
            }
          }
          $count++
        }
        if ($count -gt 0) { try { $txtLog.ScrollToLine(0) } catch {} }
        if (-not $doneThisTick) {
          $last = $null
          while ($true) {
            $p = $null
            if (-not $progressQueue.TryDequeue([ref]$p)) { break }
            $last = $p
          }
          if ($last) { Paint-Progress -Percent $last.Percent -Message $last.Message }
        }
      } catch { Write-DzDebug "`t[DEBUG][UI][logTimer][attach] ERROR: $($_.Exception.Message)" }
      if ($script:AttachDone) {
        $tmpLine = $null
        $tmpProg = $null
        if (-not $logQueue.TryPeek([ref]$tmpLine) -and -not $progressQueue.TryPeek([ref]$tmpProg)) { $logTimer.Stop(); $script:AttachDone = $false }
      }
    })
  $logTimer.Start()
  $btnBrowseMdf.Add_Click({
      try {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "SQL Data (*.mdf)|*.mdf|Todos los archivos (*.*)|*.*"
        $dlg.Multiselect = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
          $txtMdfPath.Text = $dlg.FileName
          if ([string]::IsNullOrWhiteSpace($txtDbName.Text)) { $txtDbName.Text = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName) }
          if (-not $chkRebuildLog.IsChecked -and [string]::IsNullOrWhiteSpace($txtLdfPath.Text)) {
            $dir = [System.IO.Path]::GetDirectoryName($dlg.FileName)
            $base = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
            $candidate = Join-Path $dir "$base`_log.ldf"
            if (-not (Test-Path -LiteralPath $candidate)) { $candidate = [System.IO.Path]::ChangeExtension($dlg.FileName, ".ldf") }
            $txtLdfPath.Text = $candidate
          }
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error btnBrowseMdf: $($_.Exception.Message)"
        Ui-Error "No se pudo abrir el selector de archivos: $($_.Exception.Message)" "Error" $window
      }
    })
  $btnBrowseLdf.Add_Click({
      try {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "SQL Log (*.ldf)|*.ldf|Todos los archivos (*.*)|*.*"
        $dlg.Multiselect = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtLdfPath.Text = $dlg.FileName }
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error btnBrowseLdf: $($_.Exception.Message)"
        Ui-Error "No se pudo abrir el selector de archivos: $($_.Exception.Message)" "Error" $window
      }
    })
  $btnAttach.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnAttach Click"
      if ($script:AttachRunning) { return }
      $script:AttachDone = $false
      if (-not $logTimer.IsEnabled) { $logTimer.Start() }
      try {
        $btnAttach.IsEnabled = $false
        $btnAttach.Content = "Procesando..."
        $txtLog.Text = ""
        $pbAttach.Value = 0
        $txtProgress.Text = "Esperando..."
        Add-Log "Iniciando proceso de adjuntar..."
        $mdfPath = $txtMdfPath.Text.Trim()
        $ldfPath = $txtLdfPath.Text.Trim()
        $dbName = $txtDbName.Text.Trim()
        $owner = $txtOwner.Text.Trim()
        $rebuildLog = $chkRebuildLog.IsChecked -eq $true
        $readOnly = $chkReadOnly.IsChecked -eq $true
        if ([string]::IsNullOrWhiteSpace($mdfPath)) { Ui-Warn "Selecciona el archivo MDF a adjuntar." "Atención" $window; Reset-AttachUI -ProgressText "Archivo MDF requerido"; return }
        if (-not (Test-Path -LiteralPath $mdfPath)) { Ui-Warn "El archivo MDF no existe.`n`nRuta: $mdfPath" "Atención" $window; Reset-AttachUI -ProgressText "Archivo MDF no encontrado"; return }
        if ([string]::IsNullOrWhiteSpace($dbName)) { Ui-Warn "Indica el nombre de la base de datos (Attach As)." "Atención" $window; Reset-AttachUI -ProgressText "Nombre requerido"; return }
        if (-not $rebuildLog) {
          if ([string]::IsNullOrWhiteSpace($ldfPath)) { Ui-Warn "Selecciona el archivo LDF o habilita la reconstrucción del log." "Atención" $window; Reset-AttachUI -ProgressText "Archivo LDF requerido"; return }
          if (-not (Test-Path -LiteralPath $ldfPath)) { Ui-Warn "El archivo LDF no existe.`n`nRuta: $ldfPath" "Atención" $window; Reset-AttachUI -ProgressText "Archivo LDF no encontrado"; return }
        }
        $credential = New-SafeCredential -Username $User -PlainPassword $Password
        $safeDbName = $dbName -replace ']', ']]'
        $escapedDb = $dbName -replace "'", "''"
        $checkQuery = "SELECT 1 FROM sys.databases WHERE name = N'$escapedDb'"
        $check = Invoke-SqlQuery -Server $Server -Database "master" -Query $checkQuery -Credential $credential
        if ($check.Success -and $check.DataTable -and $check.DataTable.Rows.Count -gt 0) {
          Ui-Error "Ya existe una base de datos con ese nombre.`n`nNombre: $dbName" "Error" $window
          Reset-AttachUI -ProgressText "Nombre ya existe"
          return
        }
        $escapedMdf = $mdfPath -replace "'", "''"
        $query = "CREATE DATABASE [$safeDbName] ON (FILENAME = N'$escapedMdf')"
        if (-not $rebuildLog) {
          $escapedLdf = $ldfPath -replace "'", "''"
          $query += ", (FILENAME = N'$escapedLdf')"
          $query += " FOR ATTACH;"
        } else {
          $query += " FOR ATTACH_REBUILD_LOG;"
        }
        if ($readOnly) { $query += "`nALTER DATABASE [$safeDbName] SET READ_ONLY WITH NO_WAIT;" }
        if (-not [string]::IsNullOrWhiteSpace($owner)) {
          $safeOwner = $owner -replace ']', ']]'
          $query += "`nALTER AUTHORIZATION ON DATABASE::[$safeDbName] TO [$safeOwner];"
        }
        Paint-Progress -Percent 10 -Message "Conectando a SQL Server..."
        $dbModulePath = Join-Path $ModulesPath "Database.psm1"
        $utilModulePath = Join-Path $ModulesPath "Utilities.psm1"
        Add-Log "ModulesPath: '$ModulesPath'"
        Add-Log "DatabaseModulePath: '$dbModulePath'"
        if ([string]::IsNullOrWhiteSpace($ModulesPath)) {
          Ui-Error "ModulesPath viene vacío/null. No se puede continuar." "Error" $window
          Reset-AttachUI -ProgressText "ModulesPath inválido"
          return
        }
        if ([string]::IsNullOrWhiteSpace($dbModulePath)) {
          Ui-Error "DatabaseModulePath viene vacío/null. No se puede continuar." "Error" $window
          Reset-AttachUI -ProgressText "Ruta de módulo inválida"
          return
        }
        if (-not (Test-Path -LiteralPath $dbModulePath)) {
          Ui-Error "No se encontró Database.psm1 en:`n$dbModulePath" "Error" $window
          Reset-AttachUI -ProgressText "Módulo no encontrado"
          return
        }
        Start-AttachWorkAsync -Server $Server -AttachQuery $query -Credential $credential -LogQueue $logQueue -ProgressQueue $progressQueue -DatabaseModulePath $dbModulePath -UtilitiesModulePath $utilModulePath
        $script:AttachRunning = $true
      } catch {
        Write-DzDebug "`t[DEBUG][UI] ERROR btnAttach: $($_.Exception.Message)"
        Add-Log "❌ Error: $($_.Exception.Message)"
        Reset-AttachUI -ProgressText "Error inesperado"
      }
    })
  $window.Add_PreviewKeyDown({
      param($sender, $e)
      if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
        try { $window.DialogResult = $false } catch {}
        try { $window.Close() } catch {}
      }
    })
  $btnClose.Add_Click({
      try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
      try { $window.DialogResult = $false } catch {}
      try { $window.Close() } catch {}
    })
  $btnCloseX.Add_Click({
      try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
      try { $window.DialogResult = $false } catch {}
      try { $window.Close() } catch {}
    })
  $null = $window.ShowDialog()
}
function Reset-AttachUI {
  param([string]$ButtonText = "Adjuntar", [string]$ProgressText = "Esperando...")
  $script:AttachRunning = $false
  $btnAttach.IsEnabled = $true
  $btnAttach.Content = $ButtonText
  $txtProgress.Text = $ProgressText
}
function Show-DetachDialog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
    [Parameter(Mandatory = $true)]$ParentNode
  )
  Write-DzDebug "`t[DEBUG][DetachDB] INICIO: Server='$Server' Database='$Database'"
  Add-Type -AssemblyName PresentationFramework
  $safeDb = [Security.SecurityElement]::Escape($Database)

  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Separar Base de Datos"
        Width="640" Height="470"
        MinWidth="640" MinHeight="470"
        MaxWidth="640" MaxHeight="470"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DangerButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentMagenta}"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="12" Margin="10" SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" CornerRadius="12,12,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentPrimary}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="📎 Separar Base de Datos (Detach)" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" FontSize="12"/>
            <TextBlock Text="Los archivos MDF y LDF quedarán disponibles en el sistema de archivos." Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnClose" Style="{StaticResource IconButtonStyle}" Content="✕" ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="12,12,12,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="Estás a punto de separar la siguiente base de datos:" TextWrapping="Wrap" Margin="0,0,0,10"/>
          <Border Grid.Row="1" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
            <TextBlock Text="🗄️ $safeDb" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource AccentPrimary}"/>
          </Border>
          <StackPanel Grid.Row="2" Margin="0,0,0,10">
            <CheckBox x:Name="chkUpdateStatistics" IsChecked="True" Margin="0,0,0,8">
              <TextBlock Text="Actualizar estadísticas antes de separar" TextWrapping="Wrap"/>
            </CheckBox>
            <CheckBox x:Name="chkCloseConnections" IsChecked="True">
              <TextBlock Text="Forzar cierre de conexiones existentes (SINGLE_USER + ROLLBACK IMMEDIATE)" TextWrapping="Wrap"/>
            </CheckBox>
          </StackPanel>
          <Border Grid.Row="3" Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10">
            <TextBlock FontSize="11" Foreground="{DynamicResource AccentMuted}" TextWrapping="Wrap">ℹ️ Información importante:
• Al separar la base de datos, esta dejará de estar disponible en SQL Server
• Los archivos físicos (MDF y LDF) permanecerán en el disco
• Puedes volver a adjuntar la base de datos posteriormente
• Si hay conexiones activas, usa la opción 'Forzar cierre' para cerrarlas automáticamente</TextBlock>
          </Border>
        </Grid>
      </Border>
      <Border Grid.Row="2" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="10" Margin="12,0,12,12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Enter: Separar   |   Esc: Cerrar" Foreground="{DynamicResource AccentMuted}" VerticalAlignment="Center"/>
          <StackPanel Grid.Column="1" Orientation="Horizontal">
            <Button x:Name="btnCancelar" Content="Cancelar" Width="120" Margin="0,0,10,0" IsCancel="True" Style="{StaticResource SecondaryButtonStyle}"/>
            <Button x:Name="btnSeparar" Content="Separar" Width="140" IsDefault="True" Style="{StaticResource DangerButtonStyle}"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@

  try {
    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $window = $ui.Window
    $c = $ui.Controls
    $theme = Get-DzUiTheme
    Set-DzWpfThemeResources -Window $window -Theme $theme
    try { Set-WpfDialogOwner -Dialog $window } catch {}
    try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
    $window.WindowStartupLocation = "Manual"
    $window.Add_Loaded({
        try {
          $owner = $window.Owner
          if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
          $ob = $owner.RestoreBounds
          $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
          $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $window.Left = [double]$left
          $window.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $window.DragMove() } catch {}
        }
      })
  } catch {
    Write-DzDebug "`t[DEBUG][DetachDB] ERROR creando ventana: $($_.Exception.Message)" -Color Red
    throw "No se pudo crear la ventana (XAML). $($_.Exception.Message)"
  }

  $chkUpdateStatistics = $window.FindName("chkUpdateStatistics")
  $chkCloseConnections = $window.FindName("chkCloseConnections")
  $btnSeparar = $window.FindName("btnSeparar")
  $btnCancelar = $window.FindName("btnCancelar")
  $btnClose = $window.FindName("btnClose")

  $btnClose.Add_Click({
      Write-DzDebug "`t[DEBUG][DetachDB] btnClose Click"
      try { $window.DialogResult = $false } catch {}
      try { $window.Close() } catch {}
    })

  $btnCancelar.Add_Click({
      Write-DzDebug "`t[DEBUG][DetachDB] btnCancelar Click"
      try { $window.DialogResult = $false } catch {}
      try { $window.Close() } catch {}
    })

  $window.Add_PreviewKeyDown({
      param($sender, $e)
      if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        try { $window.DialogResult = $false } catch {}
        try { $window.Close() } catch {}
      }
    })

  $btnSeparar.Add_Click({
      Write-DzDebug "`t[DEBUG][DetachDB] btnSeparar Click"
      $updateStats = $chkUpdateStatistics.IsChecked -eq $true
      $closeConnections = $chkCloseConnections.IsChecked -eq $true
      try {
        $escapedDb = $Database -replace "'", "''"
        $safeName = $Database -replace ']', ']]'
        if ($updateStats) {
          Write-DzDebug "`t[DEBUG][DetachDB] Paso 1: Actualizando estadísticas"
          $updateQuery = "USE [$safeName]; EXEC sp_updatestats"
          $result1 = Invoke-SqlQuery -Server $Server -Database $Database -Query $updateQuery -Credential $Credential
          if (-not $result1.Success) {
            Write-DzDebug "`t[DEBUG][DetachDB] Error actualizando estadísticas: $($result1.ErrorMessage)"
            Ui-Error "Error al actualizar estadísticas:`n`n$($result1.ErrorMessage)" "Error" $window
            return
          }
          Write-DzDebug "`t[DEBUG][DetachDB] Estadísticas actualizadas OK"
        }
        if ($closeConnections) {
          Write-DzDebug "`t[DEBUG][DetachDB] Paso 2: Cerrando conexiones"
          $closeQuery = "ALTER DATABASE [$safeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
          $result2 = Invoke-SqlQuery -Server $Server -Database "master" -Query $closeQuery -Credential $Credential
          if (-not $result2.Success) {
            Write-DzDebug "`t[DEBUG][DetachDB] Error cerrando conexiones: $($result2.ErrorMessage)"
            Ui-Error "Error al cerrar conexiones existentes:`n`n$($result2.ErrorMessage)" "Error" $window
            return
          }
          Write-DzDebug "`t[DEBUG][DetachDB] Conexiones cerradas OK"
        }
        Write-DzDebug "`t[DEBUG][DetachDB] Paso 3: Separando base de datos"
        $detachQuery = "EXEC sp_detach_db @dbname = N'$escapedDb', @skipchecks = 'false'"
        $result3 = Invoke-SqlQuery -Server $Server -Database "master" -Query $detachQuery -Credential $Credential
        if (-not $result3.Success) {
          Write-DzDebug "`t[DEBUG][DetachDB] Error separando BD: $($result3.ErrorMessage)"
          if ($closeConnections) {
            try {
              $restoreQuery = "ALTER DATABASE [$safeName] SET MULTI_USER"
              Invoke-SqlQuery -Server $Server -Database "master" -Query $restoreQuery -Credential $Credential | Out-Null
            } catch {
              Write-DzDebug "`t[DEBUG][DetachDB] No se pudo restaurar MULTI_USER"
            }
          }
          Ui-Error "Error al separar la base de datos:`n`n$($result3.ErrorMessage)" "Error" $window
          return
        }
        Write-DzDebug "`t[DEBUG][DetachDB] Base de datos separada OK"
        Ui-Info "La base de datos '$Database' ha sido separada exitosamente.`n`nLos archivos físicos permanecen en el disco y pueden ser adjuntados nuevamente cuando lo necesites." "✓ Éxito" $window
        $serverNode = $ParentNode.Parent
        if ($serverNode -and $serverNode.Tag.Type -eq "Server") {
          if ($serverNode.Tag.OnDatabasesRefreshed) {
            try {
              Write-DzDebug "`t[DEBUG][DetachDB] Llamando a OnDatabasesRefreshed"
              & $serverNode.Tag.OnDatabasesRefreshed
            } catch {
              Write-DzDebug "`t[DEBUG][DetachDB] Error en OnDatabasesRefreshed: $($_.Exception.Message)"
            }
          }
          Refresh-SqlTreeServerNode -ServerNode $serverNode
        }
        if ($ParentNode.Parent -is [System.Windows.Controls.ItemsControl]) {
          $window.Dispatcher.Invoke([action] {
              try {
                [void]$ParentNode.Parent.Items.Remove($ParentNode)
                Write-DzDebug "`t[DEBUG][DetachDB] Nodo removido del TreeView"
              } catch {
                Write-DzDebug "`t[DEBUG][DetachDB] Error removiendo nodo: $($_.Exception.Message)"
              }
            })
        }
        try { $window.DialogResult = $true } catch {}
        try { $window.Close() } catch {}
      } catch {
        Write-DzDebug "`t[DEBUG][DetachDB] Excepción: $($_.Exception.Message)"
        Ui-Error "Error inesperado al separar la base de datos:`n`n$($_.Exception.Message)" "Error" $window
      }
    })

  Write-DzDebug "`t[DEBUG][DetachDB] Mostrando ventana"
  $null = $window.ShowDialog()
}
function Show-DatabaseSizeDialog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
  )
  Write-DzDebug "`t[DEBUG][DBSize] INICIO: Server='$Server' Database='$Database'"
  Add-Type -AssemblyName PresentationFramework
  $safeDbName = $Database -replace ']', ']]'
  $sizeQuery = @"
SELECT
    name AS FileName,
    physical_name AS FilePath,
    type_desc AS FileType,
    CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB,
    CAST(FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedMB,
    CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(18,2)) AS FreeMB,
    CAST(FILEPROPERTY(name, 'SpaceUsed') * 100.0 / size AS DECIMAL(5,2)) AS PercentUsed
FROM [$safeDbName].sys.database_files
ORDER BY type, name;
"@
  Write-DzDebug "`t[DEBUG][DBSize] Ejecutando query..."
  $result = Invoke-SqlQuery -Server $Server -Database $Database -Query $sizeQuery -Credential $Credential
  if (-not $result.Success) {
    Write-DzDebug "`t[DEBUG][DBSize] ERROR en query: $($result.ErrorMessage)"
    Ui-Error "Error al consultar el tamaño de la base de datos:`n`n$($result.ErrorMessage)" "Error" $null
    return
  }
  if (-not $result.DataTable -or $result.DataTable.Rows.Count -eq 0) {
    Write-DzDebug "`t[DEBUG][DBSize] No se obtuvieron filas"
    Ui-Error "No se pudo obtener información de tamaño de la base de datos." "Error" $null
    return
  }
  Write-DzDebug "`t[DEBUG][DBSize] Se obtuvieron $($result.DataTable.Rows.Count) archivos"
  $dataRows = New-Object System.Collections.ArrayList
  $totalSizeMB = 0
  $totalUsedMB = 0
  $rowIndex = 1
  foreach ($row in $result.DataTable.Rows) {
    $fileName = [string]$row.FileName
    $fileType = [string]$row.FileType
    $sizeMB = [decimal]$row.SizeMB
    $usedMB = [decimal]$row.UsedMB
    $percentUsed = [decimal]$row.PercentUsed
    $totalSizeMB += $sizeMB
    $totalUsedMB += $usedMB
    $typeIcon = if ($fileType -eq "ROWS") { "📄" } else { "📋" }
    $safeFileName = [Security.SecurityElement]::Escape($fileName)
    $safeFileType = [Security.SecurityElement]::Escape($fileType)
    $rowXaml = @"
                    <Border Grid.Row="$rowIndex" Grid.Column="0" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,0,1,1" Padding="8">
                        <TextBlock Text="$typeIcon $safeFileName" FontWeight="SemiBold"/>
                    </Border>
                    <Border Grid.Row="$rowIndex" Grid.Column="1" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,0,1,1" Padding="8">
                        <TextBlock Text="$safeFileType"/>
                    </Border>
                    <Border Grid.Row="$rowIndex" Grid.Column="2" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,0,1,1" Padding="8" Background="{DynamicResource ControlBg}">
                        <TextBlock Text="$($sizeMB.ToString('N2')) MB" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Border>
                    <Border Grid.Row="$rowIndex" Grid.Column="3" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,0,1,1" Padding="8">
                        <TextBlock Text="$($usedMB.ToString('N2')) MB" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Border>
                    <Border Grid.Row="$rowIndex" Grid.Column="4" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,0,0,1" Padding="8">
                        <TextBlock Text="$($percentUsed.ToString('N2'))%" HorizontalAlignment="Right" FontFamily="Consolas" Foreground="{DynamicResource AccentPrimary}"/>
                    </Border>
"@
    [void]$dataRows.Add($rowXaml)
    $rowIndex++
  }
  $totalFreeMB = $totalSizeMB - $totalUsedMB
  $totalPercentUsed = if ($totalSizeMB -gt 0) { ($totalUsedMB / $totalSizeMB) * 100 } else { 0 }
  Write-DzDebug "`t[DEBUG][DBSize] Totales: Size=$($totalSizeMB.ToString('N2')) MB, Used=$($totalUsedMB.ToString('N2')) MB, Free=$($totalFreeMB.ToString('N2')) MB, PercentUsed=$($totalPercentUsed.ToString('N2'))%"
  $safeDb = [Security.SecurityElement]::Escape($Database)
  $totalRowCount = $result.DataTable.Rows.Count + 2
  $rowDefs = ""
  for ($i = 0; $i -lt $totalRowCount; $i++) {
    $rowDefs += "                        <RowDefinition Height='Auto'/>`n"
  }
  $allDataRows = $dataRows -join "`n"
  $totalRowIndex = $result.DataTable.Rows.Count + 1
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tamaño de Base de Datos"
        Width="820" Height="400"
        MinWidth="820" MinHeight="400"
        MaxWidth="820" MaxHeight="400"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="12" Margin="10" SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" CornerRadius="12,12,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentPrimary}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="📊 Tamaño de Base de Datos" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" FontSize="12"/>
            <TextBlock Text="🗄️ $safeDb" Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnClose" Style="{StaticResource IconButtonStyle}" Content="✕" ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="12,12,12,10">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <Grid>
            <Grid.RowDefinitions>
$rowDefs
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="2*"/>
              <ColumnDefinition Width="1.2*"/>
              <ColumnDefinition Width="1*"/>
              <ColumnDefinition Width="1*"/>
              <ColumnDefinition Width="0.8*"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Row="0" Grid.Column="0" Background="{DynamicResource AccentSecondary}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1,1,1,2" Padding="8">
              <TextBlock Text="Archivo" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="0" Grid.Column="1" Background="{DynamicResource AccentSecondary}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,1,1,2" Padding="8">
              <TextBlock Text="Tipo" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="0" Grid.Column="2" Background="{DynamicResource AccentSecondary}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,1,1,2" Padding="8">
              <TextBlock Text="Tamaño Total" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="0" Grid.Column="3" Background="{DynamicResource AccentSecondary}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,1,1,2" Padding="8">
              <TextBlock Text="Espacio Usado" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="0" Grid.Column="4" Background="{DynamicResource AccentSecondary}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,1,1,2" Padding="8">
              <TextBlock Text="% Usado" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
$allDataRows
            <Border Grid.Row="$totalRowIndex" Grid.Column="0" Grid.ColumnSpan="2" Background="{DynamicResource AccentMagenta}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1,2,1,1" Padding="8">
              <TextBlock Text="📦 TOTAL" FontWeight="Bold" Foreground="{DynamicResource FormFg}" FontSize="13"/>
            </Border>
            <Border Grid.Row="$totalRowIndex" Grid.Column="2" Background="{DynamicResource AccentMagenta}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,2,1,1" Padding="8">
              <TextBlock Text="$($totalSizeMB.ToString('N2')) MB" HorizontalAlignment="Right" FontFamily="Consolas" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="$totalRowIndex" Grid.Column="3" Background="{DynamicResource AccentMagenta}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,2,1,1" Padding="8">
              <TextBlock Text="$($totalUsedMB.ToString('N2')) MB" HorizontalAlignment="Right" FontFamily="Consolas" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
            <Border Grid.Row="$totalRowIndex" Grid.Column="4" Background="{DynamicResource AccentMagenta}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="0,2,1,1" Padding="8">
              <TextBlock Text="$($totalPercentUsed.ToString('N2'))%" HorizontalAlignment="Right" FontFamily="Consolas" FontWeight="Bold" Foreground="{DynamicResource FormFg}"/>
            </Border>
          </Grid>
        </ScrollViewer>
      </Border>
      <Border Grid.Row="2" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="10" Margin="12,0,12,10">
        <StackPanel>
          <TextBlock FontSize="11" Foreground="{DynamicResource AccentMuted}" TextWrapping="Wrap">ℹ️ Información:</TextBlock>
          <TextBlock FontSize="11" Foreground="{DynamicResource PanelFg}" TextWrapping="Wrap" Margin="0,4,0,0">• ROWS = Archivos de datos (MDF/NDF)&#x0a;• LOG = Archivos de registro de transacciones (LDF)&#x0a;• Tamaño Total = Espacio asignado en disco&#x0a;• Espacio Usado = Datos actualmente almacenados&#x0a;• Espacio Libre = $($totalFreeMB.ToString('N2')) MB disponibles</TextBlock>
        </StackPanel>
      </Border>
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="Esc: Cerrar" Foreground="{DynamicResource AccentMuted}" VerticalAlignment="Center"/>
        <Button Grid.Column="1" Name="btnCerrar" Content="Cerrar" Width="120" Style="{StaticResource SecondaryButtonStyle}"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
  try {
    Write-DzDebug "`t[DEBUG][DBSize] Creando ventana WPF..."
    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    $theme = Get-DzUiTheme
    Set-DzWpfThemeResources -Window $w -Theme $theme
    try { Set-WpfDialogOwner -Dialog $w } catch {}
    try { if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) { $w.Owner = $global:MainWindow } } catch {}
    $w.WindowStartupLocation = "Manual"
    $w.Add_Loaded({
        try {
          $owner = $w.Owner
          if (-not $owner) { $w.WindowStartupLocation = "CenterScreen"; return }
          $ob = $owner.RestoreBounds
          $targetW = $w.ActualWidth; if ($targetW -le 0) { $targetW = $w.Width }
          $targetH = $w.ActualHeight; if ($targetH -le 0) { $targetH = $w.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $w.Left = [double]$left
          $w.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $w.DragMove() } catch {}
        }
      })
    $c['btnClose'].Add_Click({ try { $w.Close() } catch {} })
    $c['btnCerrar'].Add_Click({ try { $w.Close() } catch {} })
    $w.Add_PreviewKeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
          try { $w.Close() } catch {}
        }
      })
    Write-DzDebug "`t[DEBUG][DBSize] Mostrando diálogo..."
    $null = $w.ShowDialog()
    Write-DzDebug "`t[DEBUG][DBSize] Diálogo cerrado"
  } catch {
    Write-DzDebug "`t[DEBUG][DBSize] ERROR creando ventana: $($_.Exception.Message)"
    Ui-Error "Error al mostrar el diálogo: $($_.Exception.Message)" "Error" $null
  }
}
function Show-DatabaseRepairDialog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
  )
  $script:RepairRunning = $false
  $script:RepairDone = $false
  Write-DzDebug "`t[DEBUG][DBRepair] INICIO: Server='$Server' Database='$Database'"
  Add-Type -AssemblyName PresentationFramework
  $safeDb = [Security.SecurityElement]::Escape($Database)
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Reparación de Base de Datos"
        Width="820" Height="760"
        MinWidth="820" MinHeight="760"
        MaxWidth="820" MaxHeight="760"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Foreground" Value="{DynamicResource AccentSecondary}"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DangerPanelTitle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="#FFFF3333"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="12" Margin="10" SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black" Direction="270" ShadowDepth="4" BlurRadius="14" Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Name="HeaderBar" Background="{DynamicResource FormBg}" CornerRadius="12,12,0,0" Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0" Width="6" CornerRadius="3" Background="{DynamicResource AccentPrimary}" Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="⚠️ Reparación de Base de Datos" FontWeight="SemiBold" Foreground="{DynamicResource FormFg}" FontSize="12"/>
            <TextBlock Text="🗄️ $safeDb" Foreground="{DynamicResource AccentMuted}" FontSize="10" Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2" Name="btnClose" Style="{StaticResource IconButtonStyle}" Content="✕" ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="12,12,12,10">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <Border Background="#33FF0000" BorderBrush="#FFFF0000" BorderThickness="2" CornerRadius="8" Padding="12" Margin="0,0,0,12">
              <StackPanel>
                <TextBlock Text="⚠️ ADVERTENCIA CRÍTICA" Style="{StaticResource DangerPanelTitle}"/>
                <TextBlock TextWrapping="Wrap" Foreground="{DynamicResource PanelFg}">Esta operación puede causar PÉRDIDA DE DATOS irreversible. Solo continúa si entiendes completamente las consecuencias. Se recomienda realizar un respaldo completo antes de proceder.</TextBlock>
              </StackPanel>
            </Border>
            <TextBlock Text="Paso 1: Verificar Integridad" FontWeight="Bold" FontSize="13" Margin="0,0,0,8"/>
            <Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
              <StackPanel>
                <RadioButton x:Name="rbCheckOnly" IsChecked="True" GroupName="Action" Margin="0,0,0,8">
                  <TextBlock TextWrapping="Wrap">🔍 Solo verificar (DBCC CHECKDB sin reparación)</TextBlock>
                </RadioButton>
                <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="{DynamicResource AccentMuted}" Margin="20,0,0,0">Recomendado: Primero verifica si hay errores antes de intentar reparar.</TextBlock>
              </StackPanel>
            </Border>
            <TextBlock Text="Paso 2: Reparación (Solo si hay errores)" FontWeight="Bold" FontSize="13" Margin="0,0,0,8"/>
            <Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
              <StackPanel>
                <RadioButton x:Name="rbRepairFast" GroupName="Action" Margin="0,0,0,8">
                  <TextBlock TextWrapping="Wrap">🔧 REPAIR_FAST (reparación rápida, sin pérdida de datos)</TextBlock>
                </RadioButton>
                <RadioButton x:Name="rbRepairRebuild" GroupName="Action" Margin="0,0,0,8">
                  <TextBlock TextWrapping="Wrap">🔨 REPAIR_REBUILD (reconstruir índices, sin pérdida de datos)</TextBlock>
                </RadioButton>
                <RadioButton x:Name="rbRepairAllowDataLoss" GroupName="Action" Margin="0,0,0,8">
                  <TextBlock TextWrapping="Wrap" Foreground="#FFFF6666">⚠️ REPAIR_ALLOW_DATA_LOSS (puede causar PÉRDIDA DE DATOS)</TextBlock>
                </RadioButton>
                <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="#FFFF6666" Margin="20,0,0,0">PELIGRO: Esta opción eliminará datos corruptos. Úsala solo como último recurso.</TextBlock>
              </StackPanel>
            </Border>
            <TextBlock Text="Opciones Adicionales" FontWeight="Bold" FontSize="13" Margin="0,0,0,8"/>
            <Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
              <StackPanel>
                <CheckBox x:Name="chkCloseConnections" IsChecked="True" Margin="0,0,0,8">
                  <TextBlock TextWrapping="Wrap">Cerrar conexiones activas (SINGLE_USER)</TextBlock>
                </CheckBox>
                <CheckBox x:Name="chkEmergencyMode" IsChecked="True">
                  <TextBlock TextWrapping="Wrap">Poner en modo EMERGENCY antes de reparar</TextBlock>
                </CheckBox>
              </StackPanel>
            </Border>
            <Border Background="{DynamicResource FormBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
              <StackPanel>
                <TextBlock x:Name="txtProgress" Text="Esperando..." Margin="0,0,0,8" FontWeight="SemiBold"/>
                <ProgressBar x:Name="pbProgress" Height="20" Minimum="0" Maximum="100" Value="0"/>
              </StackPanel>
            </Border>
            <TextBlock Text="Log de Operaciones" FontWeight="Bold" FontSize="13" Margin="0,0,0,8"/>
            <Border Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="8" Padding="8">
              <TextBox x:Name="txtLog" IsReadOnly="True" VerticalScrollBarVisibility="Auto" Height="180" TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" BorderThickness="0" Background="Transparent"/>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </Border>
      <Border Grid.Row="2" Background="{DynamicResource PanelBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="10" Margin="12,0,12,12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="⚠️ Lee las advertencias antes de continuar" VerticalAlignment="Center" Foreground="#FFFF6666"/>
          <StackPanel Grid.Column="1" Orientation="Horizontal">
            <Button x:Name="btnCancelar" Content="Cancelar" Width="120" Margin="0,0,10,0" Style="{StaticResource SecondaryButtonStyle}"/>
            <Button x:Name="btnIniciar" Content="Iniciar" Width="140" Style="{StaticResource PrimaryButtonStyle}"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@
  try {
    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $window = $ui.Window
    $c = $ui.Controls
    $theme = Get-DzUiTheme
    Set-DzWpfThemeResources -Window $window -Theme $theme
    try { Set-WpfDialogOwner -Dialog $window } catch {}
    try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
    $window.WindowStartupLocation = "Manual"
    $window.Add_Loaded({
        try {
          $owner = $window.Owner
          if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
          $ob = $owner.RestoreBounds
          $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
          $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $window.Left = [double]$left
          $window.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $window.DragMove() } catch {}
        }
      })
  } catch {
    Write-DzDebug "`t[DEBUG][DBRepair] ERROR creando ventana: $($_.Exception.Message)"
    throw "No se pudo crear la ventana (XAML). $($_.Exception.Message)"
  }
  $rbCheckOnly = $window.FindName("rbCheckOnly")
  $rbRepairFast = $window.FindName("rbRepairFast")
  $rbRepairRebuild = $window.FindName("rbRepairRebuild")
  $rbRepairAllowDataLoss = $window.FindName("rbRepairAllowDataLoss")
  $chkCloseConnections = $window.FindName("chkCloseConnections")
  $chkEmergencyMode = $window.FindName("chkEmergencyMode")
  $pbProgress = $window.FindName("pbProgress")
  $txtProgress = $window.FindName("txtProgress")
  $txtLog = $window.FindName("txtLog")
  $btnIniciar = $window.FindName("btnIniciar")
  $btnCancelar = $window.FindName("btnCancelar")
  $btnClose = $window.FindName("btnClose")
  $logQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $progressQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
  function Paint-Progress {
    param([int]$Percent, [string]$Message)
    $pbProgress.Value = $Percent
    $txtProgress.Text = $Message
  }
  function Add-Log {
    param([string]$Message)
    $logQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message))
  }
  function Start-RepairWorkAsync {
    param(
      [string]$Server,
      [string]$Database,
      [string]$RepairOption,
      [bool]$CloseConnections,
      [bool]$EmergencyMode,
      [System.Management.Automation.PSCredential]$Credential,
      [System.Collections.Concurrent.ConcurrentQueue[string]]$LogQueue,
      [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue
    )
    $worker = {
      param($Server, $Database, $RepairOption, $CloseConnections, $EmergencyMode, $Credential, $LogQueue, $ProgressQueue)
      function EnqLog([string]$m) { $LogQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m)) }
      function EnqProg([int]$p, [string]$m) { $ProgressQueue.Enqueue(@{Percent = $p; Message = $m }) }
      function Invoke-SqlQueryLite {
        param([string]$Server, [string]$Database, [string]$Query, [System.Management.Automation.PSCredential]$Credential)
        $connection = $null
        $passwordBstr = [IntPtr]::Zero
        $plainPassword = $null
        try {
          $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
          $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
          $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;Connection Timeout=300"
          $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
          $connection.Open()
          $cmd = $connection.CreateCommand()
          $cmd.CommandText = $Query
          $cmd.CommandTimeout = 0
          $reader = $cmd.ExecuteReader()
          $messages = New-Object System.Collections.ArrayList
          do {
            while ($reader.Read()) {
              for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $val = $reader.GetValue($i)
                if ($val -and $val -ne [DBNull]::Value) { [void]$messages.Add($val.ToString()) }
              }
            }
          } while ($reader.NextResult())
          $reader.Close()
          @{ Success = $true; Messages = $messages }
        } catch {
          @{ Success = $false; ErrorMessage = $_.Exception.Message }
        } finally {
          if ($plainPassword) { $plainPassword = $null }
          if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
          if ($connection) { try { $connection.Close(); $connection.Dispose() } catch { } }
        }
      }
      try {
        $safeName = $Database -replace ']', ']]'
        $steps = 0
        $currentStep = 0
        if ($EmergencyMode -and $RepairOption -ne "CHECK") { $steps++ }
        if ($CloseConnections) { $steps++ }
        $steps++
        if ($CloseConnections) { $steps++ }
        if ($EmergencyMode -and $RepairOption -ne "CHECK") {
          $currentStep++
          EnqProg ([int](($currentStep / $steps) * 90)) "Configurando modo EMERGENCY..."
          EnqLog "🔧 Configurando base de datos en modo EMERGENCY"
          $emergencyQuery = "ALTER DATABASE [$safeName] SET EMERGENCY"
          $result = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $emergencyQuery -Credential $Credential
          if (-not $result.Success) {
            EnqProg 0 "Error"
            EnqLog "❌ Error al configurar modo EMERGENCY: $($result.ErrorMessage)"
            EnqLog "ERROR_RESULT|$($result.ErrorMessage)"
            EnqLog "__DONE__"
            return
          }
          EnqLog "✅ Modo EMERGENCY configurado"
        }
        if ($CloseConnections) {
          $currentStep++
          EnqProg ([int](($currentStep / $steps) * 90)) "Cerrando conexiones..."
          EnqLog "🔒 Cerrando conexiones existentes (SINGLE_USER)"
          $closeQuery = "ALTER DATABASE [$safeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
          $result = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $closeQuery -Credential $Credential
          if (-not $result.Success) {
            EnqProg 0 "Error"
            EnqLog "❌ Error al cerrar conexiones: $($result.ErrorMessage)"
            EnqLog "ERROR_RESULT|$($result.ErrorMessage)"
            EnqLog "__DONE__"
            return
          }
          EnqLog "✅ Conexiones cerradas"
        }
        $currentStep++
        $actionText = if ($RepairOption -eq "CHECK") { "Verificando integridad..." } else { "Ejecutando reparación..." }
        EnqProg ([int](($currentStep / $steps) * 90)) $actionText
        EnqLog "🔍 Ejecutando DBCC CHECKDB ($RepairOption)"
        $dbccQuery = switch ($RepairOption) {
          "CHECK" { "DBCC CHECKDB([$safeName]) WITH NO_INFOMSGS" }
          "REPAIR_FAST" { "DBCC CHECKDB([$safeName], REPAIR_FAST) WITH NO_INFOMSGS" }
          "REPAIR_REBUILD" { "DBCC CHECKDB([$safeName], REPAIR_REBUILD) WITH NO_INFOMSGS" }
          "REPAIR_ALLOW_DATA_LOSS" { "DBCC CHECKDB([$safeName], REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS" }
        }
        $result = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $dbccQuery -Credential $Credential
        if (-not $result.Success) {
          EnqProg 0 "Error"
          EnqLog "❌ Error ejecutando DBCC: $($result.ErrorMessage)"
          if ($CloseConnections) {
            try {
              $restoreQuery = "ALTER DATABASE [$safeName] SET MULTI_USER"
              Invoke-SqlQueryLite -Server $Server -Database "master" -Query $restoreQuery -Credential $Credential | Out-Null
            } catch { }
          }
          EnqLog "ERROR_RESULT|$($result.ErrorMessage)"
          EnqLog "__DONE__"
          return
        }
        $hasErrors = $false
        foreach ($msg in $result.Messages) {
          EnqLog "[DBCC] $msg"
          if ($msg -match "(?i)(error|corruption|corrupt|dañ|inconsisten)") { $hasErrors = $true }
        }
        if ($result.Messages.Count -eq 0) { EnqLog "✅ No se encontraron problemas de integridad" }
        elseif (-not $hasErrors) { EnqLog "✅ Verificación completada sin errores críticos" }
        else { EnqLog "⚠️ Se encontraron problemas de integridad" }
        if ($CloseConnections) {
          $currentStep++
          EnqProg ([int](($currentStep / $steps) * 90)) "Restaurando acceso normal..."
          EnqLog "🔓 Restaurando modo MULTI_USER"
          $restoreQuery = "ALTER DATABASE [$safeName] SET MULTI_USER"
          $result = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $restoreQuery -Credential $Credential
          if (-not $result.Success) { EnqLog "⚠️ Advertencia: No se pudo restaurar MULTI_USER: $($result.ErrorMessage)" }
          else { EnqLog "✅ Modo MULTI_USER restaurado" }
        }
        EnqProg 100 "Operación completada"
        EnqLog "✅ Proceso completado exitosamente"
        EnqLog "SUCCESS_RESULT|Operación completada. Revisa el log para detalles."
        EnqLog "__DONE__"
      } catch {
        EnqProg 0 "Error"
        EnqLog "❌ Error inesperado: $($_.Exception.Message)"
        EnqLog "ERROR_RESULT|$($_.Exception.Message)"
        EnqLog "__DONE__"
      }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($worker).AddArgument($Server).AddArgument($Database).AddArgument($RepairOption).AddArgument($CloseConnections).AddArgument($EmergencyMode).AddArgument($Credential).AddArgument($LogQueue).AddArgument($ProgressQueue)
    $null = $ps.BeginInvoke()
  }
  $logTimer = [System.Windows.Threading.DispatcherTimer]::new()
  $logTimer.Interval = [TimeSpan]::FromMilliseconds(200)
  $logTimer.Add_Tick({
      try {
        $count = 0
        $doneThisTick = $false
        $finalResult = $null
        while ($count -lt 50) {
          $line = $null
          if (-not $logQueue.TryDequeue([ref]$line)) { break }
          if ($line -like "*SUCCESS_RESULT|*") { $finalResult = @{ Success = $true; Message = $line -replace '^.*SUCCESS_RESULT\|', '' } }
          if ($line -like "*ERROR_RESULT|*") { $finalResult = @{ Success = $false; Message = $line -replace '^.*ERROR_RESULT\|', '' } }
          if ($line -notmatch '(SUCCESS_RESULT|ERROR_RESULT)') {
            $txtLog.AppendText("$line`n")
            $txtLog.ScrollToEnd()
          }
          if ($line -like "*__DONE__*") {
            $doneThisTick = $true
            $script:RepairRunning = $false
            $btnIniciar.IsEnabled = $true
            $btnIniciar.Content = "Iniciar"
            $tmp = $null
            while ($progressQueue.TryDequeue([ref]$tmp)) { }
            Paint-Progress -Percent 100 -Message "Completado"
            $script:RepairDone = $true
            if ($finalResult) {
              $window.Dispatcher.Invoke([action] {
                  if ($finalResult.Success) { Ui-Info "Operación completada.`n`n$($finalResult.Message)`n`nRevisa el log para más detalles." "✓ Completado" $window }
                  else { Ui-Error "La operación falló:`n`n$($finalResult.Message)" "✗ Error" $window }
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
            }
          }
          $count++
        }
        if (-not $doneThisTick) {
          $last = $null
          while ($true) {
            $p = $null
            if (-not $progressQueue.TryDequeue([ref]$p)) { break }
            $last = $p
          }
          if ($last) { Paint-Progress -Percent $last.Percent -Message $last.Message }
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI][logTimer][repair] ERROR: $($_.Exception.Message)"
      }
      if ($script:RepairDone) {
        $tmpLine = $null
        $tmpProg = $null
        if (-not $logQueue.TryPeek([ref]$tmpLine) -and -not $progressQueue.TryPeek([ref]$tmpProg)) {
          $logTimer.Stop()
          $script:RepairDone = $false
        }
      }
    })
  $logTimer.Start()
  $btnClose.Add_Click({ $window.Close() })
  $btnCancelar.Add_Click({ $window.Close() })
  $window.Add_PreviewKeyDown({
      param($sender, $e)
      if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $window.Close() }
    })
  $btnIniciar.Add_Click({
      if ($script:RepairRunning) { return }
      $repairOption = "CHECK"
      if ($rbRepairFast.IsChecked) { $repairOption = "REPAIR_FAST" }
      elseif ($rbRepairRebuild.IsChecked) { $repairOption = "REPAIR_REBUILD" }
      elseif ($rbRepairAllowDataLoss.IsChecked) { $repairOption = "REPAIR_ALLOW_DATA_LOSS" }
      if ($repairOption -eq "REPAIR_ALLOW_DATA_LOSS") {
        $msg = @"
⚠️ ADVERTENCIA FINAL ⚠️

Estás a punto de ejecutar REPAIR_ALLOW_DATA_LOSS.

Esta operación:
• PUEDE ELIMINAR DATOS PERMANENTEMENTE
• Es IRREVERSIBLE
• Debe usarse solo como ÚLTIMO RECURSO
• Requiere que hayas respaldado la base de datos

¿Estás ABSOLUTAMENTE SEGURO de continuar?
"@
        if (-not (Ui-Confirm $msg "⚠️ Confirmar Reparación Destructiva" $window)) { return }
      }
      $script:RepairDone = $false
      if (-not $logTimer.IsEnabled) { $logTimer.Start() }
      try {
        $btnIniciar.IsEnabled = $false
        $btnIniciar.Content = "Procesando..."
        $txtLog.Text = ""
        $pbProgress.Value = 0
        $txtProgress.Text = "Iniciando..."
        Add-Log "═══════════════════════════════════════"
        Add-Log "Iniciando operación de reparación"
        Add-Log "Base de datos: $Database"
        Add-Log "Servidor: $Server"
        Add-Log "Operación: $repairOption"
        Add-Log "Cerrar conexiones: $(if ($chkCloseConnections.IsChecked) { 'Sí' } else { 'No' })"
        Add-Log "Modo EMERGENCY: $(if ($chkEmergencyMode.IsChecked) { 'Sí' } else { 'No' })"
        Add-Log "═══════════════════════════════════════"
        Start-RepairWorkAsync -Server $Server -Database $Database -RepairOption $repairOption `
          -CloseConnections ($chkCloseConnections.IsChecked -eq $true) `
          -EmergencyMode ($chkEmergencyMode.IsChecked -eq $true) `
          -Credential $Credential -LogQueue $logQueue -ProgressQueue $progressQueue
        $script:RepairRunning = $true
      } catch {
        Write-DzDebug "`t[DEBUG][UI] ERROR btnIniciar: $($_.Exception.Message)"
        Add-Log "❌ Error: $($_.Exception.Message)"
        $btnIniciar.IsEnabled = $true
        $btnIniciar.Content = "Iniciar"
        Paint-Progress -Percent 0 -Message "Error"
      }
    })
  $null = $window.ShowDialog()
  try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch { }
}
function Safe-CloseWindow {
  param(
    [System.Windows.Window]$Window,
    [Nullable[bool]]$Result = $null
  )
  try {
    if ($Result -ne $null -and $Window -and $Window.IsVisible) {
      try { $Window.DialogResult = $Result } catch { }
    }
  } catch { }
  try { if ($Window) { $Window.Close() } } catch { }
}
function Show-RestoreDialog {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Server, [Parameter(Mandatory = $true)][string]$User, [Parameter(Mandatory = $true)][string]$Password, [Parameter(Mandatory = $true)][string]$Database, [Parameter(Mandatory = $false)][scriptblock]$OnRestoreCompleted)
  $script:RestoreRunning = $false
  $script:RestoreDone = $false
  $defaultPath = "C:\NationalSoft\DATABASES"
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] INICIO"
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Server='$Server' Database='$Database' User='$User'"
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName System.Windows.Forms
  $theme = Get-DzUiTheme

  function Test-XpCmdShellEnabled {
    param([string]$Server, [System.Management.Automation.PSCredential]$Credential)
    $checkQuery = "SELECT CONVERT(int, ISNULL(value, value_in_use)) AS IsEnabled FROM sys.configurations WHERE name = 'xp_cmdshell'"
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    try {
      $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
      $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
      $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;Connection Timeout=10"
      $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
      $connection.Open()
      $cmd = $connection.CreateCommand()
      $cmd.CommandText = $checkQuery
      $cmd.CommandTimeout = 10
      $result = $cmd.ExecuteScalar()
      return ([int]$result) -eq 1
    } catch {
      Write-DzDebug "`t[DEBUG][Test-XpCmdShellEnabled] Error: $($_.Exception.Message)"
      return $false
    } finally {
      if ($plainPassword) { $plainPassword = $null }
      if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
      if ($connection) { try { $connection.Close() } catch { }; try { $connection.Dispose() } catch { } }
    }
  }

  function Enable-XpCmdShell {
    param([string]$Server, [System.Management.Automation.PSCredential]$Credential)
    $enableQuery = @"
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;
"@
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    try {
      $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
      $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
      $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;Connection Timeout=10"
      $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
      $connection.Open()
      $cmd = $connection.CreateCommand()
      $cmd.CommandText = $enableQuery
      $cmd.CommandTimeout = 30
      [void]$cmd.ExecuteNonQuery()
      return @{ Success = $true }
    } catch {
      return @{ Success = $false; ErrorMessage = $_.Exception.Message }
    } finally {
      if ($plainPassword) { $plainPassword = $null }
      if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
      if ($connection) { try { $connection.Close() } catch { }; try { $connection.Dispose() } catch { } }
    }
  }

  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Opciones de Restauración"
        Width="650" Height="720"
        MinWidth="650" MinHeight="720"
        MaxWidth="650" MaxHeight="720"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="130"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TextBoxStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>
    <Style x:Key="SmallTextBoxStyle" TargetType="TextBox" BasedOn="{StaticResource TextBoxStyle}">
      <Setter Property="Height" Value="30"/>
      <Setter Property="Padding" Value="10,5"/>
    </Style>
    <Style x:Key="GroupBoxStyle" TargetType="GroupBox">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
      <Setter Property="Padding" Value="10"/>
    </Style>
    <Style x:Key="ProgressBarStyle" TargetType="ProgressBar">
      <Setter Property="Foreground" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Height" Value="18"/>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black"
                        Direction="270"
                        ShadowDepth="4"
                        BlurRadius="14"
                        Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Opciones de Restauración"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Selecciona el .bak y define destino en el servidor SQL"
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="⚠️ Las rutas MDF/LDF son del SERVIDOR SQL, no de esta máquina. El directorio se creará automáticamente si no existe."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"
                   TextWrapping="Wrap"/>
      </Border>
      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,10">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="Archivo de respaldo (.bak):" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox Name="txtBackupPath" Style="{StaticResource TextBoxStyle}" Grid.Column="0"/>
            <Button Name="btnBrowseBackup"
                    Grid.Column="1"
                    Content="Examinar..."
                    Style="{StaticResource SecondaryButtonStyle}"
                    Width="120"
                    Margin="10,0,0,0"/>
          </Grid>
        </Grid>
        <Grid Grid.Row="1" Margin="0,0,0,10">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="Nombre destino:" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <TextBox Grid.Row="1" Name="txtDestino" Style="{StaticResource TextBoxStyle}"/>
        </Grid>
        <Grid Grid.Row="2" Margin="0,0,0,10">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Text="Carpeta destino en servidor:" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <Grid Grid.Row="1" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox Grid.Column="0" Name="txtServerFolder" Style="{StaticResource SmallTextBoxStyle}"/>
            <Button Name="btnBrowseServerFolder"
                    Grid.Column="1"
                    Content="🗂️ Servidor"
                    Style="{StaticResource SecondaryButtonStyle}"
                    Width="120"
                    Margin="10,0,0,0"
                    ToolTip="Explorar carpetas en el servidor SQL"/>
          </Grid>
          <TextBlock Grid.Row="2" Text="Ruta MDF (datos) en servidor:" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <TextBox Grid.Row="3" Name="txtMdfPath" Style="{StaticResource SmallTextBoxStyle}" IsReadOnly="True" Margin="0,0,0,10"/>
          <TextBlock Grid.Row="4" Text="Ruta LDF (log) en servidor:" FontWeight="SemiBold" Margin="0,0,0,6"/>
          <TextBox Grid.Row="5" Name="txtLdfPath" Style="{StaticResource SmallTextBoxStyle}" IsReadOnly="True"/>
        </Grid>
        <GroupBox Grid.Row="3" Header="Progreso" Style="{StaticResource GroupBoxStyle}" Margin="0,0,0,10">
          <StackPanel>
            <ProgressBar Name="pbRestore" Style="{StaticResource ProgressBarStyle}" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock Name="txtProgress" Text="Esperando..." Margin="0,8,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </GroupBox>
        <GroupBox Grid.Row="4" Header="Log" Style="{StaticResource GroupBoxStyle}">
          <TextBox Name="txtLog"
                   Background="{DynamicResource ControlBg}"
                   Foreground="{DynamicResource ControlFg}"
                   BorderBrush="{DynamicResource BorderBrushColor}"
                   BorderThickness="1"
                   Padding="10"
                   AcceptsReturn="True"
                   IsReadOnly="True"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Auto"
                   TextWrapping="NoWrap"
                   IsUndoEnabled="False"/>
        </GroupBox>
      </Grid>
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0"
                   Text="Esc: Cerrar"
                   Foreground="{DynamicResource AccentMuted}"
                   VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="btnCerrar"
                  Content="Cerrar"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="120"
                  Margin="0,0,10,0"
                  IsCancel="True"/>
          <Button Name="btnAceptar"
                  Content="Iniciar Restauración"
                  Style="{StaticResource PrimaryButtonStyle}"
                  Width="170"
                  IsDefault="True"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
  $ui = New-WpfWindow -Xaml $xaml -PassThru
  $window = $ui.Window
  $c = $ui.Controls
  $theme = Get-DzUiTheme
  Set-DzWpfThemeResources -Window $window -Theme $theme
  try { Set-WpfDialogOwner -Dialog $window } catch {}
  try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
  $window.WindowStartupLocation = "Manual"
  $window.Add_Loaded({
      try {
        $owner = $window.Owner
        if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
        $ob = $owner.RestoreBounds
        $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
        $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)
        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea
        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
        $window.Left = [double]$left
        $window.Top = [double]$top
      } catch {}
    }.GetNewClosure())
  $c['HeaderBar'].Add_MouseLeftButtonDown({
      if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        try { $window.DragMove() } catch {}
      }
    })
  $c['btnClose'].Add_Click({ try { $window.Close() } catch {} })
  $window.Add_PreviewKeyDown({
      param($sender, $e)
      if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        try { $window.Close() } catch {}
      }
    })
  $txtBackupPath = $c['txtBackupPath']
  $btnBrowseBackup = $c['btnBrowseBackup']
  $txtDestino = $c['txtDestino']
  $txtServerFolder = $c['txtServerFolder']
  $btnBrowseServerFolder = $c['btnBrowseServerFolder']
  $txtMdfPath = $c['txtMdfPath']
  $txtLdfPath = $c['txtLdfPath']
  $pbRestore = $c['pbRestore']
  $txtProgress = $c['txtProgress']
  $txtLog = $c['txtLog']
  $btnAceptar = $c['btnAceptar']
  $btnCerrar = $c['btnCerrar']
  $ResetRestoreUI = {
    param([string]$ButtonText = "Iniciar Restauración", [string]$ProgressText = "Esperando...")
    $script:RestoreRunning = $false
    if ($btnAceptar) { $btnAceptar.IsEnabled = $true; $btnAceptar.Content = $ButtonText }
    if ($txtBackupPath) { $txtBackupPath.IsEnabled = $true }
    if ($btnBrowseBackup) { $btnBrowseBackup.IsEnabled = $true }
    if ($txtDestino) { $txtDestino.IsEnabled = $true }
    if ($txtServerFolder) { $txtServerFolder.IsEnabled = $true }
    if ($btnBrowseServerFolder) { $btnBrowseServerFolder.IsEnabled = $true }
    if ($txtProgress) { $txtProgress.Text = $ProgressText }
  }.GetNewClosure()
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Controles: txtBackupPath=$([bool]$txtBackupPath) btnBrowseBackup=$([bool]$btnBrowseBackup) txtDestino=$([bool]$txtDestino) txtServerFolder=$([bool]$txtServerFolder) btnBrowseServerFolder=$([bool]$btnBrowseServerFolder) txtMdfPath=$([bool]$txtMdfPath) txtLdfPath=$([bool]$txtLdfPath) pbRestore=$([bool]$pbRestore) txtProgress=$([bool]$txtProgress) txtLog=$([bool]$txtLog) btnAceptar=$([bool]$btnAceptar) btnCerrar=$([bool]$btnCerrar)"
  if (-not $txtBackupPath -or -not $btnBrowseBackup -or -not $txtDestino -or -not $txtServerFolder -or -not $btnBrowseServerFolder -or -not $txtMdfPath -or -not $txtLdfPath -or -not $pbRestore -or -not $txtProgress -or -not $txtLog -or -not $btnAceptar -or -not $btnCerrar) {
    Write-DzDebug "`t[DEBUG][Show-RestoreDialog] ERROR: controles NULL"; throw "Controles WPF incompletos (diccionario Controls devolvió NULL)."
  }
  $txtServerFolder.Text = $defaultPath
  $bc = [System.Windows.Media.BrushConverter]::new()
  $PLACEHOLDER = "SELECCIONA PRIMERO EL RESPALDO"
  function Set-TxtDestinoPlaceholder {
    if ($txtDestino) {
      $txtDestino.Text = $PLACEHOLDER
      $txtDestino.Foreground = $bc.ConvertFromString($theme.AccentMuted)
      $txtDestino.FontStyle = [System.Windows.FontStyles]::Italic
    }
  }
  function Set-TxtDestinoNormal {
    if ($txtDestino) {
      $txtDestino.Foreground = $bc.ConvertFromString($theme.ControlForeground)
      $txtDestino.FontStyle = [System.Windows.FontStyles]::Normal
    }
  }
  Set-TxtDestinoPlaceholder
  function Normalize-RestoreFolder {
    param([string]$BasePath)
    if ([string]::IsNullOrWhiteSpace($BasePath)) { return $BasePath }
    $trimmed = $BasePath.Trim()
    if ($trimmed.EndsWith('\')) { return $trimmed.TrimEnd('\') }
    $trimmed
  }
  function Update-RestorePaths {
    param([string]$DatabaseName, [string]$ServerFolder)
    if ([string]::IsNullOrWhiteSpace($DatabaseName)) { return }
    if ($DatabaseName -eq $PLACEHOLDER) { return }
    if ([string]::IsNullOrWhiteSpace($ServerFolder)) { $ServerFolder = $defaultPath }
    $baseFolder = Normalize-RestoreFolder -BasePath $ServerFolder
    if ($txtMdfPath) { $txtMdfPath.Text = Join-Path $baseFolder "$DatabaseName.mdf" }
    if ($txtLdfPath) { $txtLdfPath.Text = Join-Path $baseFolder "$DatabaseName.ldf" }
  }
  $logQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $progressQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
  function Paint-Progress {
    param([int]$Percent, [string]$Message)
    if ($pbRestore) { $pbRestore.Value = $Percent }
    if ($txtProgress) { $txtProgress.Text = $Message }
  }
  function Add-Log { param([string]$Message) $logQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)) }
  function New-SafeCredential { param([string]$Username, [string]$PlainPassword) $secure = New-Object System.Security.SecureString; foreach ($ch in $PlainPassword.ToCharArray()) { $secure.AppendChar($ch) }; $secure.MakeReadOnly(); New-Object System.Management.Automation.PSCredential($Username, $secure) }

  function Test-ServerDirectoryExists {
    param([string]$Server, [string]$DirectoryPath, [System.Management.Automation.PSCredential]$Credential)
    $checkQuery = @"
DECLARE @Path NVARCHAR(512) = N'$($DirectoryPath -replace "'", "''")'
DECLARE @FileExists INT
EXEC master.dbo.xp_fileexist @Path, @FileExists OUTPUT
SELECT @FileExists AS DirectoryExists
"@
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    try {
      $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
      $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
      $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
      $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
      $connection.Open()
      $cmd = $connection.CreateCommand()
      $cmd.CommandText = $checkQuery
      $cmd.CommandTimeout = 30
      $reader = $cmd.ExecuteReader()
      $exists = $false
      if ($reader.Read()) {
        $exists = ([int]$reader["DirectoryExists"]) -eq 1
      }
      $reader.Close()
      return $exists
    } catch {
      Write-DzDebug "`t[DEBUG][Test-ServerDirectoryExists] Error: $($_.Exception.Message)"
      return $false
    } finally {
      if ($plainPassword) { $plainPassword = $null }
      if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
      if ($connection) { try { $connection.Close() } catch { }; try { $connection.Dispose() } catch { } }
    }
  }

  function Create-ServerDirectory {
    param([string]$Server, [string]$DirectoryPath, [System.Management.Automation.PSCredential]$Credential)
    $createQuery = @"
DECLARE @Path NVARCHAR(512) = N'$($DirectoryPath -replace "'", "''")'
DECLARE @Cmd NVARCHAR(1024) = N'cmd.exe /c if not exist "' + @Path + '" mkdir "' + @Path + '"'
EXEC master.dbo.xp_cmdshell @Cmd, NO_OUTPUT
"@
    $connection = $null
    $passwordBstr = [IntPtr]::Zero
    $plainPassword = $null
    try {
      $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
      $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
      $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
      $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
      $connection.Open()
      $cmd = $connection.CreateCommand()
      $cmd.CommandText = $createQuery
      $cmd.CommandTimeout = 60
      [void]$cmd.ExecuteNonQuery()
      return @{ Success = $true }
    } catch {
      return @{ Success = $false; ErrorMessage = $_.Exception.Message }
    } finally {
      if ($plainPassword) { $plainPassword = $null }
      if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
      if ($connection) { try { $connection.Close() } catch { }; try { $connection.Dispose() } catch { } }
    }
  }

  function Start-RestoreWorkAsync {
    param(
      [string]$Server,
      [string]$DatabaseName,
      [string]$RestoreQuery,
      [System.Management.Automation.PSCredential]$Credential,
      [System.Collections.Concurrent.ConcurrentQueue[string]]$LogQueue,
      [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue
    )
    Write-DzDebug "`t[DEBUG][Start-RestoreWorkAsync] Preparando runspace..."
    $worker = {
      param($Server, $DatabaseName, $RestoreQuery, $Credential, $LogQueue, $ProgressQueue)
      function EnqLog([string]$m) { $LogQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m)) }
      function EnqProg([int]$p, [string]$m) { $ProgressQueue.Enqueue(@{Percent = $p; Message = $m }) }
      function Invoke-SqlQueryLite {
        param([string]$Server, [string]$Database, [string]$Query, [System.Management.Automation.PSCredential]$Credential, [scriptblock]$InfoMessageCallback)
        $connection = $null
        $passwordBstr = [IntPtr]::Zero
        $plainPassword = $null
        $hasError = $false
        $errorMessages = @()
        try {
          $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
          $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
          $cs = "Server=$Server;Database=$Database;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
          $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
          $state = [pscustomobject]@{ HasError = $false; Errors = New-Object System.Collections.Generic.List[string] }
          if ($InfoMessageCallback) {
            $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] {
              param($sender, $e)
              try {
                $msg = [string]$e.Message
                if ([string]::IsNullOrWhiteSpace($msg)) { return }
                $isProgressMsg = $msg -match '(?i)\b\d{1,3}\s*(%|percent|porcentaje|por\s+ciento)\b'
                $isSuccessMsg = $msg -match '(?i)(successfully processed|procesad[oa]\s+correctamente|se proces[oó]\s+correctamente)'
                if (-not $isProgressMsg -and -not $isSuccessMsg) {
                  if ($msg -match '(?i)(abnormal termination|not compatible|no es compatible|cannot restore|failed|restore failed|imposible|\berror\b)') {
                    $state.HasError = $true
                    $null = $state.Errors.Add($msg)
                  }
                }
                & $InfoMessageCallback $msg $state.HasError
              } catch { }
            }
            $connection.add_InfoMessage($handler)
            $connection.FireInfoMessageEventOnUserErrors = $true
          }
          $connection.Open()
          $cmd = $connection.CreateCommand()
          $cmd.CommandText = $Query
          $cmd.CommandTimeout = 0
          [void]$cmd.ExecuteNonQuery()
          if ($state.HasError) {
            $combinedErrors = $state.Errors -join "`n"
            return @{ Success = $false; ErrorMessage = $combinedErrors; IsInfoMessageError = $true }
          }
          @{ Success = $true }
        } catch {
          @{ Success = $false; ErrorMessage = $_.Exception.Message; IsInfoMessageError = $false }
        } finally {
          if ($plainPassword) { $plainPassword = $null }
          if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
          if ($connection) { try { $connection.Close() } catch { } ; try { $connection.Dispose() } catch { } }
        }
      }
      try {
        EnqLog "Enviando comando de restauración a SQL Server..."
        EnqProg 10 "Iniciando restauración..."
        $hasErrorFlag = $false
        $errorDetails = ""
        $allErrors = @()
        $progressCb = {
          param([string]$Message, [bool]$IsError)
          $m = ($Message -replace '\s+', ' ').Trim()
          if (-not $m) { return }
          if ($m -match '(?i)\b(\d{1,3})\s*(%|percent|porcentaje|por\s+ciento)\b') {
            $p = [int]$Matches[1]
            $p = [math]::Max(0, [math]::Min(100, $p))
            EnqProg $p ("Progreso restauración: $p%")
            EnqLog ("[SQL] Progreso: $p%  ($m)")
            return
          }
          if ($m -match '(?i)\b(processed\s+\d{1,3}\s*percent\b|se proces[oó] correctamente|completad[oa])') {
            EnqProg 100 "Restauración completada."
            EnqLog "✅ Restauración finalizada"
            return
          }
          $isCriticalError = $m -match '(?i)(abnormal termination|failed to|error|cannot restore|not compatible|no es compatible|imposible|terminado an[oó]malo)'
          if ($IsError -or $isCriticalError) {
            $script:hasErrorFlag = $true
            $script:allErrors += $m
            if (-not $script:errorDetails -or $m.Length -gt $script:errorDetails.Length) { $script:errorDetails = $m }
            EnqLog ("[SQL ERROR] $m")
            return
          }
          EnqLog ("[SQL] $m")
        }
        $r = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $RestoreQuery -Credential $Credential -InfoMessageCallback $progressCb
        if (-not $r.Success) {
          EnqProg 0 "❌ Error en restauración"
          EnqLog ("❌ Error de SQL: {0}" -f $r.ErrorMessage)
          EnqLog "ERROR_RESULT|$($r.ErrorMessage)"
          EnqLog "__DONE__"
          return
        }
        if ($hasErrorFlag) {
          EnqProg 0 "❌ Restauración falló"
          EnqLog "❌ La restauración no se completó correctamente"
          if ($allErrors.Count -gt 0) {
            if ($allErrors.Count -le 3) {
              $finalErrorMsg = $allErrors -join "`n`n"
            } else {
              $uniqueErrors = $allErrors | Select-Object -Unique | Select-Object -First 3
              $finalErrorMsg = $uniqueErrors -join "`n`n"
            }
            EnqLog "ERROR_RESULT|$finalErrorMsg"
          } else {
            EnqLog "ERROR_RESULT|Error detectado durante la restauración. Revisa el log para más detalles."
          }
          EnqLog "__DONE__"
          return
        }
        EnqProg 100 "Restauración finalizada."
        EnqLog "✅ Comando RESTORE finalizó correctamente"
        EnqLog "SUCCESS_RESULT|Base de datos restaurada exitosamente"
        EnqLog "__DONE__"
      } catch {
        EnqProg 0 "Error"
        EnqLog ("❌ Error inesperado (worker): {0}" -f $_.Exception.Message)
        EnqLog "ERROR_RESULT|$($_.Exception.Message)"
        EnqLog "__DONE__"
      }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($worker).AddArgument($Server).AddArgument($DatabaseName).AddArgument($RestoreQuery).AddArgument($Credential).AddArgument($LogQueue).AddArgument($ProgressQueue)
    $null = $ps.BeginInvoke()
    Write-DzDebug "`t[DEBUG][Start-RestoreWorkAsync] Worker lanzado"
  }

  # Variable para controlar si el timer debe seguir ejecutándose
  $script:timerShouldRun = $true

  $logTimer = [System.Windows.Threading.DispatcherTimer]::new()
  $logTimer.Interval = [TimeSpan]::FromMilliseconds(200)
  $logTimer.Add_Tick({
      # Protección: verificar si el timer debe seguir ejecutándose
      if (-not $script:timerShouldRun) {
        $logTimer.Stop()
        return
      }

      try {
        $count = 0
        $doneThisTick = $false
        $finalResult = $null
        while ($count -lt 50) {
          $line = $null
          if (-not $logQueue.TryDequeue([ref]$line)) { break }
          if ($line -like "*SUCCESS_RESULT|*") { $finalResult = @{ Success = $true; Message = $line -replace '^.*SUCCESS_RESULT\|', '' } }
          if ($line -like "*ERROR_RESULT|*") { $finalResult = @{ Success = $false; Message = $line -replace '^.*ERROR_RESULT\|', '' } }
          if ($line -notmatch '(SUCCESS_RESULT|ERROR_RESULT)' -and $txtLog) {
            $txtLog.Text = "$line`n" + $txtLog.Text
          }
          if ($line -like "*__DONE__*") {
            Write-DzDebug "`t[DEBUG][UI] Señal DONE recibida (restore)"
            $doneThisTick = $true
            $script:RestoreRunning = $false
            if ($btnAceptar) { $btnAceptar.IsEnabled = $true; $btnAceptar.Content = "Iniciar Restauración" }
            if ($txtBackupPath) { $txtBackupPath.IsEnabled = $true }
            if ($btnBrowseBackup) { $btnBrowseBackup.IsEnabled = $true }
            if ($txtDestino) { $txtDestino.IsEnabled = $true }
            if ($txtServerFolder) { $txtServerFolder.IsEnabled = $true }
            if ($btnBrowseServerFolder) { $btnBrowseServerFolder.IsEnabled = $true }
            $tmp = $null
            while ($progressQueue.TryDequeue([ref]$tmp)) { }
            Paint-Progress -Percent 100 -Message "Completado"
            $script:RestoreDone = $true
            if ($finalResult -and $window) {
              $window.Dispatcher.Invoke([action] {
                  if ($finalResult.Success) {
                    Ui-Info "Base de datos '$($txtDestino.Text)' restaurada con éxito.`n`n$($finalResult.Message)" "✓ Restauración Exitosa" $window
                    if ($OnRestoreCompleted) {
                      Write-DzDebug "`t[DEBUG][Show-RestoreDialog] OnRestoreCompleted: DB='$($txtDestino.Text)'"
                      try { & $OnRestoreCompleted $txtDestino.Text } catch { Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Error OnRestoreCompleted: $($_.Exception.Message)" }
                    }
                  } else {
                    Ui-Error "La restauración falló:`n`n$($finalResult.Message)" "✗ Error en Restauración" $window
                  }
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
            }
          }
          $count++
        }
        if ($count -gt 0 -and $txtLog) { $txtLog.ScrollToLine(0) }
        if (-not $doneThisTick) {
          $last = $null
          while ($true) {
            $p = $null
            if (-not $progressQueue.TryDequeue([ref]$p)) { break }
            $last = $p
          }
          if ($last) { Paint-Progress -Percent $last.Percent -Message $last.Message }
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI][logTimer][restore] ERROR: $($_.Exception.Message)"
      }
      if ($script:RestoreDone) {
        $tmpLine = $null
        $tmpProg = $null
        if (-not $logQueue.TryPeek([ref]$tmpLine) -and -not $progressQueue.TryPeek([ref]$tmpProg)) {
          $logTimer.Stop()
          $script:RestoreDone = $false
        }
      }
    })
  $logTimer.Start()
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] logTimer iniciado"

  # Evento de cierre de ventana - DETENER EL TIMER
  $window.Add_Closed({
      Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Ventana cerrada - deteniendo timer"
      $script:timerShouldRun = $false
      if ($logTimer) {
        try {
          $logTimer.Stop()
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Timer detenido exitosamente"
        } catch {
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Error deteniendo timer: $($_.Exception.Message)"
        }
      }
    })

  $credential = New-SafeCredential -Username $User -PlainPassword $Password
  $xpCmdShellEnabled = Test-XpCmdShellEnabled -Server $Server -Credential $credential
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] xp_cmdshell enabled: $xpCmdShellEnabled"

  if (-not $xpCmdShellEnabled) {
    Add-Log "⚠️ xp_cmdshell está deshabilitado en el servidor"
    $enableChoice = Ui-Confirm "xp_cmdshell está deshabilitado en SQL Server.`n`nEs necesario para crear directorios automáticamente en el servidor.`n`n¿Deseas habilitarlo ahora?`n`n(Requiere permisos de administrador SQL)" "Habilitar xp_cmdshell" $window
    if ($enableChoice) {
      Add-Log "Habilitando xp_cmdshell..."
      $enableResult = Enable-XpCmdShell -Server $Server -Credential $credential
      if ($enableResult.Success) {
        Add-Log "✅ xp_cmdshell habilitado exitosamente"
        $xpCmdShellEnabled = $true
      } else {
        Add-Log "❌ No se pudo habilitar xp_cmdshell: $($enableResult.ErrorMessage)"
        Ui-Warn "No se pudo habilitar xp_cmdshell automáticamente.`n`nDeberás escribir manualmente la ruta completa en el campo 'Carpeta destino en servidor'.`n`nEjemplo: C:\NationalSoft\DATABASES" "Atención" $window
      }
    } else {
      Add-Log "⚠️ Continuando sin xp_cmdshell (sin creación automática de directorios)"
      Ui-Info "Deberás asegurarte de que el directorio de destino ya existe en el servidor, o escribir una ruta que ya exista.`n`nLa restauración fallará si el directorio no existe." "Información" $window
    }
  } else {
    Add-Log "✅ xp_cmdshell está habilitado"
  }

  $btnBrowseBackup.Add_Click({
      try {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "SQL Backup (*.bak)|*.bak|Todos los archivos (*.*)|*.*"
        $dlg.Multiselect = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
          $txtBackupPath.Text = $dlg.FileName
          $suggestedName = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
          $txtDestino.Text = $suggestedName
          Set-TxtDestinoNormal
          Update-RestorePaths -DatabaseName $suggestedName -ServerFolder $txtServerFolder.Text
          Add-Log "📝 Nombre destino sugerido: $suggestedName"
        }
      } catch {
        Ui-Error "No se pudo abrir el selector de archivos: $($_.Exception.Message)" "Error" $window
      }
    })

  $txtDestino.Add_TextChanged({
      try {
        if ($txtDestino.Text -and $txtDestino.Text -ne $PLACEHOLDER) {
          Update-RestorePaths -DatabaseName $txtDestino.Text -ServerFolder $txtServerFolder.Text
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error actualizando rutas: $($_.Exception.Message)"
      }
    })

  $txtServerFolder.Add_TextChanged({
      try {
        if ($txtDestino.Text -and $txtDestino.Text -ne $PLACEHOLDER) {
          Update-RestorePaths -DatabaseName $txtDestino.Text -ServerFolder $txtServerFolder.Text
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error actualizando rutas: $($_.Exception.Message)"
      }
    })
  $btnBrowseServerFolder.Add_Click({
      try {
        $cred = New-SafeCredential -Username $User -PlainPassword $Password

        if (Get-Command Show-ServerFolderBrowser -ErrorAction SilentlyContinue) {
          $selected = Show-ServerFolderBrowser -Server $Server -Credential $cred -StartPath $txtServerFolder.Text

          if ($selected) {
            $txtServerFolder.Text = $selected
            Update-RestorePaths -DatabaseName $txtDestino.Text -ServerFolder $txtServerFolder.Text
          }
          return
        }

        Ui-Warn "La función 'Show-ServerFolderBrowser' no está disponible en este build.`n`nPuedes escribir la ruta manualmente (es ruta del SERVIDOR SQL).`nEjemplo: C:\NationalSoft\DATABASES" "Explorador no disponible" $window
      } catch {
        Ui-Error "Error al abrir explorador de carpetas en servidor: $($_.Exception.Message)" "Error" $window
      }
    })

  $btnAceptar.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnAceptar Restore Click"
      if ($script:RestoreRunning) { return }
      $script:RestoreDone = $false
      if (-not $logTimer.IsEnabled) { $logTimer.Start() }
      try {
        $btnAceptar.IsEnabled = $false
        $btnAceptar.Content = "Procesando..."
        $txtLog.Text = ""
        $pbRestore.Value = 0
        $txtProgress.Text = "Esperando..."
        Add-Log "Iniciando proceso de restauración..."
        $backupPath = $txtBackupPath.Text.Trim()
        $destName = $txtDestino.Text.Trim()
        if ($destName -eq $PLACEHOLDER) {
          Ui-Warn "Debes seleccionar un archivo de respaldo primero.`n`nEl nombre de la base de datos se generará automáticamente basado en el archivo .bak que selecciones." "Atención" $window
          & $ResetRestoreUI -ProgressText "Selecciona archivo de respaldo"
          return
        }
        $serverFolder = $txtServerFolder.Text.Trim()
        $mdfPath = $txtMdfPath.Text.Trim()
        $ldfPath = $txtLdfPath.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($backupPath)) { Ui-Warn "Selecciona el archivo .bak a restaurar." "Atención" $window; & $ResetRestoreUI -ProgressText "Archivo de respaldo requerido"; return }
        if ([string]::IsNullOrWhiteSpace($destName)) { Ui-Warn "Indica el nombre destino de la base de datos." "Atención" $window; & $ResetRestoreUI -ProgressText "Nombre destino requerido"; return }
        if ([string]::IsNullOrWhiteSpace($serverFolder)) { Ui-Warn "Indica la carpeta destino en el servidor." "Atención" $window; & $ResetRestoreUI -ProgressText "Carpeta servidor requerida"; return }
        Add-Log "Servidor: $Server"
        Add-Log "Base de datos destino: $destName"
        Add-Log "Backup: $backupPath"
        Add-Log "Carpeta servidor: $serverFolder"
        Add-Log "MDF: $mdfPath"
        Add-Log "LDF: $ldfPath"
        Add-Log "✓ Credenciales listas"

        if ($xpCmdShellEnabled) {
          Add-Log "🔍 Verificando directorio en servidor..."
          $dirExists = Test-ServerDirectoryExists -Server $Server -DirectoryPath $serverFolder -Credential $credential
          if (-not $dirExists) {
            Add-Log "📁 El directorio no existe, creándolo..."
            $createResult = Create-ServerDirectory -Server $Server -DirectoryPath $serverFolder -Credential $credential
            if (-not $createResult.Success) {
              Ui-Error "No se pudo crear el directorio en el servidor:`n`n$($createResult.ErrorMessage)" "Error" $window
              & $ResetRestoreUI -ProgressText "Error creando directorio"
              return
            }
            Add-Log "✅ Directorio creado exitosamente"
          } else {
            Add-Log "✅ Directorio ya existe en servidor"
          }
        } else {
          Add-Log "⚠️ Sin verificación de directorio (xp_cmdshell deshabilitado)"
        }

        $escapedBackup = $backupPath -replace "'", "''"
        $escapedMdf = $mdfPath -replace "'", "''"
        $escapedLdf = $ldfPath -replace "'", "''"
        $escapedDest = $destName -replace "'", "''"
        $destNameSafe = $destName -replace ']', ']]'
        Paint-Progress -Percent 5 -Message "Leyendo metadatos del backup..."
        $fileListQuery = "RESTORE FILELISTONLY FROM DISK = N'$escapedBackup'"
        function Get-BackupFileList {
          param([string]$Server, [string]$Query, [System.Management.Automation.PSCredential]$Credential)
          $connection = $null
          $passwordBstr = [IntPtr]::Zero
          $plainPassword = $null
          try {
            $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
            $cs = "Server=$Server;Database=master;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
            $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
            $connection.Open()
            $cmd = $connection.CreateCommand()
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = 60
            $reader = $cmd.ExecuteReader()
            $dataTable = New-Object System.Data.DataTable
            $dataTable.Load($reader)
            $reader.Close()
            return @{ Success = $true; DataTable = $dataTable }
          } catch {
            return @{ Success = $false; ErrorMessage = $_.Exception.Message; DataTable = $null }
          } finally {
            if ($plainPassword) { $plainPassword = $null }
            if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
            if ($connection) { try { $connection.Close() } catch { } ; try { $connection.Dispose() } catch { } }
          }
        }
        $fileListResult = Get-BackupFileList -Server $Server -Query $fileListQuery -Credential $credential
        if (-not $fileListResult.Success) {
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Error FILELISTONLY: $($fileListResult.ErrorMessage)"
          Ui-Error "No se pudo leer el contenido del backup: $($fileListResult.ErrorMessage)" "Error" $window
          & $ResetRestoreUI -ProgressText "Error leyendo backup"
          return
        }
        if (-not $fileListResult.DataTable -or $fileListResult.DataTable.Rows.Count -eq 0) {
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] FILELISTONLY no devolvió filas"
          Ui-Error "El archivo de backup no contiene información de archivos válida." "Error" $window
          & $ResetRestoreUI -ProgressText "Backup sin información"
          return
        }
        Add-Log "Archivos en backup: $($fileListResult.DataTable.Rows.Count)"
        $logicalData = $null
        $logicalLog = $null
        foreach ($row in $fileListResult.DataTable.Rows) {
          $type = [string]$row["Type"]
          $logicalName = [string]$row["LogicalName"]
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Archivo: LogicalName='$logicalName' Type='$type'"
          if (-not $logicalData -and $type -eq "D") { $logicalData = $logicalName; Add-Log "Encontrado archivo de datos: $logicalName" }
          if (-not $logicalLog -and $type -eq "L") { $logicalLog = $logicalName; Add-Log "Encontrado archivo de log: $logicalName" }
        }
        if (-not $logicalData -or -not $logicalLog) {
          Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Logical names missing. Data='$logicalData' Log='$logicalLog'"
          Ui-Error "No se encontraron nombres lógicos válidos en el backup.`n`nData: $logicalData`nLog: $logicalLog" "Error" $window
          & $ResetRestoreUI -ProgressText "Error en nombres lógicos"
          return
        }
        Add-Log ("✓ Logical Data: {0}" -f $logicalData)
        Add-Log ("✓ Logical Log: {0}" -f $logicalLog)
        $restoreQuery = @"
IF DB_ID(N'$escapedDest') IS NOT NULL
BEGIN
    ALTER DATABASE [$destNameSafe] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
END
RESTORE DATABASE [$destNameSafe]
FROM DISK = N'$escapedBackup'
WITH MOVE N'$logicalData' TO N'$escapedMdf',
     MOVE N'$logicalLog' TO N'$escapedLdf',
     REPLACE, RECOVERY, STATS = 1;
IF DB_ID(N'$escapedDest') IS NOT NULL
BEGIN
    ALTER DATABASE [$destNameSafe] SET MULTI_USER;
END
"@
        Paint-Progress -Percent 10 -Message "Conectando a SQL Server..."
        Write-DzDebug "`t[DEBUG][UI] Llamando Start-RestoreWorkAsync"
        Start-RestoreWorkAsync -Server $Server -DatabaseName $destName -RestoreQuery $restoreQuery -Credential $credential -LogQueue $logQueue -ProgressQueue $progressQueue
        $script:RestoreRunning = $true
        $txtBackupPath.IsEnabled = $false
        $btnBrowseBackup.IsEnabled = $false
        $txtDestino.IsEnabled = $false
        $txtServerFolder.IsEnabled = $false
        $btnBrowseServerFolder.IsEnabled = $false

      } catch {
        Write-DzDebug "`t[DEBUG][UI] ERROR btnAceptar Restore: $($_.Exception.Message)"
        Add-Log "❌ Error: $($_.Exception.Message)"
        & $ResetRestoreUI -ProgressText "Error inesperado"
      }
    })

  $btnCerrar.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnCerrar Restore Click"
      $window.DialogResult = $false
      $window.Close()
    })

  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Antes de ShowDialog()"
  $null = $window.ShowDialog()
  Write-DzDebug "`t[DEBUG][Show-RestoreDialog] Después de ShowDialog()"
}
function Invoke-SqlScalarTable {
  param(
    [Parameter(Mandatory)] [string]$Server,
    [Parameter(Mandatory)] [string]$Database,
    [Parameter(Mandatory)] [string]$Query,
    [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$Credential
  )

  $conn = $null
  $bstr = [IntPtr]::Zero
  $plain = $null

  try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)

    $cs = "Server=$Server;Database=$Database;User Id=$($Credential.UserName);Password=$plain;MultipleActiveResultSets=True"
    $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 30

    $r = $cmd.ExecuteReader()
    if (-not $r) {
      return @{ Success = $false; ErrorMessage = "SQL ExecuteReader devolvió NULL."; DataTable = $null }
    }

    $dt = New-Object System.Data.DataTable
    $dt.Load($r)
    $r.Close()

    return @{ Success = $true; ErrorMessage = $null; DataTable = $dt }
  } catch {
    return @{ Success = $false; ErrorMessage = $_.Exception.Message; DataTable = $null }
  } finally {
    if ($plain) { $plain = $null }
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if ($conn) { try { $conn.Close() } catch {}; try { $conn.Dispose() } catch {} }
  }
}
function Get-ServerSubDirs {
  param(
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential
  )

  $p = [string]$Path
  $p = $p.Trim().TrimEnd('\')

  if ([string]::IsNullOrWhiteSpace($p)) {
    return @{ Success = $false; ErrorMessage = "Path vacío."; Items = @() }
  }

  $pEsc = $p -replace "'", "''"

  $q1 = @"
DECLARE @p nvarchar(4000)=N'$pEsc';
CREATE TABLE #t(subdirectory nvarchar(512), depth int, [file] int);
INSERT #t EXEC master..xp_dirtree @p, 1, 1;
SELECT subdirectory
FROM #t
WHERE [file]=0
ORDER BY subdirectory;
"@

  $r1 = Invoke-SqlScalarTable -Server $Server -Database "master" -Query $q1 -Credential $Credential

  if ($r1 -and $r1.Success -and $r1.DataTable) {
    $names = @()
    foreach ($row in $r1.DataTable.Rows) {
      $n = [string]$row["subdirectory"]
      if (-not [string]::IsNullOrWhiteSpace($n)) {
        $names += $n
      }
    }
    return @{ Success = $true; ErrorMessage = $null; Items = $names }
  }

  $q2 = @"
DECLARE @cmd nvarchar(4000)=N'cmd /c dir /b /ad "$pEsc"';
CREATE TABLE #x(line nvarchar(4000));
INSERT #x EXEC master..xp_cmdshell @cmd;
SELECT line
FROM #x
WHERE line IS NOT NULL
  AND LTRIM(RTRIM(line)) <> ''
  AND line NOT LIKE '%File Not Found%'
  AND line NOT LIKE '%Access is denied%'
ORDER BY line;
"@

  $r2 = Invoke-SqlScalarTable -Server $Server -Database "master" -Query $q2 -Credential $Credential

  if ($r2 -and $r2.Success -and $r2.DataTable) {
    $names = @()
    foreach ($row in $r2.DataTable.Rows) {
      $n = [string]$row["line"]
      if (-not [string]::IsNullOrWhiteSpace($n)) {
        $names += $n.Trim()
      }
    }
    return @{ Success = $true; ErrorMessage = $null; Items = $names }
  }

  $msg = $null
  if ($r1 -and $r1.ErrorMessage) {
    $msg = $r1.ErrorMessage
  }
  if (-not $msg -and $r2 -and $r2.ErrorMessage) {
    $msg = $r2.ErrorMessage
  }
  if (-not $msg) {
    $msg = "No se pudo listar carpetas (xp_dirtree y xp_cmdshell fallaron)."
  }

  return @{ Success = $false; ErrorMessage = $msg; Items = @() }
}
function Show-BackupDialog {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Server, [Parameter(Mandatory = $true)][string]$User, [Parameter(Mandatory = $true)][string]$Password, [Parameter(Mandatory = $true)][string]$Database)
  $script:BackupRunning = $false
  $script:BackupDone = $false
  $script:EnableThreadJob = $false
  $defaultBackupPath = "C:\Temp\SQLBackups"
  function Initialize-ThreadJob {
    [CmdletBinding()]
    param()
    Write-DzDebug "`t[DEBUG][Initialize-ThreadJob] Verificando módulo ThreadJob"
    if (Get-Module -ListAvailable -Name ThreadJob) {
      Import-Module ThreadJob -Force
      Write-DzDebug "`t[DEBUG][Initialize-ThreadJob] Módulo ThreadJob importado"
      return $true
    } else {
      Write-DzDebug "`t[DEBUG][Initialize-ThreadJob] Módulo ThreadJob no encontrado, intentando instalar"
      try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        Import-Module ThreadJob -Force
        Write-DzDebug "`t[DEBUG][Initialize-ThreadJob] Módulo ThreadJob instalado e importado"
        return $true
      } catch {
        Write-DzDebug "`t[DEBUG][Initialize-ThreadJob] Error instalando ThreadJob: $_"
        return $false
      }
    }
  }
  if ($script:EnableThreadJob) { if (-not (Initialize-ThreadJob)) { Write-Host "Advertencia: No se pudo cargar ThreadJob..." -ForegroundColor Yellow } }
  Write-DzDebug "`t[DEBUG][Show-BackupDialog] INICIO"
  Write-DzDebug "`t[DEBUG][Show-BackupDialog] Server='$Server' Database='$Database' User='$User'"
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName System.Windows.Forms
  $theme = Get-DzUiTheme
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Opciones de Respaldo"
        Width="630" Height="750"
        MinWidth="630" MinHeight="750"
        MaxWidth="630" MaxHeight="750"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="120"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle"
           TargetType="Button"
           BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TextBoxStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>
    <Style x:Key="PasswordBoxStyle" TargetType="PasswordBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>
    <Style x:Key="CheckBoxStyle" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style x:Key="CardTitleStyle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">

    <Border.Effect>
      <DropShadowEffect Color="Black"
                        Direction="270"
                        ShadowDepth="4"
                        BlurRadius="14"
                        Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0"
              x:Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="Opciones de Respaldo"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Backup + compresión opcional"
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2"
                  x:Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: si el servidor es remoto, la ruta UNC debe ser accesible para que puedas abrir la carpeta desde tu PC."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"
                   TextWrapping="Wrap"/>
      </Border>
      <Grid Grid.Row="2" Margin="12,0,12,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
         <Border Grid.Row="0" Background="{DynamicResource ControlBg}" BorderBrush="{DynamicResource BorderBrushColor}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="0,0,0,10">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Text="Opciones" Style="{StaticResource CardTitleStyle}"/>

            <!-- Carpeta destino en servidor (NUEVO) -->
            <TextBlock Grid.Row="1" Text="Carpeta destino en servidor:" FontWeight="SemiBold" Margin="0,0,0,6"/>
            <Grid Grid.Row="2" Margin="0,0,0,10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBox Grid.Column="0" Name="txtServerBackupFolder" Style="{StaticResource TextBoxStyle}" IsReadOnly="True"/>
              <Button Name="btnBrowseServerBackupFolder" Grid.Column="1" Content="🗂️ Servidor" Style="{StaticResource SecondaryButtonStyle}" Width="120" Margin="10,0,0,0" ToolTip="Explorar carpetas en el servidor SQL"/>
            </Grid>

            <CheckBox x:Name="chkRespaldo" Grid.Row="3" Style="{StaticResource CheckBoxStyle}" IsChecked="True" IsEnabled="False">
              <TextBlock Text="Respaldar" FontWeight="SemiBold"/>
            </CheckBox>
            <TextBlock Grid.Row="4" Text="Nombre del respaldo:" Margin="0,2,0,6"/>
            <TextBox x:Name="txtNombre" Grid.Row="5" Style="{StaticResource TextBoxStyle}" />

            <Grid Grid.Row="6" Margin="0,10,0,0">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <CheckBox x:Name="chkComprimir" Grid.Row="0" Style="{StaticResource CheckBoxStyle}">
                <TextBlock Text="Comprimir (requiere Chocolatey + 7-Zip)" FontWeight="SemiBold"/>
              </CheckBox>
              <TextBlock x:Name="lblPassword" Grid.Row="1" Text="Contraseña (opcional) para ZIP:" Margin="0,2,0,6"/>
              <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <PasswordBox x:Name="txtPassword" Grid.Column="0" Style="{StaticResource PasswordBoxStyle}"/>
                <Button x:Name="btnTogglePassword" Grid.Column="1" Content="👁" Width="34" Height="34" Margin="8,0,0,0" Style="{StaticResource SecondaryButtonStyle}"/>
              </Grid>
              <CheckBox x:Name="chkSubir" Grid.Row="3" Style="{StaticResource CheckBoxStyle}" Margin="0,10,0,0" IsEnabled="False" IsChecked="False">
                <TextBlock Text="Subir a Mega.nz (opción deshabilitada)" FontWeight="SemiBold"/>
              </CheckBox>
            </Grid>
          </Grid>
        </Border>
        <Border Grid.Row="1"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="12"
                Margin="0,0,0,10">
          <StackPanel>
            <TextBlock Text="Progreso" Style="{StaticResource CardTitleStyle}"/>
            <ProgressBar x:Name="pbBackup" Height="20" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock x:Name="txtProgress" Text="Esperando..." Margin="0,8,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <Border Grid.Row="2"
                Background="{DynamicResource ControlBg}"
                BorderBrush="{DynamicResource BorderBrushColor}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="12">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="Log" Style="{StaticResource CardTitleStyle}"/>
            <TextBox x:Name="txtLog" Grid.Row="1"
                     IsReadOnly="True"
                     VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Auto"
                     TextWrapping="NoWrap"
                     Background="{DynamicResource PanelBg}"
                     Foreground="{DynamicResource PanelFg}"
                     BorderBrush="{DynamicResource BorderBrushColor}"
                     BorderThickness="1"
                     Padding="10"/>
          </Grid>
        </Border>
      </Grid>
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0"
                   Text="Enter: Iniciar   |   Esc: Cerrar"
                   Foreground="{DynamicResource AccentMuted}"
                   VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="btnAbrirCarpeta"
                  Content="Abrir Carpeta"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="130"
                  Margin="0,0,10,0"/>
          <Button x:Name="btnCerrar"
                  Content="Cerrar"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="110"
                  Margin="0,0,10,0"
                  IsCancel="True"/>
          <Button x:Name="btnAceptar"
                  Content="Iniciar Respaldo"
                  Style="{StaticResource PrimaryButtonStyle}"
                  Width="160"
                  IsDefault="True"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
  $ui = New-WpfWindow -Xaml $xaml -PassThru
  $window = $ui.Window
  $c = $ui.Controls
  function Get-Ctrl([string]$name) {
    try {
      if ($null -ne $c -and $c.ContainsKey($name) -and $null -ne $c[$name]) { return $c[$name] }
    } catch {}
    try { return $window.FindName($name) } catch { return $null }
  }
  $theme = Get-DzUiTheme
  Set-DzWpfThemeResources -Window $window -Theme $theme
  try { Set-WpfDialogOwner -Dialog $window } catch {}
  try { if (-not $window.Owner -and $global:MainWindow -is [System.Windows.Window]) { $window.Owner = $global:MainWindow } } catch {}
  $chkRespaldo = Get-Ctrl "chkRespaldo"
  $txtNombre = Get-Ctrl "txtNombre"
  $txtServerBackupFolder = Get-Ctrl "txtServerBackupFolder"
  $btnBrowseServerBackupFolder = Get-Ctrl "btnBrowseServerBackupFolder"
  $chkComprimir = Get-Ctrl "chkComprimir"
  $txtPassword = Get-Ctrl "txtPassword"
  $lblPassword = Get-Ctrl "lblPassword"
  $chkSubir = Get-Ctrl "chkSubir"
  $pbBackup = Get-Ctrl "pbBackup"
  $txtProgress = Get-Ctrl "txtProgress"
  $txtLog = Get-Ctrl "txtLog"
  $btnAceptar = Get-Ctrl "btnAceptar"
  $btnAbrirCarpeta = Get-Ctrl "btnAbrirCarpeta"
  $btnCerrar = Get-Ctrl "btnCerrar"
  $btnTogglePassword = Get-Ctrl "btnTogglePassword"
  $headerBar = Get-Ctrl "HeaderBar"
  $btnClose = Get-Ctrl "btnClose"
  if ($txtServerBackupFolder) {
    $txtServerBackupFolder.Text = $defaultBackupPath
    Write-DzDebug "`t[DEBUG][Show-BackupDialog] Carpeta por omisión establecida: $defaultBackupPath"
  }

  Write-DzDebug "`t[DEBUG][Show-BackupDialog] Controles: chkRespaldo=$([bool]$chkRespaldo) txtNombre=$([bool]$txtNombre) chkComprimir=$([bool]$chkComprimir) txtPassword=$([bool]$txtPassword) lblPassword=$([bool]$lblPassword) chkSubir=$([bool]$chkSubir) pbBackup=$([bool]$pbBackup) txtProgress=$([bool]$txtProgress) txtLog=$([bool]$txtLog) btnAceptar=$([bool]$btnAceptar) btnAbrirCarpeta=$([bool]$btnAbrirCarpeta) btnCerrar=$([bool]$btnCerrar) btnTogglePassword=$([bool]$btnTogglePassword)"
  $window.WindowStartupLocation = "Manual"
  $window.Add_Loaded({
      try {
        $owner = $window.Owner
        if (-not $owner) { $window.WindowStartupLocation = "CenterScreen"; return }
        $ob = $owner.RestoreBounds
        $targetW = $window.ActualWidth; if ($targetW -le 0) { $targetW = $window.Width }
        $targetH = $window.ActualHeight; if ($targetH -le 0) { $targetH = $window.Height }
        $left = $ob.Left + (($ob.Width - $targetW) / 2)
        $top = $ob.Top + (($ob.Height - $targetH) / 2)
        $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
        $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
        $wa = $screen.WorkingArea
        if ($left -lt $wa.Left) { $left = $wa.Left }
        if ($top -lt $wa.Top) { $top = $wa.Top }
        if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
        if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
        $window.Left = [double]$left
        $window.Top = [double]$top
      } catch {}
    }.GetNewClosure())

  if ($headerBar) {
    $headerBar.Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $window.DragMove() } catch {}
        }
      })
  } else {
    Write-DzDebug "`t[DEBUG][Show-BackupDialog] HeaderBar=NULL (no se pudo enganchar DragMove)"
  }
  if ($btnClose) {
    $btnClose.Add_Click({
        try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
        try { if ($timer -and $timer.IsEnabled) { $timer.Stop() } } catch {}
        try { if ($stopwatch) { $stopwatch.Stop() } } catch {}
        Safe-CloseWindow -Window $window -Result $false
      })
  }

  $btnCerrar.Add_Click({
      try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
      try { if ($timer -and $timer.IsEnabled) { $timer.Stop() } } catch {}
      try { if ($stopwatch) { $stopwatch.Stop() } } catch {}
      Safe-CloseWindow -Window $window -Result $false
    })

  $window.Add_PreviewKeyDown({
      param($sender, $e)
      if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch {}
        try { if ($timer -and $timer.IsEnabled) { $timer.Stop() } } catch {}
        try { if ($stopwatch) { $stopwatch.Stop() } } catch {}
        Safe-CloseWindow -Window $window -Result $false
      }
    })
  if (-not $txtNombre -or -not $txtServerBackupFolder -or -not $btnBrowseServerBackupFolder -or -not $chkComprimir -or -not $txtPassword -or -not $lblPassword -or -not $chkSubir -or -not $pbBackup -or -not $txtProgress -or -not $txtLog -or -not $btnAceptar -or -not $btnAbrirCarpeta -or -not $btnCerrar) {
    Write-DzDebug "`t[DEBUG][Show-BackupDialog] ERROR: uno o más controles son NULL. Cerrando..."
    throw "Controles WPF incompletos (FindName devolvió NULL)."
  }

  $timestampsDefault = Get-Date -Format 'yyyyMMdd-HHmmss'
  $txtNombre.Text = ("$Database-$timestampsDefault.bak")
  $txtPassword.IsEnabled = $false
  $lblPassword.IsEnabled = $false
  $chkSubir.IsEnabled = $false
  $chkSubir.IsChecked = $false

  $logQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $progressQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[hashtable]'
  $script:DonePopupShown = $false
  $script:LastDoneStatus = $null
  function Paint-Progress { param([int]$Percent, [string]$Message) $pbBackup.Value = $Percent; $txtProgress.Text = $Message }
  function Add-Log { param([string]$Message) $logQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)) }
  function Disable-CompressionUI { $chkComprimir.IsChecked = $false; $txtPassword.IsEnabled = $false; $lblPassword.IsEnabled = $false; $txtPassword.Password = "" }
  function New-SafeCredential { param([string]$Username, [string]$PlainPassword) $secure = New-Object System.Security.SecureString; foreach ($ch in $PlainPassword.ToCharArray()) { $secure.AppendChar($ch) }; $secure.MakeReadOnly(); New-Object System.Management.Automation.PSCredential($Username, $secure) }
  function Start-BackupWorkAsync {
    param(
      [string]$Server,
      [string]$Database,
      [string]$BackupQuery,
      [string]$ScriptBackupPath,
      [bool]$DoCompress,
      [string]$ZipPassword,
      [System.Management.Automation.PSCredential]$Credential,
      [System.Collections.Concurrent.ConcurrentQueue[string]]$LogQueue,
      [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue
    )
    Write-DzDebug "`t[DEBUG][Start-BackupWorkAsync] Preparando runspace..."
    $worker = {
      param($Server, $Database, $BackupQuery, $ScriptBackupPath, $DoCompress, $ZipPassword, $Credential, $LogQueue, $ProgressQueue)
      function EnqLog([string]$m) { $LogQueue.Enqueue(("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m)) }
      function EnqProg([int]$p, [string]$m) { $ProgressQueue.Enqueue(@{Percent = $p; Message = $m }) }
      function Invoke-SqlQueryLite {
        param([string]$Server, [string]$Database, [string]$Query, [System.Management.Automation.PSCredential]$Credential, [scriptblock]$InfoMessageCallback)
        $connection = $null
        $passwordBstr = [IntPtr]::Zero
        $plainPassword = $null
        try {
          $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
          $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($passwordBstr)
          $cs = "Server=$Server;Database=$Database;User Id=$($Credential.UserName);Password=$plainPassword;MultipleActiveResultSets=True"
          $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
          if ($InfoMessageCallback) { $connection.add_InfoMessage({ param($sender, $e) try { & $InfoMessageCallback $e.Message } catch { } }); $connection.FireInfoMessageEventOnUserErrors = $true }
          $connection.Open()
          $cmd = $connection.CreateCommand()
          $cmd.CommandText = $Query
          $cmd.CommandTimeout = 0
          [void]$cmd.ExecuteNonQuery()
          @{ Success = $true }
        } catch { @{ Success = $false; ErrorMessage = $_.Exception.Message } } finally {
          if ($plainPassword) { $plainPassword = $null }
          if ($passwordBstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr) }
          if ($connection) { try { $connection.Close() } catch { } ; try { $connection.Dispose() } catch { } }
        }
      }
      function Get-7ZipPath {
        $c = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
        foreach ($p in $c) { if (Test-Path $p) { return $p } }
        $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $null
      }
      try {
        EnqLog "Enviando comando a SQL Server..."
        EnqProg 10 "Iniciando backup..."
        $progressCb = {
          param([string]$Message)
          $m = ($Message -replace '\s+', ' ').Trim()
          if ($m) { EnqLog ("[SQL] {0}" -f $m) }
          $backupMax = 100
          if ($DoCompress) { $backupMax = 90 }
          if ($Message -match '(?i)\b(\d{1,3})\s*(percent|porcentaje|por\s+ciento)\b') {
            $p = [int]$Matches[1]
            if ($p -gt 100) { $p = 100 }
            if ($p -lt 0) { $p = 0 }
            $scaled = [int][math]::Floor(($p * $backupMax) / 100)
            if ($DoCompress -and $scaled -ge 100) { $scaled = 90 }
            EnqProg $scaled ("Progreso backup: {0}%" -f $p)
            EnqLog ("Progreso backup: {0}%" -f $p)
            return
          }
          if ($Message -match '(?i)\b(successfully processed|procesad[oa]\s+correctamente|completad[oa])\b') {
            if ($DoCompress) { EnqProg 90 "Backup listo. Iniciando compresión..." } else { EnqProg 100 "¡Backup completado!" }
            EnqLog "✅ Backup completado (mensaje SQL)"
            return
          }
        }
        $r = Invoke-SqlQueryLite -Server $Server -Database "master" -Query $BackupQuery -Credential $Credential -InfoMessageCallback $progressCb
        if (-not $r.Success) { EnqProg 0 "Error en backup"; EnqLog ("❌ Error de SQL: {0}" -f $r.ErrorMessage); EnqLog "__DONE_ERR__"; return }
        if ($DoCompress) { EnqProg 90 "Backup terminado. Iniciando compresión..." } else { EnqProg 100 "Backup terminado." }
        EnqLog "✅ Comando BACKUP finalizó (ExecuteNonQuery)"
        Start-Sleep -Milliseconds 500
        $canSeeFile = $false
        try { $canSeeFile = Test-Path $ScriptBackupPath } catch { $canSeeFile = $false }
        if ($canSeeFile) {
          $sizeMB = [math]::Round((Get-Item $ScriptBackupPath).Length / 1MB, 2)
          EnqLog ("📊 Tamaño del archivo: {0} MB" -f $sizeMB)
          EnqLog ("📁 Ubicación: {0}" -f $ScriptBackupPath)
        } else {
          EnqLog ("⚠️ No se encontró el archivo en: {0}" -f $ScriptBackupPath)
          EnqLog ("ℹ️ Nota: Si es servidor remoto, puede ser permisos/UNC. El backup pudo haberse generado en el servidor.")
        }
        if ($DoCompress) {
          EnqProg 90 "Backup listo. Preparando compresión..."
          EnqLog "🗜️ Iniciando compresión ZIP..."
          $inputBak = $ScriptBackupPath
          $zipPath = "$ScriptBackupPath.zip"
          if (-not (Test-Path $inputBak)) { EnqProg 0 "Error: no existe BAK"; EnqLog ("⚠️ No existe el BAK accesible: {0}" -f $inputBak); EnqLog "__DONE_ERR__"; return }
          $sevenZip = Get-7ZipPath
          if (-not $sevenZip -or -not (Test-Path $sevenZip)) { EnqProg 0 "Error: no se encontró 7-Zip"; EnqLog "❌ No se encontró 7z.exe. No se puede comprimir."; EnqLog "__DONE_ERR__"; return }
          try {
            if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
            EnqProg 92 "Comprimiendo (ZIP)..."
            if ($ZipPassword -and $ZipPassword.Trim().Length -gt 0) { & $sevenZip a -tzip -p"$($ZipPassword.Trim())" -mem=AES256 $zipPath $inputBak | Out-Null } else { & $sevenZip a -tzip $zipPath $inputBak | Out-Null }
            EnqProg 97 "Finalizando compresión..."
            Start-Sleep -Milliseconds 300
            if (Test-Path $zipPath) { $zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2); EnqProg 99 "ZIP creado. Cerrando..."; EnqLog ("✅ ZIP creado ({0} MB): {1}" -f $zipMB, $zipPath) } else { EnqProg 0 "Error: ZIP no generado"; EnqLog ("❌ Se ejecutó 7-Zip pero NO se generó el ZIP: {0}" -f $zipPath) }
          } catch { EnqProg 0 "Error al comprimir"; EnqLog ("❌ Error al comprimir: {0}" -f $_.Exception.Message) }
        }
        if ($DoCompress) {
          EnqLog "__DONE_OK__"
        } else {
          if ($canSeeFile) { EnqLog "__DONE_OK__" } else { EnqLog "__DONE_WARN__" }
        }

      } catch {
        EnqProg 0 "Error"
        EnqLog ("❌ Error inesperado (worker): {0}" -f $_.Exception.Message)
        EnqLog "__DONE_ERR__"
      }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($worker).AddArgument($Server).AddArgument($Database).AddArgument($BackupQuery).AddArgument($ScriptBackupPath).AddArgument($DoCompress).AddArgument($ZipPassword).AddArgument($Credential).AddArgument($LogQueue).AddArgument($ProgressQueue)
    $null = $ps.BeginInvoke()
    Write-DzDebug "`t[DEBUG][Start-BackupWorkAsync] Worker lanzado"
  }
  $stopwatch = $null
  $timer = $null
  $logTimer = [System.Windows.Threading.DispatcherTimer]::new()
  $logTimer.Interval = [TimeSpan]::FromMilliseconds(200)
  $script:LogMaxChars = 60000
  $logTimer.Add_Tick({
      try {
        $count = 0
        $doneThisTick = $false
        $prependBuffer = New-Object System.Text.StringBuilder
        while ($count -lt 50) {
          $line = $null
          if (-not $logQueue.TryDequeue([ref]$line)) { break }
          [void]$prependBuffer.AppendLine($line)
          if ($line -like "*__DONE_OK__*" -or $line -like "*__DONE_WARN__*" -or $line -like "*__DONE_ERR__*") {
            if ($line -like "*__DONE_OK__*") { $script:LastDoneStatus = "OK" }
            elseif ($line -like "*__DONE_WARN__*") { $script:LastDoneStatus = "WARN" }
            else { $script:LastDoneStatus = "ERR" }
            $doneThisTick = $true
            Write-DzDebug "`t[DEBUG][UI] Señal DONE recibida: $script:LastDoneStatus"
            $script:BackupRunning = $false
            $btnAceptar.IsEnabled = $true
            $btnAceptar.Content = "Iniciar Respaldo"
            $txtNombre.IsEnabled = $true
            $chkComprimir.IsEnabled = $true
            if ($chkComprimir.IsChecked -eq $true) { $txtPassword.IsEnabled = $true }
            $btnAbrirCarpeta.IsEnabled = $true
            $tmp = $null
            while ($progressQueue.TryDequeue([ref]$tmp)) { }
            if ($script:LastDoneStatus -eq "ERR") {
              Paint-Progress -Percent 0 -Message "Error"
            } else {
              Paint-Progress -Percent 100 -Message "Completado"
            }
            $script:BackupDone = $true
            if (-not $script:DonePopupShown) {
              $script:DonePopupShown = $true
              if ($script:LastDoneStatus -eq "OK") {
                Ui-Info "Respaldo finalizado." "Información" $window
              } elseif ($script:LastDoneStatus -eq "WARN") {
                Ui-Warn "Respaldo finalizado.`n`nTen en cuenta que a veces marca error de lectura porque es en un servidor (permisos/UNC). El backup pudo haberse generado en el servidor." "Atención" $window
              } else {
                Ui-Error "Ocurrió un error durante el respaldo. Revisa el log." "Error" $window
              }
            }
          }
          $count++
        }
        if ($count -gt 0) {
          $newText = $prependBuffer.ToString()
          if ($newText.Length -gt 0) {
            $txtLog.Text = $newText + $txtLog.Text
            if ($txtLog.Text.Length -gt $script:LogMaxChars) {
              $txtLog.Text = $txtLog.Text.Substring(0, $script:LogMaxChars)
            }
            $txtLog.ScrollToLine(0)  # siempre arriba
          }
        }

        if (-not $doneThisTick) {
          $last = $null
          while ($true) {
            $p = $null
            if (-not $progressQueue.TryDequeue([ref]$p)) { break }
            $last = $p
          }
          if ($last) { Paint-Progress -Percent $last.Percent -Message $last.Message }
        }
      } catch { Write-DzDebug "`t[DEBUG][UI][logTimer] ERROR: $($_.Exception.Message)" }
      if ($script:BackupDone) {
        $tmpLine = $null
        $tmpProg = $null
        if (-not $logQueue.TryPeek([ref]$tmpLine) -and -not $progressQueue.TryPeek([ref]$tmpProg)) { $logTimer.Stop(); $script:BackupDone = $false }
      }
    })
  $logTimer.Start()
  Write-DzDebug "`t[DEBUG][Show-BackupDialog] logTimer iniciado"
  $chkComprimir.Add_Checked({
      Write-DzDebug "`t[DEBUG][UI] chkComprimir CHECKED"
      try {
        if (-not (Test-ChocolateyInstalled)) {
          $msg = @"
Chocolatey es necesario SOLAMENTE si deseas:
✓ Comprimir el respaldo (ZIP con contraseña)
Si solo necesitas crear el respaldo básico (.BAK), NO es necesario instalarlo.
¿Deseas instalar Chocolatey ahora?
"@
          $wantChoco = Ui-Confirm $msg "Chocolatey requerido" $window
          if (-not $wantChoco) { Ui-Warn "Compresión deshabilitada (Chocolatey no instalado)." "Atención" $window; Disable-CompressionUI; return }
          $okChoco = Install-Chocolatey
          if (-not $okChoco -or -not (Test-ChocolateyInstalled)) { Ui-Warn "No se pudo instalar Chocolatey. Compresión deshabilitada." "Atención" $window; Disable-CompressionUI; return }
        }
        if (-not (Test-7ZipInstalled)) {
          $want7z = Ui-Confirm "Para comprimir se requiere 7-Zip. ¿Deseas instalarlo ahora con Chocolatey?" "7-Zip requerido" $window
          if (-not $want7z) { Ui-Warn "Compresión deshabilitada (7-Zip no instalado)." "Atención" $window; Disable-CompressionUI; return }
          $ok7z = Install-7ZipWithChoco
          if (-not $ok7z) { Ui-Warn "No se pudo instalar 7-Zip. Compresión deshabilitada." "Atención" $window; Disable-CompressionUI; return }
        }
        $txtPassword.IsEnabled = $true
        $lblPassword.IsEnabled = $true
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error chkComprimir CHECKED: $($_.Exception.Message)"
        Ui-Error "Error validando requisitos de compresión: $($_.Exception.Message)" "Error" $window
        Disable-CompressionUI
      }
    })
  $credential = New-SafeCredential -Username $User -PlainPassword $Password
  $btnBrowseServerBackupFolder.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnBrowseServerBackupFolder Click"
      try {
        if (Get-Command Show-ServerFolderBrowser -ErrorAction SilentlyContinue) {
          $selected = Show-ServerFolderBrowser -Server $Server -Credential $credential -StartPath $txtServerBackupFolder.Text

          if ($selected) {
            $txtServerBackupFolder.Text = $selected
            Add-Log "📁 Carpeta de respaldo cambiada a: $selected"
            Write-DzDebug "`t[DEBUG][UI] Nueva carpeta seleccionada: $selected"
          }
        } else {
          Ui-Warn "La función 'Show-ServerFolderBrowser' no está disponible en este build.`n`nPuedes escribir la ruta manualmente (es ruta del SERVIDOR SQL).`nEjemplo: C:\Temp\SQLBackups" "Explorador no disponible" $window
        }
      } catch {
        Write-DzDebug "`t[DEBUG][UI] Error en btnBrowseServerBackupFolder: $($_.Exception.Message)"
        Ui-Error "Error al abrir explorador de carpetas en servidor: $($_.Exception.Message)" "Error" $window
      }
    })
  $chkComprimir.Add_Unchecked({ Write-DzDebug "`t[DEBUG][UI] chkComprimir UNCHECKED"; Disable-CompressionUI })
  $btnAceptar.Add_Click({
      if ($script:BackupRunning) { return }
      $script:DonePopupShown = $false
      $script:LastDoneStatus = $null
      $script:BackupDone = $false
      if ($script:BackupRunning) { return }
      $script:BackupDone = $false
      if (-not $logTimer.IsEnabled) { $logTimer.Start() }
      if (-not $logTimer.IsEnabled) { $logTimer.Start() }
      try {
        $btnAceptar.IsEnabled = $false
        $btnAceptar.Content = "Procesando..."
        if ([string]::IsNullOrWhiteSpace($txtLog.Text)) {
          # no hace nada
        } else {
          # opción 1: conservar siempre (recomendado)
          Add-Log "— Iniciando nuevo respaldo (se conserva el log anterior) —"
          $txtLog.AppendText("`r`n— Iniciando nuevo respaldo —`r`n")
        }
        $pbBackup.Value = 0
        $txtProgress.Text = "Esperando..."
        Add-Log "Iniciando proceso de backup..."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Start()
        Write-DzDebug "`t[DEBUG][UI] Timer iniciado OK"
        $machinePart = $Server.Split('\')[0]
        $machineName = $machinePart.Split(',')[0]
        if ($machineName -eq '.') { $machineName = $env:COMPUTERNAME }
        $sameHost = ($env:COMPUTERNAME -ieq $machineName)
        $backupFileName = $txtNombre.Text
        $sqlBackupFolder = $txtServerBackupFolder.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($sqlBackupFolder)) {
          $sqlBackupFolder = $defaultBackupPath
          $txtServerBackupFolder.Text = $defaultBackupPath
        }
        $sqlBackupPath = Join-Path $sqlBackupFolder $backupFileName
        if ($sameHost) {
          $scriptBackupPath = $sqlBackupPath
        } else {
          $folderPart = $sqlBackupFolder -replace '^[A-Za-z]:', ''  # Quitar la letra de unidad
          $scriptBackupPath = "\\$machineName\$($sqlBackupFolder[0])$`$$folderPart\$backupFileName"
        }
        Add-Log "Servidor: $Server"
        Add-Log "Base de datos: $Database"
        Add-Log "Usuario: $User"
        Add-Log "Carpeta de respaldo: $sqlBackupFolder"
        Add-Log "Ruta SQL (donde escribe el motor): $sqlBackupPath"
        Add-Log "Ruta accesible desde esta PC: $scriptBackupPath"
        if (-not $backupFileName.ToLower().EndsWith(".bak")) { $backupFileName = "$backupFileName.bak"; $txtNombre.Text = $backupFileName }
        $invalid = [System.IO.Path]::GetInvalidFileNameChars()
        if ($backupFileName.IndexOfAny($invalid) -ge 0) { Show-WarnDialog -Message "El nombre contiene caracteres no válidos..." -Title "Nombre inválido" -Owner $window; Reset-BackupUI -ProgressText "Nombre inválido"; return }
        $scriptBackupExists = $false
        try {
          $scriptBackupExists = Test-Path $scriptBackupPath -ErrorAction Stop
        } catch {
          Write-DzDebug "`t[DEBUG][UI] No se pudo validar la ruta de respaldo: $scriptBackupPath. $($_.Exception.Message)"
        }
        if ($scriptBackupExists) {
          $choice = Ui-Confirm "Ya existe un respaldo con ese nombre en:`n$scriptBackupPath`n`n¿Deseas sobrescribirlo?" "Archivo existente" $window
          if (-not $choice) { $timestampsDefault = Get-Date -Format 'yyyyMMdd-HHmmss'; $txtNombre.Text = "$Database-$timestampsDefault.bak"; Add-Log "⚠️ Operación cancelada: el archivo ya existe. Se sugirió un nuevo nombre."; Reset-BackupUI -ProgressText "Cancelado (elige otro nombre y vuelve a intentar)"; return }
        }
        if ($sameHost) {
          if (-not (Test-Path $sqlBackupFolder)) {
            New-Item -ItemType Directory -Path $sqlBackupFolder -Force | Out-Null
            Add-Log "✓ Carpeta creada: $sqlBackupFolder"
          }
        } else {
          $uncFolder = "\\$machineName\$($sqlBackupFolder[0])$`$" + ($sqlBackupFolder -replace '^[A-Za-z]:', '')
          try {
            if (-not (Test-Path $uncFolder -ErrorAction Stop)) {
              Add-Log "⚠️ No pude validar la carpeta UNC: $uncFolder (puede ser permisos). SQL intentará escribir en $sqlBackupFolder en el servidor."
            }
          } catch {
            Write-DzDebug "`t[DEBUG][UI] No se pudo validar la carpeta UNC: $uncFolder. $($_.Exception.Message)"
            Add-Log "⚠️ No pude validar la carpeta UNC: $uncFolder (puede ser permisos). SQL intentará escribir en $sqlBackupFolder en el servidor."
          }
        }
        Add-Log "✓ Credenciales listas"
        $backupQuery = @"
BACKUP DATABASE [$Database]
TO DISK = '$sqlBackupPath'
WITH CHECKSUM, STATS = 1, FORMAT, INIT
"@
        Paint-Progress -Percent 5 -Message "Conectando a SQL Server..."
        Write-DzDebug "`t[DEBUG][UI] Llamando Start-BackupWorkAsync"
        Start-BackupWorkAsync -Server $Server -Database $Database -BackupQuery $backupQuery -ScriptBackupPath $scriptBackupPath -DoCompress ($chkComprimir.IsChecked -eq $true) -ZipPassword $txtPassword.Password -Credential $credential -LogQueue $logQueue -ProgressQueue $progressQueue
      } catch {
        Write-DzDebug "`t[DEBUG][UI] ERROR btnAceptar: $($_.Exception.Message)"
        Add-Log "❌ Error: $($_.Exception.Message)"
        $btnAceptar.IsEnabled = $true
        $btnAceptar.Content = "Iniciar Respaldo"
        if ($timer -and $timer.IsEnabled) { $timer.Stop() }
        if ($stopwatch) { $stopwatch.Stop() }
      }
    })
  $btnAbrirCarpeta.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnAbrirCarpeta Click"
      $machinePart = $Server.Split('\')[0]
      $machineName = $machinePart.Split(',')[0]
      if ($machineName -eq '.') { $machineName = $env:COMPUTERNAME }
      $sqlBackupFolder = $txtServerBackupFolder.Text.Trim()
      if ([string]::IsNullOrWhiteSpace($sqlBackupFolder)) {
        $sqlBackupFolder = $defaultBackupPath
      }
      $folderPart = $sqlBackupFolder -replace '^[A-Za-z]:', ''
      $backupFolder = "\\$machineName\$($sqlBackupFolder[0])$`$$folderPart"
      if (Test-Path $backupFolder) {
        Start-Process explorer.exe $backupFolder
      } else {
        Ui-Warn "La carpeta de respaldos no existe o no es accesible.`n`nRuta: $backupFolder" "Atención" $window
      }
    })
  $btnCerrar.Add_Click({
      Write-DzDebug "`t[DEBUG][UI] btnCerrar Click"
      try { if ($logTimer -and $logTimer.IsEnabled) { $logTimer.Stop() } } catch { }
      try { if ($timer -and $timer.IsEnabled) { $timer.Stop() } } catch { }
      try { if ($stopwatch) { $stopwatch.Stop() } } catch { }
      Safe-CloseWindow -Window $window -Result $false
    })
  Write-DzDebug "`t[DEBUG][Show-BackupDialog] Antes de ShowDialog()"
  $null = $window.ShowDialog()
  Write-DzDebug "`t[DEBUG][Show-BackupDialog] Después de ShowDialog()"
}
function Reset-BackupUI {
  param([string]$ButtonText = "Iniciar Respaldo", [string]$ProgressText = "Esperando...")
  $script:BackupRunning = $false
  $btnAceptar.IsEnabled = $true
  $btnAceptar.Content = $ButtonText
  $txtNombre.IsEnabled = $true
  $chkComprimir.IsEnabled = $true
  if ($chkComprimir.IsChecked -eq $true) { $txtPassword.IsEnabled = $true; $lblPassword.IsEnabled = $true } else { $txtPassword.IsEnabled = $false; $lblPassword.IsEnabled = $false }
  $btnAbrirCarpeta.IsEnabled = $true
  $txtProgress.Text = $ProgressText
}
function Show-ServerFolderBrowser {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Server,
    [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$Credential,
    [Parameter(Mandatory)] [string]$StartPath
  )
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName System.Windows.Forms
  function Normalize-Path([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    return $p.Trim().TrimEnd('\')
  }
  $current = Normalize-Path $StartPath
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "C:\" }
  $safeTitle = [Security.SecurityElement]::Escape("Explorar carpetas en servidor SQL")
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$safeTitle"
        Width="650" Height="500"
        MinWidth="650" MinHeight="500"
        MaxWidth="650" MaxHeight="500"
        WindowStartupLocation="Manual"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="False"
        FontFamily="{DynamicResource UiFontFamily}"
        FontSize="{DynamicResource UiFontSize}">
  <Window.Resources>
    <Style TargetType="{x:Type Control}">
      <Setter Property="FontFamily" Value="{DynamicResource UiFontFamily}"/>
      <Setter Property="FontSize" Value="10"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
    </Style>
    <Style x:Key="IconButtonStyle" TargetType="Button">
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentRed}"/>
                <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.92"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource PrimaryButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource PanelBg}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
                <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TextBoxStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>
    <Style x:Key="TreeViewStyle" TargetType="TreeView">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="4"/>
    </Style>
    <Style x:Key="TreeViewItemStyle" TargetType="TreeViewItem">
      <Setter Property="IsExpanded" Value="{Binding IsExpanded, Mode=TwoWay}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="Padding" Value="2"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{DynamicResource AccentPrimary}"/>
          <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <HierarchicalDataTemplate x:Key="FolderTemplate" ItemsSource="{Binding Children}">
      <StackPanel Orientation="Horizontal" Margin="2">
        <TextBlock Text="📁 " Margin="0,0,4,0"/>
        <TextBlock Text="{Binding Name}"/>
      </StackPanel>
    </HierarchicalDataTemplate>
  </Window.Resources>
  <Border Background="{DynamicResource FormBg}"
          BorderBrush="{DynamicResource BorderBrushColor}"
          BorderThickness="1"
          CornerRadius="12"
          Margin="10"
          SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="Black"
                        Direction="270"
                        ShadowDepth="4"
                        BlurRadius="14"
                        Opacity="0.25"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0"
              Name="HeaderBar"
              Background="{DynamicResource FormBg}"
              CornerRadius="12,12,0,0"
              Padding="12,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Grid.Column="0"
                  Width="6"
                  CornerRadius="3"
                  Background="{DynamicResource AccentPrimary}"
                  Margin="0,4,10,4"/>
          <StackPanel Grid.Column="1" Orientation="Vertical">
            <TextBlock Text="$safeTitle"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="10"/>
            <TextBlock Text="Navega por el árbol de carpetas del servidor"
                       Foreground="{DynamicResource AccentMuted}"
                       FontSize="10"
                       Margin="0,2,0,0"/>
          </StackPanel>
          <Button Grid.Column="2"
                  Name="btnClose"
                  Style="{StaticResource IconButtonStyle}"
                  Content="✕"
                  ToolTip="Cerrar"/>
        </Grid>
      </Border>
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,10"
              Margin="12,0,12,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0"
                     Text="Ruta seleccionada:"
                     FontWeight="SemiBold"
                     Margin="0,0,0,8"/>
          <TextBox Grid.Row="1"
                   Name="txtPath"
                   Style="{StaticResource TextBoxStyle}"
                   IsReadOnly="True"
                   VerticalContentAlignment="Center"/>
          <TextBlock Grid.Row="2"
                     Name="lblStatus"
                     Foreground="{DynamicResource AccentMuted}"
                     Margin="0,8,0,0"
                     TextWrapping="Wrap"/>
        </Grid>
      </Border>
      <Border Grid.Row="2"
              Background="{DynamicResource ControlBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="6"
              Margin="12,0,12,10">
        <TreeView Name="tvFolders"
                  Style="{StaticResource TreeViewStyle}"
                  ItemContainerStyle="{StaticResource TreeViewItemStyle}"
                  ItemTemplate="{StaticResource FolderTemplate}"/>
      </Border>
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0"
                   Text="Expande las carpetas con + | Selecciona y presiona Enter"
                   Foreground="{DynamicResource AccentMuted}"
                   VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="btnCancel"
                  Content="Cancelar"
                  Style="{StaticResource SecondaryButtonStyle}"
                  Width="120"
                  Margin="0,0,10,0"
                  IsCancel="True"/>
          <Button Name="btnOk"
                  Content="Aceptar"
                  Style="{StaticResource PrimaryButtonStyle}"
                  Width="140"
                  IsDefault="True"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
  try {
    $ui = New-WpfWindow -Xaml $xaml -PassThru
    $w = $ui.Window
    $c = $ui.Controls
    $theme = Get-DzUiTheme
    Set-DzWpfThemeResources -Window $w -Theme $theme
    try { Set-WpfDialogOwner -Dialog $w } catch {}
    try { if (-not $w.Owner -and $global:MainWindow -is [System.Windows.Window]) { $w.Owner = $global:MainWindow } } catch {}
    $w.WindowStartupLocation = "Manual"
    $w.Add_Loaded({
        try {
          $owner = $w.Owner
          if (-not $owner) { $w.WindowStartupLocation = "CenterScreen"; return }
          $ob = $owner.RestoreBounds
          $targetW = $w.ActualWidth; if ($targetW -le 0) { $targetW = $w.Width }
          $targetH = $w.ActualHeight; if ($targetH -le 0) { $targetH = $w.Height }
          $left = $ob.Left + (($ob.Width - $targetW) / 2)
          $top = $ob.Top + (($ob.Height - $targetH) / 2)
          $hOwner = [System.Windows.Interop.WindowInteropHelper]::new($owner).Handle
          $screen = [System.Windows.Forms.Screen]::FromHandle($hOwner)
          $wa = $screen.WorkingArea
          if ($left -lt $wa.Left) { $left = $wa.Left }
          if ($top -lt $wa.Top) { $top = $wa.Top }
          if (($left + $targetW) -gt $wa.Right) { $left = $wa.Right - $targetW }
          if (($top + $targetH) -gt $wa.Bottom) { $top = $wa.Bottom - $targetH }
          $w.Left = [double]$left
          $w.Top = [double]$top
        } catch {}
      }.GetNewClosure())
    $c['HeaderBar'].Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
          try { $w.DragMove() } catch {}
        }
      })
    $txtPath = $c['txtPath']
    $tvFolders = $c['tvFolders']
    $btnCancel = $c['btnCancel']
    $btnOk = $c['btnOk']
    $btnClose = $c['btnClose']
    $lblStatus = $c['lblStatus']
    $script:resultPath = $null
    Add-Type -TypeDefinition @"
    using System.Collections.ObjectModel;
    using System.ComponentModel;
    public class FolderNode : INotifyPropertyChanged
    {
        private string _name;
        private string _fullPath;
        private ObservableCollection<FolderNode> _children;
        private bool _isExpanded;
        private bool _isLoaded;
        public string Name
        {
            get { return _name; }
            set { _name = value; OnPropertyChanged("Name"); }
        }
        public string FullPath
        {
            get { return _fullPath; }
            set { _fullPath = value; OnPropertyChanged("FullPath"); }
        }
        public ObservableCollection<FolderNode> Children
        {
            get { return _children; }
            set { _children = value; OnPropertyChanged("Children"); }
        }
        public bool IsExpanded
        {
            get { return _isExpanded; }
            set { _isExpanded = value; OnPropertyChanged("IsExpanded"); }
        }
        public bool IsLoaded
        {
            get { return _isLoaded; }
            set { _isLoaded = value; }
        }
        public FolderNode()
        {
            Children = new ObservableCollection<FolderNode>();
        }
        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string propertyName)
        {
            if (PropertyChanged != null)
                PropertyChanged(this, new PropertyChangedEventArgs(propertyName));
        }
    }
"@ -ReferencedAssemblies 'PresentationFramework', 'WindowsBase' -IgnoreWarnings -ErrorAction SilentlyContinue
    function Get-DriveNodes {
      $drives = @()
      foreach ($letter in 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') {
        $drivePath = "${letter}:\"
        try {
          $testQuery = "DECLARE @path nvarchar(512) = N'$drivePath'; DECLARE @exists int; EXEC master.dbo.xp_fileexist @path, @exists OUTPUT; SELECT @exists AS [Exists]"
          $result = Invoke-SqlScalarTable -Server $Server -Database "master" -Query $testQuery -Credential $Credential
          if ($result.Success -and $result.DataTable.Rows.Count -gt 0) {
            $exists = [int]$result.DataTable.Rows[0]["Exists"]
            if ($exists -eq 1) {
              $node = New-Object FolderNode
              $node.Name = "${letter}:\"
              $node.FullPath = $drivePath
              $node.IsLoaded = $false
              $dummy = New-Object FolderNode
              $dummy.Name = "..."
              $node.Children.Add($dummy)
              $drives += $node
            }
          }
        } catch {
          if ($letter -in 'C', 'D', 'E') {
            $node = New-Object FolderNode
            $node.Name = "${letter}:\"
            $node.FullPath = $drivePath
            $node.IsLoaded = $false
            $dummy = New-Object FolderNode
            $dummy.Name = "..."
            $node.Children.Add($dummy)
            $drives += $node
          }
        }
      }
      return $drives
    }
    function Load-ChildFolders {
      param([FolderNode]$Node)
      if ($Node.IsLoaded) { return }
      $lblStatus.Text = "Cargando subcarpetas..."
      try {
        $result = Get-ServerSubDirs -Server $Server -Path $Node.FullPath -Credential $Credential
        $Node.Children.Clear()
        if ($result.Success -and $result.Items.Count -gt 0) {
          foreach ($folderName in $result.Items) {
            $childNode = New-Object FolderNode
            $childNode.Name = $folderName
            $childNode.FullPath = Join-Path $Node.FullPath $folderName
            $childNode.IsLoaded = $false
            $dummy = New-Object FolderNode
            $dummy.Name = "..."
            $childNode.Children.Add($dummy)
            $Node.Children.Add($childNode)
          }
          $lblStatus.Text = "Cargadas $($result.Items.Count) subcarpetas"
        } else {
          $lblStatus.Text = "Sin subcarpetas o sin acceso"
        }
        $Node.IsLoaded = $true
      } catch {
        $lblStatus.Text = "Error cargando subcarpetas: $($_.Exception.Message)"
        Write-DzDebug "`t[DEBUG][Load-ChildFolders] Error: $($_.Exception.Message)"
      }
    }
    $lblStatus.Text = "Detectando unidades disponibles..."
    $rootNodes = Get-DriveNodes
    if ($rootNodes.Count -eq 0) {
      $cNode = New-Object FolderNode
      $cNode.Name = "C:\"
      $cNode.FullPath = "C:\"
      $cNode.IsLoaded = $false
      $dummy = New-Object FolderNode
      $dummy.Name = "..."
      $cNode.Children.Add($dummy)
      $rootNodes = @($cNode)
    }
    $tvFolders.ItemsSource = $rootNodes
    $lblStatus.Text = "Listo. Expande las carpetas para navegar."
    if ($current -match '^([A-Za-z]):\\(.*)') {
      $driveLetter = $Matches[1].ToUpper()
      $pathParts = $Matches[2] -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      $driveNode = $rootNodes | Where-Object { $_.Name -eq "${driveLetter}:\" } | Select-Object -First 1
      if ($driveNode) {
        function Expand-PathRecursively {
          param(
            [Parameter(Mandatory)] [FolderNode]$Node,
            [Parameter(Mandatory)] [string[]]$Parts,
            [Parameter(Mandatory)] $ParentContainer,
            [int]$Index = 0
          )

          if (-not $Node.IsLoaded) { Load-ChildFolders -Node $Node }

          $Node.IsExpanded = $true
          $txtPath.Text = $Node.FullPath

          $w.Dispatcher.Invoke([Action] {
              $tvFolders.UpdateLayout()
            }, [System.Windows.Threading.DispatcherPriority]::Render)

          $thisContainer = Get-ContainerFromParent -Parent $ParentContainer -Item $Node
          if ($thisContainer) {
            $thisContainer.IsExpanded = $true
            $thisContainer.BringIntoView()
            $w.Dispatcher.Invoke([Action] {
                $tvFolders.UpdateLayout()
              }, [System.Windows.Threading.DispatcherPriority]::Render)
          }

          if ($Index -lt $Parts.Count) {
            $partName = $Parts[$Index]
            $childNode = $Node.Children | Where-Object { $_.Name -eq $partName } | Select-Object -First 1
            if ($childNode) {
              if ($thisContainer) {
                Expand-PathRecursively -Node $childNode -Parts $Parts -ParentContainer $thisContainer -Index ($Index + 1)
              } else {
                Select-TreeViewNode -Node $Node -ParentContainer $ParentContainer
              }
            } else {
              Write-DzDebug "`t[DEBUG] No se encontró la carpeta: $partName en $($Node.FullPath)"
              Select-TreeViewNode -Node $Node -ParentContainer $ParentContainer
            }
          } else {
            if ($thisContainer) {
              Select-TreeViewNode -Node $Node -ParentContainer $ParentContainer
            } else {
              Select-TreeViewNode -Node $Node -ParentContainer $ParentContainer
            }
          }
        }
        function Get-ContainerFromParent {
          param(
            [Parameter(Mandatory)] $Parent,
            [Parameter(Mandatory)] $Item
          )
          try {
            return $Parent.ItemContainerGenerator.ContainerFromItem($Item)
          } catch {
            return $null
          }
        }

        function Select-TreeViewNode {
          param(
            [Parameter(Mandatory)] [FolderNode]$Node,
            [Parameter(Mandatory)] $ParentContainer
          )
          $w.Dispatcher.Invoke([Action] {
              try {
                $tvFolders.UpdateLayout()
                $container = Get-ContainerFromParent -Parent $ParentContainer -Item $Node
                if (-not $container) {
                  $tvFolders.UpdateLayout()
                  $container = Get-ContainerFromParent -Parent $ParentContainer -Item $Node
                }
                if ($container) {
                  $container.IsSelected = $true
                  $container.BringIntoView()
                  $container.Focus()
                  $txtPath.Text = $Node.FullPath
                  $script:resultPath = $Node.FullPath
                } else {
                  Write-DzDebug "`t[DEBUG] No se pudo obtener el contenedor para: $($Node.FullPath)"
                }
              } catch {
                Write-DzDebug "`t[DEBUG] Error seleccionando nodo: $($_.Exception.Message)"
              }
            }, [System.Windows.Threading.DispatcherPriority]::Loaded)
        }
        $null = $w.Dispatcher.BeginInvoke([Action] {
            try { Expand-PathRecursively -Node $driveNode -Parts $pathParts -ParentContainer $tvFolders -Index 0 } catch {}
          }, [System.Windows.Threading.DispatcherPriority]::Loaded)
      }
    }
    $tvFolders.Add_PreviewMouseDown({
        param($sender, $e)
        try {
          $item = $e.OriginalSource
          while ($item -and $item -isnot [System.Windows.Controls.TreeViewItem]) {
            $item = [System.Windows.Media.VisualTreeHelper]::GetParent($item)
          }
          if ($item -is [System.Windows.Controls.TreeViewItem]) {
            $node = $item.DataContext
            if ($node -and $node -is [FolderNode]) {
              if (-not $node.IsLoaded -and $node.Name -ne "...") {
                Load-ChildFolders -Node $node
              }
            }
          }
        } catch {}
      })
    $tvFolders.Add_SelectedItemChanged({
        try {
          $selected = $tvFolders.SelectedItem
          if ($selected -and $selected -is [FolderNode] -and $selected.Name -ne "...") {
            $txtPath.Text = $selected.FullPath
            $script:resultPath = $selected.FullPath
          }
        } catch {}
      })
    $btnClose.Add_Click({ $script:resultPath = $null; try { $w.Close() } catch {} })
    $btnCancel.Add_Click({ $script:resultPath = $null; try { $w.Close() } catch {} })
    $w.Add_PreviewKeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
          $script:resultPath = $null
          try { $w.Close() } catch {}
        }
      })
    $btnOk.Add_Click({
        try {
          $selected = $tvFolders.SelectedItem
          if ($selected -and $selected -is [FolderNode] -and $selected.Name -ne "...") {
            $script:resultPath = $selected.FullPath
            $w.DialogResult = $true
            $w.Close()
          } else {
            [System.Windows.MessageBox]::Show(
              "Por favor selecciona una carpeta válida",
              "Selección requerida",
              [System.Windows.MessageBoxButton]::OK,
              [System.Windows.MessageBoxImage]::Warning
            )
          }
        } catch {}
      })
    $null = $w.ShowDialog()
    return $script:resultPath
  } catch {
    Write-Error "Error creando diálogo de exploración mejorado: $($_.Exception.Message)"
    return $null
  }
}

Export-ModuleMember -Function @(
  'Show-RestoreDialog',
  'Show-ServerFolderBrowser',
  'Show-AttachDialog',
  'Reset-AttachUI',
  'Show-BackupDialog',
  'Reset-BackupUI',
  'Show-DetachDialog',
  'Reset-DetachUI',
  'Show-DatabaseSizeDialog',
  'Show-DatabaseRepairDialog',
  'Reset-DatabaseRepairUI'
)