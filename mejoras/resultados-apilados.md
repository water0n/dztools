# Mejora: Resultados apilados en una sola pestaña (estilo SSMS)

## Descripción del problema

Actualmente, cuando una consulta SQL devuelve múltiples result sets (por ejemplo `SELECT * FROM Tabla1; SELECT * FROM Tabla2`), la función `Show-MultipleResultSets` crea **un `TabItem` por cada result set** dentro del `TabControl` de resultados (`tcResults`). Esto obliga al usuario a cambiar entre pestañas para comparar datos de diferentes tablas, lo cual es ineficiente al hacer soporte remoto y necesitar ver información de 2 o más tablas al mismo tiempo.

## Objetivo

Agregar un **CheckBox** en la sección de Ejecución que permita alternar entre dos modos de visualización de resultados:

| Estado del CheckBox | Comportamiento |
|---|---|
| ✅ Habilitado (default) | **Una sola pestaña** con todos los DataGrids apilados verticalmente dentro de un ScrollViewer (estilo SSMS) |
| ☐ Deshabilitado | Comportamiento actual: **múltiples pestañas**, una por cada result set |

La preferencia se persiste en el archivo INI `C:\Temp\dztools\dztools.ini` para que se conserve entre sesiones.

---

## Análisis del código actual

### Archivos involucrados

