#requires -Version 5.0
#SqlTreeView.psm1
function New-SqlTreeNode {
    param(
        [Parameter(Mandatory = $true)][string]$Header,
        [Parameter(Mandatory = $true)][hashtable]$Tag,
        [Parameter(Mandatory = $false)][bool]$HasPlaceholder
    )
    $node = New-Object System.Windows.Controls.TreeViewItem
    $node.Header = $Header
    $node.Tag = $Tag
    if ($HasPlaceholder) {
        $placeholder = New-Object System.Windows.Controls.TreeViewItem
        $placeholder.Header = "Cargando..."
        $placeholder.Tag = @{ Type = "Placeholder" }
        [void]$node.Items.Add($placeholder)
    }
    $node
}
function bdd_RenameFromTree {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $false)][string]$DefaultValue = ""
    )
    $safeTitle = [Security.SecurityElement]::Escape($Title)
    $safePrompt = [Security.SecurityElement]::Escape($Prompt)
    $safeDefault = [Security.SecurityElement]::Escape($DefaultValue)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$safeTitle"
        Width="560" Height="280"
        MinWidth="560" MinHeight="280"
        MaxWidth="560" MaxHeight="280"
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

      <!-- Header draggable -->
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
                       FontSize="12"/>
            <TextBlock Text="Renombrar"
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

      <!-- Hint -->
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Tip: usa un nombre descriptivo y evita caracteres especiales."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"/>
      </Border>

      <!-- Content -->
      <Border Grid.Row="2"
              Background="{DynamicResource ControlBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="12"
              Margin="12,0,12,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <TextBlock Grid.Row="0"
                     Text="$safePrompt"
                     Foreground="{DynamicResource FormFg}"
                     FontWeight="SemiBold"
                     Margin="0,0,0,10"
                     TextWrapping="Wrap"/>

          <TextBox Grid.Row="1"
                   Name="txtInput"
                   Style="{StaticResource TextBoxStyle}"
                   Text="$safeDefault"
                   VerticalContentAlignment="Center"/>
        </Grid>
      </Border>

      <!-- Footer -->
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Column="0"
                   Text="Enter: Aceptar   |   Esc: Cerrar"
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
        $script:renameResult = $null
        $c['btnClose'].Add_Click({
                $script:renameResult = $null
                try { $w.Close() } catch {}
            })
        $txtInput = $c['txtInput']
        $btnOk = $c['btnOk']
        $btnCancel = $c['btnCancel']
        $btnClose = $c['btnClose']
        $script:renameResult = $null
        $c['HeaderBar'].Add_MouseLeftButtonDown({
                if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                    try { $w.DragMove() } catch {}
                }
            })
        $w.Add_Loaded({
                $c['txtInput'].Focus()
                $c['txtInput'].SelectAll()
            })
        $c['btnClose'].Add_Click({
                $script:renameResult = $null
                try { $w.Close() } catch {}
            })
        $c['btnCancel'].Add_Click({
                $script:renameResult = $null
                try { $w.Close() } catch {}
            })
        $w.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                    $script:renameResult = $null
                    try { $w.Close() } catch {}
                }
            })
        $c['btnOk'].Add_Click({
                $script:renameResult = $c['txtInput'].Text
                try { $w.DialogResult = $true } catch {}
                try { $w.Close() } catch {}
            })
        $null = $w.ShowDialog()
        return $script:renameResult
        if ($result -eq $true) { return $script:renameResult }
        return $null
    } catch {
        Write-Error "Error creando diálogo de renombrar: $($_.Exception.Message)"
        return $null
    }
}
function Initialize-SqlTreeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TreeView,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $false)][string]$User,
        [Parameter(Mandatory = $false)][string]$Password,
        [Parameter(Mandatory = $false)][scriptblock]$InsertTextHandler,
        [Parameter(Mandatory = $false)][scriptblock]$OnDatabaseSelected,
        [Parameter(Mandatory = $false)][scriptblock]$GetCurrentDatabase,
        [Parameter(Mandatory = $false)][bool]$AutoExpand = $true,
        [Parameter(Mandatory = $false)][scriptblock]$OnDatabasesRefreshed
    )
    $TreeView.Items.Clear()
    $serverTag = @{
        Type                 = "Server"
        Server               = $Server
        Credential           = $Credential
        User                 = $User
        Password             = $Password
        InsertTextHandler    = $InsertTextHandler
        OnDatabaseSelected   = $OnDatabaseSelected
        GetCurrentDatabase   = $GetCurrentDatabase
        OnDatabasesRefreshed = $OnDatabasesRefreshed
        Loaded               = $false
    }
    $serverNode = New-SqlTreeNode -Header "📊 $Server" -Tag $serverTag -HasPlaceholder $true
    Add-ServerContextMenu -ServerNode $serverNode
    $serverNode.Add_Expanded({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG][TreeView] Expand Server: $($sender.Tag.Server) Loaded=$($sender.Tag.Loaded)"
            if (-not $sender.Tag.Loaded) {
                $sender.Tag.Loaded = $true
                Load-DatabasesIntoTree -ServerNode $sender
            }
        })
    [void]$TreeView.Items.Add($serverNode)
    if (-not $TreeView.Tag -or -not $TreeView.Tag.TreeViewKeyHandlerAdded) {
        $TreeView.Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq 'F5') {
                    $selected = $sender.SelectedItem
                    if (-not $selected -or -not $selected.Tag -or $selected.Tag.Type -ne 'Server') { return }
                    Write-DzDebug "`t[DEBUG][TreeView] F5 Refresh Server: $($selected.Tag.Server)"
                    Refresh-SqlTreeServerNode -ServerNode $selected
                    $e.Handled = $true
                    return
                }
                if ($e.Key -eq 'F2') {
                    $selected = $sender.SelectedItem
                    if (-not $selected -or -not $selected.Tag -or $selected.Tag.Type -ne 'Database') { return }
                    Write-DzDebug "`t[DEBUG][TreeView] F2 Rename Database: $($selected.Tag.Database)"
                    $dbName = [string]$selected.Tag.Database
                    $server = [string]$selected.Tag.Server
                    $credential = $selected.Tag.Credential
                    $newName = bdd_RenameFromTree -Title "Renombrar base de datos" `
                        -Prompt "Nuevo nombre para la base de datos:" `
                        -DefaultValue $dbName
                    if ($null -eq $newName) {
                        Write-DzDebug "`t[DEBUG][TreeView] Rename cancelado"
                        $e.Handled = $true
                        return
                    }
                    $newName = $newName.Trim()
                    if ([string]::IsNullOrWhiteSpace($newName)) {
                        Ui-Error "El nombre no puede estar vacío." $global:MainWindow
                        $e.Handled = $true
                        return
                    }
                    if ($newName -eq $dbName) {
                        Write-DzDebug "`t[DEBUG][TreeView] Rename sin cambios"
                        $e.Handled = $true
                        return
                    }
                    Write-DzDebug "`t[DEBUG][TreeView] F2 RENAME DB: Server='$server' Old='$dbName' New='$newName'"
                    $safeOld = $dbName -replace ']', ']]'
                    $safeNew = $newName -replace ']', ']]'
                    $query = @"
ALTER DATABASE [$safeOld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [$safeOld] MODIFY NAME = [$safeNew];
ALTER DATABASE [$safeNew] SET MULTI_USER;
"@
                    $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
                    if (-not $result.Success) {
                        Ui-Error "Error al renombrar la base de datos:`n`n$($result.ErrorMessage)" $global:MainWindow
                        $e.Handled = $true
                        return
                    }
                    Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
                    $e.Handled = $true
                    return
                }
            })
        $TreeView.Tag = [pscustomobject]@{ TreeViewKeyHandlerAdded = $true }
    }
    if ($AutoExpand) {
        Write-DzDebug "`t[DEBUG][TreeView] AutoExpand Server: $Server"
        $serverNode.Tag.Loaded = $true
        Load-DatabasesIntoTree -ServerNode $serverNode
        $serverNode.IsExpanded = $true
    }
}
function Refresh-SqlTreeServerNode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ServerNode)
    if (-not $ServerNode -or -not $ServerNode.Tag) { return }
    Write-DzDebug "`t[DEBUG][TreeView] Refresh Server: $($ServerNode.Tag.Server)"
    $ServerNode.Tag.Databases = $null
    $ServerNode.Tag.Loaded = $true
    $ServerNode.Items.Clear()
    Load-DatabasesIntoTree -ServerNode $ServerNode
    $ServerNode.IsExpanded = $true
    if ($ServerNode.Tag.OnDatabasesRefreshed) {
        & $ServerNode.Tag.OnDatabasesRefreshed
    }
}
function Refresh-SqlTreeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TreeView,
        [Parameter(Mandatory = $true)][string]$Server
    )
    if (-not $TreeView) { return }
    Write-DzDebug "`t[DEBUG][TreeView] Refresh TreeView Server='$Server'"
    $targetNode = $null
    foreach ($item in $TreeView.Items) {
        if ($item -is [System.Windows.Controls.TreeViewItem] -and $item.Tag -and $item.Tag.Type -eq "Server" -and $item.Tag.Server -eq $Server) {
            $targetNode = $item
            break
        }
    }
    if ($targetNode) { Refresh-SqlTreeServerNode -ServerNode $targetNode }
}
function Load-DatabasesIntoTree {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ServerNode)
    $ServerNode.Items.Clear()
    $server = [string]$ServerNode.Tag.Server
    $credential = $ServerNode.Tag.Credential
    Write-DzDebug "`t[DEBUG][TreeView] Load DBs: Server='$server'"
    try {
        $databases = $ServerNode.Tag.Databases
        if (-not $databases -or $databases.Count -eq 0) {
            Write-DzDebug "`t[DEBUG][TreeView] No hay Databases precargadas, consultando a SQL..."
            try {
                $databases = Get-SqlDatabasesInfo -Server $server -Credential $credential
                $ServerNode.Tag.Databases = $databases
                Write-DzDebug "`t[DEBUG][TreeView] Obtenidas $($databases.Count) bases de datos"
            } catch {
                Write-DzDebug "`t[DEBUG][TreeView] Error obteniendo bases: $($_.Exception.Message)" -Color Red
                $errorNode = New-SqlTreeNode -Header "Error cargando bases" -Tag @{ Type = "Error" } -HasPlaceholder $false
                [void]$ServerNode.Items.Add($errorNode)
                return
            }
        } else {
            Write-DzDebug "`t[DEBUG][TreeView] Usando Databases precargadas: $($databases.Count)"
        }
    } catch {
        Write-DzDebug "`t[DEBUG][TreeView] Excepción general: $($_.Exception.Message)" -Color Red
        $errorNode = New-SqlTreeNode -Header "Error cargando bases" -Tag @{ Type = "Error" } -HasPlaceholder $false
        [void]$ServerNode.Items.Add($errorNode)
        return
    }
    foreach ($dbInfo in $databases) {
        $db = $dbInfo.Name
        $stateDesc = $dbInfo.StateDesc
        $userAccessDesc = $dbInfo.UserAccessDesc
        $isReadOnly = $dbInfo.IsReadOnly
        # Write-DzDebug "`t[DEBUG][TreeView] Procesando DB: $db | State=$stateDesc | Access=$userAccessDesc | ReadOnly=$isReadOnly"
        $statusInfo = Get-DbStatusInfo -StateDesc $stateDesc -UserAccessDesc $userAccessDesc -IsReadOnly $isReadOnly
        $showBadge = $false
        if ($stateDesc -ne "ONLINE") {
            $showBadge = $true
        } elseif ($userAccessDesc -ne "MULTI_USER") {
            $showBadge = $true
        } elseif ($isReadOnly) {
            $showBadge = $true
        }
        if ($showBadge) {
            $header = "🗄️ $db  —  $($statusInfo.Badge)"
        } else {
            $header = "🗄️ $db"
        }
        $dbTag = @{
            Type               = "Database"
            Database           = $db
            Server             = $server
            Credential         = $credential
            User               = $ServerNode.Tag.User
            Password           = $ServerNode.Tag.Password
            InsertTextHandler  = $ServerNode.Tag.InsertTextHandler
            OnDatabaseSelected = $ServerNode.Tag.OnDatabaseSelected
            DbStateDesc        = $stateDesc
            DbUserAccessDesc   = $userAccessDesc
            DbIsReadOnly       = $isReadOnly
            DbStatusColor      = $statusInfo.Color
        }
        $dbNode = New-SqlTreeNode -Header $header -Tag $dbTag -HasPlaceholder $false
        if ($statusInfo.Color -ne "PanelFg") {
            try {
                if ($global:MainWindow -and $global:MainWindow.Resources.Contains($statusInfo.Color)) {
                    $dbNode.Foreground = $global:MainWindow.Resources[$statusInfo.Color]
                } else {
                    Write-DzDebug "`t[DEBUG][TreeView] No se encontró recurso de color: $($statusInfo.Color)"
                }
            } catch {
                Write-DzDebug "`t[DEBUG][TreeView] Error aplicando color $($statusInfo.Color): $($_.Exception.Message)" -Color Red
            }
        }
        Add-DatabaseContextMenu -DatabaseNode $dbNode
        if ($stateDesc -ne "ONLINE") {
            $infoNode = New-SqlTreeNode -Header "⚠️ Base de datos no disponible ($stateDesc)" -Tag @{ Type = "Info" } -HasPlaceholder $false
            [void]$dbNode.Items.Add($infoNode)
            [void]$ServerNode.Items.Add($dbNode)
            continue
        }
        $dbNode.Add_MouseDoubleClick({
                param($s, $e)
                $db = [string]$s.Tag.Database
                $state = [string]$s.Tag.DbStateDesc
                $hasHandler = ($null -ne $s.Tag.OnDatabaseSelected)
                Write-DzDebug "`t[DEBUG][TreeView] Doble clic DB: $db | State=$state | HasOnDatabaseSelected=$hasHandler"
                if ($state -ne "ONLINE") {
                    Ui-Warn "La base de datos '$db' está en estado '$state'.`nDebes ponerla ONLINE primero." "Base de datos no disponible" $global:MainWindow
                    $e.Handled = $true
                    return
                }
                if ($hasHandler) {
                    try {
                        & $s.Tag.OnDatabaseSelected $db
                        Write-DzDebug "`t[DEBUG][TreeView] OnDatabaseSelected ejecutado OK para DB='$db'"
                    } catch {
                        Write-DzDebug "`t[DEBUG][TreeView] ERROR OnDatabaseSelected: $($_.Exception.Message)" -Color Red
                        Write-DzDebug "`t[DEBUG][TreeView] Stack: $($_.ScriptStackTrace)" -Color Red
                    }
                } else {
                    Write-DzDebug "`t[DEBUG][TreeView] OnDatabaseSelected es NULL (no hay handler)" -Color Red
                }
                $e.Handled = $true
            })
        $tablesTag = @{
            Type               = "TablesRoot"
            Database           = $db
            Server             = $server
            Credential         = $credential
            InsertTextHandler  = $ServerNode.Tag.InsertTextHandler
            OnDatabaseSelected = $ServerNode.Tag.OnDatabaseSelected
            Loaded             = $false
        }
        $viewsTag = @{
            Type               = "ViewsRoot"
            Database           = $db
            Server             = $server
            Credential         = $credential
            InsertTextHandler  = $ServerNode.Tag.InsertTextHandler
            OnDatabaseSelected = $ServerNode.Tag.OnDatabaseSelected
            Loaded             = $false
        }
        $procsTag = @{
            Type               = "ProceduresRoot"
            Database           = $db
            Server             = $server
            Credential         = $credential
            InsertTextHandler  = $ServerNode.Tag.InsertTextHandler
            OnDatabaseSelected = $ServerNode.Tag.OnDatabaseSelected
            Loaded             = $false
        }
        $tablesNode = New-SqlTreeNode -Header "📋 Tablas" -Tag $tablesTag -HasPlaceholder $true
        $viewsNode = New-SqlTreeNode -Header "👁️ Vistas" -Tag $viewsTag -HasPlaceholder $true
        $procsNode = New-SqlTreeNode -Header "⚙️ Procedimientos" -Tag $procsTag -HasPlaceholder $true
        $tablesNode.Add_Expanded({
                param($s, $e)
                Write-DzDebug "`t[DEBUG][TreeView] Expand TablasRoot DB: $($s.Tag.Database)"
                Load-TablesIntoNode -RootNode $s
            })
        $viewsNode.Add_Expanded({
                param($s, $e)
                Write-DzDebug "`t[DEBUG][TreeView] Expand VistasRoot DB: $($s.Tag.Database)"
                Load-TablesIntoNode -RootNode $s
            })
        $procsNode.Add_Expanded({
                param($s, $e)
                Write-DzDebug "`t[DEBUG][TreeView] Expand ProcsRoot DB: $($s.Tag.Database)"
                Load-TablesIntoNode -RootNode $s
            })
        [void]$dbNode.Items.Add($tablesNode)
        [void]$dbNode.Items.Add($viewsNode)
        [void]$dbNode.Items.Add($procsNode)
        [void]$ServerNode.Items.Add($dbNode)
    }
    Write-DzDebug "`t[DEBUG][TreeView] Load DBs completado. Total nodos: $($ServerNode.Items.Count)"
}
function Load-TablesIntoNode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$RootNode)
    if ($RootNode.Tag.Loaded) { return }
    $RootNode.Tag.Loaded = $true
    $RootNode.Items.Clear()
    $server = [string]$RootNode.Tag.Server
    $database = [string]$RootNode.Tag.Database
    $credential = $RootNode.Tag.Credential
    $nodeType = [string]$RootNode.Tag.Type
    Write-DzDebug "`t[DEBUG][TreeView] Load NodeType=$nodeType Server='$server' DB='$database'"
    switch ($nodeType) {
        "TablesRoot" {
            $query = @"
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME
"@
            $result = Invoke-SqlQuery -Server $server -Database $database -Query $query -Credential $credential
            if (-not $result.Success) { return }
            foreach ($row in $result.DataTable.Rows) {
                $schema = $row.TABLE_SCHEMA
                $table = $row.TABLE_NAME
                $tag = @{
                    Type               = "Table"
                    Database           = $database
                    Schema             = $schema
                    Table              = $table
                    Server             = $server
                    Credential         = $credential
                    InsertTextHandler  = $RootNode.Tag.InsertTextHandler
                    OnDatabaseSelected = $RootNode.Tag.OnDatabaseSelected
                    Loaded             = $false
                }
                $tableNode = New-SqlTreeNode -Header "📋 [$schema].[$table]" -Tag $tag -HasPlaceholder $true
                $tableNode.Add_Expanded({
                        param($s, $e)
                        Write-DzDebug "`t[DEBUG][TreeView] Expand Table: $($s.Tag.Database) [$($s.Tag.Schema)].[$($s.Tag.Table)]"
                        Load-ColumnsIntoTableNode -TableNode $s
                    })
                $tableNode.Add_MouseDoubleClick({
                        param($s, $e)
                        Write-DzDebug "`t[DEBUG][TreeView] Doble clic Table: DB=$($s.Tag.Database) [$($s.Tag.Schema)].[$($s.Tag.Table)]"
                        if ($s.Tag.OnDatabaseSelected) { & $s.Tag.OnDatabaseSelected $s.Tag.Database }
                        if ($global:tcQueries) {
                            $tab = New-QueryTab -TabControl $global:tcQueries
                            $queryText = "SELECT TOP 100 * FROM [$($s.Tag.Schema)].[$($s.Tag.Table)]"
                            Set-QueryTextInActiveTab -TabControl $global:tcQueries -Text $queryText
                        } else {
                            $queryText = "SELECT TOP 100 * FROM [$($s.Tag.Schema)].[$($s.Tag.Table)]"
                            if ($s.Tag.InsertTextHandler) { & $s.Tag.InsertTextHandler $queryText }
                        }
                        $e.Handled = $true
                    })
                Add-TreeNodeContextMenu -TableNode $tableNode
                [void]$RootNode.Items.Add($tableNode)
            }
        }
        "ViewsRoot" {
            $query = @"
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_SCHEMA, TABLE_NAME
"@
            $result = Invoke-SqlQuery -Server $server -Database $database -Query $query -Credential $credential
            if (-not $result.Success) { return }
            foreach ($row in $result.DataTable.Rows) {
                $schema = $row.TABLE_SCHEMA
                $view = $row.TABLE_NAME
                $tag = @{
                    Type               = "View"
                    Database           = $database
                    Schema             = $schema
                    View               = $view
                    Server             = $server
                    Credential         = $credential
                    InsertTextHandler  = $RootNode.Tag.InsertTextHandler
                    OnDatabaseSelected = $RootNode.Tag.OnDatabaseSelected
                }
                $viewNode = New-SqlTreeNode -Header "👁️ [$schema].[$view]" -Tag $tag -HasPlaceholder $false
                $viewNode.Add_MouseDoubleClick({
                        param($s, $e)
                        Write-DzDebug "`t[DEBUG][TreeView] Doble clic View: DB=$($s.Tag.Database) [$($s.Tag.Schema)].[$($s.Tag.View)]"
                        if ($s.Tag.OnDatabaseSelected) { & $s.Tag.OnDatabaseSelected $s.Tag.Database }
                        $queryText = "SELECT TOP 100 * FROM [$($s.Tag.Schema)].[$($s.Tag.View)]"
                        if ($s.Tag.InsertTextHandler) { & $s.Tag.InsertTextHandler $queryText }
                        $e.Handled = $true
                    })
                [void]$RootNode.Items.Add($viewNode)
            }
        }
        "ProceduresRoot" {
            $query = @"
SELECT SPECIFIC_SCHEMA, SPECIFIC_NAME
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
ORDER BY SPECIFIC_SCHEMA, SPECIFIC_NAME
"@
            $result = Invoke-SqlQuery -Server $server -Database $database -Query $query -Credential $credential
            if (-not $result.Success) { return }
            foreach ($row in $result.DataTable.Rows) {
                $schema = $row.SPECIFIC_SCHEMA
                $proc = $row.SPECIFIC_NAME
                $tag = @{
                    Type               = "Procedure"
                    Database           = $database
                    Schema             = $schema
                    Procedure          = $proc
                    Server             = $server
                    Credential         = $credential
                    InsertTextHandler  = $RootNode.Tag.InsertTextHandler
                    OnDatabaseSelected = $RootNode.Tag.OnDatabaseSelected
                }
                $procNode = New-SqlTreeNode -Header "⚙️ [$schema].[$proc]" -Tag $tag -HasPlaceholder $false
                $procNode.Add_MouseDoubleClick({
                        param($s, $e)
                        Write-DzDebug "`t[DEBUG][TreeView] Doble clic Proc: DB=$($s.Tag.Database) [$($s.Tag.Schema)].[$($s.Tag.Procedure)]"
                        if ($s.Tag.OnDatabaseSelected) { & $s.Tag.OnDatabaseSelected $s.Tag.Database }
                        $queryText = "EXEC [$($s.Tag.Schema)].[$($s.Tag.Procedure)]"
                        if ($s.Tag.InsertTextHandler) { & $s.Tag.InsertTextHandler $queryText }
                        $e.Handled = $true
                    })
                [void]$RootNode.Items.Add($procNode)
            }
        }
    }
}
function Load-ColumnsIntoTableNode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$TableNode)
    if ($TableNode.Tag.Loaded) { return }
    $TableNode.Tag.Loaded = $true
    $TableNode.Items.Clear()
    $server = [string]$TableNode.Tag.Server
    $database = [string]$TableNode.Tag.Database
    $schema = [string]$TableNode.Tag.Schema
    $table = [string]$TableNode.Tag.Table
    $credential = $TableNode.Tag.Credential
    Write-DzDebug "`t[DEBUG][TreeView] Load Columns: Server='$server' DB='$database' [$schema].[$table]"
    $query = @"
