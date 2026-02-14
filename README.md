# pacdep.ps1 — Automated Dataverse Solution Deployer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![PAC CLI](https://img.shields.io/badge/PAC%20CLI-1.27%2B-green.svg)](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)

> **Version del script documentada:** `1.0.0`

## Indice

1. [Descripcion General](#descripcion-general)
2. [Inicio Rapido](#inicio-rapido)
3. [Requisitos](#requisitos)
4. [Alcance Funcional (v1.1.0)](#alcance-funcional-v110)
5. [Estructura de Carpetas](#estructura-de-carpetas--repositorio-del-cliente)
6. [Configuracion: config.json](#configuracion-configjson)
7. [Parametros](#parametros)
8. [Ejemplo Completo (datos ficticios)](#ejemplo-completo-datos-ficticios)
9. [Flujo Colaborativo con Git](#flujo-colaborativo-con-git)
10. [Logica de Settings (detalle)](#logica-de-settings-detalle)
11. [Flujo Visual](#flujo-visual)
12. [Consideraciones](#consideraciones)
13. [Restricciones (v1.1.0)](#restricciones-v110)
14. [Historial de Versiones](#historial-de-versiones)
15. [Autor](#autor)
16. [Licencia](#licencia)

---

## Descripcion General

Script PowerShell para automatizar el despliegue de soluciones de Dataverse desde un entorno de **Desarrollo (DEV)** hacia entornos **Pre-produccion (PRE)** y/o **Produccion (PRO)**, utilizando el CLI de Power Platform (`pac`).

Solo necesitas el archivo `pacdep.ps1`. Al ejecutarlo por primera vez, el script genera automaticamente el `config.json` con una plantilla de ejemplo para que configures los datos de tu cliente.

Se trabaja con **una carpeta/repositorio por cada cliente o proyecto**. Cada carpeta contiene su propio `config.json` (entornos/perfiles) y `settings_pre.json` / `settings_pro.json` (variables de entorno y conexiones por entorno). Estos archivos se comparten via **repositorio git** del equipo para que cualquier desarrollador pueda clonar y ejecutar sin tener que reconfigurar desde cero.

---

## Inicio Rapido

```bash
# 1. Crear carpeta para el cliente
mkdir mi-cliente && cd mi-cliente

# 2. Descargar el script
curl -O https://raw.githubusercontent.com/coviedo194/pacdep/main/pacdep.ps1

# 3. Ejecutar (genera config.json con plantilla de ejemplo)
pwsh ./pacdep.ps1

# 4. Editar config.json con los datos reales del cliente

# 5. Desplegar a PRE
pwsh ./pacdep.ps1 -TargetEnv pre
```

> **Nota:** En Windows con PowerShell nativo, usar `.\pacdep.ps1` en lugar de `pwsh ./pacdep.ps1`.

---

## Requisitos

| Requisito | Minimo | Notas |
|-----------|--------|-------|
| **Power Platform CLI (`pac`)** | >= 1.27 | Necesario para `pac auth select --name` y `pac solution online-version` |
| **PowerShell** | >= 5.1 (Windows) o pwsh >= 7.0 (macOS/Linux) | En macOS/Linux usar `pwsh` |
| **.NET SDK** | >= 6.0 | Solo si se instala `pac` como dotnet tool |
| **Git** | Cualquier version | Para clonar/push del repo del cliente (operaciones manuales) |
| **Credenciales** | — | Acceso a los entornos Dataverse (DEV, PRE, PRO) del cliente |

### Instalacion de `pac` (multiplataforma)

```bash
# Como dotnet global tool (Windows, macOS, Linux)
dotnet tool install --global Microsoft.PowerApps.CLI.Tool

# Verificar instalacion
pac --version
```

**macOS / Linux:** asegurar que `~/.dotnet/tools` esta en PATH:

```bash
export PATH="$HOME/.dotnet/tools:$PATH"
```

**VS Code:** tambien se puede instalar desde la extension *Power Platform Tools*.

---

## Alcance Funcional (v1.1.0)

| Paso | Descripcion | Detenciones |
|------|-------------|:-----------:|
| **[1/8] Verificar `pac`** | Comprueba que `pac` esta instalado y accesible en PATH | Error si no |
| **[2/8] Validar `config.json`** | Si no existe, genera plantilla con valores de ejemplo. Valida que los entornos requeridos no tengan valores de ejemplo (PRO se omite si solo se despliega a PRE) | STOP |
| **[3/8] Validar perfiles auth** | Verifica perfiles PAC CLI. Si no existen, ofrece crearlos (login interactivo) | STOP si rechaza |
| **[4/8] Limpiar zips anteriores** | Elimina solution.zip y solution_managed.zip anteriores para evitar confusiones | — |
| **[5/8] Incrementar version** | `pac solution online-version` sube el ultimo segmento directamente en DEV | Error si falla |
| **[6/8] Exportar solucion** | Dos exports: unmanaged (`solution.zip`) + managed (`solution_managed.zip`). Se renombran a nombres fijos | Error si falla |
| **[7/8] Verificar settings** | Genera `settings_generated.json`, compara estructura vs `settings_pre.json` / `settings_pro.json` segun destino | STOP si hay diferencias o es primera vez |
| **[8/8] Importar (upgrade)** | Importa el zip managed como holding y aplica upgrade en PRE/PRO (elimina componentes huerfanos). Usa settings del entorno correspondiente. Pide confirmacion para PRO | STOP si cancela PRO |

---

## Estructura de Carpetas (= Repositorio del Cliente)

```
cliente-proyecto/                     <-- raiz del repo git
|-- pacdep.ps1                        <-- el script
|-- config.json                       <-- configuracion de entornos (commitear)
|-- settings_pre.json                 <-- settings configurados para PRE (commitear)
|-- settings_pro.json                 <-- settings configurados para PRO (commitear)
|-- settings_generated.json           <-- auto-generado, para comparacion (NO commitear)
|-- solution.zip                      <-- unmanaged exportado (NO commitear)
|-- solution_managed.zip              <-- managed exportado (NO commitear)
|-- .gitignore                        <-- excluir zips, logs/, settings_generated
'-- logs/
    '-- deploy-YYYY-MM-DD_HH-mm-ss.txt   <-- log por ejecucion (NO commitear)
```

### `.gitignore` recomendado

```gitignore
solution.zip
solution_managed.zip
logs/
settings_generated.json
.DS_Store
```

### Que va al repo y que no

| Archivo | Commitear | Razon |
|---------|:---------:|-------|
| `pacdep.ps1` | Si | Referencia del script |
| `config.json` | Si | URLs de entornos y nombres de perfiles compartidos |
| `settings_pre.json` | Si | Valores de env vars y conexiones para PRE |
| `settings_pro.json` | Si | Valores de env vars y conexiones para PRO |
| `settings_generated.json` | No | Se regenera en cada ejecucion |
| `solution.zip` | No | Binario, se regenera |
| `solution_managed.zip` | No | Binario, se regenera |
| `logs/*` | No | Locales de cada desarrollador |

---

## Configuracion: `config.json`

Se genera automaticamente en la primera ejecucion. Editarlo con los datos reales:

```json
{
  "solutionName": "NombreDeLaSolucion",
  "dev": {
    "authProfile": "cliente_dev_usuario",
    "env": "https://org-dev.crm.dynamics.com"
  },
  "pre": {
    "authProfile": "cliente_pre_usuario",
    "env": "https://org-pre.crm.dynamics.com"
  },
  "pro": {
    "authProfile": "cliente_pro_usuario",
    "env": "https://org-pro.crm.dynamics.com"
  }
}
```

| Campo | Descripcion |
|-------|-------------|
| `solutionName` | **Unique Name** de la solucion en Dataverse (no el Display Name) |
| `*.authProfile` | Nombre del perfil PAC CLI con formato `<cliente>_<entorno>_<usuario>`. Ejemplo: `microsoft_dev_coviedo` |
| `*.env` | URL del entorno Dataverse (ej: `https://org12345.crm.dynamics.com`) |

> **Formato de authProfile:** `<cliente>_<entorno>_<usuario>` donde:
> - `cliente` = nombre, siglas o abreviatura del cliente (ej: `microsoft`, `msft`)
> - `entorno` = `dev`, `pre` o `pro`
> - `usuario` = abreviatura o inicio del correo del usuario que crea el perfil (ej: `coviedo`)
>
> Esto permite distinguir perfiles entre distintos clientes y usuarios en el mismo equipo.

---

## Parametros

| Parametro | Tipo | Obligatorio | Descripcion |
|-----------|------|:-----------:|-------------|
| `-TargetEnv` | `pre` \| `pro` \| `ambos` | Si* | Entorno destino de importacion |
| `-ExportOnly` | switch | No | Solo exportar (no importar). No requiere `-TargetEnv` |
| `-ImportOnly` | switch | No | Solo importar (no exportar). Requiere `-TargetEnv`. Mutuamente excluyente con `-ExportOnly` |
| `-SkipVersionIncrement` | switch | No | Omitir incremento de version antes de exportar. No tiene efecto con `-ImportOnly` |
| `-ShowHelp` | switch | No | Muestra referencia rapida de comandos y sale. Tambien disponible via `Get-Help .\pacdep.ps1` |

> *`-TargetEnv` es obligatorio excepto con `-ExportOnly`.
>
> **Tres modos de ejecucion:**
> | Modo | Comando | Que hace |
> |------|---------|----------|
> | Completo | `.\pacdep.ps1 -TargetEnv pre` | Export + Import |
> | Solo export | `.\pacdep.ps1 -ExportOnly` | Solo exporta, no necesita `-TargetEnv` |
> | Solo import | `.\pacdep.ps1 -ImportOnly -TargetEnv pre` | Solo importa, requiere zip existente |

---

## Ejemplo Completo (datos ficticios)

Supongamos que trabajamos con el cliente **Contoso**, la solucion se llama `ContosoVentas` y el desarrollador es **coviedo**.

### 1. config.json del cliente

```json
{
  "solutionName": "ContosoVentas",
  "dev": {
    "authProfile": "contoso_dev_coviedo",
    "env": "https://org1a2b3c-dev.crm4.dynamics.com"
  },
  "pre": {
    "authProfile": "contoso_pre_coviedo",
    "env": "https://org1a2b3c-pre.crm4.dynamics.com"
  },
  "pro": {
    "authProfile": "contoso_pro_coviedo",
    "env": "https://org1a2b3c.crm4.dynamics.com"
  }
}
```

### 2. Comandos de ejecucion

```powershell
# --- Primera vez: setup ---

# Genera config.json plantilla (STOP, editar y volver a ejecutar)
.\pacdep.ps1 -TargetEnv pre

# Tras editar config.json: exporta, genera settings (STOP si hay env vars)
.\pacdep.ps1 -TargetEnv pre

# Tras editar settings_pre.json: importa en PRE
.\pacdep.ps1 -TargetEnv pre

# --- Uso habitual ---

# Desplegar a PRE (exporta desde DEV e importa en PRE)
.\pacdep.ps1 -TargetEnv pre

# Desplegar a PRO (pide confirmacion antes de importar)
.\pacdep.ps1 -TargetEnv pro

# Desplegar a PRE y luego a PRO
.\pacdep.ps1 -TargetEnv ambos

# Solo exportar (util para revisar zips sin importar)
.\pacdep.ps1 -ExportOnly

# Solo exportar sin incrementar version (snapshot)
.\pacdep.ps1 -ExportOnly -SkipVersionIncrement

# Solo importar (tras ajustar settings, sin volver a exportar)
.\pacdep.ps1 -ImportOnly -TargetEnv pre
```

### 3. Ejemplo de salida esperada (flujo normal)

```
===============================================
 pacdep.ps1  v1.0.0
 Automated Dataverse Solution Deployer
 Ejecucion: 2026-02-14_10-30-00
===============================================

  Destino:  pre

[1/8] Verificando Power Platform CLI (pac)...
  OK: pac encontrado.

[2/8] Validando config.json...
  OK: Solucion = ContosoVentas

[3/8] Validando perfiles de autenticacion...
  OK: Perfil 'contoso_dev_coviedo' encontrado.
  OK: Perfil 'contoso_pre_coviedo' encontrado.

[4/8] Limpiando exportaciones anteriores...
  OK: Zips anteriores eliminados.

[5/8] Incrementando version de la solucion en DEV...
  OK: Perfil 'contoso_dev_coviedo' encontrado.
  -> Seleccionando perfil 'contoso_dev_coviedo'...
  Version actual: 1.0.0.15
  Nueva version:  1.0.0.16
  OK: Version actualizada en DEV: 1.0.0.15 -> 1.0.0.16

[6/8] Exportando solucion desde DEV...
  Exportando unmanaged...
  OK: /ruta/solution.zip
  Exportando managed...
  OK: /ruta/solution_managed.zip

[7/8] Verificando settings (variables de entorno / conexiones)...
  Comparando estructura del settings configurado vs. exportado...
  OK: Estructura de settings PRE sin cambios.

[8/8] Importando solucion...

  Importando solucion (managed, upgrade) en PRE...
  OK: Perfil 'contoso_pre_coviedo' encontrado.
  -> Seleccionando perfil 'contoso_pre_coviedo'...
  -> Stage: importando como holding solution...
  -> Usando settings-file: settings_pre.json
  -> Aplicando upgrade...
  OK: Upgrade completado en PRE (https://org1a2b3c-pre.crm4.dynamics.com)

===============================================
  PROCESO FINALIZADO CORRECTAMENTE
  Solucion:  ContosoVentas
  Version:   1.0.0.16
  Destino:   pre
  Log:       /ruta/logs/deploy-2026-02-14_10-30-00.txt
===============================================

  RECORDATORIO: Si hubo cambios en settings_pre/pro.json,
  haz commit y push al repo del cliente.
```

### 4. Ejemplo de salida cuando settings cambian (STOP)

```
[7/8] Verificando settings (variables de entorno / conexiones)...
  Comparando estructura de settings PRE vs. exportado...

  ============================================================
  ATENCION: La estructura de settings cambio
  ============================================================

  La solucion en DEV tiene cambios en variables de entorno o
  referencias de conexion respecto a los settings actuales.

  Archivos afectados: settings_pre.json

  Agregados (existen en DEV, faltan en los settings):
      + Variable de entorno: contoso_ApiEndpoint
      + Referencia de conexion: contoso_SharePointConn

  Pasos:
    1. Revisa settings_generated.json (estructura actual)
    2. Actualiza los archivos afectados con los nuevos campos/valores
    3. Ejecuta el script nuevamente
    4. Haz commit y push de los settings al repo
  ============================================================
```

---

## Flujo Colaborativo con Git

### Escenario A: Primer desarrollador (setup inicial)

```
1. Crear carpeta y entrar
   mkdir cliente-proyecto && cd cliente-proyecto

2. Copiar pacdep.ps1 a la carpeta

3. Primera ejecucion → genera config.json plantilla → STOP
   .\pacdep.ps1 -TargetEnv pre

4. Editar config.json con datos reales

5. Segunda ejecucion → exporta, genera settings_pre.json → STOP (si tiene env vars)
   .\pacdep.ps1 -TargetEnv pre

6. Editar settings_pre.json con los valores del entorno PRE

7. Tercera ejecucion → compara estructura OK → importa
   .\pacdep.ps1 -TargetEnv pre

8. Inicializar repo y subir
   git init
   echo "solution.zip\nsolution_managed.zip\nlogs/\nsettings_generated.json\n.DS_Store" > .gitignore
   git add .
   git commit -m "Setup inicial: config + settings_pre"
   git remote add origin <url-repo>
   git push -u origin main
```

### Escenario B: Siguiente desarrollador

```
1. Clonar repo del cliente
   git clone <url-repo> cliente-proyecto
   cd cliente-proyecto

2. Ejecutar directamente → aprovecha config.json y settings_pre.json del repo
   .\pacdep.ps1 -TargetEnv pre

   El script:
   - Valida perfiles auth (los crea si no existen en TU equipo)
   - Exporta desde DEV
   - Genera settings_generated.json
   - Compara estructura con settings_pre.json del repo
   - Si es igual → importa automaticamente usando settings_pre.json
   - Si es diferente → STOP (alguien cambio la solucion en DEV)
```

### Escenario C: Cambios en la solucion (nueva env var o conexion)

```
1. Ejecutar → STOP porque la estructura cambio
   .\pacdep.ps1 -TargetEnv pre

2. Revisar settings_generated.json (estructura nueva, valores vacios)
3. Actualizar settings_pre.json con los nuevos campos
4. Reimportar sin volver a exportar (los zips ya estan generados)
   .\pacdep.ps1 -ImportOnly -TargetEnv pre

5. Commit y push para que el equipo tenga los settings actualizados
   git add settings_pre.json
   git commit -m "Agregar nueva env var XYZ a settings_pre"
   git push
```

---

## Logica de Settings (detalle)

El script **siempre** genera `settings_generated.json` fresco desde el zip exportado. Luego verifica los archivos de settings del entorno destino (`settings_pre.json` y/o `settings_pro.json`):

```
Entorno destino necesita settings?
|
|-- Archivo settings_{env}.json existe?
|   |-- NO  → Copia plantilla, STOP para configuracion manual
|   '-- SI  → Comparar ESTRUCTURA (nombres de env vars y connection refs)
|       |-- IGUALES    → Usar settings_{env}.json para import
|       '-- DIFERENTES → STOP, mostrar que cambio
|
'-- Sin env vars/conexiones → No se necesitan settings, continuar
```

> Cada entorno tiene su propio archivo de settings porque los valores (connection IDs, env var values) son distintos entre PRE y PRO. La comparacion es por **estructura** (nombres), no por valores.

---

## Flujo Visual

```
.\pacdep.ps1 -TargetEnv X [-ExportOnly] [-ImportOnly] [-SkipVersionIncrement]
         |
   [1/8] pac en PATH? ── NO ──> ERROR
         | SI
   [2/8] config.json existe? ── NO ──> Generar plantilla y STOP
         | SI
         |── Valores de ejemplo en entornos requeridos? ── SI ──> STOP
         | NO
   [3/8] Perfiles auth OK? ── NO ──> Crear? ── NO ──> ERROR
         | SI                          | SI
         |<────────────────────────────'
         |
         |── ImportOnly? ── SI ──> [4/8] Validar zips existentes
         |                        (solution_managed.zip debe existir)
         |                        -> saltar a [7/8]
         | NO
   [4/8] Limpiar zips anteriores
         |
   [5/8] Incrementar version en DEV (o -SkipVersionIncrement)
         |
   [6/8] Exportar unmanaged + managed
         |
   [7/8] Generar settings_generated.json
         |
         |── Sin env vars/conexiones ──> continuar
         |
         |── settings_{env}.json NO existe ──> Copiar plantilla, STOP
         |
         |── Estructura DIFERENTE ──> Mostrar cambios, STOP
         |
         |── Estructura OK ──> Usar settings_{env}.json
         |
         |── ExportOnly? ── SI ──> FIN (exportacion lista)
         | NO
         |── Destino PRO? ── SI ──> Confirmar? ── NO ──> CANCELAR
         |                                        | SI
   [8/8] Importar managed (upgrade) en PRE / PRO / AMBOS
         |
    FIN: Log + recordatorio git push
```

---

## Consideraciones

- **Un repo por cliente/proyecto:** cada repositorio es completamente independiente.
- **config.json y settings_pre/pro.json se comparten via git.** Cualquier desarrollador clona y ejecuta sin reconfigurar.
- **Settings por entorno:** cada entorno destino (PRE, PRO) tiene su propio archivo de settings con valores independientes.
- **Los perfiles de autenticacion son locales** (por equipo/usuario). Cada dev crea los suyos al ejecutar por primera vez.
- **La version se incrementa en DEV online** (`pac solution online-version`). +1 en el ultimo segmento por ejecucion.
- **Se importa siempre el zip managed** a PRE/PRO mediante **upgrade** (stage as holding + apply upgrade). Los componentes eliminados de la solucion en DEV se eliminan tambien en destino.
- **Confirmacion para PRO:** se pide confirmacion explicita antes de importar a produccion.
- **Cada ejecucion limpia los zips anteriores** y genera un log en `logs/`.
- **Operaciones git son manuales.** El script no ejecuta comandos git; solo recuerda al final que hagas push si hubo cambios.
- **Validacion de valores de ejemplo:** El script detecta si `authProfile` o `env` aun tienen los valores de la plantilla y se detiene antes de continuar.
- **PRO puede quedar sin configurar** si solo se despliega a PRE. Solo se validan los entornos que se van a usar (DEV siempre, PRE/PRO segun `-TargetEnv`).

---

## Restricciones (v1.1.0)

| Restriccion | Detalle |
|-------------|---------|
| Una solucion por carpeta | Un `config.json` = una solucion |
| Sin aprobaciones ni gates | Flujo directo: exportar → importar. Solo confirmacion para PRO |
| Sin rollback automatico | Si la importacion falla, no se revierte |
| Requiere sesion interactiva | Creacion de perfiles auth requiere login en navegador |
| PAC CLI >= 1.27 | Versiones anteriores no soportan algunos comandos |
| Git manual | El script no hace clone/commit/push |
| Settings por estructura | Solo compara nombres de env vars y conn refs, no valores |

---

## Historial de Versiones

| Version | Fecha | Cambios |
|---------|-------|---------|
| 1.2.0 | 2026-02-14 | Importacion inteligente: detecta si la solucion ya existe en destino (upgrade) o es primera vez (import directo). Correccion de pac version check |
| 1.1.0 | 2026-02-14 | Parametro -ShowHelp: muestra referencia rapida de comandos y sale. Comment-based help para soporte nativo de Get-Help y -?. Ayuda automatica al ejecutar sin parametros |
| 1.0.0 | 2026-02-14 | Version inicial: export dual (managed+unmanaged), version online, validacion pac, perfiles auth, comparacion de settings por estructura, confirmacion PRO, logging, soporte cross-platform, flujo git colaborativo, validacion de valores de ejemplo en config.json, PRO opcional al desplegar solo a PRE, parametro -SkipVersionIncrement, pac auth --environment (depreca --url), settings por entorno (settings_pre/pro.json), zips exportados con nombres fijos (solution.zip / solution_managed.zip), parametro -ImportOnly, parametros en ingles, import via upgrade (holding + apply) |

---

## Autor

**Carlos Oviedo Gibbons** — [@coviedo194](https://github.com/coviedo194)

## Licencia

Este proyecto esta bajo la licencia MIT. Ver [LICENSE](LICENSE) para mas detalles.