| Archivo | Rol | Líneas clave |
|---|---|---|
| [`GUI.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/GUI.psm1#L1638-L1663) | XAML de la sección "▶ Ejecución" | L1638-1663 |
| [`Database.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/Database.psm1#L757-L1339) | Función `Show-MultipleResultSets` | L757-1339 |
| [`QueriesPad.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/QueriesPad.psm1#L794) | Invocaciones a `Show-MultipleResultSets` | L794, L821, L853 |
| [`Utilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/Utilities.psm1#L90-L161) | Funciones INI: `Update-DzIniSetting`, `Get-DzIniSectionMap` | L90-161, L221-254 |
| [`main.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1#L360-L395) | Wiring de controles UI y carga de preferencias | L185, L360-395, L800-804 |

### Flujo actual de ejecución de queries

```text
F5 / btnExecute.Click
  └─> Execute-QueryUiSafe()                               [QueriesPad.psm1:L869]
       └─> Execute-QueryCore($ctx)                         [QueriesPad.psm1:L435]
            └─> Invoke-SqlQueryMultiResultSet (async)      [Database.psm1]
                 └─> QueryDoneTimer (DispatcherTimer 150ms)
                      ├─ Si hay ResultSets:
                      │   └─> Show-MultipleResultSets      [QueriesPad.psm1:L821]
                      │        └─> Crea N TabItems en tcResults  [Database.psm1:L937-1326]
                      ├─ Si hay error con ResultSets parciales:
                      │   └─> Show-MultipleResultSets      [QueriesPad.psm1:L794]
                      └─ Si no hay ResultSets:
                          └─> Show-MultipleResultSets(@())  [QueriesPad.psm1:L853]
```

### Estructura XAML actual de la sección "Ejecución"

```xml
<!-- GUI.psm1:L1638-1663 -->
<Border Grid.Row="1" Margin="0,0,0,8" Padding="8" ...>
    <StackPanel>
        <TextBlock Text="▶ Ejecución" FontWeight="SemiBold" FontSize="12" Margin="0,0,0,8"/>
        <Button Content="▶ Ejecutar (F5)" Name="btnExecute" ... />
        <TextBlock Text="Queries:" FontSize="10" Margin="0,0,0,2"/>
        <ComboBox Name="cmbQueries" ... />
    </StackPanel>
</Border>
```

### Función `Show-MultipleResultSets` actual (resumen)

```text
Database.psm1:L757-1339
1. Busca pestañas permanentes (Mensajes, IA)
2. Remueve pestañas de resultados anteriores
3. Si no hay resultados → crea pestaña "Resultado" vacía
4. Si hay resultados → por cada ResultSet:
   a. Crea un TabItem con header "📊 Resultado N (X filas)"
   b. Crea un DataGrid con todo el estilo (tema dark/light, NULL highlight, etc.)
   c. Configura context menu (Copiar, Copiar con headers, Copiar Markdown, Seleccionar todo)
   d. Configura atajos de teclado (Ctrl+C, Ctrl+Shift+C, Ctrl+A)
   e. Auto-dimensiona columnas
   f. Inserta el TabItem ANTES de las pestañas fijas
5. Actualiza lblRowCount con total de filas
6. Selecciona la primera pestaña
```

### Sistema de configuración INI existente

El proyecto ya tiene un patrón establecido para persistir preferencias:

```text
Archivo: C:\Temp\dztools\dztools.ini

[desarrollo]
debug=false

[UI]
mode=light

[sql]
; server=user|password
```

Funciones disponibles en `Utilities.psm1`:
- `Update-DzIniSetting -Section "seccion" -Key "clave" -Value "valor"` → escribe/actualiza una clave
- `Get-DzIniSectionMap -Section "seccion"` → devuelve hashtable con todas las claves de una sección
- `Initialize-DzToolsConfig` → crea el archivo INI con valores por defecto si no existe

---

## Cambios propuestos

### 1. XAML — Agregar CheckBox en sección Ejecución

#### [MODIFY] [`GUI.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/GUI.psm1#L1653-L1655)

Agregar un `CheckBox` llamado `chkStackedResults` entre el botón `btnExecute` y el label `Queries:`.

```diff
 <Button Content="▶ Ejecutar (F5)" Name="btnExecute"
         Height="32" Margin="0,0,0,8"
         Style="{StaticResource DatabaseButtonStyle}"
         IsEnabled="False" FontSize="11"/>

+<!-- Modo de resultados -->
+<CheckBox Name="chkStackedResults"
+        Content="📊 Resultados en una pestaña"
+        IsChecked="True"
+        FontSize="10"
+        Margin="0,0,0,8"
+        ToolTip="Habilitado: muestra todos los resultados apilados en una sola pestaña. Deshabilitado: cada resultado en una pestaña separada."/>

 <!-- Queries Predefinidas -->
 <TextBlock Text="Queries:" FontSize="10" Margin="0,0,0,2"/>
```

> [!NOTE]
> El CheckBox va **marcado por defecto** (`IsChecked="True"`) y mostrará los resultados apilados. Al desmarcarlo se vuelve al comportamiento original de pestañas múltiples.

---

### 2. Persistencia INI — Guardar preferencia

#### [MODIFY] [`Utilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/Utilities.psm1#L208-L220)

**2a.** Agregar funciones `Get-DzStackedResults` y `Set-DzStackedResults`:

```powershell
function Get-DzStackedResults {
    $configPath = Get-DzToolsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) { return $true }
    $content = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
    $inUiSection = $false
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*;') { continue }
        if ($trimmed -match '^\[UI\]\s*$') { $inUiSection = $true; continue }
        if ($inUiSection -and $trimmed -match '^\[') { break }
        if ($inUiSection -and $trimmed -match '^\s*stacked_results\s*=\s*(.+)\s*$') {
            return ($matches[1].ToLower() -eq 'true')
        }
    }
    return $true  # Por defecto habilitado
}

function Set-DzStackedResults {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    $value = if ($Enabled) { 'true' } else { 'false' }
    Update-DzIniSetting -Section "UI" -Key "stacked_results" -Value $value
}
```

**2b.** Actualizar `Initialize-DzToolsConfig` para incluir `stacked_results=true` en la plantilla por defecto:

```diff
 "[desarrollo]`ndebug=false`n`n[UI]`nmode=light`n`n[sql]`n; server=user|password"
+"[desarrollo]`ndebug=false`n`n[UI]`nmode=light`nstacked_results=true`n`n[sql]`n; server=user|password"
```

Resultado en `dztools.ini`:
```ini
[UI]
mode=light
stacked_results=true
```

---

### 3. Wiring en main.ps1 — Conectar CheckBox con la preferencia

#### [MODIFY] [`main.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1#L185)

**3a.** Registrar el control (junto a los demás `FindName`):

```powershell
$chkStackedResults = $window.FindName("chkStackedResults")
```

**3b.** Cargar preferencia al iniciar (junto a los toggles de dark mode y debug, ~línea 362):

```powershell
if ($chkStackedResults) { $chkStackedResults.IsChecked = (Get-DzStackedResults) }
```

**3c.** Guardar al cambiar (después del bloque de tglDebugMode, ~línea 400):

```powershell
if ($chkStackedResults) {
    $chkStackedResults.Add_Checked({
        Set-DzStackedResults -Enabled $true
        Write-DzDebug "`t[DEBUG] Resultados apilados: habilitado"
    })
    $chkStackedResults.Add_Unchecked({
        Set-DzStackedResults -Enabled $false
        Write-DzDebug "`t[DEBUG] Resultados apilados: deshabilitado"
    })
}
```

**3d.** Exponer como variable global para que `Show-MultipleResultSets` pueda leerla:

```powershell
$global:chkStackedResults = $chkStackedResults
```

---

### 4. Refactorización — Extraer `New-DzResultDataGrid`

#### [MODIFY] [`Database.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/Database.psm1#L957-L1316)

