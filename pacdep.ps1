# =============================================================================
# pacdep.ps1 - Automated Dataverse Solution Deployer
# Version: 1.0.1
# Autor: Carlos Oviedo Gibbons (github.com/coviedo194)
# Licencia: MIT
# Descripcion: Exporta una solucion de Dataverse desde DEV e importa a PRE/PRO
# Requisitos: Power Platform CLI (pac) >= 1.27 | PowerShell >= 5.1 / pwsh 7+
# Plataformas: Windows, macOS, Linux (via pwsh + pac dotnet tool)
# Repo: https://github.com/coviedo194/pacdep
# =============================================================================

<#
.SYNOPSIS
    Automated Dataverse Solution Deployer.

.DESCRIPTION
    Exporta una solucion de Dataverse desde DEV (managed + unmanaged)
    e importa el zip managed a PRE y/o PRO usando el CLI pac.

.PARAMETER TargetEnv
    Entorno destino: pre, pro o both.

.PARAMETER ExportOnly
    Solo exportar desde DEV, no importar.

.PARAMETER ImportOnly
    Solo importar a destino, no exportar. Requiere -TargetEnv.

.PARAMETER SkipVersionIncrement
    No incrementar la version antes de exportar.

.PARAMETER ShowHelp
    Muestra ejemplos de uso y sale.

.EXAMPLE
    .\pacdep.ps1 -TargetEnv pre
    Exporta desde DEV e importa en PRE.

.EXAMPLE
    .\pacdep.ps1 -TargetEnv pro
    Exporta desde DEV e importa en PRO (pide confirmacion).

.EXAMPLE
    .\pacdep.ps1 -TargetEnv both
    Exporta desde DEV e importa en PRE y luego en PRO.

.EXAMPLE
    .\pacdep.ps1 -ExportOnly
    Solo exporta desde DEV, no importa en ningun entorno.

.EXAMPLE
    .\pacdep.ps1 -ExportOnly -SkipVersionIncrement
    Exporta sin incrementar version (snapshot).

.EXAMPLE
    .\pacdep.ps1 -ImportOnly -TargetEnv pre
    Importa zips existentes en PRE sin exportar.

.EXAMPLE
    .\pacdep.ps1 -ShowHelp
    Muestra referencia rapida de comandos.
#>

param(
    # Target environment (required except with -ExportOnly)
    [ValidateSet("pre", "pro", "both")]
    [string]$TargetEnv,

    # Export only, do not import
    [switch]$ExportOnly,

    # Import only, skip export and version increment
    [switch]$ImportOnly,

    # Skip version increment before export
    [switch]$SkipVersionIncrement,

    # Show usage examples and exit
    [switch]$ShowHelp
)

$ScriptVersion = "1.0.1"

# ─────────────────────────────────────────────────────────────────────────────
# SHOW HELP
# ─────────────────────────────────────────────────────────────────────────────
# Si no se paso ningun parametro, mostrar ayuda automaticamente
if (-not $ShowHelp -and -not $TargetEnv -and -not $ExportOnly -and -not $ImportOnly) {
    $ShowHelp = $true
}

