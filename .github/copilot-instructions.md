# Copilot Instructions — pacdep.ps1

## Regla de análisis automático

Siempre que sea relevante para responder sobre el proceso, revisa el script directamente (pacdep.ps1 y archivos relacionados) sin preguntar al usuario si desea que lo analices. Anticipa posibles causas o comportamientos del código para dar respuestas precisas y útiles.

## Proyecto

**pacdep.ps1** es un script PowerShell que automatiza el despliegue de soluciones de Dataverse (Power Platform) desde un entorno DEV hacia PRE y/o PRO usando el CLI `pac`.

Es una herramienta open source. El usuario descarga únicamente el archivo `pacdep.ps1` y lo coloca en la carpeta de su cliente/proyecto. Al ejecutarlo por primera vez, el script genera automáticamente `config.json` con una plantilla de ejemplo. Cada cliente/proyecto tiene su propia carpeta con una copia del script + archivos de configuración, alojados en un repositorio git independiente del equipo.

**Este repositorio** contiene el script fuente y la documentación. No se clona para usar — solo se descarga el `.ps1`.

## Archivos en este repositorio

| Archivo | Propósito |
|---------|----------|
| `pacdep.ps1` | Script principal. Única pieza que el usuario necesita |
| `README.md` | Documentación completa |
| `LICENSE` | Licencia MIT |
| `.gitignore` | Archivos excluidos del repo |
| `.github/copilot-instructions.md` | Instrucciones para Copilot |

## Archivos en el repositorio del cliente (generados por el script)

| Archivo | Propósito | Se commitea |
|---------|-----------|:-----------:|
| `pacdep.ps1` | Copia del script | Sí |
| `config.json` | URLs de entornos y nombres de perfiles auth (por cliente) | Sí |
| `settings_pre.json` | Valores de env vars y conn refs para PRE | Sí |
| `settings_pro.json` | Valores de env vars y conn refs para PRO | Sí |
| `settings_generated.json` | Generado automáticamente para comparación de estructura | No |
| `README.md` | Documentación de uso, flujos, requisitos | Sí |
| `solution.zip` | Zip unmanaged exportado (respaldo) | No |
| `solution_managed.zip` | Zip managed exportado (se importa a PRE/PRO) | No |
| `logs/*.txt` | Logs de ejecución | No |

## Decisiones de diseño (respetar al modificar)

1. **Versión del script** se declara en dos lugares: header del .ps1 (`# Version: X.Y.Z`) y variable `$ScriptVersion`. Ambos deben coincidir. El README documenta para qué versión aplica.

2. **Git es manual.** El script NO ejecuta comandos git. Solo recuerda al usuario que haga push. Esto es intencional para mantener simplicidad.

3. **Sin aprobaciones ni gates complejos.** El único gate es una confirmación `Read-Host` antes de importar a PRO. No agregar workflows de aprobación.

4. **Settings: comparación por estructura, no por valores.** Se comparan los `SchemaName` de EnvironmentVariables y `LogicalName` de ConnectionReferences entre `settings_pre.json` / `settings_pro.json` (configurados, con valores reales) y `settings_generated.json` (fresco del zip, valores vacíos). Nunca comparar valores. Cada entorno destino tiene su propio archivo de settings.

5. **Siempre se detiene si hay diferencias de estructura o es primera vez con settings.** No ofrecer opción de "continuar de todos modos". El desarrollador debe actualizar el archivo de settings correspondiente manualmente.

6. **Se importa siempre el zip managed** (`_managed.zip`) a PRE/PRO. Si la solucion ya existe en el entorno destino, se usa **upgrade** (import as holding + apply upgrade), lo que elimina componentes huerfanos. Si es la primera vez (la solucion no existe), se usa **import directo**. El script detecta automaticamente cual modo usar. El unmanaged se exporta solo como respaldo.

7. **La versión de la solución se incrementa online** vía `pac solution online-version`, no desempaquetando el zip. Solo se incrementa el 4to segmento (revisión).

8. **Cada ejecución limpia los zips anteriores** (`solution.zip` y `solution_managed.zip`) antes de exportar.

9. **Los perfiles de autenticación (`pac auth`) son locales** por equipo. El script los crea si no existen, pidiendo confirmación. Los nombres de perfil se comparten vía `config.json`. El formato obligatorio es `<cliente>_<entorno>_<usuario>` (ej: `microsoft_dev_coviedo`).

10. **El parámetro `-ExportOnly`** permite exportar sin importar. No requiere `-TargetEnv`.

11. **Validación de valores de ejemplo en config.json.** Antes de continuar, el script verifica que `authProfile` y `env` de los entornos requeridos no contengan los valores de la plantilla generada. Los valores de ejemplo conocidos son: `cliente_dev_usuario`, `cliente_pre_usuario`, `cliente_pro_usuario` (perfiles) y `https://orgdev.crm.dynamics.com`, `https://orgpre.crm.dynamics.com`, `https://orgpro.crm.dynamics.com` (URLs).