Crear una función auxiliar **privada** que encapsule la creación del DataGrid. Esto evita duplicar ~350 líneas entre el modo tabs y el modo apilado.

```powershell
function New-DzResultDataGrid {
    param(
        [Parameter(Mandatory)]$ResultSet,
        [Parameter(Mandatory)]$HdrStyle,
        [Parameter(Mandatory)]$RowHdrStyle,
        [Parameter(Mandatory)]$CellStyle,
        [Parameter(Mandatory)]$TextStyleBase,
        $GridBg, $GridFg, $RowAlt, $GridLine
    )

    $dg = New-Object System.Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $true
    $dg.ItemsSource = $ResultSet.DataTable.DefaultView
    $dg.IsReadOnly = $true
    $dg.CanUserAddRows = $false
    $dg.CanUserDeleteRows = $false
    $dg.SelectionUnit = "CellOrRowHeader"
    $dg.SelectionMode = "Extended"
    $dg.HeadersVisibility = "All"
    $dg.GridLinesVisibility = "None"
    # ... (todo el bloque actual de L957-L1316)
    # ... estilos, HorizontalGridLinesBrush, context menu, atajos, auto-sizing, etc.

    return $dg
}
```

Luego, tanto el modo **tabs** como el modo **apilado** llamarán a `New-DzResultDataGrid`:

```powershell
# En el loop foreach ($rs in $ResultSets):
$dg = New-DzResultDataGrid -ResultSet $rs -HdrStyle $hdrStyle `
      -RowHdrStyle $rowHdrStyle -CellStyle $cellStyle `
      -TextStyleBase $textStyleBase -GridBg $gridBg -GridFg $gridFg `
      -RowAlt $rowAlt -GridLine $gridLine
```

---

### 5. Lógica de renderizado — Modo apilado en `Show-MultipleResultSets`

#### [MODIFY] [`Database.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/Database.psm1#L757-L762)

**5a.** Agregar parámetro opcional `-Stacked`:

```diff
 function Show-MultipleResultSets {
     [CmdletBinding()]
     param(
         [Parameter(Mandatory)][System.Windows.Controls.TabControl]$TabControl,
-        [Parameter()][AllowEmptyCollection()][array]$ResultSets = @()
+        [Parameter()][AllowEmptyCollection()][array]$ResultSets = @(),
+        [Parameter()][bool]$Stacked = $false
     )
```

**5b.** Después de la limpieza de pestañas y detección de pestañas fijas (después de línea ~833), agregar la bifurcación del modo apilado:

```powershell
# --- MODO APILADO ---
if ($Stacked -and $ResultSets.Count -gt 0) {
    # Crear contenedor
    $stackPanel = New-Object System.Windows.Controls.StackPanel
    $stackPanel.Orientation = "Vertical"

    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = "Auto"
    $scrollViewer.HorizontalScrollBarVisibility = "Disabled"
    $scrollViewer.Content = $stackPanel

    $totalRows = 0
    $i = 0

    foreach ($rs in $ResultSets) {
        $i++
        $rowCount = if ($rs.RowCount -ne $null) { $rs.RowCount } else { $rs.DataTable.Rows.Count }
        $totalRows += $rowCount

        # --- Encabezado visual del result set ---
        $headerLabel = New-Object System.Windows.Controls.TextBlock
        $headerLabel.Text = "📊 Resultado $i — $rowCount filas"
        $headerLabel.FontWeight = "SemiBold"
        $headerLabel.FontSize = 11
        $headerLabel.Margin = "4,$(if ($i -gt 1) { '12' } else { '4' }),4,4"
        $headerLabel.Foreground = $headerFg
        [void]$stackPanel.Children.Add($headerLabel)

        # --- DataGrid (reutiliza función extraída) ---
        $dg = New-DzResultDataGrid -ResultSet $rs -HdrStyle $hdrStyle `
              -RowHdrStyle $rowHdrStyle -CellStyle $cellStyle `
              -TextStyleBase $textStyleBase -GridBg $gridBg -GridFg $gridFg `
              -RowAlt $rowAlt -GridLine $gridLine
        $dg.MinHeight = 150
        $dg.MaxHeight = 400
        [void]$stackPanel.Children.Add($dg)
    }

    # Crear pestaña única
    $tab = New-Object System.Windows.Controls.TabItem
    $tabHeaderPanel = New-Object System.Windows.Controls.StackPanel
    $tabHeaderPanel.Orientation = "Horizontal"
    $iconText = New-Object System.Windows.Controls.TextBlock
    $iconText.Text = "📊"; $iconText.Margin = "0,0,4,0"; $iconText.FontSize = 10
    $titleText = New-Object System.Windows.Controls.TextBlock
    if ($ResultSets.Count -eq 1) {
        $titleText.Text = "Resultado ($totalRows filas)"
    } else {
        $titleText.Text = "Resultados ($($ResultSets.Count) sets, $totalRows filas)"
    }
    $titleText.FontSize = 10; $titleText.VerticalAlignment = "Center"
    [void]$tabHeaderPanel.Children.Add($iconText)
    [void]$tabHeaderPanel.Children.Add($titleText)
    $tab.Header = $tabHeaderPanel
    $tab.Content = $scrollViewer

    # Insertar antes de pestañas fijas
    if ($permanentTabIndex -ge 0) {
        $TabControl.Items.Insert(0, $tab)
    } else {
        [void]$TabControl.Items.Add($tab)
    }

    # Actualizar lblRowCount
    if ($global:lblRowCount) {
        if ($ResultSets.Count -eq 1) {
            $global:lblRowCount.Text = "📊 $totalRows"
        } else {
            $global:lblRowCount.Text = "📊 $totalRows ($($ResultSets.Count) resultsets)"
        }
    }
    $TabControl.SelectedIndex = 0
    Write-DzDebug "`t[DEBUG][Show-MultipleResultSets] Modo apilado: $($ResultSets.Count) grids en 1 pestaña"
    return
}

# --- MODO TABS (flujo original sin cambios) ---
$i = 0
foreach ($rs in $ResultSets) {
    # ... código existente usando New-DzResultDataGrid ...
}
```

---

### 6. Actualizar invocaciones en QueriesPad.psm1

#### [MODIFY] [`QueriesPad.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/QueriesPad.psm1#L794)

Pasar el estado del CheckBox a `Show-MultipleResultSets`:

```diff
 # Línea 794 (error con resultsets parciales)
-Show-MultipleResultSets -TabControl $global:tcResults -ResultSets $result.ResultSets
+$isStacked = if ($global:chkStackedResults) { $global:chkStackedResults.IsChecked -eq $true } else { $false }
+Show-MultipleResultSets -TabControl $global:tcResults -ResultSets $result.ResultSets -Stacked $isStacked

 # Línea 821 (resultados exitosos)
-try { Show-MultipleResultSets -TabControl $global:tcResults -ResultSets $result.ResultSets } catch {
+$isStacked = if ($global:chkStackedResults) { $global:chkStackedResults.IsChecked -eq $true } else { $false }
+try { Show-MultipleResultSets -TabControl $global:tcResults -ResultSets $result.ResultSets -Stacked $isStacked } catch {

 # Línea 853 (sin resultados — no aplica apilado)
 Show-MultipleResultSets -TabControl $global:tcResults -ResultSets @()
```

> [!NOTE]
> La línea 853 no necesita cambio porque `@()` siempre muestra "La consulta no devolvió resultados" independientemente del modo.

---

## Resumen de archivos modificados

| Archivo | Tipo de cambio | Complejidad |
|---|---|---|
| `src/modules/GUI.psm1` | Agregar 1 CheckBox en XAML | Baja |
| `src/modules/Utilities.psm1` | Agregar 2 funciones + actualizar plantilla INI | Baja |
| `src/main.ps1` | Registrar control + cargar/guardar preferencia | Baja |
| `src/modules/Database.psm1` | Extraer `New-DzResultDataGrid` + agregar modo apilado | **Media-Alta** |
| `src/modules/QueriesPad.psm1` | Pasar parámetro `-Stacked` en 2 invocaciones | Baja |

---

## Consideraciones técnicas