SELECT
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.NUMERIC_PRECISION,
    c.NUMERIC_SCALE,
    c.IS_NULLABLE,
    CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
FROM INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN (
    SELECT ku.TABLE_SCHEMA, ku.TABLE_NAME, ku.COLUMN_NAME
    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
    JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
        ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
    WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
) pk ON c.TABLE_SCHEMA = pk.TABLE_SCHEMA AND c.TABLE_NAME = pk.TABLE_NAME AND c.COLUMN_NAME = pk.COLUMN_NAME
WHERE c.TABLE_SCHEMA = '$schema' AND c.TABLE_NAME = '$table'
ORDER BY c.ORDINAL_POSITION
"@
    $result = Invoke-SqlQuery -Server $server -Database $database -Query $query -Credential $credential
    if (-not $result.Success) { return }
    foreach ($row in $result.DataTable.Rows) {
        $name = $row.COLUMN_NAME
        $type = $row.DATA_TYPE
        $isPk = ([int]$row.IS_PRIMARY_KEY -eq 1)
        $label = if ($isPk) { "🔑 $name ($type)" } else { "• $name ($type)" }
        $tag = @{ Type = "Column"; Column = $name; InsertTextHandler = $TableNode.Tag.InsertTextHandler }
        $colNode = New-SqlTreeNode -Header $label -Tag $tag -HasPlaceholder $false
        $colNode.Add_MouseDoubleClick({
                param($s, $e)
                Write-DzDebug "`t[DEBUG][TreeView] Doble clic Column: [$($s.Tag.Column)]"
                if ($s.Tag.InsertTextHandler) {
                    & $s.Tag.InsertTextHandler "[$($s.Tag.Column)]"
                }
                $e.Handled = $true
            })
        [void]$TableNode.Items.Add($colNode)
    }
}
function Get-CreateTableScript {
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Schema,
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
    )
    $query = @"
