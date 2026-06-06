# pacdep.ps1 — Automatización de despliegues de soluciones de Dataverse con PAC - v1.0.4

Script PowerShell para exportar e importar soluciones de Dataverse (Power Platform) entre entornos DEV, PRE y PRO usando el CLI `pac`. Automatiza el flujo de despliegue, genera archivos de configuración y valida settings, permitiendo un proceso colaborativo y seguro.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![PAC CLI](https://img.shields.io/badge/PAC%20CLI-1.27%2B-green.svg)](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)

## Inicio Rapido

### Uso frecuente esperado
```bash
# TOP 3 PRINCIPALES

# Despliegue solo a PRE
pwsh ./pacdep.ps1 -TargetEnv pre

# Despliegue solo a PRO
pwsh ./pacdep.ps1 -TargetEnv pro

# Despliegue solo a PRE y a PRO
pwsh ./pacdep.ps1 -TargetEnv both

#OTRAS OPCIONES

# Solo export
pwsh ./pacdep.ps1 -ExportOnly

# Solo export sin incrementar version
pwsh ./pacdep.ps1 -ExportOnly -SkipVersionIncrement

# Solo import a pre
pwsh ./pacdep.ps1 -ImportOnly -TargetEnv pre

# Solo unpack desde solution.zip a carpeta solution/
pwsh ./pacdep.ps1 -UnpackOnly
```

### La primera configuración tendría un flujo similar a este
```bash
# Ubicarse dentro una carpeta para su solución/proyecto.

# Descargar el pacdep.ps1 directo desde github
curl -O https://raw.githubusercontent.com/coviedo194/pacdep/main/pacdep.ps1
# La alternativa, descargarlo manualmente desde Releases: https://github.com/coviedo194/pacdep/releases/latest y luego ubicarlo en el directorio de su proyecto

# Ejecutar para generar config.json. Sería el comando despliegue, en este caso solo a pre
pwsh ./pacdep.ps1 -TargetEnv pre

# Editar config.json con datos reales
# - solutionName: Ajustar el valor por el nombre interno de su solución.
# - authProfile: Definir nombres para los perfiles de conexiones, para cada entorno. Se propone: <cliente><env><usuario>

# Volver a ejecutar "comando de despliegue"
pwsh ./pacdep.ps1 -TargetEnv pre

# Configurar archivos settings En caso de detectarse variables de entorno o referencias de conexiones en la solución, se crearán los archivos de settings_pre/pro.json con la estructura correspondiente a la solución (estandar de pac), y deberán actualizarse de forma manual por el desarrollador. Los ids de conexiones de las ConnectionReferences y valores de las [EnvironmentVariables] pueden copiarse desde la UI de Power Platform de los entornos destinos (PRE/PRO).

# Recomendación: Para algunos suele ser mas fácil, hacer un despliegue inicial manual nativa desde la UI de Power Platform, y luego copiar los valores  de conexiones y variables de las tablas nativas [EnvironmentVariableValue] y [connectionreference] para los proximos despliegues

# 7. Volver a ejecutar "comando de despliegue"
pwsh ./pacdep.ps1 -TargetEnv pre

# (Opcional) Ver la ayuda 
pwsh ./pacdep.ps1

```

## Ejemplo de config.json (autogenerado)

```json
{
  "solutionName": "NombreDeLaSolucion",
  "maxWaitSeconds": 3600,
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

### Configuración de maxWaitSeconds

- **Qué es**: Tiempo máximo de espera (en segundos) para que una importación de solución se complete en el servidor.
- **Valor por defecto**: `3600` (1 hora) - cubre la mayoría de soluciones.
- **Cuándo cambiarlo**:
  - Solución **pequeña** (< 5 min): Cambia a `300` (5 min) para feedback más rápido.
  - Solución **grande** (> 30 min): Cambia a `3600` (1 hora, default) o más.
  - Solución **muy grande** (> 1 hora): Cambia a `7200` (2 horas) o más.
- **Nota**: Si durante la importación falla, el script reintenta automáticamente (hasta 3 veces). No bloquea: solo espera hasta detectar que la solución esté lista.

## Ejemplo de settings_env.json (autogenerado según solución)

```json
{
  "EnvironmentVariables": [
    {
      "SchemaName": "ovg_pacdep_test1",
      "Value": "Hola desde 'pre' "
    }
  ],
  "ConnectionReferences": [
    {
      "LogicalName": "ovg_pacdep_dvtest01",
      "ConnectionId": "12345678901234567890123456789012",
      "ConnectorId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    }
  ]
}
```

---


## ¿Qué hace el script? (pseudocódigo)

```
INICIO (parametros: TargetEnv, ExportOnly, ImportOnly, SkipVersionIncrement, UnpackOnly)
│
├─ [1/9] Verificar pac CLI instalado
│
├─ SI es UnpackOnly:
│   └─ [2/9] pac solution unpack de solution.zip -> solution/ y SALIR
│
├─ [3/9] Validar config.json
│     ├─ Si no existe → generar plantilla de ejemplo y SALIR
│     └─ Validar que no tenga valores de ejemplo en entornos requeridos
│
├─ [4/9] Validar perfiles de autenticacion (pac auth)
│     └─ Si no existe un perfil → preguntar si crearlo
│
├─ [5/9] Limpiar zips anteriores (o validar que existan si es ImportOnly)
│
├─ SI NO es ImportOnly:
│  │
│  ├─ Conectar a DEV (pac auth select)
│  │
│  ├─ [6/9] Incrementar version (4to segmento) en DEV
│  │     └─ pac solution online-version
│  │
│  └─ [7/9] Exportar solucion desde DEV
│        ├─ Exportar unmanaged → solution.zip (respaldo)
│        └─ Exportar managed  → solution_managed.zip (se importa a destino)
│
├─ [8/9] Verificar settings (variables de entorno / conexiones)
│     ├─ Generar settings_generated.json desde solution.zip
│     ├─ Si la solucion no tiene env vars ni conn refs → continuar sin settings
│     ├─ Si es primera vez → copiar plantilla y SALIR (config manual)
│     └─ Comparar ESTRUCTURA (SchemaName / LogicalName) vs. settings existentes
│           └─ Si hay diferencias → mostrar detalle y SALIR
│
├─ SI es ExportOnly → mostrar resumen y SALIR
│
├─ SI destino incluye PRO → pedir confirmacion (Read-Host S/N)
│
├─ [9/9] Importar solucion managed en destino(s)
│     │
│     └─ POR CADA entorno destino (PRE, PRO):
│           │
│           ├─ Conectar al entorno (pac auth select)
│           ├─ Listar soluciones del entorno (pac solution list --json)
│           │
│           ├─ SI la solucion YA EXISTE → modo STAGE AND UPGRADE:
│           │     │
│           │     ├─ Buscar holding huerfano (_Upgrade)
│           │     │     └─ Si existe → ERROR: mostrar instrucciones y SALIR
│           │     │
│           │     └─ pac solution import --stage-and-upgrade --async con reintentos
│           │           (Stage and Upgrade = holding + apply en un solo comando)
│           │
│           └─ SI la solucion NO EXISTE → modo IMPORT DIRECTO:
│                 └─ pac solution import --async con reintentos
│
├─ Mostrar resumen final (solucion, version, duracion)
└─ Recordar hacer commit y push de settings

ERRORES TEMPORALES (se reintentan):
  - "Cannot start another [X] ... running"
  - "timeout" / "timed out" / "tiempo de espera" (multi-idioma)
  - "server busy" / "service unavailable"
  - "try again later"

ERRORES PERMANENTES (se aborta):
  - Dependencias faltantes
  - Version incompatible
  - Cualquier otro error no listado arriba
```

---

## Ficheros generados por el script dentro de la carpeta 

- config.json                       --> configuracion de entornos
- settings_pre.json                 --> settings configurados para PRE
- settings_pro.json                 --> settings configurados para PRO
- settings_generated.json           --> auto-generado, para comparacion
- solution.zip                      --> unmanaged exportado
- solution_managed.zip              --> managed exportado
- solution/                         --> contenido desempaquetado (modo -UnpackOnly)
- logs/
    '-- deploy-YYYY-MM-DD_HH-mm-ss.txt   <-- log por ejecucion

---

## Repo para su proyecto

La propuesta es que luego de haber generado los archivos json (settings y config), incializar un repositio git, y sincronizarlo contra algún repositorio PRIVADO de su cliente-proyecto, para que otros compañeros puedan aprovechar su configuración. Para no sincronizar datos innecesarios, se recomienda generar el .gitignore con este contenido: 

```.gitignore
solution.zip
solution_managed.zip
solution/
settings_generated.json
logs/
.DS_Store
```

Así los ficheros a sincronizarse serían solo:
- pacdep.ps1
- config.json
- settings_pre.json
- settings_pro.json

---

## Requisitos

| Requisito | Minimo |
|-----------|--------|
| PowerShell | pwsh >= 7.0 |
| Power Platform CLI | pac >= 1.27 |
| .NET SDK | >= 6.0 |
| Git | Cualquiera |

---

## Troubleshooting

- Si usas la extensión Power Platform Tools con VS Code y el PAC que se autoinstala te da problemas, desinstalarlo y realizarlo via .NET SDK: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`

---

## Autor y Licencia

Carlos Oviedo Gibbons

[Github/coviedo194](https://github.com/coviedo194)

[LinkedIn/coviedo194](https://www.linkedin.com/in/coviedo194/)

powercreatorpy@outlook.com

MIT — Ver LICENSE

---

> **Agent-ready:** el repo incluye instrucciones estándar para agentes de IA (Agents.md).

---

## Disclaimer

El autor no se hace responsable por daños, perdida de datos o errores derivados del uso.

---

Happy coding!
Maitei! 🇵🇾

---