12. **Solo se validan los entornos que se van a usar.** DEV se valida salvo en modo `-ImportOnly`. PRE y PRO solo se validan si `-TargetEnv` los incluye. Esto permite que PRO quede sin configurar cuando solo se despliega a PRE.

13. **El parámetro `-SkipVersionIncrement`** permite exportar sin incrementar el número de versión en DEV. Útil para obtener un snapshot del estado actual sin modificar la solución. No tiene efecto con `-ImportOnly`.

14. **`pac auth create` usa `--environment`** en lugar de `--url` (deprecado por PAC CLI).

15. **Los zips exportados usan nombres fijos** (`solution.zip` y `solution_managed.zip`) independientemente del nombre de la solución. Después de cada `pac solution export`, el script renombra el archivo generado por PAC CLI al nombre fijo.

16. **El parámetro `-ImportOnly`** permite importar sin exportar. Requiere `-TargetEnv`. Mutuamente excluyente con `-ExportOnly`. Salta los pasos 4 (limpiar), 5 (versión) y 6 (exportar). Valida que `solution_managed.zip` exista. Si `solution.zip` existe, compara estructura de settings; si no, usa los settings existentes sin comparación.

17. **Todos los parámetros del script están en inglés** (`-TargetEnv`, `-ExportOnly`, `-ImportOnly`, `-SkipVersionIncrement`, `-ShowHelp`).

18. **El parámetro `-ShowHelp`** muestra una referencia rápida de comandos con ejemplos y sale sin ejecutar nada. El script también incluye comment-based help para soporte nativo de `Get-Help` y `-?`. La sección `-ShowHelp` usa `Write-Host` directamente (no `Write-Log`) porque no debe generar archivo de log. Si se ejecuta sin ningún parámetro, muestra la ayuda automáticamente.

## Convenciones de código en el .ps1

- **Sin emojis ni caracteres especiales** en mensajes del script. Usar texto plano ASCII: `OK:`, `ERROR:`, `ATENCION:`, `AVISO:`, `INFO:`.
- **Pasos numerados** `[1/8]`, `[2/8]`, etc. Si se agregan pasos, actualizar la numeración total.
- **`Write-Log`** para toda salida. Nunca usar `Write-Host` o `Write-Output` directamente. Excepcion: `-ShowHelp` usa `Write-Host` porque sale antes de inicializar el log.
- **`Assert-PacSuccess`** después de cada comando `pac` para verificar `$LASTEXITCODE`.
- **Funciones con `param()` block**, no parámetros posicionales.
- **Sin acentos** en strings del script (compatibilidad cross-platform).
- **Separadores visuales** con `# ─────` entre secciones.

## Convenciones del README.md

- Texto en **español sin acentos** (ASCII limpio) para consistencia con el script.
- Incluir sección "Historial de Versiones" al final, actualizar con cada cambio.
- El campo `Version del script documentada` al inicio debe coincidir con `$ScriptVersion`.
- Diagramas de flujo en texto plano (no Mermaid), para que sean legibles en cualquier terminal.

## Dependencias externas

- **Power Platform CLI (`pac`)** >= 1.27 — instalado como `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`
- **PowerShell** >= 5.1 (Windows) o pwsh >= 7.0 (macOS/Linux)
- **.NET SDK** >= 6.0 (para instalar pac como dotnet tool)

## Comandos pac usados

```
pac auth list
pac auth create --name <name> --environment <url>
pac auth select --name <name>
pac solution list
pac solution online-version --solution-name <name> --solution-version <version>
pac solution export --name <name> --path <dir> [--managed] [--overwrite]
pac solution create-settings --solution-zip <zip> --settings-file <file>
pac solution import --path <zip> [--import-as-holding] [--settings-file <file>]
pac solution upgrade --solution-name <name>
```

## Qué NO hacer

- No agregar dependencias adicionales (módulos PS, herramientas externas).
- No automatizar git dentro del script.
- No agregar flujos de aprobación multi-paso.
- No cambiar el flujo para que ignore diferencias de settings.
- No usar `Write-Host` directamente; siempre `Write-Log`.
- No generar archivos .md adicionales por cada cambio (solo actualizar README.md existente).


## Para futuras mejoras

Cuando el usuario pida cambios, considerar:
- Actualizar `$ScriptVersion` y el header del .ps1.
- Actualizar la sección "Historial de Versiones" en README.md.
- Actualizar el conteo de pasos `[N/M]` si se agregan o eliminan pasos.
- Mantener el README sincronizado con el comportamiento real del script.
- Probar mentalmente el flujo completo antes de entregar cambios.

---

**Revisión periódica recomendada:**
Se recomienda realizar revisiones periódicas de todo el proyecto (código y documentación) para detectar y corregir ambigüedades o inconsistencias. Esto ayuda a mantener la calidad y coherencia a lo largo del tiempo, especialmente en proyectos colaborativos o en evolución.