SELECT
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.NUMERIC_PRECISION,
    c.NUMERIC_SCALE,
    c.IS_NULLABLE,
    CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
FROM INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN (
    SELECT ku.TABLE_SCHEMA, ku.TABLE_NAME, ku.COLUMN_NAME
    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
    JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
        ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
    WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
) pk ON c.TABLE_SCHEMA = pk.TABLE_SCHEMA AND c.TABLE_NAME = pk.TABLE_NAME AND c.COLUMN_NAME = pk.COLUMN_NAME
WHERE c.TABLE_SCHEMA = '$Schema' AND c.TABLE_NAME = '$Table'
ORDER BY c.ORDINAL_POSITION
"@
    $result = Invoke-SqlQuery -Server $Server -Database $Database -Query $query -Credential $Credential
    if (-not $result.Success) { return $null }
    $lines = New-Object System.Collections.Generic.List[string]
    $pkColumns = New-Object System.Collections.Generic.List[string]
    foreach ($row in $result.DataTable.Rows) {
        $colName = $row.COLUMN_NAME
        $dataType = $row.DATA_TYPE
        $len = $row.CHARACTER_MAXIMUM_LENGTH
        $precision = $row.NUMERIC_PRECISION
        $scale = $row.NUMERIC_SCALE
        $nullable = ($row.IS_NULLABLE -eq "YES")
        $typeSuffix = ""
        if ($dataType -in @("char", "varchar", "nchar", "nvarchar", "binary", "varbinary")) {
            if ($len -eq -1) { $typeSuffix = "(MAX)" } else { $typeSuffix = "($len)" }
        } elseif ($dataType -in @("decimal", "numeric")) {
            $typeSuffix = "($precision,$scale)"
        }
        $nullText = if ($nullable) { "NULL" } else { "NOT NULL" }
        $lines.Add("    [$colName] $dataType$typeSuffix $nullText")
        if ([int]$row.IS_PRIMARY_KEY -eq 1) { $pkColumns.Add("[$colName]") }
    }
    if ($pkColumns.Count -gt 0) {
        $pkLine = "    CONSTRAINT [PK_$Table] PRIMARY KEY (" + ($pkColumns -join ", ") + ")"
        $lines.Add($pkLine)
    }
    $script = @()
    $script += "CREATE TABLE [$Schema].[$Table] ("
    $script += ($lines -join ",`n")
    $script += ")"
    ($script -join "`n")
}
function Add-TreeNodeContextMenu {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$TableNode)
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menuSelectTop = New-Object System.Windows.Controls.MenuItem
    $menuSelectTop.Header = "SELECT TOP 100 *"
    $menuSelectTop.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $db = [string]$node.Tag.Database
            $schema = [string]$node.Tag.Schema
            $table = [string]$node.Tag.Table
            Write-DzDebug "`t[DEBUG][TreeView] Context SELECT TOP: DB=$db [$schema].[$table]"
            if ($node.Tag.OnDatabaseSelected) { & $node.Tag.OnDatabaseSelected $db }
            if ($global:tcQueries) {
                $tab = New-QueryTab -TabControl $global:tcQueries
                $queryText = "SELECT TOP 100 * FROM [$schema].[$table]"
                Set-QueryTextInActiveTab -TabControl $global:tcQueries -Text $queryText
            } else {
                $queryText = "SELECT TOP 100 * FROM [$schema].[$table]"
                if ($node.Tag.InsertTextHandler) { & $node.Tag.InsertTextHandler $queryText }
            }
        })
    $menuSelectAll = New-Object System.Windows.Controls.MenuItem
    $menuSelectAll.Header = "SELECT *"
    $menuSelectAll.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $db = [string]$node.Tag.Database
            $schema = [string]$node.Tag.Schema
            $table = [string]$node.Tag.Table
            Write-DzDebug "`t[DEBUG][TreeView] Context SELECT *: DB=$db [$schema].[$table]"
            if ($node.Tag.OnDatabaseSelected) { & $node.Tag.OnDatabaseSelected $db }
            if ($global:tcQueries) {
                $tab = New-QueryTab -TabControl $global:tcQueries
                $queryText = "SELECT * FROM [$schema].[$table]"
                Set-QueryTextInActiveTab -TabControl $global:tcQueries -Text $queryText
            } else {
                $queryText = "SELECT * FROM [$schema].[$table]"
                if ($node.Tag.InsertTextHandler) { & $node.Tag.InsertTextHandler $queryText }
            }
        })
    $menuScript = New-Object System.Windows.Controls.MenuItem
    $menuScript.Header = "Script CREATE TABLE"
    $menuScript.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $srv = [string]$node.Tag.Server
            $db = [string]$node.Tag.Database
            $schema = [string]$node.Tag.Schema
            $table = [string]$node.Tag.Table
            Write-DzDebug "`t[DEBUG][TreeView] Context CREATE: Server='$srv' DB='$db' [$schema].[$table]"
            if ([string]::IsNullOrWhiteSpace($srv)) {
                Ui-Error "TreeView: Server vacío en el Tag. Reconecta a la BD para recargar el explorador." $global:MainWindow
                return
            }
            if ([string]::IsNullOrWhiteSpace($db)) {
                Ui-Error "TreeView: Database vacía en el Tag." $global:MainWindow
                return
            }
            if ($node.Tag.OnDatabaseSelected) { & $node.Tag.OnDatabaseSelected $db }
            $scriptText = Get-CreateTableScript -Server $srv -Database $db -Schema $schema -Table $table -Credential $node.Tag.Credential
            if ($scriptText) {
                if ($global:tcQueries) {
                    $tab = New-QueryTab -TabControl $global:tcQueries
                    Set-QueryTextInActiveTab -TabControl $global:tcQueries -Text $scriptText
                } else {
                    if ($node.Tag.InsertTextHandler) { & $node.Tag.InsertTextHandler $scriptText }
                }
            }
        })
    $menuCopy = New-Object System.Windows.Controls.MenuItem
    $menuCopy.Header = "Copiar nombre"
    $menuCopy.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $schema = [string]$node.Tag.Schema
            $table = [string]$node.Tag.Table
            Write-DzDebug "`t[DEBUG][TreeView] Context COPY: [$schema].[$table]"
            $name = "[$schema].[$table]"
            [System.Windows.Clipboard]::SetText($name)
        })
    [void]$menu.Items.Add($menuSelectTop)
    [void]$menu.Items.Add($menuSelectAll)
    [void]$menu.Items.Add($menuScript)
    [void]$menu.Items.Add($menuCopy)
    $TableNode.ContextMenu = $menu
}
function Add-DatabaseContextMenu {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$DatabaseNode)
    if ($DatabaseNode -and $DatabaseNode.Tag) {
        Write-DzDebug "`t[DEBUG][TreeView] Init DB ContextMenu: $($DatabaseNode.Tag.Database)"
    }
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menuSize = New-Object System.Windows.Controls.MenuItem
    $menuSize.Header = "📊 Ver Tamaño..."
    $menuSize.Add_Click({
            Write-DzDebug "`t[DEBUG][TreeView] Click Context SIZE DB Menu"
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            Write-DzDebug "`t[DEBUG][TreeView] Context SIZE DB: Server='$server' DB='$dbName'"
            Show-DatabaseSizeDialog -Server $server -Database $dbName -Credential $credential
        })
    $menuRepair = New-Object System.Windows.Controls.MenuItem
    $menuRepair.Header = "🔧 Verificar/Reparar..."
    $menuRepair.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            Write-DzDebug "`t[DEBUG][TreeView] Context REPAIR DB: Server='$server' DB='$dbName'"
            Show-DatabaseRepairDialog -Server $server -Database $dbName -Credential $credential
        })
    $separator0 = New-Object System.Windows.Controls.Separator
    $menuBackup = New-Object System.Windows.Controls.MenuItem
    $menuBackup.Header = "💾 Respaldar..."
    $menuBackup.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $user = [string]$node.Tag.User
            $password = [string]$node.Tag.Password
            Write-DzDebug "`t[DEBUG][TreeView] Context BACKUP DB: Server='$server' DB='$dbName'"
            if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($password)) {
                Ui-Error "No se encontraron credenciales para respaldar la base de datos." $global:MainWindow
                return
            }
            Show-BackupDialog -Server $server -User $user -Password $password -Database $dbName
        })
    $menuRename = New-Object System.Windows.Controls.MenuItem
    $menuRename.Header = "✏️ Renombrar..."
    $menuRename.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $newName = bdd_RenameFromTree -Title "Renombrar base de datos" `
                -Prompt "Nuevo nombre para la base de datos:" `
                -DefaultValue $dbName
            if ($null -eq $newName) {
                Write-DzDebug "`t[DEBUG][TreeView] Rename cancelado"
                return
            }
            $newName = $newName.Trim()
            if ([string]::IsNullOrWhiteSpace($newName)) {
                Ui-Error "El nombre no puede estar vacío." $global:MainWindow
                return
            }
            if ($newName -eq $dbName) {
                Write-DzDebug "`t[DEBUG][TreeView] Rename sin cambios"
                return
            }
            Write-DzDebug "`t[DEBUG][TreeView] Context RENAME DB: Server='$server' Old='$dbName' New='$newName'"
            $safeOld = $dbName -replace ']', ']]'
            $safeNew = $newName -replace ']', ']]'
            $query = @"