if ($ShowHelp) {
    Write-Host ""
    Write-Host "  pacdep.ps1  v$ScriptVersion  -  Referencia Rapida" -ForegroundColor Cyan
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  COMANDOS DE EJEMPLO:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Desplegar a PRE (exporta desde DEV e importa en PRE):"
    Write-Host "      .\pacdep.ps1 -TargetEnv pre" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Desplegar a PRO (pide confirmacion antes de importar):"
    Write-Host "      .\pacdep.ps1 -TargetEnv pro" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Desplegar a PRE y luego a PRO:"
    Write-Host "      .\pacdep.ps1 -TargetEnv both" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Solo exportar (no importar):"
    Write-Host "      .\pacdep.ps1 -ExportOnly" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Solo exportar sin incrementar version (snapshot):"
    Write-Host "      .\pacdep.ps1 -ExportOnly -SkipVersionIncrement" -ForegroundColor Green
    Write-Host ""
    Write-Host "    Solo importar (usa zips existentes, no exporta):"
    Write-Host "      .\pacdep.ps1 -ImportOnly -TargetEnv pre" -ForegroundColor Green
    Write-Host ""
    Write-Host "  PARAMETROS:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    -TargetEnv <pre|pro|both>    Entorno destino"
    Write-Host "    -ExportOnly                   Solo exportar, no importar"
    Write-Host "    -ImportOnly                   Solo importar, no exportar"
    Write-Host "    -SkipVersionIncrement          No incrementar version"
    Write-Host "    -ShowHelp                      Mostrar esta ayuda"
    Write-Host ""
    Write-Host "  Tambien disponible: Get-Help .\pacdep.ps1 -Detailed"
    Write-Host ""
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# RUTAS
# ─────────────────────────────────────────────────────────────────────────────
$configPath = Join-Path $PSScriptRoot "config.json"
$logsDir = Join-Path $PSScriptRoot "logs"
$settingsFilePre = Join-Path $PSScriptRoot "settings_pre.json"
$settingsFilePro = Join-Path $PSScriptRoot "settings_pro.json"
$settingsGenerated = Join-Path $PSScriptRoot "settings_generated.json"
$unmanagedZip = Join-Path $PSScriptRoot "solution.zip"
$managedZip = Join-Path $PSScriptRoot "solution_managed.zip"

# ─────────────────────────────────────────────────────────────────────────────
# CREAR CARPETAS
# ─────────────────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

# ─────────────────────────────────────────────────────────────────────────────
# LOG
# ─────────────────────────────────────────────────────────────────────────────
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logsDir "deploy-$timestamp.txt"

function Write-Log {
    param(
        [string]$Message,
        [string]$Color
    )
    if ($Color) {
        Write-Host $Message -ForegroundColor $Color
    }
    else {
        Write-Host $Message
    }
    Add-Content -Path $logFile -Value $Message
}

# ─────────────────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "==============================================="
Write-Log " pacdep.ps1  v$ScriptVersion"
Write-Log " Automated Dataverse Solution Deployer"
Write-Log " Ejecucion: $timestamp"
Write-Log "==============================================="
Write-Log ""

# ─────────────────────────────────────────────────────────────────────────────
# VALIDAR PARAMETROS
# ─────────────────────────────────────────────────────────────────────────────
if ($ExportOnly -and $ImportOnly) {
    Write-Log "ERROR: -ExportOnly y -ImportOnly son mutuamente excluyentes."
    exit 1
}

if (-not $ExportOnly -and -not $TargetEnv) {
    Write-Log "ERROR: -TargetEnv es obligatorio (excepto con -ExportOnly)."
    Write-Log "   Uso: .\pacdep.ps1 -TargetEnv <pre|pro|both>"
    Write-Log "   Uso: .\pacdep.ps1 -ExportOnly"
    Write-Log "   Uso: .\pacdep.ps1 -ImportOnly -TargetEnv <pre|pro|both>"
    exit 1
}

if ($ImportOnly -and $SkipVersionIncrement) {
    Write-Log "AVISO: -SkipVersionIncrement no tiene efecto con -ImportOnly."
}

if ($TargetEnv) { Write-Log "  Destino:  $TargetEnv" }
if ($ExportOnly) { Write-Log "  Modo:     Solo exportacion" }
if ($ImportOnly) { Write-Log "  Modo:     Solo importacion" }
if ($SkipVersionIncrement -and -not $ImportOnly) { Write-Log "  Version:  Sin incrementar" }
Write-Log ""

# Booleans de destino (evita repetir el patron TargetEnv -eq "pre" -or "both")
$deployPre = $TargetEnv -eq "pre" -or $TargetEnv -eq "both"
$deployPro = $TargetEnv -eq "pro" -or $TargetEnv -eq "both"

# Cronometro de ejecucion
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ─────────────────────────────────────────────────────────────────────────────
# VALIDAR PAC CLI
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "[1/8] Verificando Power Platform CLI (pac)..."
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: 'pac' no encontrado en PATH."
    Write-Log "   Instalar: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
    Write-Log "   O usar la extension 'Power Platform Tools' en VS Code."
    exit 1
}
$pacVersion = (pac 2>&1 | Select-String -Pattern "Version" | Select-Object -First 1) -replace '.*Version:\s*', ''
if ($pacVersion) {
    Write-Log "  OK: pac encontrado (v$pacVersion)"
}
else {
    Write-Log "  OK: pac encontrado."
}
Write-Log ""

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Verificar exit code de pac
# ─────────────────────────────────────────────────────────────────────────────
function Assert-PacSuccess {
    param([string]$StepDescription)
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR en: $StepDescription (exit code: $LASTEXITCODE)"
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Extraer identificadores de estructura de un settings JSON
# Compara SchemaName de EnvironmentVariables y LogicalName de ConnectionReferences
# ─────────────────────────────────────────────────────────────────────────────
function Get-SettingsStructure {
    param([string]$FilePath)

    $result = @{ EnvVars = @(); ConnRefs = @() }
    try {
        $json = Get-Content $FilePath -Raw | ConvertFrom-Json

        if ($json.EnvironmentVariables) {
            $result.EnvVars = @($json.EnvironmentVariables | ForEach-Object {
                    if ($_.SchemaName) { $_.SchemaName }
                } | Sort-Object)
        }
        if ($json.ConnectionReferences) {
            $result.ConnRefs = @($json.ConnectionReferences | ForEach-Object {
                    if ($_.LogicalName) { $_.LogicalName }
                } | Sort-Object)
        }
    }
    catch {
        Write-Log "  AVISO: No se pudo parsear $FilePath como JSON."
    }
    return $result
}

function Compare-SettingsStructure {
    param([string]$ConfiguredFile, [string]$GeneratedFile)

    $configured = Get-SettingsStructure $ConfiguredFile
    $generated = Get-SettingsStructure $GeneratedFile

    $added = @()
    $removed = @()

    # Comparar EnvironmentVariables
    $envDiff = Compare-Object $configured.EnvVars $generated.EnvVars -ErrorAction SilentlyContinue
    if ($envDiff) {
        foreach ($d in $envDiff) {
            if ($d.SideIndicator -eq "=>") { $added += "  + Variable de entorno: $($d.InputObject)" }
            if ($d.SideIndicator -eq "<=") { $removed += "  - Variable de entorno: $($d.InputObject)" }
        }
    }

    # Comparar ConnectionReferences
    $connDiff = Compare-Object $configured.ConnRefs $generated.ConnRefs -ErrorAction SilentlyContinue
    if ($connDiff) {
        foreach ($d in $connDiff) {
            if ($d.SideIndicator -eq "=>") { $added += "  + Referencia de conexion: $($d.InputObject)" }
            if ($d.SideIndicator -eq "<=") { $removed += "  - Referencia de conexion: $($d.InputObject)" }
        }
    }

    return @{ Added = $added; Removed = $removed; HasDifferences = ($added.Count -gt 0 -or $removed.Count -gt 0) }
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDAR / GENERAR config.json
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "[2/8] Validando config.json..."
if (-Not (Test-Path $configPath)) {
    $template = [ordered]@{
        solutionName = "MiSolucion"
        dev          = [ordered]@{ authProfile = "cliente_dev_usuario"; env = "https://orgdev.crm.dynamics.com" }
        pre          = [ordered]@{ authProfile = "cliente_pre_usuario"; env = "https://orgpre.crm.dynamics.com" }
        pro          = [ordered]@{ authProfile = "cliente_pro_usuario"; env = "https://orgpro.crm.dynamics.com" }
    } | ConvertTo-Json -Depth 3
    $template | Out-File $configPath -Encoding UTF8
    Write-Log "  ATENCION: Se genero config.json con valores de ejemplo." -Color Yellow
    Write-Log "   1. Edita config.json con los datos reales del cliente." -Color Yellow
    Write-Log "   2. Vuelve a ejecutar el script." -Color Yellow
    Write-Log ""
    Write-Log "  INFO: Formato de authProfile: <cliente>_<entorno>_<usuario>"
    Write-Log "         Ejemplo: microsoft_dev_coviedo"
    Write-Log "  INFO: Para ver perfiles existentes: pac auth list"
    exit 0
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$solutionName = $config.solutionName

if (-not $solutionName -or $solutionName -eq "MiSolucion") {
    Write-Log "  ATENCION: 'solutionName' en config.json tiene el valor de ejemplo." -Color Yellow
    Write-Log "   Edita config.json con el Unique Name real de la solucion." -Color Yellow
    exit 0
}

# Validar que los entornos requeridos no tengan valores de ejemplo
$exampleProfiles = @("cliente_dev_usuario", "cliente_pre_usuario", "cliente_pro_usuario")
$exampleUrls = @("https://orgdev.crm.dynamics.com", "https://orgpre.crm.dynamics.com", "https://orgpro.crm.dynamics.com")

# DEV se necesita salvo en modo -ImportOnly. PRE/PRO solo si se van a usar.
$requiredEnvs = @()
if (-not $ImportOnly) { $requiredEnvs += "dev" }
if (-not $ExportOnly) {
    if ($deployPre) { $requiredEnvs += "pre" }
    if ($deployPro) { $requiredEnvs += "pro" }
}

$configErrors = @()
foreach ($envKey in $requiredEnvs) {
    $envConfig = $config.$envKey
    $label = $envKey.ToUpper()

    if (-not $envConfig.authProfile -or $exampleProfiles -contains $envConfig.authProfile) {
        $configErrors += "  - $label : authProfile tiene valor de ejemplo ('$($envConfig.authProfile)')"
    }
    if (-not $envConfig.env -or $exampleUrls -contains $envConfig.env) {
        $configErrors += "  - $label : env tiene valor de ejemplo ('$($envConfig.env)')"
    }
}

if ($configErrors.Count -gt 0) {
    Write-Log "  ATENCION: config.json tiene valores de ejemplo en entornos requeridos:" -Color Yellow
    foreach ($err in $configErrors) { Write-Log $err -Color Yellow }
    Write-Log ""
    Write-Log "  Edita config.json con los datos reales antes de continuar." -Color Yellow
    Write-Log "  Formato de authProfile: <cliente>_<entorno>_<usuario>" -Color Yellow
    Write-Log "  Ejemplo: microsoft_dev_coviedo" -Color Yellow
    exit 0
}

Write-Log "  OK: Solucion = $solutionName"
Write-Log ""

# ─────────────────────────────────────────────────────────────────────────────
# FUNCIONES DE AUTENTICACION
# ─────────────────────────────────────────────────────────────────────────────
function Test-AuthProfile {
    param([string]$ProfileName, [string]$EnvUrl)
    $profiles = pac auth list 2>&1 | Out-String
    if ($profiles -notmatch [regex]::Escape($ProfileName)) {
        Write-Log "  AVISO: El perfil '$ProfileName' no existe." -Color Yellow
        $confirm = Read-Host "     Deseas crearlo con URL '$EnvUrl'? (S/N)"
        if ($confirm -eq "S" -or $confirm -eq "s") {
            Write-Log "     Creando perfil '$ProfileName'..."
            pac auth create --name $ProfileName --environment $EnvUrl
            Assert-PacSuccess "Crear perfil '$ProfileName'"
            Write-Log "     OK: Perfil '$ProfileName' creado."
        }
        else {
            Write-Log "  ERROR: Perfil '$ProfileName' requerido. Ejecucion abortada."
            exit 1
        }
    }
    else {
        Write-Log "  OK: Perfil '$ProfileName' encontrado."
    }
}

function Select-AuthProfile {
    param([string]$ProfileName, [string]$EnvUrl)
    Test-AuthProfile $ProfileName $EnvUrl
    Write-Log "  -> Seleccionando perfil '$ProfileName'..."
    pac auth select --name $ProfileName
    Assert-PacSuccess "Seleccionar perfil '$ProfileName'"
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDAR PERFILES DE AUTENTICACION
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "[3/8] Validando perfiles de autenticacion..."
if (-not $ImportOnly) {
    Test-AuthProfile $config.dev.authProfile $config.dev.env
}
if (-not $ExportOnly) {
    if ($deployPre) {
        Test-AuthProfile $config.pre.authProfile $config.pre.env
    }
    if ($deployPro) {
        Test-AuthProfile $config.pro.authProfile $config.pro.env
    }
}
Write-Log ""

# ─────────────────────────────────────────────────────────────────────────────
# LIMPIAR EXPORTACIONES ANTERIORES / VALIDAR ZIPS PARA IMPORTACION
# ─────────────────────────────────────────────────────────────────────────────
if (-not $ImportOnly) {
    Write-Log "[4/8] Limpiando exportaciones anteriores..."
    @($unmanagedZip, $managedZip) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force }
    }
    Write-Log "  OK: Zips anteriores eliminados."
}
else {
    Write-Log "[4/8] Validando zips existentes para importacion..."
    if (-not (Test-Path $managedZip)) {
        Write-Log "  ERROR: No se encontro solution_managed.zip para importar."
        Write-Log "  Ejecuta primero una exportacion: .\pacdep.ps1 -ExportOnly"
        exit 1
    }
    Write-Log "  OK: solution_managed.zip encontrado."
}
Write-Log ""

# ─────────────────────────────────────────────────────────────────────────────
# CONECTAR A DEV, INCREMENTAR VERSION Y EXPORTAR (se omite con -ImportOnly)
# ─────────────────────────────────────────────────────────────────────────────
if (-not $ImportOnly) {
    Select-AuthProfile $config.dev.authProfile $config.dev.env

    $listOutput = pac solution list 2>&1
    Assert-PacSuccess "Listar soluciones en DEV"

    $currentVersion = $null
    foreach ($line in $listOutput) {
        $lineStr = "$line"
        if ($lineStr -match [regex]::Escape($solutionName) -and $lineStr -match '(\d+\.\d+\.\d+\.\d+)') {
            $currentVersion = $Matches[1]
            break
        }
    }

    if (-not $currentVersion) {
        Write-Log "  ERROR: No se encontro la solucion '$solutionName' en DEV."
        Write-Log "  Verifica que solutionName en config.json coincida con el Unique Name."
        exit 1
    }

    if ($SkipVersionIncrement) {
        Write-Log "[5/8] Omitiendo incremento de version (-SkipVersionIncrement)..."
        $newVersion = $currentVersion
        Write-Log "  Version actual (sin cambios): $currentVersion"
    }
    else {
        Write-Log "[5/8] Incrementando version de la solucion en DEV..."
        Write-Log "  Version actual: $currentVersion"

        $parts = $currentVersion.Split(".")
        $parts[3] = [int]$parts[3] + 1
        $newVersion = $parts -join "."

        Write-Log "  Nueva version:  $newVersion"
        pac solution online-version --solution-name $solutionName --solution-version $newVersion
        Assert-PacSuccess "Actualizar version en DEV"
        Write-Log "  OK: Version actualizada en DEV: $currentVersion -> $newVersion"
    }
    Write-Log ""

    # ─────────────────────────────────────────────────────────────────────────────
    # EXPORTAR SOLUCION (UNMANAGED + MANAGED)
    # ─────────────────────────────────────────────────────────────────────────────
    # pac genera los zips con el nombre de la solucion; se renombran a nombres fijos
    $pacUnmanaged = Join-Path $PSScriptRoot "$solutionName.zip"
    $pacManaged = Join-Path $PSScriptRoot "${solutionName}_managed.zip"

    Write-Log "[6/8] Exportando solucion desde DEV..."

    Write-Log "  Exportando unmanaged..."
    pac solution export --name $solutionName --path $PSScriptRoot --overwrite
    Assert-PacSuccess "Exportar solucion unmanaged"
    Rename-Item $pacUnmanaged $unmanagedZip -Force
    Write-Log "  OK: $unmanagedZip"

    Write-Log "  Exportando managed..."
    pac solution export --name $solutionName --path $PSScriptRoot --managed --overwrite
    Assert-PacSuccess "Exportar solucion managed"
    Rename-Item $pacManaged $managedZip -Force
    Write-Log "  OK: $managedZip"
    Write-Log ""
    # ─────────────────────────────────────────────────────────────────────────────
    # GENERAR settings_generated.json SI SE USA -ExportOnly
    # ─────────────────────────────────────────────────────────────────────────────
    if ($ExportOnly) {
        Write-Log "[7/8] Generando settings_generated.json desde solution.zip..."
        pac solution create-settings --solution-zip $unmanagedZip --settings-file $settingsGenerated 2>&1 | Out-Null
        if (Test-Path $settingsGenerated) {
            $genContent = Get-Content $settingsGenerated -Raw
            if ($genContent -and $genContent.Trim().Length -gt 5) {
                Write-Log "  OK: settings_generated.json generado."
                Write-Log "  Si la solucion tiene variables de entorno o referencias de conexion, revisa este archivo."
            } else {
                Write-Log "  OK: La solucion no requiere variables de entorno ni referencias de conexion."
                Remove-Item $settingsGenerated -Force
            }
        }
        else {
            Write-Log "  ERROR: No se pudo generar settings_generated.json."
        }
        Write-Log ""
    }
}
else {
    Write-Log "[5/8] Omitido (modo -ImportOnly)"
    Write-Log "[6/8] Omitido (modo -ImportOnly)"
    $newVersion = $null
    Write-Log ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SETTINGS: GENERAR / COMPARAR ESTRUCTURA POR ENTORNO
#
# Flujo:
#   1. Siempre genera settings_generated.json (estructura fresca del zip)
#   2. Determina que archivos de settings verificar segun destino:
#      - ExportOnly: verifica los que ya existan (settings_pre / settings_pro)
#      - TargetEnv: verifica solo los del entorno destino
#   3. Para cada archivo requerido:
#      - Si existe: compara ESTRUCTURA vs. generado. Si difiere -> DETENERSE
#      - Si no existe: copia plantilla y DETENERSE para configuracion manual
#   4. Si el generado esta vacio -> la solucion no necesita settings
# ─────────────────────────────────────────────────────────────────────────────
$settingsNeeded = $false

Write-Log "[7/8] Verificando settings (variables de entorno / conexiones)..."

if ($ImportOnly -and -not (Test-Path $unmanagedZip)) {
    # Sin zip unmanaged no se puede comparar estructura
    Write-Log "  AVISO: solution.zip no disponible, se omite comparacion de estructura."
    $envsToCheck = @()
    if ($deployPre) {
        $envsToCheck += @{File = $settingsFilePre; Label = "PRE" }
    }
    if ($deployPro) {
        $envsToCheck += @{File = $settingsFilePro; Label = "PRO" }
    }
    foreach ($envInfo in $envsToCheck) {
        if (Test-Path $envInfo.File) {
            Write-Log "  OK: Usando $(Split-Path $envInfo.File -Leaf) sin verificacion de estructura."
            $settingsNeeded = $true
        }
    }
    Write-Log ""
}
else {

    # Generar desde el zip exportado
    pac solution create-settings --solution-zip $unmanagedZip --settings-file $settingsGenerated 2>&1 | Out-Null

    $generatedHasContent = $false
    if (Test-Path $settingsGenerated) {
        $genContent = Get-Content $settingsGenerated -Raw
        if ($genContent -and $genContent.Trim().Length -gt 5) {
            $generatedHasContent = $true
        }
    }

    if (-not $generatedHasContent) {
        # La solucion no requiere configuracion de settings
        Write-Log "  OK: La solucion no tiene variables de entorno ni referencias de conexion."
        Write-Log "       No se requiere archivo de settings."
        if (Test-Path $settingsGenerated) { Remove-Item $settingsGenerated -Force }
        Write-Log ""

    }
    else {
        # Determinar que archivos de settings verificar segun destino
        $envsToCheck = @()
        if ($ExportOnly) {
            # En modo solo exportacion, verificar settings existentes
            if (Test-Path $settingsFilePre) { $envsToCheck += @{Key = "pre"; Label = "PRE"; File = $settingsFilePre } }
            if (Test-Path $settingsFilePro) { $envsToCheck += @{Key = "pro"; Label = "PRO"; File = $settingsFilePro } }
            if ($envsToCheck.Count -eq 0) {
                Write-Log "  INFO: La solucion tiene variables de entorno o referencias de conexion."
                Write-Log "        Se genero settings_generated.json como referencia."
                Write-Log ""
                Write-Log "  Al importar, el script creara el archivo de settings del entorno destino."
                Write-Log "  Ejemplo: .\pacdep.ps1 -TargetEnv pre -> genera settings_pre.json"
                Write-Log ""
            }
        }
        else {
            if ($deployPre) {
                $envsToCheck += @{Key = "pre"; Label = "PRE"; File = $settingsFilePre }
            }
            if ($deployPro) {
                $envsToCheck += @{Key = "pro"; Label = "PRO"; File = $settingsFilePro }
            }
        }

        # Verificar cada archivo de settings requerido
        $missingFiles = @()
        $diffFiles = @()
        $diffDetails = $null

        foreach ($envInfo in $envsToCheck) {
            $envSettingsFile = $envInfo.File
            $envLabel = $envInfo.Label

            if (Test-Path $envSettingsFile) {
                Write-Log "  Comparando estructura de settings $envLabel vs. exportado..."
                $comparison = Compare-SettingsStructure -ConfiguredFile $envSettingsFile -GeneratedFile $settingsGenerated
                if ($comparison.HasDifferences) {
                    $diffFiles += $envInfo
                    if (-not $diffDetails) { $diffDetails = $comparison }
                }
                else {
                    Write-Log "  OK: Estructura de settings $envLabel sin cambios."
                }
            }
            else {
                $missingFiles += $envInfo
            }
        }

        # Estructura cambio en uno o mas archivos
        if ($diffFiles.Count -gt 0) {
            $affectedNames = ($diffFiles | ForEach-Object { Split-Path $_.File -Leaf }) -join ", "
            Write-Log ""
            Write-Log "  ============================================================" -Color Yellow
            Write-Log "  ATENCION: La estructura de settings cambio" -Color Yellow
            Write-Log "  ============================================================" -Color Yellow
            Write-Log ""
            Write-Log "  La solucion en DEV tiene cambios en variables de entorno o" -Color Yellow
            Write-Log "  referencias de conexion respecto a los settings actuales." -Color Yellow
            Write-Log ""
            Write-Log "  Archivos afectados: $affectedNames"
            Write-Log ""

            if ($diffDetails.Added.Count -gt 0) {
                Write-Log "  Agregados (existen en DEV, faltan en los settings):"
                foreach ($a in $diffDetails.Added) { Write-Log "    $a" }
            }
            if ($diffDetails.Removed.Count -gt 0) {
                Write-Log "  Eliminados (existen en los settings, ya no estan en DEV):"
                foreach ($r in $diffDetails.Removed) { Write-Log "    $r" }
            }

            Write-Log ""
            Write-Log "  Pasos:"
            Write-Log "    1. Revisa settings_generated.json (estructura actual)"
            Write-Log "    2. Actualiza los archivos afectados con los nuevos campos/valores"
            Write-Log "    3. Ejecuta el script nuevamente"
            Write-Log "    4. Haz commit y push de los settings al repo"
            Write-Log ""
            Write-Log "  NOTA: settings_generated.json tiene la estructura nueva con" -Color Yellow
            Write-Log "        valores vacios. Usalo como referencia." -Color Yellow
            Write-Log "  ============================================================" -Color Yellow
            exit 0
        }

        # Primera vez: crear archivos de settings faltantes
        if ($missingFiles.Count -gt 0) {
            foreach ($envInfo in $missingFiles) {
                Copy-Item $settingsGenerated $envInfo.File -Force
                Write-Log "  -> Generado: $(Split-Path $envInfo.File -Leaf)"
            }
            $fileNames = ($missingFiles | ForEach-Object { Split-Path $_.File -Leaf }) -join ", "
            Write-Log ""
            Write-Log "  ============================================================" -Color Yellow
            Write-Log "  ATENCION: Settings generados por primera vez" -Color Yellow
            Write-Log "  ============================================================" -Color Yellow
            Write-Log ""
            Write-Log "  La solucion tiene variables de entorno o referencias de" -Color Yellow
            Write-Log "  conexion que requieren configuracion manual." -Color Yellow
            Write-Log ""
            Write-Log "  Archivos creados: $fileNames"
            Write-Log ""
            Write-Log "  Pasos:"
            Write-Log "    1. Edita cada archivo con los valores del entorno correspondiente" -Color Yellow
            Write-Log "    2. Ejecuta el script nuevamente" -Color Yellow
            Write-Log "    3. Haz commit y push de los settings al repo" -Color Yellow
            Write-Log "  ============================================================" -Color Yellow
            exit 0
        }

        # Todos los archivos de settings verificados OK
        if ($envsToCheck.Count -gt 0) {
            $settingsNeeded = $true
            # No eliminar settings_generated.json si tiene datos
        }
        Write-Log ""
    }

} # fin: verificacion de settings con generacion

# ─────────────────────────────────────────────────────────────────────────────
# MODO SOLO EXPORTACION
# ─────────────────────────────────────────────────────────────────────────────
if ($ExportOnly) {
    Write-Log "==============================================="
    Write-Log "  Exportacion completada (modo -ExportOnly)."
    Write-Log "  Version exportada: $newVersion"
    Write-Log "  Archivos en: $PSScriptRoot"
    Write-Log "==============================================="
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRMACION ANTES DE IMPORTAR A PRODUCCION
# ─────────────────────────────────────────────────────────────────────────────
if ($deployPro) {
    Write-Log ""
    Write-Log "  ATENCION: Vas a importar en PRODUCCION." -Color Yellow
    Write-Log "  Si la solucion ya existe: UPGRADE (holding + apply)." -Color Yellow
    Write-Log "  Los componentes eliminados en DEV se eliminaran en PRO." -Color Yellow
    Write-Log "  Si es primera vez: import directo." -Color Yellow
    Write-Log ""
    $confirmPro = Read-Host "  Confirmar importacion en PRODUCCION? (S/N)"
    if ($confirmPro -ne "S" -and $confirmPro -ne "s") {
        Write-Log "  Importacion a PRODUCCION cancelada por el usuario."
        if ($TargetEnv -eq "both") {
            Write-Log "  (Tambien se cancelo PRE al estar en modo 'both')."
        }
        exit 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCION DE IMPORTACION
# Si la solucion ya existe en destino -> Upgrade (holding + apply)
# Si es primera vez -> Import directo
# ─────────────────────────────────────────────────────────────────────────────
function Import-Solution {
    param(
        [string]$EnvUrl,
        [string]$ProfileName,
        [string]$EnvLabel,
        [string]$SettingsFile
    )
    Write-Log ""
    Write-Log "  Importando solucion en $EnvLabel..."
    Select-AuthProfile $ProfileName $EnvUrl

    # Detectar si la solucion ya existe en el entorno destino
    Write-Log "  -> Verificando si la solucion ya existe en $EnvLabel..."
    $targetList = pac solution list 2>&1 | Out-String
    $solutionExists = $targetList -match [regex]::Escape($solutionName)

    if ($solutionExists) {
        # --- UPGRADE: la solucion ya existe ---
        Write-Log "  -> Solucion encontrada en $EnvLabel. Modo: UPGRADE (holding + apply)"

        # Paso 1: Importar como holding
        Write-Log "  -> Stage: importando como holding solution..."
        if ($SettingsFile -and (Test-Path $SettingsFile)) {
            Write-Log "  -> Usando settings-file: $(Split-Path $SettingsFile -Leaf)"
            pac solution import --path $managedZip --import-as-holding --settings-file $SettingsFile
        }
        else {
            pac solution import --path $managedZip --import-as-holding
        }
        Assert-PacSuccess "Importar solucion como holding en $EnvLabel"

        # Paso 2: Aplicar upgrade (elimina componentes huerfanos)
        Write-Log "  -> Aplicando upgrade..."
        pac solution upgrade --solution-name $solutionName
        Assert-PacSuccess "Aplicar upgrade en $EnvLabel"
        Write-Log "  OK: Upgrade completado en $EnvLabel ($EnvUrl)"
    }
    else {
        # --- PRIMERA VEZ: import directo ---
        Write-Log "  -> Solucion NO encontrada en $EnvLabel. Modo: IMPORT DIRECTO (primera vez)"

        if ($SettingsFile -and (Test-Path $SettingsFile)) {
            Write-Log "  -> Usando settings-file: $(Split-Path $SettingsFile -Leaf)"
            pac solution import --path $managedZip --settings-file $SettingsFile
        }
        else {
            pac solution import --path $managedZip
        }
        Assert-PacSuccess "Importar solucion en $EnvLabel"
        Write-Log "  OK: Import directo completado en $EnvLabel ($EnvUrl)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# IMPORTAR SEGUN DESTINO
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "[8/8] Importando solucion..."

$preSettings = if ($settingsNeeded) { $settingsFilePre } else { $null }
$proSettings = if ($settingsNeeded) { $settingsFilePro } else { $null }

switch ($TargetEnv) {
    "pre" {
        Import-Solution -EnvUrl $config.pre.env -ProfileName $config.pre.authProfile -EnvLabel "PRE" -SettingsFile $preSettings
    }
    "pro" {
        Import-Solution -EnvUrl $config.pro.env -ProfileName $config.pro.authProfile -EnvLabel "PRO" -SettingsFile $proSettings
    }
    "both" {
        Import-Solution -EnvUrl $config.pre.env -ProfileName $config.pre.authProfile -EnvLabel "PRE" -SettingsFile $preSettings
        Import-Solution -EnvUrl $config.pro.env -ProfileName $config.pro.authProfile -EnvLabel "PRO" -SettingsFile $proSettings
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FIN
# ─────────────────────────────────────────────────────────────────────────────
Write-Log ""
$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed.ToString("mm\:ss")
Write-Log "==============================================="
Write-Log "  PROCESO FINALIZADO CORRECTAMENTE"
Write-Log "  Solucion:  $solutionName"
if ($newVersion) { Write-Log "  Version:   $newVersion" }
Write-Log "  Destino:   $TargetEnv"
Write-Log "  Duracion:  $elapsed"
Write-Log "  Log:       $logFile"
Write-Log "==============================================="
Write-Log ""
Write-Log "  RECORDATORIO: Si hubo cambios en settings_pre/pro.json,"
Write-Log "  haz commit y push al repo del cliente."