# Agents.md — pacdep.ps1 Copilot Instructions

## Context

**pacdep.ps1** es un script PowerShell que automatiza el despliegue de soluciones de Dataverse (Power Platform) desde un entorno DEV hacia PRE y/o PRO usando el CLI `pac`.

Es una herramienta open source. El usuario descarga únicamente el archivo `pacdep.ps1` y lo coloca en la carpeta de su cliente/proyecto. Al ejecutarlo por primera vez, el script genera automáticamente `config.json` con una plantilla de ejemplo.

## Key Principles

1. **Automatic Analysis Rule**: Siempre que sea relevante para responder sobre el proceso, revisa el script directamente (`pacdep.ps1` y archivos relacionados) sin preguntar al usuario si desea que lo analices.

2. **Manual Git**: El script NO ejecuta comandos git. Solo recuerda al usuario que haga push. Esto es intencional para mantener simplicidad.

3. **No Complex Gates**: El único gate es una confirmación `Read-Host` antes de importar a PRO. No agregar workflows de aprobación.

4. **Settings Comparison by Structure**: Se comparan los `SchemaName` de EnvironmentVariables y `LogicalName` de ConnectionReferences entre archivos de settings, nunca los valores. Cada entorno destino tiene su propio archivo de settings.

5. **Stop on Differences**: Siempre se detiene si hay diferencias de estructura o es primera vez con settings. No ofrecer opción de "continuar de todos modos".

6. **Managed Zip Import**: Se importa siempre el zip managed (`_managed.zip`) a PRE/PRO. Si la solucion existe en destino → **stage-and-upgrade** (`--stage-and-upgrade`, holding + apply en un solo comando). Si es primera vez → **import directo**.

7. **Version Increment Online**: La versión de la solución se incrementa online vía `pac solution online-version`, no desempaquetando. Solo se incrementa el 4to segmento (revisión).

8. **Clean Zips Per Run**: Cada ejecución limpia los zips anteriores (`solution.zip` y `solution_managed.zip`) antes de exportar.

9. **Local Auth Profiles**: Los perfiles de autenticacion (`pac auth`) son locales por equipo. El script los crea si no existen. Formato obligatorio: `<cliente>_<entorno>_<usuario>` (ej: `microsoft_dev_coviedo`).

10. **ExportOnly Parameter**: permite exportar sin importar. No requiere `-TargetEnv`.

11. **Import-Only Parameter**: permite importar sin exportar. Requiere `-TargetEnv`. Mutuamente excluyente con `-ExportOnly`. Valida que `solution_managed.zip` exista.

12. **Configurable Import Timeout**: El tiempo máximo de espera para importaciones se configura en `config.json` con la clave `maxWaitSeconds` (default: 3600 seg = 1h). Esto permite adaptarse a soluciones muy grandes que tardan más de 30 minutos. Se reintenta automáticamente si falla.

13. **Smart Retry Logic**: Solo reintenta si el error es temporal (timeout, "Cannot start another [Import]...", servidor ocupado). Para errores permanentes (dependencias faltantes, versión incompatible, etc) falla inmediatamente sin reintentos.

## Code Conventions

- **No emojis**: Usar texto plano ASCII: `OK:`, `ERROR:`, `ATENCION:`, `AVISO:`, `INFO:`
- **Numbered Steps**: `[1/8]`, `[2/8]`, etc. Si se agregan pasos, actualizar la numeración total.
- **Write-Log Always**: Nunca `Write-Host` o `Write-Output` directamente. Excepcion: `-ShowHelp` usa `Write-Host` porque sale antes de inicializar el log.
- **Assert After pac**: `Assert-PacSuccess` después de cada comando `pac` para verificar `$LASTEXITCODE`.
- **Functions with param()**: No parámetros posicionales.
- **ASCII Clean**: Sin acentos en strings del script (compatibilidad cross-platform).
- **Visual Separators**: `# ─────` entre secciones.
- **Retry Logic**: Usar `Invoke-PacWithRetry` para comandos pac que puedan fallar por timeouts del servidor. Solo reintenta errores temporales (`Test-IsRetryableError`).

## Documentation Conventions

- Texto en **español sin acentos** (ASCII limpio) para consistencia con el script.
- Diagramas de flujo en texto plano (no Mermaid).
- **Version History**: Gestionar exclusivamente con GitHub Releases. No mantener historial en README.

## File Structure

| Archivo | Propósito | Se commitea |
|---------|-----------|:-----------:|
| `pacdep.ps1` | Script principal | Sí |
| `config.json` | URLs de entornos y nombres de perfiles auth | Sí |
| `settings_pre.json` | Valores de env vars y conn refs para PRE | Sí |
| `settings_pro.json` | Valores de env vars y conn refs para PRO | Sí |
| `settings_generated.json` | Generado para comparación de estructura | No |
| `README.md` | Documentación de uso, flujos, requisitos | Sí |
| `solution.zip` | Zip unmanaged exportado (respaldo) | No |
| `solution_managed.zip` | Zip managed exportado (se importa a PRE/PRO) | No |
| `logs/*.txt` | Logs de ejecucion | No |

## External Dependencies

- **Power Platform CLI (`pac`)** >= 1.27
- **PowerShell** >= 5.1 (Windows) o pwsh >= 7.0 (macOS/Linux)
- **.NET SDK** >= 6.0 (para instalar pac como dotnet tool)

## pac CLI Commands Used

```
pac auth list
pac auth create --name <name> --environment <url>
pac auth select --name <name>
pac solution list
pac solution online-version --solution-name <name> --solution-version <version>
pac solution export --name <name> --path <dir> [--managed] [--overwrite]
pac solution create-settings --solution-zip <zip> --settings-file <file>
pac solution import --path <zip> [--stage-and-upgrade] [--async] [--max-async-wait-time <min>] [--settings-file <file>]
pac solution delete --solution-name <name>
```

## What NOT to Do

- No agregar dependencias adicionales (módulos PS, herramientas externas).
- No automatizar git dentro del script.
- No agregar flujos de aprobación multi-paso.
- No cambiar el flujo para que ignore diferencias de settings.
- No usar `Write-Host` directamente; siempre `Write-Log`.
- No generar archivos .md adicionales por cada cambio (solo actualizar README.md existente).

## Future Improvements

Cuando el usuario pida cambios, preguntar si desea subir la version del script. Si la respuesta es sí, recordar:
- Actualizar `$ScriptVersion` y el header del .ps1.
- Actualizar el conteo de pasos `[N/M]` si se agregan o eliminan pasos.
- Mantener el README sincronizado con el comportamiento real del script.
- Probar mentalmente el flujo completo antes de entregar cambios.