### Altura de los DataGrids apilados

Cuando hay varios result sets apilados, cada DataGrid necesita un alto limitado para que todos sean visibles sin scroll excesivo:

- **`MinHeight = 150`**: suficiente para mostrar ~6-7 filas mínimo
- **`MaxHeight = 400`**: evita que un result set con muchas filas acapare todo el espacio
- El `ScrollViewer` padre permite hacer scroll vertical entre los DataGrids
- Cada `DataGrid` individual mantiene su propio scroll vertical interno

### Compatibilidad

- ✅ PowerShell 5.0 — todos los controles usados (`ScrollViewer`, `StackPanel`, `DataGrid`) son WPF estándar
- ✅ .NET Framework — no se requieren ensamblados adicionales
- ✅ Modo oscuro/claro — reutiliza el mismo sistema de temas existente
- ✅ Context menu — cada DataGrid apilado conserva su menú contextual individual
- ✅ Atajos de teclado — Ctrl+C, Ctrl+Shift+C, Ctrl+A funcionan en el DataGrid enfocado

### Resultado visual esperado

```text
┌─────────────────────────────────────────────┐
│ 📊 Resultados (2 sets, 150 filas)           │  ← Pestaña única
├─────────────────────────────────────────────┤
│ 📊 Resultado 1 — 100 filas                  │  ← Header visual
│ ┌─────────┬─────────┬─────────┐             │
│ │ Col1    │ Col2    │ Col3    │             │
│ ├─────────┼─────────┼─────────┤             │  ← DataGrid 1
│ │ ...     │ ...     │ ...     │             │     (MaxHeight=400)
│ └─────────┴─────────┴─────────┘             │
│                                             │
│ 📊 Resultado 2 — 50 filas                   │  ← Header visual
│ ┌─────────┬─────────┬──────┐                │
│ │ ColA    │ ColB    │ ColC │                │  ← DataGrid 2
│ ├─────────┼─────────┼──────┤                │     (MaxHeight=400)
│ │ ...     │ ...     │ ...  │                │
│ └─────────┴─────────┴──────┘                │
│                               [scroll ↕]    │
├─────────────────────────────────────────────┤
│ 💬 Mensajes │ 🤖 IA │                       │  ← Pestañas fijas
└─────────────────────────────────────────────┘
```

---

## Plan de verificación

### Pruebas manuales

1. **Multi result set apilado**: Ejecutar `SELECT TOP 10 * FROM Tabla1; SELECT TOP 5 * FROM Tabla2` con el check habilitado → verificar que ambos grids aparecen en una sola pestaña
2. **Multi result set en tabs**: Desmarcar el check → misma consulta → verificar que se crean 2 pestañas separadas (comportamiento original)
3. **Result set único**: Ejecutar `SELECT TOP 10 * FROM Tabla1` con check habilitado → solo un grid, sin header redundante
4. **Sin resultados**: Ejecutar `UPDATE ... SET ...` → verificar que sigue mostrando "Filas afectadas: N"
5. **Consulta vacía**: Ejecutar `SELECT TOP 0 * FROM Tabla1` → verificar "La consulta no devolvió resultados"
6. **Persistencia**: Marcar/desmarcar el check → cerrar y abrir la app → verificar que el estado se conservó en `dztools.ini`
7. **Copiar datos**: En modo apilado, hacer Ctrl+C en cada grid individual → verificar que copia correctamente
8. **Context menu**: Click derecho en cada grid apilado → verificar que el menú funciona
9. **Modo oscuro**: Verificar que los DataGrids apilados respetan el tema dark
10. **Scroll**: Con 3+ result sets, verificar que el scroll vertical del contenedor funciona correctamente

### Pruebas automatizadas

```powershell
Invoke-Pester .\tests\ -Output Detailed
```

---

## Orden de implementación

1. Crear funciones `Get-DzStackedResults` y `Set-DzStackedResults` en `Utilities.psm1`
2. Actualizar plantilla por defecto en `Initialize-DzToolsConfig`
3. Agregar CheckBox `chkStackedResults` al XAML en `GUI.psm1`
4. Registrar y conectar el CheckBox en `main.ps1`
5. Extraer función `New-DzResultDataGrid` en `Database.psm1` (refactor)
6. Agregar modo apilado en `Show-MultipleResultSets`
7. Actualizar invocaciones en `QueriesPad.psm1`
8. Pruebas manuales completas
