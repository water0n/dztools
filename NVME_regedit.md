# Plan de Trabajo: Automatización de Corrección NVMe (`ForcedPhysicalSectorSizeInBytes`) y Modularización de Herramientas de Registro

## 1. Resumen y Contexto Técnico (Ticket #70199)

En equipos actualizados de Windows 10 a **Windows 11** (o instalaciones limpias de Windows 11 / Windows Server modernos) que utilizan unidades SSD **NVMe / M.2**, el controlador nativo `stornvme` puede reportar un tamaño de sector físico superior a 4 KB (por ejemplo `8192`, `16384` o `32768` bytes).

SQL Server exige un tamaño de sector físico máximo de 4 KB para las operaciones de escritura sincrónica/asincrónica de archivos `.mdf` y `.ldf`. Cuando el driver reporta sectores mayores, la instalación o el arranque de la instancia (por ejemplo `NATIONALSOFT`) falla con síntomas característicos en el `ERRORLOG`:

- Mensajes: `There have been 256 misaligned log IOs which required falling back to synchronous IO` (típicamente sobre `master.mdf`).
- Códigos de error relacionados con tamaño de sector: **5178** / **5179**.
- Excepción de desbordamiento de pila: `Exception c00000fd EXCEPTION_STACK_OVERFLOW`.

### Solución manual documentada que se busca automatizar

- **Ruta del Registro:**
  `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device` *(crear la clave `Parameters` y/o `Device` si no existen).*
- **Valor:**
  - Nombre: `ForcedPhysicalSectorSizeInBytes`
  - Tipo: Cadena múltiple (`REG_MULTI_SZ` / `MultiString`)
  - Dato: `* 4095` *(indica al driver `stornvme` emular sectores de 4 KB para todos los dispositivos NVMe).*
- **Verificación por consola (Administrador):**
  ```cmd
  REG QUERY "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "ForcedPhysicalSectorSizeInBytes"
  ```
- **Requisito final:**
  Reiniciar el equipo para que el driver `stornvme` aplique el parámetro y confirmar con `fsutil fsinfo sectorinfo C:` que el tamaño efectivo reportado sea `4096` bytes.

---

## 2. Decisiones de Diseño Acordadas

