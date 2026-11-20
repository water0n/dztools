@"
# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nuevo módulo `DzStorage.psm1` con motor SQLite unificado en `C:\Temp\dztools\dztools.db` (reemplaza `dztools.ini` y `Queries.ini`)
- Descarga y verificación SHA256 de `sqlite3.dll` en `C:\Temp\dztools\runtime\` (migrando automáticamente copias previas desde `release\resources\`)
- Cifrado de contraseñas SQL con Windows DPAPI (`CurrentUser` + entropía por servidor) y bandera `needs_reentry`
- Historial de queries sin límite de 100 registros con paginación keyset, búsqueda FTS5 trigrama / `LIKE`, filtros, duración (`duration_ms`), favoritos y limpieza de duplicados
- Persistencia completa de pestañas abiertas (`file_path`, `database_name`, `is_active`) con autoguardado periódico
- Bitácora `audit_log` con captura global WPF filtrada (sin ruido) y eventos enriquecidos en operaciones sensibles, más cola `audit-pending.jsonl` en modo fallback
- Migración automática atómica con `.migrated.bak` redactado, recuperación automática ante corrupción y respaldos rotativos con `VACUUM INTO`
- Suite de pruebas de integración `tests/DzStorage.Tests.ps1`
- Estructura modular del proyecto
- Módulo GUI para creación de formularios
- Módulo Database para operaciones SQL
- GitHub Actions para CI/CD
- Pruebas con Pester

### Changed
- Reorganización del código en módulos
- Mejor manejo de dependencias
- `SqliteOps.psm1` usa `C:\Temp\dztools\runtime\` para el DLL nativo evitando pérdida al actualizar con `dztools.ps1`
- `QueriesPad.psm1` rediseñado para paginación, búsqueda y favoritos sobre SQLite

### Fixed
- Problemas de compatibilidad con PS5.0
- Correcciones de typos y exportaciones duplicadas (`.\NationalSoft`, `$global:lblExecutionTimer`, carga única de módulos en `src\main.ps1`, exports duplicados)

## [0.1.0] - 2024-01-15
### Added
- Proyecto inicial con todas las funcionalidades
- Interfaz gráfica completa
- Conexión a SQL Server
- Herramientas de instalación
- Gestión de impresoras
- Sistema de backup

## Cómo actualizar el changelog

### Added
Para nuevas funcionalidades.

### Changed
Para cambios en funcionalidades existentes.

### Deprecated
Para funcionalidades que serán removidas en versiones futuras.

### Removed
Para funcionalidades removidas.

### Fixed
Para corrección de bugs.

### Security
En caso de vulnerabilidades.
"@ | Out-File -FilePath "CHANGELOG.md" -Encoding UTF8