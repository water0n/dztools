# Gerardo Zermeno Tools (dztools)

[![CI](https://github.com/water0n/dztools/actions/workflows/ci.yml/badge.svg)](https://github.com/water0n/dztools/actions/workflows/ci.yml)

Suite de utilidades para soporte tecnico, administracion de Windows y operaciones comunes con SQL Server. La aplicacion esta construida en PowerShell 5 con interfaz WPF y agrupa herramientas que normalmente se ejecutan por separado: diagnostico del equipo, gestion de conexiones SQL, consultas, respaldos, restauraciones, impresoras, firewall, instaladores y utilidades para entornos NationalSoft.

> Estado del proyecto: beta. Algunas funciones pueden modificar configuraciones del sistema, usuarios locales, firewall, servicios, impresoras o bases de datos. Ejecuta la herramienta solo si entiendes el alcance de la accion que vas a realizar.

## Caracteristicas

### Interfaz principal

- Interfaz grafica WPF para Windows.
- Modo oscuro y modo debug configurables.
- Panel de informacion del equipo con hostname, puertos y estado de red.
- Botones de acceso rapido para herramientas administrativas frecuentes.
- Ventanas de progreso, mensajes y dialogos consistentes en toda la app.

### SQL Server

- Conexion a instancias SQL Server con usuario, contrasena y seleccion de base de datos.
- Carga de conexiones guardadas desde archivos INI compatibles con entornos NationalSoft.
- Explorador de servidor con bases de datos, tablas y columnas.
- Consultas SQL en pestanas multiples.
- Historial de consultas y restauracion de pestanas abiertas.
- Consultas predefinidas para diagnostico y soporte.
- Ejecucion de consultas con multiples result sets.
- Panel de resultados y mensajes.
- Exportacion de resultados a CSV o texto delimitado.
- Deteccion y consulta de puertos SQL.
- Acceso a herramientas relacionadas como SQL Server Management Studio, SQL Server Manager, Database4 y ExpressProfiler cuando estan disponibles.

### Asistente de Inteligencia Artificial (Gemini)

- Integracion nativa con la API de Google Gemini.
- Seleccion automatica del Flash estable mas reciente disponible para la API key, con respaldo en versiones anteriores ante errores de disponibilidad.
- Generacion de consultas SQL a partir de lenguaje natural, analizando el contexto y esquema de tu base de datos.
- Explicacion detallada de consultas complejas de manera automatica.
- Interpretacion y explicacion de mensajes de error de SQL para facilitar el diagnostico.
- Gestion integrada de API Key para mantener tu sesion y datos seguros.

### Operaciones de bases de datos

- Respaldo de bases de datos locales y opcionalmente de bases de datos SQLite asociadas.
- Compresion opcional de respaldos con 7-Zip y contrasena.
- Opcion de subida automatica de los respaldos comprimidos a la nube (Cloudflare R2), con generacion de enlaces directos.
- Restauracion de respaldos con seleccion de rutas logicas.
- Adjuntar bases de datos desde archivos MDF/LDF.
- Separar bases de datos.
- Visualizar tamanos de bases de datos.
- Reparacion de bases de datos.
- Crear, renombrar y eliminar bases de datos desde el explorador.
- Explorador de carpetas del servidor SQL para seleccionar destinos de backup o restore.

### Utilidades de Windows

- Limpieza de archivos temporales.
- Liberador de espacio en disco.
- Actualizacion de datos del sistema.
- Consulta y administracion de adaptadores de red.
- Asignacion de IP fija, IP adicional o regreso a DHCP.
- Configuracion de reglas de firewall de entrada y salida.
- Creacion de usuarios locales como usuario estandar o administrador.
- Limpieza de AnyDesk.
- Consulta de componentes del sistema.
- Diagnostico y correccion de sector fisico NVMe 4KB (`ForcedPhysicalSectorSizeInBytes`) en Registro para SQL Server, con respaldo y reversion.

### Impresoras

- Listado de impresoras instaladas con puerto, driver y estado de comparticion.
- Instalacion de impresoras, incluyendo escenarios por IP.
- Limpieza y reinicio de la cola de impresion.
- Acceso a Printer Tools.

### Instaladores y herramientas portables

- Instalacion y validacion de Chocolatey.
- Busqueda, instalacion y desinstalacion de paquetes Chocolatey.
- Validacion de dependencias como 7-Zip.
- Instalador de SSMS.
- Ejecucion de herramientas portables.
- Busqueda de instaladores LZMA.
- Descarga y expansion de archivos desde la interfaz.

### Utilidades NationalSoft

- Reporte de aplicaciones NationalSoft desde INI.
- Sincronizacion y operaciones con bases de datos locales usando SQLite NSsync.
- Cambio de configuracion OTM entre SQL y DBF.
- Validacion y correccion de permisos en `C:\NationalSoft`.
- Registro y desregistro de DLLs con `regsvr32`.
- Extractor de instaladores.
- Creacion de APK SRM.
- Instaladores NS.
- Monitor de servicios y logs.
- Lector DP / permisos.

## Requisitos

| Componente | Requisito |
| --- | --- |
| Sistema operativo | Windows 10/11 o Windows Server 2016+ |
| PowerShell | Windows PowerShell 5.0 o superior |
| .NET | .NET Framework con soporte WPF |
| SQL Server | Opcional, requerido solo para las funciones SQL |
| Permisos | Administrador para funciones de sistema, firewall, usuarios, impresoras y algunos procesos SQL |

Dependencias recomendadas para desarrollo:

- `PSScriptAnalyzer` 1.22.0+
- `Pester` 5.7.1+

Estas dependencias estan documentadas en `requirements.psd1`.

## Instalacion rapida

Ejecuta PowerShell como administrador y lanza el instalador:

```powershell
irm bit.ly/gdzTools | iex
```

El script descarga la ultima version publicada desde GitHub Releases, la instala en:

```text
C:\temp\dztools\release
```

Despues valida la version local y ejecuta `main.ps1`.

## Instalacion manual

1. Descarga `dztools-release.zip` desde la seccion de releases del repositorio.
2. Extrae el contenido en una carpeta local.
3. Ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\main.ps1
```

Tambien puedes usar `run.bat` dentro del paquete release.

## Uso basico

1. Acepta la advertencia beta al iniciar la herramienta.
2. Revisa el panel de informacion del sistema.
3. Para SQL Server, captura servidor, usuario y contrasena, despues presiona `Conectar`.
4. Selecciona una base de datos o explora el arbol de objetos.
5. Ejecuta consultas con `F5` o desde el boton de ejecucion.
6. Usa los modulos laterales para tareas de Windows, impresoras, instaladores o NationalSoft.

## Estructura del proyecto

```text
dztools/
|-- src/
|   |-- main.ps1
|   |-- run.bat
|   |-- version.json
|   |-- lib/
|   |   `-- AvalonEdit.dll
|   |-- resources/
|   |   `-- SQL.xshd
|   `-- modules/
|       |-- AI.psm1
|       |-- AISqlContext.psm1
|       |-- CloudBackup.psm1
|       |-- Database.psm1
|       |-- DzStorage.psm1
|       |-- GUI.psm1
|       |-- Installers.psm1
|       |-- NationalUtilities.psm1
|       |-- QueriesPad.psm1
|       |-- RegistryUtilities.psm1
|       |-- SqliteOps.psm1
|       |-- SqlOps.psm1
|       |-- SqlTreeView.psm1
|       |-- Utilities.psm1
|       `-- WindowsUtilities.psm1
|-- tests/
|   |-- AiModelSelection.Tests.ps1
|   |-- AISqlContext.Tests.ps1
|   |-- Basic.Tests.ps1
|   |-- DatabaseMarkdown.Tests.ps1
|   |-- DzStorage.Tests.ps1
|   |-- NationalUtilities.Tests.ps1
|   |-- QueriesPad.Tests.ps1
|   `-- RegistryUtilities.Tests.ps1
|-- .github/
|   `-- workflows/
|       `-- ci.yml
|-- build.ps1
|-- tools.ps1
|-- dztools.ps1
|-- requirements.psd1
`-- README.md
```

## Desarrollo

Clona el repositorio:

```powershell
git clone https://github.com/water0n/dztools.git
cd dztools
```

Ejecuta la aplicacion desde codigo fuente:

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\src\main.ps1
```

Ejecuta pruebas:

```powershell
Invoke-Pester .\tests\ -Output Detailed
```

Ejecuta el flujo de pruebas incluido en el script de build:

```powershell
.\build.ps1 -Test
```

Crea un paquete release:

```powershell
.\build.ps1 -Release
```

O especifica version:

```powershell
.\build.ps1 -Release -Version "v260214.1056"
```

## Integracion continua

GitHub Actions ejecuta el flujo definido en `.github/workflows/ci.yml`:

- Analisis con `PSScriptAnalyzer`.
- Validacion de compatibilidad con PowerShell 5.
- Pruebas con Pester.
- Generacion del paquete `release`.
- Publicacion del artefacto `dztools-package`.

## Almacenamiento local (dztools.db)

`dztools` persiste su configuracion, credenciales SQL, historial de queries, pestanas abiertas y bitacora en una base SQLite local ubicada en `C:\Temp\dztools\dztools.db` (reemplazando `dztools.ini` y `Queries.ini`):

- **Runtime nativo (`sqlite3.dll`)**: se descarga de forma externa a `C:\Temp\dztools\runtime\sqlite3.dll` con validacion SHA256 (`.sha256`), manteniendo liviano el paquete `release\`. Guardar el DLL en `runtime\` evita que las actualizaciones con `dztools.ps1` lo eliminen.
- **Migracion automatica**: al detectar `dztools.ini` y/o `Queries.ini`, se importan en una transaccion atomica hacia `dztools.db` y se renombran a `*.migrated.bak` (con las contrasenas SQL redactadas en `dztools.ini.migrated.bak`).
- **Cifrado de credenciales**: las contrasenas SQL se almacenan cifradas por usuario de Windows mediante **DPAPI** (`CurrentUser` + entropia por servidor). Si cambia el usuario o equipo y no pueden descifrarse, se marca `needs_reentry` sin bloquear el arranque.
- **Historial de queries y pestanas**: sin limite de 100 registros; paginacion *keyset* en SQL, busqueda FTS5 trigrama (con respaldo `LIKE`), filtros por servidor/BD/estado/periodo, registro de `duration_ms`, favoritos, eliminacion de duplicados conservando favoritos, y restauracion de pestanas con archivo, base y autoguardado.
- **Bitacora de auditoria (`audit_log`)**: registra acciones relevantes de interfaz (con filtro anti-ruido que omite ventanas de sistema y botones como Cerrar/Cancelar) y eventos enriquecidos para operaciones sensibles (redaccion automatica de secretos). Cuando el modo **DEBUG** esta activo, habilita la pestana **Bitacora** (despues de *SSMS portable*) para consultar `audit_log` en modo solo lectura con filtros por columnas, facetas, rango de fechas y paginacion.
- **Modo fallback**: si falta `sqlite3.dll` (por ejemplo, primer arranque sin red o PowerShell x86), opera en modo INI legible y encola eventos de auditoria en `C:\Temp\dztools\audit-pending.jsonl` para sincronizarlos cuando SQLite vuelva a estar disponible.
- **Respaldos y rollback**: genera copias rotativas semanales con `VACUUM INTO` en `C:\Temp\dztools\backups\db\`. Para volver temporalmente a INIs, cierra `dztools`, respalda/mueve `dztools.db` y restaura `dztools.ini.migrated.bak` y `Queries.ini.migrated.bak` eliminando el sufijo `.migrated.bak`.

## Seguridad y buenas practicas

- Ejecuta respaldos antes de usar operaciones destructivas sobre bases de datos.
- Valida servidor, base de datos y rutas antes de restaurar, separar, adjuntar o eliminar bases.
- Usa una cuenta con permisos minimos suficientes para la tarea.
- Ejecuta como administrador solo cuando la funcion lo requiera.
- Revisa los logs y mensajes de progreso antes de cerrar procesos largos.
- No publiques archivos de configuracion con credenciales reales.

## Roadmap

- Mejorar cobertura de pruebas automatizadas.
- Documentar capturas de pantalla por modulo.
- Agregar exportacion avanzada de bitacora (`audit_log`).
- Refinar empaquetado y publicacion de releases.
- Incorporar exportacion avanzada de resultados.
- Fortalecer validaciones antes de operaciones destructivas.

## Contribuir

1. Crea un fork del repositorio.
2. Crea una rama descriptiva:

```powershell
git checkout -b feature/nueva-funcion
```

3. Realiza tus cambios.
4. Ejecuta pruebas y analisis antes de abrir el pull request.
5. Envia un pull request contra `develop` o la rama indicada por el mantenedor.

## Autor

Desarrollado y mantenido por Gerardo Zermeno (`water0n`).

Repositorio: <https://github.com/water0n/dztools>
