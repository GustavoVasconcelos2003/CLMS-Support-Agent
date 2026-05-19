# ==========================================================
# CONFIGURAÇÕES
# ==========================================================
$zabbixSrv = "seuservidoraqui.com.br"
$machineJson = "C:\CLMS\Github\machine.json"
# Link direto para a versão 7.0 LTS estável (AMD64)
$msiUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/zabbix_agent-7.4.8-windows-amd64-openssl.msi"
$tempMsi = "$env:TEMP\zabbix_agent_v7.msi"

# ==========================================================
# 1. VALIDAÇÃO: JÁ ESTÁ INSTALADO?
# ==========================================================
$service = Get-Service "Zabbix Agent" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "[INFO] Zabbix Agent já instalado e rodando. Saindo para evitar redundância."
    exit 0
}

# ==========================================================
# 2. COLETA DE METADADOS (machine.json)
# ==========================================================
if (Test-Path $machineJson) {
    $data = Get-Content $machineJson | ConvertFrom-Json
    # Criamos uma string de metadados para o Autocadastro
    $metadata = "CLMS_AGENT;Cliente:$($data.cliente);Setor:$($data.setor)"
} else {
    $metadata = "CLMS_AGENT;DESCONHECIDO"
}

# ==========================================================
# 3. DOWNLOAD (Apenas se necessário)
# ==========================================================
Write-Host "[INFO] Baixando instalador Zabbix..."
try {
    Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -ErrorAction Stop
} catch {
    Write-Host "[ERRO] Falha ao baixar o MSI. Verifique o link ou a conexão."
    exit 1
}

# ==========================================================
# 4. INSTALAÇÃO SILENCIOSA E AUTO-CONFIGURAÇÃO
# ==========================================================
# Aqui passamos os comandos que escrevem direto no zabbix_agentd.conf
$installArgs = "/i `"$tempMsi`" /qn " +
               "SERVER=$zabbixSrv " +
               "SERVERACTIVE=$zabbixSrv " +
               "HOSTMETADATA=`"$metadata`" " +
               "ENABLEPATH=1 " +
               "INSTALLFOLDER=`"C:\Program Files\Zabbix Agent`""

Write-Host "[INFO] Iniciando instalação silenciosa..."
$process = Start-Process msiexec.exe -ArgumentList $installArgs -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host "[OK] Zabbix instalado e configurado automaticamente!"
    # Remove o instalador para não ocupar espaço
    Remove-Item $tempMsi -ErrorAction SilentlyContinue
} else {
    Write-Host "[ERRO] Falha na instalação. Código: $($process.ExitCode)"
}