1. **Ubicación en la interfaz principal (`tabAplicaciones`):**
   - El nuevo botón compartirá la misma fila actual del botón `LZMAbtnBuscarCarpeta` dentro de la **Columna 1** ([`GUI.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/GUI.psm1#L1455)), ocupando **50% y 50%** del ancho de la columna, ya que ambas herramientas trabajan directamente sobre el Registro de Windows (`regedit`).
2. **Organización modular:**
   - Crear un módulo dedicado: `src/modules/RegistryUtilities.psm1`.
   - Migrar la funcionalidad de **Carpetas LZMA** (`Show-LZMADialog`) desde [`WindowsUtilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/WindowsUtilities.psm1#L2357-L2724) hacia `RegistryUtilities.psm1`, centralizando así las utilidades basadas en Registro.
3. **Alcance del análisis previo y manejo de casos borde:**
   - El paso de análisis evaluará:
     - Versión / Build de Windows.
     - Inventario de discos NVMe y estado del driver `stornvme`.
     - Tamaños de sector reportados por `fsutil fsinfo sectorinfo`.
     - Estado actual de la clave y valor en el Registro (`stornvme\Parameters\Device`).
     - Búsqueda opcional (activada por defecto) de incidencias (`misaligned log IO`, `5178`/`5179`, `EXCEPTION_STACK_OVERFLOW`) en los `ERRORLOG` locales de SQL Server.
   - El botón de corrección solo se habilitará automáticamente cuando el análisis determine que el equipo es **candidato** (o con corrección incompleta).
   - Se incluirá un checkbox **Modo avanzado** dentro del modal para que el técnico pueda forzar la habilitación del botón en casos borde donde decida intervenir manualmente.
4. **Respaldo, reversión y reinicio:**
   - Antes de escribir en el Registro, se generará **obligatoriamente** un respaldo en `C:\Temp\dztools\backups\nvme\` compuesto por un archivo `.reg` nativo (`reg.exe export`) y un archivo de metadata `.json`.
   - El modal incluirá un botón **Revertir / Restaurar** capaz de restaurar el estado exacto previo al cambio.
   - Al aplicar (o restaurar) exitosamente, se ofrecerá un diálogo opcional de confirmación para reiniciar el equipo (`shutdown /r /t 10`).
5. **Alcance del driver (agregado tras revisión):**
   - `ForcedPhysicalSectorSizeInBytes` solo es leído por el driver inbox de Microsoft `stornvme`. Si el NVMe usa otro driver (Intel RST/VMD `iaStorVD`/`iaStorAC`, Samsung `secnvme`, etc.), la corrección **no tiene efecto**. El análisis debe detectarlo (estado `UnsupportedDriver`) y nunca presentar el equipo como "corregido".
6. **Dictamen basado en tamaño de sector, no en versión de Windows:**
   - Equipos Windows Server modernos (p. ej. Server 2022, build 20348 < 22000) también pueden verse afectados. `IsWindows11` / `IsServer` son solo informativos y **no participan** en el dictamen.
   - Solo se evalúan los volúmenes que residen en discos NVMe (se excluyen SATA/USB/virtuales).
7. **Análisis asíncrono:**
   - Todo el Paso 1 (CIM, `Get-PhysicalDisk`, `fsutil` por unidad, lectura de `ERRORLOG`) se ejecuta fuera del hilo de WPF (ver 4.5) para no congelar la ventana.

---

## 3. Mapa de Archivos Impactados

| Estado | Archivo | Propósito / Cambios clave |
|---|---|---|
| `[NEW]` | `src/modules/RegistryUtilities.psm1` | Nuevo módulo (`#requires -Version 5.0`) con `Show-LZMADialog` migrado, motor de análisis NVMe/SQL, respaldo/restauración en Registro, aplicación segura y modal WPF `Show-NvmeRegFixDialog`. |
| `[MODIFY]` | [`src/modules/WindowsUtilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/WindowsUtilities.psm1#L2357-L2724) | Eliminar `Show-LZMADialog` (líneas 2357–2724) y quitar `'Show-LZMADialog'` de `Export-ModuleMember` (líneas 3403–3405). |
| `[MODIFY]` | [`src/modules/GUI.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/GUI.psm1#L1453-L1463) | Reemplazar el botón `LZMAbtnBuscarCarpeta` en línea 1455 por un `Grid` 50%/50% con `LZMAbtnBuscarCarpeta` (izquierda) y `btnNvmeRegFix` (derecha). |
| `[MODIFY]` | [`src/main.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1#L31) | Registrar `"RegistryUtilities.psm1"` en `$modules` (línea **31**) y **eliminar la redefinición duplicada de la línea 977** para que `Start-Application` reutilice la lista de L31 (hoy la de L977 ya está desactualizada: le faltan `CloudBackup`, `AISqlContext` y `AI`). Obtener `$btnNvmeRegFix`, agregarlo a `$buttonsToUpdate`, conectar su evento `Click` y documentar la novedad en `$global:defaultInstructions`. |
| `[MODIFY]` | [`build.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/build.ps1#L62) | Agregar `"RegistryUtilities.psm1"` en la lista de módulos de la plantilla de respaldo (línea 62) y corregir el faltante existente `"CloudBackup.psm1"`. |
| `[NEW]` | `tests/RegistryUtilities.Tests.ps1` | Pruebas unitarias Pester 5 para parsers, matriz de elegibilidad, respaldo/restauración simulada y verificación de migración de `Show-LZMADialog`. |
| `[MODIFY]` | [`tests/Basic.Tests.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/tests/Basic.Tests.ps1#L38-L55) | Ampliar la validación de módulos: hoy solo inspecciona la **primera** coincidencia de `$modules = @(...)` en `main.ps1`. Debe validar **todas** las listas (`[regex]::Matches`) y también la de `build.ps1`. |
| `[MODIFY]` | [`README.md`](file:///C:/Users/water/Documents/githubProyects/dztools/README.md#L55-L183) | Documentar el nuevo módulo `RegistryUtilities.psm1` en la estructura del proyecto y la nueva utilidad NVMe en la sección de características. |

> [!IMPORTANT]
> **Hallazgo clave en `src/main.ps1`:** el listado `$modules` aparece definido **dos veces** ([L31](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1#L31) y [L977](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1#L977) dentro de `Start-Application`) y **ya están desincronizadas** (L977 carece de `CloudBackup`, `AISqlContext`, `AI`; `build.ps1` L62 carece de `CloudBackup`). [`tests/Basic.Tests.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/tests/Basic.Tests.ps1#L38-L75) solo valida la **primera** lista (L31) y que cada función de `Export-ModuleMember` exista en su archivo; **no protege** L977 ni `build.ps1`. Por eso el plan unifica la lista (elimina la redefinición de L977) y amplía el test.

---

## 4. Diseño Técnico de `src/modules/RegistryUtilities.psm1`

El módulo debe iniciar con `#requires -Version 5.0` y mantener estricta compatibilidad con PowerShell 5.0 y las reglas de `PSScriptAnalyzer`.

### 4.1. Sección A — Migración de Carpetas LZMA (`Show-LZMADialog`)

Al revisar [`WindowsUtilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/WindowsUtilities.psm1#L2357-L2724), se confirma que `Show-LZMADialog` es autocontenida respecto a `WindowsUtilities.psm1`: sus helpers `Convert-RegProviderPathToDisplay` y `Get-LzmaInstallerItems` están definidos internamente y solo consume utilidades transversales de `GUI.psm1` (`Get-DzUiTheme`, `New-WpfWindow`, `Set-DzWpfThemeResources`, `Set-WpfDialogOwner`, `Show-WpfMessageBox`, `Show-WpfMessageBoxSafe`) y de `Utilities.psm1` (`Write-DzDebug`).

- **Acción:** Mover el bloque completo de `Show-LZMADialog` sin alterar su firma (`param([array]$Instaladores)`) ni su comportamiento, garantizando cero regresiones para el botón `LZMAbtnBuscarCarpeta`.

### 4.2. Sección B — Motor de Análisis (Funciones puras y de solo lectura)

Diseñado separando la recolección de datos del veredicto lógico para facilitar pruebas unitarias con Pester:

| Función | Responsabilidad | Detalles técnicos clave |
|---|---|---|
| `Get-NvmeOsInfo` | Identificar versión y build de Windows. | Lee `Win32_OperatingSystem` + `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (`CurrentBuildNumber`, `DisplayVersion`, `UBR`). Marca `IsWindows11 = ([int]$Build -ge 22000)`, `IsServer = ($ProductType -ne 1)`. **Son datos informativos para la UI; no intervienen en el dictamen.** |
| `Get-NvmeDiskInfo` | Detectar discos NVMe, **driver que los controla** y estado de `stornvme`. | Consulta `Get-PhysicalDisk` (`BusType -eq 'NVMe'`, `FriendlyName`, `PhysicalSectorSize`, `LogicalSectorSize`) con respaldo en `CIM_DiskDrive` (`PNPDeviceID -match 'NVME'`). Verifica el servicio `HKLM:\SYSTEM\CurrentControlSet\Services\stornvme` (`Start`, existencia) y `Win32_SystemDriver -Filter "Name='stornvme'"`.<br>**Detección de driver:** enumera los controladores NVMe (`Win32_PnPEntity` con `PNPDeviceID -like 'PCI\*CC_0108*'`) y lee su propiedad `Service`; el mapeo disco→controlador se hace por mejor esfuerzo (`DEVPKEY_Device_Parent`). Cada disco expone `DriverService` e `IsStornvme`. Servicios como `iaStorVD`, `iaStorAC` o `secnvme` marcan el disco como **no soportado** por la clave. |
| `ConvertFrom-FsutilSectorInfo` | Parser puro y agnóstico al idioma de la salida de `fsutil`. | Extrae por regex los valores numéricos de:<br>- `LogicalBytesPerSector`<br>- `PhysicalBytesPerSectorForAtomicity`<br>- `PhysicalBytesPerSectorForPerformance`<br>- `FileSystemEffectivePhysicalBytesPerSectorForAtomicity`<br>Soporta separadores de miles o texto local sin depender de etiquetas en inglés/español fuera del nombre del campo técnico de `fsutil`. |
| `Get-NvmeSectorDiagnostics` | Ejecutar `fsutil fsinfo sectorinfo <Unidad>:` **solo para volúmenes en discos NVMe**. | Recorre unidades locales fijas (`DriveType -eq 3` vía `Win32_LogicalDisk`) y, antes de invocar `fsutil`, mapea letra→partición→disco (`Get-Partition -DriveLetter X` → `Get-Disk` → `BusType`), descartando SATA/USB/virtuales para que no contaminen el dictamen. Si no hay elevación Admin, `fsutil` devuelve error de privilegios (`Access is denied` / `Acceso denegado`): captura `RequiresElevation = $true` sin lanzar excepción y usa como **fallback de solo lectura** `PhysicalSectorSize` de `Get-PhysicalDisk` (marcando el origen del dato como `PhysicalDisk`, no `fsutil`). La invocación pasa por el wrapper `Invoke-Fsutil` (ver 4.5). |
| `Get-NvmeRegistryState` | Inspeccionar la clave objetivo en el Registro. | Acepta `-RootPath` (por defecto `HKLM:\SYSTEM\CurrentControlSet\Services\stornvme`) para poder probarse con `TestRegistry:`. Revisa `...\Parameters` y `...\Device`. Determina:<br>- `ParametersKeyExists` (`bool`)<br>- `DeviceKeyExists` (`bool`)<br>- `ValueExists` (`bool`)<br>- `ValueKind` (`MultiString`, `String`, etc.)<br>- `ValueData` (`string[]`)<br>- `Has4095Rule` (`bool`, valida coincidencia con `^\*\s*4095$` o `* 4095` tras trim)<br>- `RawRegQueryOutput` (salida real de `reg.exe query` vía wrapper `Invoke-RegExe`). |
| `Find-SqlMisalignedIoErrors` | Búsqueda opcional en `ERRORLOG` locales de SQL Server. | Descubre las instancias desde `HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL` (y `WOW6432Node`). La ruta real del log se obtiene del parámetro de arranque `-e` (`SQLArgN`) en `HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\<InstanceId>\MSSQLServer\Parameters`, con fallback en `<ruta de instalación>\MSSQL\Log` y `C:\Program Files\Microsoft SQL Server\MSSQL*\MSSQL\Log`.<br>**Lectura:** `ERRORLOG` está en **UTF-16 LE** y SQL Server lo mantiene abierto, por lo que se lee con `FileStream` (`FileMode.Open`, `FileAccess.Read`, `FileShare.ReadWrite`) y `Encoding.Unicode`, tomando **solo las últimas ~2,000 líneas** (cola acotada) de `ERRORLOG` y `ERRORLOG.1`. Busca:<br>- `misaligned log IO`<br>- `5178` / `5179` con contexto de sector/IO<br>- `EXCEPTION_STACK_OVERFLOW` (`c00000fd`). |
| `Test-NvmeSqlFixCandidate` | Función pura de evaluación y dictamen. | Recibe los objetos de SO, discos, sectores, Registro y SQL Logs y retorna un objeto de dictamen con:<br>- `Status`: `'Candidate'`, `'AlreadyAppliedPendingReboot'`, `'AlreadyFixed'`, `'UnsupportedDriver'`, `'NotCandidate'`<br>- `CanApplyByDefault`: `$true` únicamente en `'Candidate'` (o si el tipo de valor existente es incorrecto/corrupto)<br>- `RequiresReboot`: `$true` si ya existe `* 4095` en Registro pero algún volumen NVMe sigue reportando sector > 4096 bytes<br>- `Reasons`: lista ordenada de hallazgos técnicos claros para mostrar en la UI.<br>Es **pura** (sin I/O), por lo que corre en el hilo de UI sobre los datos devueltos por el job. |
| `Invoke-NvmeSystemAnalysis` | Orquestador del Paso 1 del modal. | Ejecuta las funciones anteriores (respetando el parámetro `[-IncludeSqlLogs]`), consolida un objeto integral con tiempos, salidas crudas y dictamen final. |
| `Invoke-Fsutil` / `Invoke-RegExe` *(internas, no exportadas)* | Wrappers delgados sobre `fsutil.exe` y `reg.exe`. | Devuelven `[pscustomobject]@{ ExitCode; Output }`. Permiten simularlos con `Mock` (vía `InModuleScope`) en Pester, ya que `reg.exe` no opera sobre `TestRegistry:`. |

#### Reglas de elegibilidad (`Test-NvmeSqlFixCandidate`)

| Condición evaluada | Estado resultante | ¿Habilita `Aplicar` automático? |
|---|---|---|
| Algún NVMe es controlado por un driver distinto de `stornvme` (`iaStorVD`, `iaStorAC`, `secnvme`, etc.) **y ninguno** lo es por `stornvme` | `UnsupportedDriver` | ❌ **No** *(la clave no tendría efecto; solo Modo avanzado con advertencia explícita)* |
| Existe al menos un NVMe bajo `stornvme` **y** algún **volumen NVMe** reporta `PhysicalBytesPerSectorForAtomicity > 4096` o `PhysicalBytesPerSectorForPerformance > 4096` o `FileSystemEffectivePhysicalBytesPerSectorForAtomicity > 4096` (o `PhysicalSectorSize > 4096` desde `Get-PhysicalDisk` si no hay Admin) **y** NO tiene `* 4095` válido en Registro. Si hay discos mixtos (parte con otro driver) se agrega una advertencia en `Reasons`. | `Candidate` | ✅ **Sí** |
| Tiene `* 4095` válido en Registro (`REG_MULTI_SZ`), pero algún volumen NVMe sigue reportando sector > 4096 bytes | `AlreadyAppliedPendingReboot` | ❌ **No** *(reinicio pendiente; desbloqueable solo con Modo avanzado si se requiere reescribir)* |
| Tiene `* 4095` válido en Registro **y** todos los volúmenes NVMe reportan `<= 4096` bytes | `AlreadyFixed` | ❌ **No** *(ya corregido y activo; Modo avanzado solo para reescribir)* |
| Equipo sin discos NVMe, **o** sectores NVMe ya en 512/4096, **o** hay evidencia en `ERRORLOG` pero **todos** los sectores NVMe son `<= 4096` (puede deberse a VM, SAN u otra causa; se indica en `Reasons`), **o** no hay datos de sector suficientes | `NotCandidate` | ❌ **No** *(desbloqueable solo con **Modo avanzado**)* |

> [!NOTE]
> El dictamen **nunca** usa el número de build de Windows. La evidencia en `ERRORLOG` por sí sola no habilita `Aplicar`: solo refuerza el dictamen cuando además existe un sector > 4096 en un volumen NVMe bajo `stornvme`.

### 4.3. Sección C — Respaldo, Aplicación, Verificación y Restauración

#### ¿Por qué se requiere archivo `.reg` + metadata `.json`?
Al importar un archivo `.reg` mediante `reg import`, Windows sobrescribe o agrega valores existentes, **pero no elimina claves o valores que no existían antes del cambio**. Por ello, cada respaldo en `C:\Temp\dztools\backups\nvme\` debe guardar dos archivos hermanos con el mismo prefijo temporal (ej. `nvme_backup_20261119_141530`):

1. **`nvme_backup_<timestamp>.reg`**: exportado con `reg.exe export`:
   - Si existe `...\stornvme\Parameters\Device`, exporta esa clave.
   - Si `Device` no existía pero sí `...\stornvme\Parameters`, exporta `Parameters`.
2. **`nvme_backup_<timestamp>.json`**: snapshot estructurado en UTF-8 con:
   ```json
   {
     "BackupId": "nvme_backup_20261119_141530",
     "Timestamp": "2026-11-19T14:15:30-06:00",
     "ComputerName": "EQUIPO-POS",
     "UserName": "Administrador",
     "OsBuild": "26100",
     "TargetKey": "HKLM\\SYSTEM\\CurrentControlSet\\Services\\stornvme\\Parameters\\Device",
     "ParametersKeyExisted": true,
     "DeviceKeyExisted": false,
     "ValueExisted": false,
     "PreviousValueType": null,
     "PreviousValueData": [],
      "DriverService": "stornvme",
      "RegExportPath": "C:\\Temp\\dztools\\backups\\nvme\\nvme_backup_20261119_141530.reg",
      "RestoredAt": null
   }
   ```

#### Funciones de escritura y recuperación

- **`Backup-NvmeRegistryState`**:
  - Asegura la existencia de `C:\Temp\dztools\backups\nvme\`.
  - Captura el estado previo exacto, ejecuta `reg.exe export` (si la clave base existe) y guarda el `.json`.
  - Retorna objeto con `Success`, `JsonPath`, `RegPath` y resumen. Si el respaldo falla, la operación de escritura **se aborta**.
- **`Set-NvmePhysicalSectorFix`**:
  1. Valida `Test-Administrator`; si no es administrador, aborta con mensaje claro.
  2. Ejecuta `Backup-NvmeRegistryState` de forma obligatoria.
  3. Crea recursivamente `HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device` si no existe.
  4. Lee el valor actual de `ForcedPhysicalSectorSizeInBytes`:
     - Si ya existía como `MultiString` con otras entradas válidas distintas, **las preserva** y agrega `* 4095` sin duplicar.
     - Si no existía o tenía otro tipo incorrecto, crea/reemplaza el valor como `[Microsoft.Win32.RegistryValueKind]::MultiString` con `@('* 4095')`.
  5. Ejecuta la verificación oficial:
     ```cmd
     REG QUERY "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "ForcedPhysicalSectorSizeInBytes"
     ```
     y valida que el código de salida sea `0` y contenga `* 4095`.
   6. Registra una línea de auditoría (fecha, usuario, equipo, `BackupId`, acción `Apply`) en `C:\Temp\dztools\backups\nvme\nvme_audit.log` y con `Write-DzDebug`.
- **`Get-NvmeRegistryBackups`**:
  - Lista los archivos `nvme_backup_*.json` en `C:\Temp\dztools\backups\nvme\` ordenados del más reciente al más antiguo.
- **`Restore-NvmeRegistryBackup`**:
  1. Valida `Test-Administrator`.
  2. Lee el `.json` seleccionado:
     - Si `ValueExisted -eq $false`: elimina el valor `ForcedPhysicalSectorSizeInBytes`. Adicionalmente, si `DeviceKeyExisted -eq $false` y la clave `Device` no contiene otros valores ni subclaves, elimina la clave `Device` (y `Parameters` solo si `ParametersKeyExisted -eq $false` y quedó vacía).
      - Si `ValueExisted -eq $true`: restaura tipo (`PreviousValueType`) y datos (`PreviousValueData`) desde el `.json`, que es la **única fuente de verdad** de la restauración. El `.reg` **no** se importa automáticamente: queda como respaldo manual de emergencia y su ruta se muestra en el log técnico.
  3. Ejecuta `REG QUERY` posterior para confirmar el estado restaurado.
   4. Si el respaldo elegido no es el más reciente, solicita confirmación previa con `Ui-Confirm` indicando que se sobrescribirá un estado posterior.
   5. Al finalizar escribe `RestoredAt` en el `.json` (los respaldos ya usados se muestran como "(restaurado)" en la lista) y registra la acción `Restore` en `nvme_audit.log`.

### 4.4. `Export-ModuleMember` en `RegistryUtilities.psm1`

Cumpliendo el patrón exigido por [`tests/Basic.Tests.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/tests/Basic.Tests.ps1#L62-L72) (`Export-ModuleMember -Function @(...)`):

```powershell
Export-ModuleMember -Function @(
    'Show-LZMADialog',
    'Get-NvmeOsInfo',
    'Get-NvmeDiskInfo',
    'ConvertFrom-FsutilSectorInfo',
    'Get-NvmeSectorDiagnostics',
    'Get-NvmeRegistryState',
    'Find-SqlMisalignedIoErrors',
    'Test-NvmeSqlFixCandidate',
    'Invoke-NvmeSystemAnalysis',
    'Backup-NvmeRegistryState',
    'Set-NvmePhysicalSectorFix',
    'Get-NvmeRegistryBackups',
    'Restore-NvmeRegistryBackup',
    'Show-NvmeRegFixDialog'
)
```

### 4.5. Ejecución asíncrona y testabilidad

- **Asincronía:** `Invoke-NvmeSystemAnalysis` se ejecuta con `Start-Job` + `DispatcherTimer` (mismo patrón que [`NationalUtilities.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/NationalUtilities.psm1#L628-L636)). El job importa `RegistryUtilities.psm1` por ruta (`$PSScriptRoot`) y devuelve un objeto con los datos crudos; como los objetos regresan deserializados, solo deben usarse propiedades simples. `Test-NvmeSqlFixCandidate` (pura) se evalúa en el hilo de UI. Mientras corre, se aplica la fila 2 de la máquina de estados (5.2).
- **Wrappers:** todo acceso a `fsutil.exe` y `reg.exe` pasa por `Invoke-Fsutil` / `Invoke-RegExe` (internas) para poder simularlos en Pester con `InModuleScope`.
- **Rutas parametrizables:** `Get-NvmeRegistryState`, `Backup-NvmeRegistryState`, `Set-NvmePhysicalSectorFix` y `Restore-NvmeRegistryBackup` aceptan `-RootPath` (clave base en el Registro, por defecto `HKLM:\SYSTEM\CurrentControlSet\Services\stornvme`) y `-BackupRoot` (por defecto `C:\Temp\dztools\backups\nvme`) para ejecutarse sobre `TestRegistry:` y `$TestDrive` sin tocar el sistema real.

---

## 5. Diseño UX/UI del Modal WPF (`Show-NvmeRegFixDialog`)

El modal seguirá exactamente la arquitectura visual de [`Show-FirewallConfigDialog`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/WindowsUtilities.psm1#L2731-L3096) y `Show-LZMADialog`:
- Ventana flotante sin bordes (`WindowStyle="None"`, `AllowsTransparency="True"`, `CornerRadius="12"`).
- Recursos dinámicos de tema vía `Set-DzWpfThemeResources -Window $w -Theme $theme` (soporte completo Light / Dark Mode).
- `HeaderBar` arrastrable con botón `✕` y centrado automático sobre `$global:MainWindow`.
- Dimensiones sugeridas: `Width="780" Height="640"` (con `ScrollViewer` en el área de diagnóstico técnico).

### 5.1. Wireframe del Modal

```text
+----------------------------------------------------------------------------------+
| [|] Corrección NVMe 4KB para SQL Server (Regedit)                          [ ✕ ] |
|     Analiza sectores físicos NVMe/stornvme, respalda y aplica * 4095             |
+----------------------------------------------------------------------------------+
| [!] Banner de advertencia (solo visible si no se ejecuta como Administrador)     |
+----------------------------------------------------------------------------------+
| PASO 1: Análisis del sistema                                                     |
|   [ 🔍 Analizar estado actual ]   [✓] Revisar ERRORLOG de SQL Server             |
|                                                                                  |
|   +------------------+ +------------------+ +------------------+                 |
|   | SO: --           | | Discos NVMe: --  | | Sector fsutil: - |                 |
|   +------------------+ +------------------+ +------------------+                 |
|   +---------------------------------------+ +------------------+                 |
|   | Registro stornvme: --                 | | SQL ERRORLOG: -- |                 |
|   +---------------------------------------+ +------------------+                 |
|                                                                                  |
|   Log técnico (Consolas - salida fsutil, REG QUERY, errores SQL):                |
|   +----------------------------------------------------------------------------+ |
|   | > Presiona "Analizar estado actual" para inspeccionar el equipo...         | |
|   +----------------------------------------------------------------------------+ |
+----------------------------------------------------------------------------------+
| PASO 2: Dictamen de elegibilidad                                                 |
|   +----------------------------------------------------------------------------+ |
|   | Estado: Pendiente de análisis                                              | |
|   | - Ejecuta el Paso 1 para determinar si el equipo es candidato.             | |
|   +----------------------------------------------------------------------------+ |
|   [ ] Modo avanzado (forzar habilitación en casos borde)                         |
+----------------------------------------------------------------------------------+
| [ Estado: Listo. ]                                                               |
| [ 📂 Respaldos ]  [ ↩️ Revertir / Restaurar ]  [ 🛠️ Aplicar corrección ] [Cerrar]|
+----------------------------------------------------------------------------------+
```

### 5.2. Máquina de Estados Progresiva de Botones

| Estado del flujo | `btnAnalyze` | `btnApplyFix` | `chkAdvancedMode` | `btnRestore` |
|---|---|---|---|---|
| **1. Al abrir modal (sin analizar)** | ✅ Habilitado | ❌ Deshabilitado | ❌ Deshabilitado | ✅ Habilitado si existen backups en `C:\Temp\dztools\backups\nvme\` **y** es Admin |
| **2. Analizando** | ❌ Deshabilitado | ❌ Deshabilitado | ❌ Deshabilitado | ❌ Deshabilitado |
| **3. Dictamen: `Candidate` (con Admin)** | ✅ Habilitado | ✅ **Habilitado** | ❌ Opcional / N/A | Según backups existentes |
| **4. Dictamen: `NotCandidate` o `AlreadyAppliedPendingReboot` (con Admin)** | ✅ Habilitado | ❌ Deshabilitado | ✅ **Habilitado** | Según backups existentes |
| **5. `NotCandidate` + `chkAdvancedMode` marcado (con Admin)** | ✅ Habilitado | ✅ **Habilitado** *(con advertencia previa al confirmar)* | ✅ Marcado | Según backups existentes |
| **6. Dictamen: `AlreadyFixed`** | ✅ Habilitado | ❌ Deshabilitado | ✅ Habilitado *(solo si técnico desea reescribir)* | Según backups existentes |
| **7. Sin permisos de Administrador** | ✅ Habilitado *(análisis parcial)* | ❌ **Siempre deshabilitado** | ❌ **Deshabilitado** | ❌ **Siempre deshabilitado** |
| **8. Tras aplicar o restaurar con éxito** | ✅ Habilitado *(re-analiza automáticamente y actualiza estado)* | Según nuevo dictamen | Según nuevo dictamen | ✅ **Habilitado** *(respaldo recién creado disponible)* |

| **9. Dictamen: `UnsupportedDriver`** | ✅ Habilitado | ❌ Deshabilitado | ✅ Habilitado *(advertencia: la clave no tendrá efecto con el driver detectado)* | Según backups existentes |
### 5.3. Flujo de Aplicación y Post-Ejecución

1. Usuario presiona `🛠️ Aplicar corrección`.
2. Se solicita confirmación explícita con `Ui-Confirm` indicando:
   - Clave y valor a modificar (`HKLM\...\stornvme\Parameters\Device` -> `ForcedPhysicalSectorSizeInBytes = * 4095`).
   - Aviso de que si estaba en **Modo avanzado** fuera de dictamen candidato, procede bajo criterio del técnico.
   - Ruta donde se guardará el respaldo automático.
3. Ejecuta `Set-NvmePhysicalSectorFix`:
   - Crea respaldo (`.reg` + `.json`).
   - Escribe el valor `MultiString`.
   - Ejecuta `REG QUERY` y agrega la salida real al panel de log técnico del modal.
4. Re-ejecuta `Invoke-NvmeSystemAnalysis` para refrescar tarjetas y estados de botones (pasa a `AlreadyAppliedPendingReboot` hasta reiniciar).
5. Muestra confirmación informando la ruta del respaldo creado y pregunta mediante `Ui-Confirm` (estilo [`Start-SystemUpdate`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/WindowsUtilities.psm1#L109-L118)):
   > *"La corrección NVMe se aplicó y verificó correctamente. Es necesario reiniciar Windows para que el driver `stornvme` aplique el tamaño de sector de 4 KB. ¿Desea reiniciar el equipo ahora?"*
   - Si el usuario elige **Sí**: ejecuta `shutdown /r /t 10 /c "Reinicio para aplicar emulacion de sector 4KB NVMe para SQL Server"`.
   - Si elige **No**: recuerda reiniciar manualmente antes de instalar o iniciar SQL Server.

---

## 6. Plan de Integración en Botón Compartido (50% / 50%) y Wiring

### 6.1. Cambio XAML en [`src/modules/GUI.psm1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/modules/GUI.psm1#L1453-L1463)

En `MinWidth="1000"` de la ventana principal, cada columna `*` dispone de ~238 px de ancho útil. Al dividir la fila de `LZMAbtnBuscarCarpeta` en dos columnas del **50%**, cada botón tendrá ~116 px en resolución mínima. Para evitar truncamiento del texto, se usarán etiquetas concisas con `Padding="6,6"` y `ToolTip` descriptivos completos:

```diff
                         <StackPanel Grid.Column="1" Margin="0,0,10,0" VerticalAlignment="Top">
                             <Button Content="🔐 Lector DP - Permisos" Name="btnLectorDPicacls" Margin="0,0,0,10" Style="{StaticResource PermissionButtonStyle}"/>
-                            <Button Content="📦 Buscar Instalador LZMA" Name="LZMAbtnBuscarCarpeta" Margin="0,0,0,10" Style="{StaticResource PackageButtonStyle}"/>
+                            <Grid Margin="0,0,0,10">
+                                <Grid.ColumnDefinitions>
+                                    <ColumnDefinition Width="*"/>
+                                    <ColumnDefinition Width="6"/>
+                                    <ColumnDefinition Width="*"/>
+                                </Grid.ColumnDefinitions>
+                                <Button Grid.Column="0"
+                                        Content="📦 LZMA"
+                                        Name="LZMAbtnBuscarCarpeta"
+                                        Padding="6,6"
+                                        ToolTip="Buscar y renombrar instaladores LZMA en el Registro (Advanced Installer)"
+                                        Style="{StaticResource PackageButtonStyle}"/>
+                                <Button Grid.Column="2"
+                                        Content="💾 NVMe 4KB Reg"
+                                        Name="btnNvmeRegFix"
+                                        Padding="6,6"
+                                        ToolTip="Analizar discos NVMe/M.2 y corregir sector físico 4KB en Registro para SQL Server"
+                                        Style="{StaticResource PackageButtonStyle}"/>
+                            </Grid>
                             <Button Content="🌐 Agregar IPs" Name="btnConfigurarIPs" Margin="0,0,0,10" Style="{StaticResource NetworkButtonStyle}"/>
```

*(Nota: se conserva exactamente el atributo `Name="LZMAbtnBuscarCarpeta"` para no romper referencias existentes ni futuras automatizaciones).*

### 6.2. Cambios en [`src/main.ps1`](file:///C:/Users/water/Documents/githubProyects/dztools/src/main.ps1)

1. **Carga de módulos en ambos arreglos:**
   - Línea 31: agregar `"RegistryUtilities.psm1"` en `$modules`.
   - Línea 977 (dentro de `Start-Application`): **eliminar la redefinición de `$modules`** y reutilizar la lista de L31 (verificar que `Start-Application` se ejecuta en el mismo alcance de script). Si se prefiere conservar una lista local, debe ser idéntica a la de L31 (hoy le faltan `CloudBackup`, `AISqlContext` y `AI`) y quedar cubierta por `Basic.Tests.ps1`.
2. **Novedades en `$global:defaultInstructions` (líneas 48–110):**
   - Agregar viñeta descriptiva: `- Se agregó herramienta de diagnóstico y corrección NVMe 4KB (Regedit) para SQL Server`.
3. **Referencia del control (junto a línea 151):**
   ```powershell
   $LZMAbtnBuscarCarpeta = $window.FindName("LZMAbtnBuscarCarpeta")
   $btnNvmeRegFix = $window.FindName("btnNvmeRegFix")
   ```
4. **Arreglo `$buttonsToUpdate` (línea 442):**
   - Añadir `$btnNvmeRegFix` al arreglo (validando antes de asignar `Add_MouseLeave` o manteniendo el formato actual).
5. **Evento Click (junto a líneas 751–755):**
   ```powershell
   $btnNvmeRegFix.Add_Click({
           Write-DzDebug ("`t[DEBUG] Click en 'Corrección NVMe 4KB (Regedit)' - {0}" -f (Get-Date -Format "HH:mm:ss")) -Color DarkYellow
           Write-Host "`n- - - Comenzando el proceso de 'Corrección NVMe 4KB (Regedit)' - - -" -ForegroundColor Magenta
           Show-NvmeRegFixDialog -Owner $window
       })
   ```

---

## 7. Plan de Trabajo por Fases

### Fase 1 — Modularización y Migración LZMA
- [ ] Crear `src/modules/RegistryUtilities.psm1` con encabezado `#requires -Version 5.0` y codificación UTF-8 con BOM (compatible con `Set-Utf8BomFile` en `build.ps1`).
- [ ] Mover `Show-LZMADialog` desde `src/modules/WindowsUtilities.psm1` (L2357–L2724) a `src/modules/RegistryUtilities.psm1`.
- [ ] Retirar `'Show-LZMADialog'` de `Export-ModuleMember` en `src/modules/WindowsUtilities.psm1` y agregarlo en `RegistryUtilities.psm1`.
- [ ] Registrar `"RegistryUtilities.psm1"` en `src/main.ps1` (línea 31), eliminar/sincronizar la lista duplicada de la línea 977 y actualizar `build.ps1` (línea 62, incluyendo el faltante `CloudBackup.psm1`).
- [ ] Verificar que `tests/Basic.Tests.ps1` pase sin errores de módulos ni funciones exportadas.
- [ ] Ampliar `tests/Basic.Tests.ps1` para validar **todas** las listas `$modules` de `main.ps1` y la de `build.ps1`.

### Fase 2 — Motor de Análisis NVMe, `fsutil`, Registro y SQL `ERRORLOG`
- [ ] Implementar `Get-NvmeOsInfo` y `Get-NvmeDiskInfo`.
- [ ] Implementar `ConvertFrom-FsutilSectorInfo` (parser independiente del idioma) y `Get-NvmeSectorDiagnostics`.
- [ ] Implementar `Get-NvmeRegistryState` (lectura de `HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device`).
- [ ] Implementar `Find-SqlMisalignedIoErrors` (escaneo opcional con lectura acotada de últimas líneas).
- [ ] Implementar `Test-NvmeSqlFixCandidate` (matriz de elegibilidad) e `Invoke-NvmeSystemAnalysis`.
- [ ] Detección de driver por controlador NVMe (`stornvme` vs. `iaStorVD`/`iaStorAC`/`secnvme`) y estado `UnsupportedDriver`.
- [ ] Mapeo letra→partición→disco→`BusType` para evaluar `fsutil` solo en volúmenes NVMe, con fallback sin Admin vía `Get-PhysicalDisk`.
- [ ] Lectura de `ERRORLOG` en UTF-16 con `FileShare.ReadWrite` y descubrimiento de ruta por `SQLArg -e`.
- [ ] Wrappers `Invoke-Fsutil` / `Invoke-RegExe` y parámetros `-RootPath` / `-BackupRoot`.

### Fase 3 — Respaldo, Aplicación, Verificación y Reversión
- [ ] Implementar `Backup-NvmeRegistryState` (`.reg` + `.json` en `C:\Temp\dztools\backups\nvme\`).
- [ ] Implementar `Set-NvmePhysicalSectorFix` (validación Admin, respaldo obligatorio, preservación de entradas previas en `REG_MULTI_SZ`, alta de `* 4095`, verificación con `REG QUERY`).
- [ ] Implementar `Get-NvmeRegistryBackups` y `Restore-NvmeRegistryBackup` (restauración de valores o limpieza segura cuando la clave/valor no existía).
- [ ] Auditoría (`nvme_audit.log`), marca `RestoredAt` en el `.json` y advertencia al restaurar un respaldo que no es el más reciente. Restauración basada únicamente en el `.json` (el `.reg` es solo respaldo manual).

### Fase 4 — Interfaz Modal WPF (`Show-NvmeRegFixDialog`)
- [ ] Construir XAML del modal reutilizando estilos y recursos dinámicos (`Set-DzWpfThemeResources`).
- [ ] Implementar máquina de estados para habilitación progresiva de botones (`Analizar` -> `Dictamen` -> `Aplicar` / `Modo avanzado` / `Revertir`).
- [ ] Agregar visor de log técnico en fuente monoespaciada (`Consolas`) y botones para abrir carpeta de respaldos y consultar detalles.
- [ ] Integrar confirmaciones (`Ui-Confirm`) antes de modificar el Registro y diálogo opcional de reinicio al completar.
- [ ] Ejecutar el análisis en `Start-Job` + `DispatcherTimer` (sin bloquear el hilo de WPF) y reflejar el estado "Analizando" en los botones.

### Fase 5 — UI Principal, Wiring y Documentación
- [ ] Actualizar `src/modules/GUI.psm1` para dividir el espacio de `LZMAbtnBuscarCarpeta` en 50%/50% con `btnNvmeRegFix`.
- [ ] Conectar `$btnNvmeRegFix` en `src/main.ps1`.
- [ ] Actualizar `README.md` con el nuevo módulo `RegistryUtilities.psm1` y la funcionalidad NVMe.

### Fase 6 — Pruebas Automatizadas y Validación Manual
- [ ] Crear `tests/RegistryUtilities.Tests.ps1` con Pester 5 (mocks de `Invoke-Fsutil` / `Invoke-RegExe` con `InModuleScope`, `TestRegistry:` / `$TestDrive` vía `-RootPath` / `-BackupRoot`, y textos de `ERRORLOG` en UTF-16).
- [ ] Ejecutar `PSScriptAnalyzer`, `.\build.ps1 -Test` y `Invoke-Pester .\tests\ -Output Detailed`.
- [ ] Realizar pruebas manuales en ventana WPF (Dark Mode, Light Mode, con/sin Admin, botón LZMA y flujo completo NVMe).

---

## 8. Riesgos, Consideraciones Técnicas y Mitigaciones

| Riesgo / Pitfall | Impacto | Mitigación |
|---|---|---|
| `fsutil fsinfo sectorinfo C:` requiere privilegios de Administrador. | Si `dztools` se abre sin elevar, `fsutil` falla con acceso denegado. | Capturar la condición limpiamente en `Get-NvmeSectorDiagnostics`, mostrar banner informativo en el modal y deshabilitar `Aplicar` / `Revertir` sin bloquear el resto del análisis. |
| Desincronización de `$modules` en `main.ps1` (L31 y L977), `build.ps1` o `Export-ModuleMember`. | Falla `tests/Basic.Tests.ps1` o `Show-LZMADialog` / `Show-NvmeRegFixDialog` no se cargan en runtime. | Unificar la lista (eliminar la redefinición de L977), corregir `build.ps1` L62 y ampliar `Basic.Tests.ps1` para validar todas las listas. Verificar con `Invoke-Pester .\tests\Basic.Tests.ps1`. |
| Incompatibilidad con PowerShell 5.0 o warnings/errores en `PSScriptAnalyzer`. | Fallo en CI (`.github/workflows/ci.yml`). | Evitar sintaxis de PS 6/7+ (`??`, ternarios, `-AsHashtable` en `ConvertFrom-Json`), usar verbos aprobados (`Get`, `Test`, `Invoke`, `Backup`, `Set`, `Restore`, `Show`, `Find`, `ConvertFrom`) y ejecutar `Invoke-ScriptAnalyzer` localmente. |
| Lectura lenta o bloqueo de UI al escanear `ERRORLOG` de SQL grandes. | Congelamiento momentáneo del hilo WPF. | Escaneo opcional (Controlado por checkbox), restringido a `ERRORLOG` y `ERRORLOG.1`, leyendo solo la cola acotada (últimas ~2,000 líneas o límite de tamaño por stream). |
| Restaurar un `.reg` no elimina claves/valores creados desde cero. | Una reversión basada solo en `reg import` dejaría `ForcedPhysicalSectorSizeInBytes = * 4095` activo. | Persistir metadata `.json` junto al `.reg` indicando `DeviceKeyExisted` y `ValueExisted`, permitiendo eliminar exactamente lo agregado durante la corrección. |
| Sobrescribir valores previos en `ForcedPhysicalSectorSizeInBytes` (`REG_MULTI_SZ`). | Pérdida de reglas previas si existían configuraciones de otro hardware/software. | Leer el arreglo actual si ya es `MultiString`, conservar líneas previas no duplicadas y anexar `* 4095`. |
| Ancho reducido (50%) en Columna 1 cuando la ventana está en `MinWidth="1000"`. | Texto cortado en botones `LZMAbtnBuscarCarpeta` y `btnNvmeRegFix`. | Etiquetas compactas (`📦 LZMA` y `💾 NVMe 4KB Reg`), `Padding="6,6"` y `ToolTip` descriptivo completo. |
| Codificación de caracteres (acentos y emojis) en Windows PowerShell 5. | Caracteres corruptos en XAML o mensajes si el `.psm1` se guarda como UTF-8 sin BOM. | Guardar `RegistryUtilities.psm1` en **UTF-8 con BOM** (mismo criterio que `Set-Utf8BomFile` en `build.ps1`). |
| El NVMe usa un driver distinto de `stornvme` (Intel RST/VMD, Samsung, etc.). | La clave se escribe pero no tiene efecto; el técnico cree que el problema quedó resuelto. | Detectar el servicio de cada controlador NVMe, dictaminar `UnsupportedDriver` y advertir en el modal. |
| `fsutil` se evalúa sobre unidades que no son NVMe (SATA, USB, virtuales). | Falsos candidatos o `AlreadyFixed` que nunca se alcanza. | Mapear letra→disco→`BusType` y evaluar únicamente volúmenes NVMe. |
| Análisis completo (CIM, `fsutil`, `Get-PhysicalDisk`) tarda varios segundos. | Congelamiento del hilo WPF más allá del `ERRORLOG`. | Ejecutar el Paso 1 en `Start-Job` + `DispatcherTimer` (ver 4.5). |
| `ERRORLOG` está en UTF-16 LE y abierto por SQL Server. | Texto ilegible o error de archivo en uso. | `FileStream` con `FileShare.ReadWrite` y `Encoding.Unicode`; ruta tomada de `SQLArg -e`. |
| Usar el número de build para decidir elegibilidad. | Se excluyen equipos afectados (p. ej. Windows Server 2022, build 20348). | El dictamen se basa solo en tamaño de sector, driver y estado del Registro. |
| Ambigüedad en la restauración (datos del `.json` vs. `reg import`). | Estados inconsistentes tras revertir. | El `.json` es la única fuente de verdad; el `.reg` es solo respaldo manual. |

---

## 9. Verificación y Criterios de Aceptación

### 9.1. Validaciones automatizadas obligatorias (CI local)

```powershell
# 1. Análisis estático (igual que .github/workflows/ci.yml)
Invoke-ScriptAnalyzer -Path ./src/ -Recurse -Severity @('Error','Warning') -Settings ./PSScriptAnalyzerSettings.psd1

# 2. Pruebas Pester completas y script de build
.\build.ps1 -Test
Invoke-Pester .\tests\ -Output Detailed
```

### 9.2. Matriz de pruebas (Unitarias y Manuales)

1. **Migración LZMA (Regresión):**
   - El botón `LZMAbtnBuscarCarpeta` abre correctamente `Show-LZMADialog` desde `RegistryUtilities.psm1` y sigue listando y renombrando claves en `HKLM:\SOFTWARE\WOW6432Node\Caphyon\Advanced Installer\LZMA`.
2. **Parser de `fsutil` (`ConvertFrom-FsutilSectorInfo`):**
   - Parsea correctamente salidas con sectores de `4096`, `8192`, `16384` y `32768`, además de manejar salida vacía o acceso denegado.
3. **Caso Candidato (NVMe bajo `stornvme` + volumen NVMe con sector > 4 KB, sin `* 4095`):**
   - Paso 1 concluye `Candidate`.
   - Botón `Aplicar corrección` se habilita automáticamente.
   - Al aplicar: crea respaldo `.reg` + `.json`, escribe `ForcedPhysicalSectorSizeInBytes` como `REG_MULTI_SZ` con `* 4095`, confirma salida de `REG QUERY` y ofrece diálogo opcional de reinicio.
4. **Caso Ya Aplicado Pendiente de Reinicio:**
   - Existe `* 4095` en Registro, pero `fsutil` aún muestra > 4 KB.
   - Dictamen: `AlreadyAppliedPendingReboot`; botón `Aplicar` deshabilitado por defecto con aviso claro de reinicio pendiente.
5. **Caso No Candidato + Modo Avanzado (ej. Windows 10 o sector ya en 4 KB):**
   - Dictamen: `NotCandidate`; botón `Aplicar` deshabilitado inicialmente.
   - Al marcar `Modo avanzado`, se habilita `Aplicar` tras mostrar advertencia en el modal.
6. **Caso Sin Permisos de Administrador:**
   - Se muestra banner de advertencia; el análisis de Registro/SO funciona en modo solo lectura y los botones `Aplicar` y `Revertir` permanecen bloqueados.
7. **Respaldo y Reversión (`Restore-NvmeRegistryBackup`):**
   - Si antes no existía la clave `Device` o el valor `ForcedPhysicalSectorSizeInBytes`, al revertir elimina el valor (y la clave vacía si fue creada por la herramienta).
   - Si antes existía otro valor previo, restaura exactamente los datos anteriores y lo verifica con `REG QUERY`.
8. **Interfaz WPF (Light / Dark Mode):**
   - El modal y los botones compartidos 50%/50% se visualizan alineados y legibles tanto en `mode=light` como en `mode=dark` a `1000x600`.
9. **Driver no soportado:**
   - Disco NVMe controlado por `iaStorVD` / `secnvme` (simulado): dictamen `UnsupportedDriver`, `Aplicar` deshabilitado y advertencia visible.
10. **Discos mixtos (NVMe + SATA/USB):**
   - Solo los volúmenes NVMe participan en el dictamen; un SATA con sector 512 o un USB no cambian el resultado.
11. **Evidencia en `ERRORLOG` sin sector > 4 KB:**
   - Dictamen `NotCandidate` con razón explícita; `Aplicar` solo con Modo avanzado.
12. **Lectura de `ERRORLOG`:**
   - Archivo UTF-16 LE abierto por otro proceso (`FileShare.ReadWrite`) se lee correctamente; ruta resuelta desde `SQLArg -e`.
13. **Windows Server (build < 22000) con sector > 4 KB:**
   - Dictamen `Candidate` (el build no interviene).
14. **Restauración de un respaldo no reciente:**
   - Muestra confirmación previa, restaura desde el `.json`, marca `RestoredAt` y deja registro en `nvme_audit.log`.
