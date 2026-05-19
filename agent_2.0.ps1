# ==========================================================
# AGENTE DE INSTALACAO CLMS (BOOTSTRAP)
# ==========================================================
param(
    [string]$cliente = "desconhecido",
    [string]$setor   = "default"
)

# --- CONFIGURACOES ---
$basePath = "C:\CLMS"
$logDir   = "$basePath\LOGS"
$logFile  = "$logDir\agent_install.log"
$githubPath = "$basePath\Github"
$repoPath   = "$githubPath\repo"
$pythonExe  = "C:\Program Files\Python312\python.exe"
$gitExe     = "C:\Program Files\Git\cmd\git.exe"

# Cria pasta de logs antes de qualquer escrita
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Funcao de logging (cria o arquivo se necessario)
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    if ($Level -eq "ERROR") { Write-Host $logEntry -ForegroundColor Red }
    elseif ($Level -eq "WARNING") { Write-Host $logEntry -ForegroundColor Yellow }
    else { Write-Host $logEntry }
}

# --- 1. TESTE DE REDE (com retry) ---
Write-Log "Iniciando agente de instalacao CLMS"
Write-Log "Testando conectividade com a internet..."

$online = $false
for ($i = 1; $i -le 12; $i++) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet) {
        $online = $true
        break
    }
    Write-Log "Sem internet, aguardando 5s (tentativa $i/12)" -Level "WARNING"
    Start-Sleep -Seconds 5
}
if (-not $online) {
    Write-Log "Sem internet apos varias tentativas. Abortando." -Level "ERROR"
    exit 1
}
Write-Log "Internet OK"

# --- 2. VERIFICACAO DO TOKEN GITHUB ---

$repoUrl = "https://github.com/GustavoVasconcelos2003/CLMS-Support-Agent.git"
Write-Log "Repositorio publico configurado"

# --- 3. CRIAR ESTRUTURA DE PASTAS ---
if (-not (Test-Path $githubPath)) {
    New-Item -ItemType Directory -Path $githubPath -Force | Out-Null
    Write-Log "Pasta $githubPath criada"
}

# --- 3.5 CRIAR machine.json e state.json (se nao existirem) ---
$machineJsonPath = "$githubPath\machine.json"
$stateJsonPath   = "$githubPath\state.json"

if (-not (Test-Path $machineJsonPath)) {
    $machine = @{
        cliente  = $cliente
        setor    = $setor
        hostname = $env:COMPUTERNAME
    }
    $machine | ConvertTo-Json | Out-File $machineJsonPath -Force -Encoding ascii
    Write-Log "machine.json criado em $machineJsonPath (cliente=$cliente, setor=$setor)"
} else {
    Write-Log "machine.json ja existe em $machineJsonPath"
}

if (-not (Test-Path $stateJsonPath)) {
    @{ scripts = @{} } | ConvertTo-Json | Out-File $stateJsonPath -Force -Encoding ascii
    Write-Log "state.json criado em $stateJsonPath (vazio)"
} else {
    Write-Log "state.json ja existe em $stateJsonPath"
}

# --- 4. INSTALAR PYTHON (DIRETO DA URL) ---
function Install-Python {
    if (Test-Path $pythonExe) {
        Write-Log "Python ja instalado em $pythonExe"
        return $true
    }
    Write-Log "Instalando Python 3.12 via download direto..."
    $installer = "$env:TEMP\python-3.12.0-amd64.exe"
    $url = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Start-Process $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
        Remove-Item $installer -Force
        if (Test-Path $pythonExe) {
            Write-Log "Python instalado com sucesso"
            return $true
        }
        throw "Python nao encontrado apos instalacao"
    } catch {
        Write-Log "Erro ao instalar Python: $_" -Level "ERROR"
        return $false
    }
}

# --- 5. INSTALAR GIT (DIRETO DA URL) ---
function Install-Git {
    if (Test-Path $gitExe) {
        Write-Log "Git ja instalado em $gitExe"
        return $true
    }
    Write-Log "Instalando Git via download direto..."
    $installer = "$env:TEMP\git-installer.exe"
    $url = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Start-Process $installer -ArgumentList "/VERYSILENT /NORESTART" -Wait
        Remove-Item $installer -Force
        if (Test-Path $gitExe) {
            Write-Log "Git instalado com sucesso"
            return $true
        }
        throw "Git nao encontrado apos instalacao"
    } catch {
        Write-Log "Erro ao instalar Git: $_" -Level "ERROR"
        return $false
    }
}

# Executa as instalacoes (aborta se alguma falhar)
if (-not (Install-Python)) { exit 1 }
if (-not (Install-Git)) { exit 1 }

# --- 6. CLONAR OU ATUALIZAR REPOSITORIO ---
if (-not (Test-Path $repoPath)) {
    Write-Log "Clonando repositorio..."
    try {
        & $gitExe clone $repoUrl $repoPath
        & $gitExe config --global --add safe.directory $repoPath
        Write-Log "Clone concluido"
    } catch {
        Write-Log "Falha ao clonar: $_" -Level "ERROR"
        exit 1
    }
} else {
    Write-Log "Repositorio ja existe. Atualizando..."
    Set-Location $repoPath
    & $gitExe remote set-url origin $repoUrl
    & $gitExe pull
}

# --- 7. CRIAR TAREFA AGENDADA (chama engine.py diretamente) ---
$action = New-ScheduledTaskAction -Execute $pythonExe -Argument "`"$repoPath\SCRIPTS\GLOBAL\engine.py`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

try {
    Register-ScheduledTask -TaskName "CLMS_AGENT" `
        -Description "Agente CLMS - Executa engine.py a cada 10 min" `
        -Action $action -Trigger $trigger -Settings $settings `
        -User "SYSTEM" -RunLevel Highest -Force
    Write-Log "Tarefa agendada CLMS_AGENT criada com sucesso"
} catch {
    Write-Log "Falha ao registrar tarefa agendada: $_" -Level "ERROR"
    exit 1
}

Write-Log "--- AGENTE INSTALADO COM SUCESSO ---"
Write-Host "Instalacao concluida. O agente comecara a executar em breve." -ForegroundColor Green

# --- EXECUTAR ENGINE PELA PRIMEIRA VEZ (IMEDIATO) ---
Write-Log "Executando engine pela primeira vez..."
try {
    & $pythonExe "$repoPath\SCRIPTS\GLOBAL\engine.py"
    Write-Log "Primeira execucao da engine concluida com sucesso."
} catch {
    Write-Log "Erro na primeira execucao da engine: $_" -Level "WARNING"
}