ALTER DATABASE [$safeOld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [$safeOld] MODIFY NAME = [$safeNew];
ALTER DATABASE [$safeNew] SET MULTI_USER;
"@
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "Error al renombrar la base de datos:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
        })
    $menuNewQuery = New-Object System.Windows.Controls.MenuItem
    $menuNewQuery.Header = "🧾 Nuevo Query"
    $menuNewQuery.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            Write-DzDebug "`t[DEBUG][TreeView] Context NEW QUERY: DB='$dbName'"
            if ($node.Tag.OnDatabaseSelected) { & $node.Tag.OnDatabaseSelected $dbName }
            if (-not $global:tcQueries) { return }
            $tab = New-QueryTab -TabControl $global:tcQueries
            $safeDb = $dbName -replace ']', ']]'
            Set-QueryTextInActiveTab -TabControl $global:tcQueries -Text "USE [$safeDb]`n`n"
        })
    $separator1 = New-Object System.Windows.Controls.Separator
    $menuState = New-Object System.Windows.Controls.MenuItem
    $menuState.Header = "🧭 Cambiar estado"
    $menuOnline = New-Object System.Windows.Controls.MenuItem
    $menuOnline.Header = "🟢 ONLINE"
    $menuOnline.Add_Click({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG][TreeView] Click Context SET ONLINE Menu"
            $cm = $sender.Parent.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) {
                Write-DzDebug "`t[DEBUG][TreeView] SET ONLINE: node null or tag null" -Color Red
                return
            }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $safeName = $dbName -replace ']', ']]'
            Write-DzDebug "`t[DEBUG][TreeView] Context SET ONLINE: Server='$server' DB='$dbName'"
            $confirm = Ui-Confirm "Se pondrá la base '$dbName' en modo ONLINE. ¿Deseas continuar?" "Cambiar estado" $global:MainWindow
            if (-not $confirm) {
                Write-DzDebug "`t[DEBUG][TreeView] SET ONLINE cancelado por usuario"
                return
            }
            $query = "ALTER DATABASE [$safeName] SET ONLINE"
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "No se pudo poner ONLINE la base:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Ui-Info "La base '$dbName' quedó ONLINE." "Estado actualizado" $global:MainWindow
            Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
        })
    $menuOffline = New-Object System.Windows.Controls.MenuItem
    $menuOffline.Header = "🔴 OFFLINE"
    $menuOffline.Add_Click({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG][TreeView] Click Context SET OFFLINE Menu"
            $cm = $sender.Parent.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) {
                Write-DzDebug "`t[DEBUG][TreeView] SET OFFLINE: node null or tag null" -Color Red
                return
            }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $safeName = $dbName -replace ']', ']]'
            Write-DzDebug "`t[DEBUG][TreeView] Context SET OFFLINE: Server='$server' DB='$dbName'"
            $confirm = Ui-Confirm "Se pondrá la base '$dbName' en modo OFFLINE (con ROLLBACK IMMEDIATE). ¿Deseas continuar?" "Cambiar estado" $global:MainWindow
            if (-not $confirm) {
                Write-DzDebug "`t[DEBUG][TreeView] SET OFFLINE cancelado por usuario"
                return
            }
            $query = "ALTER DATABASE [$safeName] SET OFFLINE WITH ROLLBACK IMMEDIATE"
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "No se pudo poner OFFLINE la base:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Ui-Info "La base '$dbName' quedó OFFLINE." "Estado actualizado" $global:MainWindow
            Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
        })
    $menuReadOnly = New-Object System.Windows.Controls.MenuItem
    $menuReadOnly.Header = "🔒 READ_ONLY"
    $menuReadOnly.Add_Click({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG][TreeView] Click Context SET READ_ONLY Menu"
            $cm = $sender.Parent.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) {
                Write-DzDebug "`t[DEBUG][TreeView] SET READ_ONLY: node null or tag null" -Color Red
                return
            }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $safeName = $dbName -replace ']', ']]'
            Write-DzDebug "`t[DEBUG][TreeView] Context SET READ_ONLY: Server='$server' DB='$dbName'"
            $confirm = Ui-Confirm "Se pondrá la base '$dbName' en modo READ_ONLY. ¿Deseas continuar?" "Cambiar estado" $global:MainWindow
            if (-not $confirm) {
                Write-DzDebug "`t[DEBUG][TreeView] SET READ_ONLY cancelado por usuario"
                return
            }
            $query = "ALTER DATABASE [$safeName] SET READ_ONLY WITH NO_WAIT"
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "No se pudo poner READ_ONLY la base:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Ui-Info "La base '$dbName' quedó READ_ONLY." "Estado actualizado" $global:MainWindow
            Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
        })
    $menuReadWrite = New-Object System.Windows.Controls.MenuItem
    $menuReadWrite.Header = "✍️ READ_WRITE"
    $menuReadWrite.Add_Click({
            param($sender, $e)
            Write-DzDebug "`t[DEBUG][TreeView] Click Context SET READ_WRITE Menu"
            $cm = $sender.Parent.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) {
                Write-DzDebug "`t[DEBUG][TreeView] SET READ_WRITE: node null or tag null" -Color Red
                return
            }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $safeName = $dbName -replace ']', ']]'
            Write-DzDebug "`t[DEBUG][TreeView] Context SET READ_WRITE: Server='$server' DB='$dbName'"
            $confirm = Ui-Confirm "Se pondrá la base '$dbName' en modo READ_WRITE. ¿Deseas continuar?" "Cambiar estado" $global:MainWindow
            if (-not $confirm) {
                Write-DzDebug "`t[DEBUG][TreeView] SET READ_WRITE cancelado por usuario"
                return
            }
            $query = "ALTER DATABASE [$safeName] SET READ_WRITE WITH ROLLBACK IMMEDIATE"
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "No se pudo poner READ_WRITE la base:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Ui-Info "La base '$dbName' quedó READ_WRITE." "Estado actualizado" $global:MainWindow
            Refresh-SqlTreeView -TreeView $global:tvDatabases -Server $server
        })
    [void]$menuState.Items.Add($menuOnline)
    [void]$menuState.Items.Add($menuOffline)
    [void]$menuState.Items.Add($menuReadOnly)
    [void]$menuState.Items.Add($menuReadWrite)
    $menuDetach = New-Object System.Windows.Controls.MenuItem
    $menuDetach.Header = "📎 Separar (Detach)..."
    $menuDetach.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            Write-DzDebug "`t[DEBUG][TreeView] Context DETACH DB: Server='$server' DB='$dbName'"
            Show-DetachDialog -Server $server -Database $dbName -Credential $credential -ParentNode $node
        })
    $menuDelete = New-Object System.Windows.Controls.MenuItem
    $menuDelete.Header = "🗑️ Eliminar base de datos..."
    $menuDelete.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $dbName = [string]$node.Tag.Database
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            Write-DzDebug "`t[DEBUG][TreeView] Context DELETE DB: Server='$server' DB='$dbName'"
            Show-DeleteDatabaseDialog -Server $server -Database $dbName -Credential $credential -ParentNode $node
        })
    $separator2 = New-Object System.Windows.Controls.Separator
    $menuRefresh = New-Object System.Windows.Controls.MenuItem
    $menuRefresh.Header = "🔄 Actualizar"
    $menuRefresh.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            Write-DzDebug "`t[DEBUG][TreeView] Context REFRESH DB: $($node.Tag.Database)"
            $node.Items.Clear()
            $db = $node.Tag.Database
            $server = $node.Tag.Server
            $credential = $node.Tag.Credential
            $insertHandler = $node.Tag.InsertTextHandler
            $dbSelectedHandler = $node.Tag.OnDatabaseSelected
            $tablesTag = @{ Type = "TablesRoot"; Database = $db; Server = $server; Credential = $credential; InsertTextHandler = $insertHandler; OnDatabaseSelected = $dbSelectedHandler; Loaded = $false }
            $viewsTag = @{ Type = "ViewsRoot"; Database = $db; Server = $server; Credential = $credential; InsertTextHandler = $insertHandler; OnDatabaseSelected = $dbSelectedHandler; Loaded = $false }
            $procsTag = @{ Type = "ProceduresRoot"; Database = $db; Server = $server; Credential = $credential; InsertTextHandler = $insertHandler; OnDatabaseSelected = $dbSelectedHandler; Loaded = $false }
            $tablesNode = New-SqlTreeNode -Header "📋 Tablas" -Tag $tablesTag -HasPlaceholder $true
            $viewsNode = New-SqlTreeNode -Header "👁️ Vistas" -Tag $viewsTag -HasPlaceholder $true
            $procsNode = New-SqlTreeNode -Header "⚙️ Procedimientos" -Tag $procsTag -HasPlaceholder $true
            $tablesNode.Add_Expanded({ param($s, $e) Load-TablesIntoNode -RootNode $s })
            $viewsNode.Add_Expanded({ param($s, $e) Load-TablesIntoNode -RootNode $s })
            $procsNode.Add_Expanded({ param($s, $e) Load-TablesIntoNode -RootNode $s })
            [void]$node.Items.Add($tablesNode)
            [void]$node.Items.Add($viewsNode)
            [void]$node.Items.Add($procsNode)
        })
    [void]$menu.Items.Add($menuSize)
    [void]$menu.Items.Add($menuRepair)
    [void]$menu.Items.Add($separator0)
    [void]$menu.Items.Add($menuBackup)
    [void]$menu.Items.Add($menuRename)
    [void]$menu.Items.Add($menuNewQuery)
    [void]$menu.Items.Add($separator1)
    [void]$menu.Items.Add($menuState)
    [void]$menu.Items.Add($menuDetach)
    [void]$menu.Items.Add($menuDelete)
    [void]$menu.Items.Add($separator2)
    [void]$menu.Items.Add($menuRefresh)
    $DatabaseNode.ContextMenu = $menu
}
function Add-ServerContextMenu {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ServerNode)
    if ($ServerNode -and $ServerNode.Tag) { Write-DzDebug "`t[DEBUG][TreeView] Init Server ContextMenu: $($ServerNode.Tag.Server)" }
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menuRefresh = New-Object System.Windows.Controls.MenuItem
    $menuRefresh.Header = "🔄 Actualizar"
    $menuRefresh.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            Write-DzDebug "`t[DEBUG][TreeView] Context REFRESH Server: $($node.Tag.Server)"
            Refresh-SqlTreeServerNode -ServerNode $node
            if ($node.Tag.OnDatabasesRefreshed) {
                & $node.Tag.OnDatabasesRefreshed
            }
        })
    $menuRestore = New-Object System.Windows.Controls.MenuItem
    $menuRestore.Header = "♻️ Restaurar..."
    $serverNodeRef = $ServerNode
    $menuRestore.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $server = [string]$node.Tag.Server
            $user = [string]$node.Tag.User
            $password = [string]$node.Tag.Password
            $defaultDb = "master"
            if ($node.Tag.GetCurrentDatabase) { $defaultDb = & $node.Tag.GetCurrentDatabase }
            Write-DzDebug "`t[DEBUG][TreeView] Context RESTORE Server: $server DefaultDB='$defaultDb'"
            if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($password)) {
                Ui-Error "No se encontraron credenciales para restaurar." $global:MainWindow
                return
            }
            Show-RestoreDialog -Server $server -User $user -Password $password -Database $defaultDb -OnRestoreCompleted {
                param($dbName)
                Write-DzDebug "`t[DEBUG][TreeView] Restore completed. Refresh Server: $server"
                Refresh-SqlTreeServerNode -ServerNode $serverNodeRef
            }
        }.GetNewClosure())
    $menuAttach = New-Object System.Windows.Controls.MenuItem
    $menuAttach.Header = "📎 Adjuntar..."
    $menuAttach.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $server = [string]$node.Tag.Server
            $user = [string]$node.Tag.User
            $password = [string]$node.Tag.Password
            if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($password)) {
                Ui-Error "No se encontraron credenciales para adjuntar." $global:MainWindow
                return
            }
            $modulesPath = Join-Path $PSScriptRoot "modules"
            Show-AttachDialog -Server $server -User $user -Password $password -Database "master" `
                -ModulesPath $PSScriptRoot `
                -OnAttachCompleted {
                param($dbName)
                Write-DzDebug "`t[DEBUG][TreeView] Attach completed. Refresh Server: $server"
                Refresh-SqlTreeServerNode -ServerNode $serverNodeRef
            }
        }.GetNewClosure())
    $menuCreateDb = New-Object System.Windows.Controls.MenuItem
    $menuCreateDb.Header = "🆕 Crear base de datos..."
    $menuCreateDb.Add_Click({
            $cm = $this.Parent
            $node = $null
            if ($cm -is [System.Windows.Controls.ContextMenu]) { $node = $cm.PlacementTarget }
            if ($null -eq $node -or $null -eq $node.Tag) { return }
            $server = [string]$node.Tag.Server
            $credential = $node.Tag.Credential
            $dbName = New-WpfInputDialog -Title "Crear base de datos" -Prompt "Nombre de la nueva base de datos:" -DefaultValue ""
            if ($null -eq $dbName) { Write-DzDebug "`t[DEBUG][TreeView] Create DB cancelado"; return }
            $dbName = $dbName.Trim()
            if ([string]::IsNullOrWhiteSpace($dbName)) { Ui-Error "El nombre no puede estar vacío." $global:MainWindow; return }
            Write-DzDebug "`t[DEBUG][TreeView] Context CREATE DB: Server='$server' DB='$dbName'"
            $safeName = $dbName -replace ']', ']]'
            $query = "CREATE DATABASE [$safeName]"
            $result = Invoke-SqlQuery -Server $server -Database "master" -Query $query -Credential $credential
            if (-not $result.Success) {
                Ui-Error "Error al crear la base de datos:`n`n$($result.ErrorMessage)" $global:MainWindow
                return
            }
            Refresh-SqlTreeServerNode -ServerNode $node
        })
    [void]$menu.Items.Add($menuRefresh)
    [void]$menu.Items.Add($menuRestore)
    [void]$menu.Items.Add($menuAttach)
    [void]$menu.Items.Add($menuCreateDb)
    $ServerNode.ContextMenu = $menu
}
function Show-DeleteDatabaseDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $true)]$ParentNode
    )
    Write-DzDebug "`t[DEBUG][DeleteDB] INICIO: Server='$Server' Database='$Database'"
    Add-Type -AssemblyName PresentationFramework
    $safeDb = [Security.SecurityElement]::Escape($Database)
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Eliminar Base de Datos"
        Width="560" Height="360"
        MinWidth="560" MinHeight="360"
        MaxWidth="560" MaxHeight="360"
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

    <Style x:Key="TextBoxStyle" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Height" Value="34"/>
    </Style>

    <!-- Botón ícono (close) como en rename -->
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

    <!-- Botones base / acción / outline (tu estilo, pero ordenado) -->
    <Style x:Key="BaseButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="110"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
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

    <Style x:Key="ActionButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource AccentMagenta}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccentFg}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource AccentMagentaHover}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
          <Setter Property="Foreground" Value="{DynamicResource AccentMuted}"/>
          <Setter Property="BorderThickness" Value="1"/>
          <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="OutlineButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
      <Setter Property="Background" Value="{DynamicResource ControlBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource ControlFg}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrushColor}"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource PanelBg}"/>
          <Setter Property="BorderBrush" Value="{DynamicResource AccentPrimary}"/>
          <Setter Property="Foreground" Value="{DynamicResource FormFg}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

  </Window.Resources>

  <!-- Contenedor con sombra (como rename) -->
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

      <!-- Header draggable -->
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

          <StackPanel Grid.Column="1">
            <TextBlock Text="⚠️ Eliminar base de datos"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource FormFg}"
                       FontSize="12"/>
            <TextBlock Text="Esta acción es irreversible. Verifica antes de continuar."
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

      <!-- Tip / warning -->
      <Border Grid.Row="1"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="10,8"
              Margin="12,0,12,10">
        <TextBlock Text="Recomendación: realiza un respaldo antes de continuar. Si la base de datos está en uso, se forzará el cierre de sesiones."
                   Foreground="{DynamicResource PanelFg}"
                   FontSize="10"
                   Opacity="0.9"
                   TextWrapping="Wrap"/>
      </Border>

      <!-- Content -->
      <Border Grid.Row="2"
              Background="{DynamicResource PanelBg}"
              BorderBrush="{DynamicResource BorderBrushColor}"
              BorderThickness="1"
              CornerRadius="10"
              Padding="12"
              Margin="12,0,12,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <TextBlock Grid.Row="0"
                     Text="Estás a punto de eliminar permanentemente la base de datos:"
                     TextWrapping="Wrap"
                     Margin="0,0,0,10"/>

          <Border Grid.Row="1"
                  Background="{DynamicResource ControlBg}"
                  BorderBrush="{DynamicResource BorderBrushColor}"
                  BorderThickness="1"
                  CornerRadius="8"
                  Padding="10"
                  Margin="0,0,0,12">
            <TextBlock Text="🗄️ $safeDb"
                       FontSize="14"
                       FontWeight="SemiBold"
                       Foreground="{DynamicResource AccentPrimary}"/>
          </Border>

          <StackPanel Grid.Row="2" Margin="0,0,0,10">
            <CheckBox x:Name="chkDeleteBackupHistory" IsChecked="True" Margin="0,0,0,8">
              <TextBlock Text="Eliminar historial de backup y restore" TextWrapping="Wrap"/>
            </CheckBox>
            <CheckBox x:Name="chkCloseConnections" IsChecked="True">
              <TextBlock Text="Cerrar conexiones existentes (SINGLE_USER + ROLLBACK IMMEDIATE)" TextWrapping="Wrap"/>
            </CheckBox>
          </StackPanel>

          <Border Grid.Row="3"
                  Background="{DynamicResource FormBg}"
                  BorderBrush="{DynamicResource BorderBrushColor}"
                  BorderThickness="1"
                  CornerRadius="8"
                  Padding="10">
            <TextBlock FontSize="11"
                       Foreground="{DynamicResource AccentMuted}"
                       TextWrapping="Wrap">
              Enter: Eliminar   |   Esc: Cerrar
            </TextBlock>
          </Border>

        </Grid>
      </Border>

      <!-- Footer -->
      <Grid Grid.Row="3" Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Column="0"
                   Text="Server: $Server"
                   Foreground="{DynamicResource AccentMuted}"
                   VerticalAlignment="Center"
                   TextTrimming="CharacterEllipsis"/>

        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="btnCancelar"
                  Content="Cancelar"
                  Width="120"
                  Margin="0,0,10,0"
                  IsCancel="True"
                  Style="{StaticResource OutlineButtonStyle}"/>
          <Button x:Name="btnEliminar"
                  Content="Eliminar"
                  Width="140"
                  IsDefault="True"
                  Style="{StaticResource ActionButtonStyle}"/>
        </StackPanel>
      </Grid>

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
        if ($c['HeaderBar']) {
            $c['HeaderBar'].Add_MouseLeftButtonDown({
                    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                        try { $window.DragMove() } catch {}
                    }
                })
        }
        $brdTitleBar = $window.FindName("brdTitleBar")
        if ($brdTitleBar) {
            $brdTitleBar.Add_MouseLeftButtonDown({
                    param($sender, $e)
                    if ($e.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
                        try { $window.DragMove() } catch {}
                    }
                })
        }
    } catch {
        Write-DzDebug "`t[DEBUG][DeleteDB] ERROR creando ventana: $($_.Exception.Message)" -Color Red
        throw "No se pudo crear la ventana (XAML). $($_.Exception.Message)"
    }
    $chkDeleteBackupHistory = $window.FindName("chkDeleteBackupHistory")
    $chkCloseConnections = $window.FindName("chkCloseConnections")
    $btnEliminar = $window.FindName("btnEliminar")
    $btnCancelar = $window.FindName("btnCancelar")
    $btnClose = $window.FindName("btnClose")
    $btnClose.Add_Click({
            Write-DzDebug "`t[DEBUG][DeleteDB] btnClose Click"
            $window.DialogResult = $false
            $window.Close()
        })
    $btnCancelar.Add_Click({
            Write-DzDebug "`t[DEBUG][DeleteDB] btnCancelar Click"
            $window.DialogResult = $false
            $window.Close()
        })
    $window.Add_PreviewKeyDown({
            param($sender, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $window.DialogResult = $false
                $window.Close()
            }
        })
    $btnEliminar.Add_Click({
            Write-DzDebug "`t[DEBUG][DeleteDB] btnEliminar Click"
            $deleteBackupHistory = $chkDeleteBackupHistory.IsChecked -eq $true
            $closeConnections = $chkCloseConnections.IsChecked -eq $true
            try {
                $escapedDb = $Database -replace "'", "''"
                $safeName = $Database -replace ']', ']]'
                if ($closeConnections) {
                    Write-DzDebug "`t[DEBUG][DeleteDB] Paso 1: Cerrando conexiones"
                    $closeQuery = "ALTER DATABASE [$safeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
                    $result1 = Invoke-SqlQuery -Server $Server -Database "master" -Query $closeQuery -Credential $Credential
                    if (-not $result1.Success) {
                        Write-DzDebug "`t[DEBUG][DeleteDB] Error cerrando conexiones: $($result1.ErrorMessage)"
                        Ui-Error "Error al cerrar conexiones existentes:`n`n$($result1.ErrorMessage)" "Error" $window
                        return
                    }
                    Write-DzDebug "`t[DEBUG][DeleteDB] Conexiones cerradas OK"
                }
                Write-DzDebug "`t[DEBUG][DeleteDB] Paso 2: Eliminando base de datos"
                $dropQuery = "DROP DATABASE [$safeName]"
                $result2 = Invoke-SqlQuery -Server $Server -Database "master" -Query $dropQuery -Credential $Credential
                if (-not $result2.Success) {
                    Write-DzDebug "`t[DEBUG][DeleteDB] Error eliminando DB: $($result2.ErrorMessage)"
                    Ui-Error "Error al eliminar la base de datos:`n`n$($result2.ErrorMessage)" "Error" $window
                    return
                }
                Write-DzDebug "`t[DEBUG][DeleteDB] Base de datos eliminada OK"
                if ($deleteBackupHistory) {
                    Write-DzDebug "`t[DEBUG][DeleteDB] Paso 3: Eliminando historial de backup"
                    $historyQuery = "EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$escapedDb'"
                    $result3 = Invoke-SqlQuery -Server $Server -Database "master" -Query $historyQuery -Credential $Credential
                    if ($result3.Success) {
                        Write-DzDebug "`t[DEBUG][DeleteDB] Historial eliminado OK"
                    } else {
                        Write-DzDebug "`t[DEBUG][DeleteDB] Historial no eliminado (puede no existir): $($result3.ErrorMessage)"
                    }
                }
                Ui-Info "La base de datos '$Database' ha sido eliminada exitosamente." "✓ Éxito" $window
                $serverNode = $ParentNode.Parent
                if ($serverNode -and $serverNode.Tag.Type -eq "Server") {
                    if ($serverNode.Tag.OnDatabasesRefreshed) {
                        try {
                            Write-DzDebug "`t[DEBUG][DeleteDB] Llamando a OnDatabasesRefreshed"
                            & $serverNode.Tag.OnDatabasesRefreshed
                        } catch {
                            Write-DzDebug "`t[DEBUG][DeleteDB] Error en OnDatabasesRefreshed: $($_.Exception.Message)"
                        }
                    }
                    Refresh-SqlTreeServerNode -ServerNode $serverNode
                }
                if ($ParentNode.Parent -is [System.Windows.Controls.ItemsControl]) {
                    $window.Dispatcher.Invoke([action] {
                            try {
                                [void]$ParentNode.Parent.Items.Remove($ParentNode)
                                Write-DzDebug "`t[DEBUG][DeleteDB] Nodo removido del TreeView"
                            } catch {
                                Write-DzDebug "`t[DEBUG][DeleteDB] Error removiendo nodo: $($_.Exception.Message)"
                            }
                        })
                }
                $window.DialogResult = $true
                $window.Close()
            } catch {
                Write-DzDebug "`t[DEBUG][DeleteDB] Excepción: $($_.Exception.Message)"
                Ui-Error "Error inesperado al eliminar la base de datos:`n`n$($_.Exception.Message)" "Error" $window
            }
        })
    Write-DzDebug "`t[DEBUG][DeleteDB] Mostrando ventana"
    $null = $window.ShowDialog()
}
function Get-DbStatusInfo {
    param(
        [Parameter(Mandatory = $true)][string]$StateDesc,
        [Parameter(Mandatory = $true)][string]$UserAccessDesc,
        [Parameter(Mandatory = $true)][bool]$IsReadOnly
    )
    $color = "PanelFg"
    $stateIcon = ""
    switch ($StateDesc) {
        "ONLINE" {
            $stateIcon = "🟢"
            if ($UserAccessDesc -ne "MULTI_USER" -or $IsReadOnly) {
                $color = "DbOnline"
            }
        }
        "OFFLINE" {
            $stateIcon = "🔴"
            $color = "DbOffline"
        }
        "RESTORING" {
            $stateIcon = "🟠"
            $color = "DbRestoring"
        }
        "RECOVERING" {
            $stateIcon = "🟠"
            $color = "DbRestoring"
        }
        "RECOVERY_PENDING" {
            $stateIcon = "🟠"
            $color = "DbRestoring"
        }
        "SUSPECT" {
            $stateIcon = "🟣"
            $color = "DbSuspect"
        }
        "EMERGENCY" {
            $stateIcon = "🟣"
            $color = "DbSuspect"
        }
        default {
            $stateIcon = "⚪"
            $color = "DbSuspect"
        }
    }
    if ($StateDesc -eq "ONLINE") {
        switch ($UserAccessDesc) {
            "SINGLE_USER" { $color = "DbSingleUser" }
            "RESTRICTED_USER" { $color = "DbRestricted" }
        }
        if ($IsReadOnly) {
            $color = "DbReadOnly"
        }
    }
    $accessIcon = switch ($UserAccessDesc) {
        "MULTI_USER" { "👥" }
        "SINGLE_USER" { "👤" }
        "RESTRICTED_USER" { "🔒" }
        default { "❔" }
    }
    $roText = if ($IsReadOnly) { " | RO" } else { "" }
    $badge = "$stateIcon $StateDesc | $accessIcon $UserAccessDesc$roText"
    return @{
        Badge     = $badge
        Color     = $color
        StateIcon = $stateIcon
    }
}
function Get-DbStatusBadgeText {
    param(
        [Parameter(Mandatory = $true)][string]$StateDesc,
        [Parameter(Mandatory = $true)][string]$UserAccessDesc,
        [Parameter(Mandatory = $true)][bool]$IsReadOnly
    )
    $info = Get-DbStatusInfo -StateDesc $StateDesc -UserAccessDesc $UserAccessDesc -IsReadOnly $IsReadOnly
    return $info.Badge
}
function Select-SqlTreeDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TreeView,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [Parameter(Mandatory = $false)][switch]$SelectItem
    )
    if (-not $TreeView) { return }
    if ([string]::IsNullOrWhiteSpace($DatabaseName)) { return }
    $target = $DatabaseName.Trim()
    $foundNode = $null
    foreach ($serverNode in $TreeView.Items) {
        if (-not ($serverNode -is [System.Windows.Controls.TreeViewItem])) { continue }
        foreach ($dbNode in $serverNode.Items) {
            if (-not ($dbNode -is [System.Windows.Controls.TreeViewItem])) { continue }
            if (-not $dbNode.Tag -or $dbNode.Tag.Type -ne "Database") { continue }
            $dbName = [string]$dbNode.Tag.Database
            if ($dbName -eq $target) {
                $dbNode.FontWeight = "Bold"
                $foundNode = $dbNode
            } else {
                $dbNode.FontWeight = "Normal"
            }
        }
    }
    if ($foundNode -and $SelectItem) {
        $foundNode.IsSelected = $true
        try { $foundNode.BringIntoView() | Out-Null } catch {}
    }
}
Export-ModuleMember -Function @(
    "bdd_RenameFromTree", "Initialize-SqlTreeView", "Refresh-SqlTreeServerNode", "Refresh-SqlTreeView",
    "Load-DatabasesIntoTree", "Load-TablesIntoNode", "Load-ColumnsIntoTableNode", "Add-TreeNodeContextMenu",
    "Add-DatabaseContextMenu", "Add-ServerContextMenu", "Show-DeleteDatabaseDialog", "Get-DbStatusBadgeText",
    "Get-DbStatusInfo", "Select-SqlTreeDatabase"
)