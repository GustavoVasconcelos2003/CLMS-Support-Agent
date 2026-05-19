#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CLMS Engine - Executa scripts do repositorio (PowerShell ou Python).
"""

import json
import subprocess
import os
import sys
import datetime

# ============================================
# CAMINHOS FIXOS
# ============================================
BASE_DIR = r"C:\CLMS"
GITHUB_DIR = os.path.join(BASE_DIR, "Github")
REPO_DIR = os.path.join(GITHUB_DIR, "repo")
MACHINE_JSON = os.path.join(GITHUB_DIR, "machine.json")
STATE_JSON = os.path.join(GITHUB_DIR, "state.json")
MANIFEST_JSON = os.path.join(REPO_DIR, "manifest.json")
LOG_FILE = os.path.join(BASE_DIR, "LOGS", "engine.log")
GIT_EXE = r"C:\Program Files\Git\cmd\git.exe"
PYTHON_EXE = sys.executable  # o mesmo python que roda a engine

# Garante pasta de logs
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

def log(msg, nivel="INFO"):
    """Escreve no log e no console."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    linha = f"[{timestamp}] [{nivel}] {msg}"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(linha + "\n")
    print(linha)

# ============================================
# 1. ATUALIZA REPOSITORIO
# ============================================
log("Iniciando CLMS Engine")

if not os.path.exists(GIT_EXE):
    log(f"Git nao encontrado em {GIT_EXE}", "ERRO")
    sys.exit(1)

if not os.path.exists(REPO_DIR):
    log(f"Repositorio nao encontrado em {REPO_DIR}", "ERRO")
    sys.exit(1)

# Marca diretorio como seguro (evita warning)
subprocess.run([GIT_EXE, "-C", REPO_DIR, "config", "--global", "--add", "safe.directory", REPO_DIR],
               capture_output=True)

# Executa git pull
result = subprocess.run([GIT_EXE, "-C", REPO_DIR, "pull"], capture_output=True, text=True)
if result.returncode != 0:
    log(f"Falha no git pull: {result.stderr.strip()}", "ERRO")
    sys.exit(1)
log("Git pull OK")

# ============================================
# 2. CARREGA ARQUIVOS JSON
# ============================================
def ler_json(caminho):
    try:
        with open(caminho, "r", encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception as e:
        log(f"Erro ao ler {caminho}: {e}", "ERRO")
        return None

machine = ler_json(MACHINE_JSON)
if not machine:
    log("machine.json nao encontrado ou invalido", "ERRO")
    sys.exit(1)

state = ler_json(STATE_JSON)
if not state:
    log("state.json nao encontrado ou invalido", "ERRO")
    sys.exit(1)

manifest = ler_json(MANIFEST_JSON)
if not manifest or "scripts" not in manifest:
    log("manifest.json invalido ou sem scripts", "ERRO")
    sys.exit(1)

# ============================================
# 3. DADOS DA MAQUINA
# ============================================
cliente = machine.get("cliente", "desconhecido")
setor = machine.get("setor", "default")
cliente_tag = f"{cliente}:{setor}"
cliente_wild = f"{cliente}:*"
log(f"Alvo: {cliente_tag}")

# ============================================
# 4. EXECUTA SCRIPTS
# ============================================
scripts = manifest["scripts"]
alterado = False

for script in scripts:
    nome = script.get("name")
    versao = script.get("version")
    tipo = script.get("type", "powershell").lower()
    targets = script.get("targets", [])
    caminho_rel = script.get("path")
    
    if not nome or not versao or not caminho_rel:
        log(f"Script ignorado (dados faltando): {script}", "AVISO")
        continue
    
    # Verifica se deve rodar para este cliente/setor
    if "*" not in targets and cliente_tag not in targets and cliente_wild not in targets:
        log(f"Ignorando {nome} - targets {targets} nao batem com {cliente_tag}")
        continue
    
    # Verifica versao atual
    versao_atual = state.get("scripts", {}).get(nome)
    if versao_atual == versao:
        log(f"{nome} ja esta na versao {versao}. Pulando.")
        continue
    
    log(f"Executando {nome} v{versao} ({tipo})...")
    caminho_abs = os.path.join(REPO_DIR, caminho_rel)
    
    if not os.path.exists(caminho_abs):
        log(f"Script nao encontrado: {caminho_abs}", "ERRO")
        if "script_logs" not in state:
            state["script_logs"] = {}
        state["script_logs"][nome] = {
            "last_run": datetime.datetime.now().isoformat(),
            "status": "failed",
            "error": f"Arquivo nao encontrado: {caminho_rel}"
        }
        continue
    
    # Monta comando conforme tipo
    if tipo == "python":
        cmd = [PYTHON_EXE, caminho_abs]
    else:  # powershell
        cmd = ["powershell.exe", "-NoProfile", "-NonInteractive",
               "-ExecutionPolicy", "Bypass", "-File", caminho_abs]
    
    # Executa com timeout de 10 minutos
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600
        )
        sucesso = (proc.returncode == 0)
        
        log_entry = {
            "last_run": datetime.datetime.now().isoformat(),
            "status": "success" if sucesso else "failed",
            "returncode": proc.returncode,
            "stdout": proc.stdout[-500:] if proc.stdout else None,
            "stderr": proc.stderr[-500:] if proc.stderr else None
        }
        if not sucesso:
            log_entry["error"] = (proc.stderr.strip() or f"Returncode {proc.returncode}")[:200]
        
        if "script_logs" not in state:
            state["script_logs"] = {}
        state["script_logs"][nome] = log_entry
        
        if sucesso:
            state.setdefault("scripts", {})[nome] = versao
            alterado = True
            log(f"Sucesso: {nome}")
        else:
            log(f"Falha: {nome} - {log_entry.get('error')}", "ERRO")
    
    except subprocess.TimeoutExpired:
        log(f"Timeout de 10 minutos em {nome}", "ERRO")
        if "script_logs" not in state:
            state["script_logs"] = {}
        state["script_logs"][nome] = {
            "last_run": datetime.datetime.now().isoformat(),
            "status": "failed",
            "error": "Timeout apos 10 minutos"
        }
    except Exception as e:
        log(f"Excecao ao executar {nome}: {e}", "ERRO")
        if "script_logs" not in state:
            state["script_logs"] = {}
        state["script_logs"][nome] = {
            "last_run": datetime.datetime.now().isoformat(),
            "status": "failed",
            "error": f"{type(e).__name__}: {str(e)}"
        }

# ============================================
# 5. SALVA STATE.JSON
# ============================================
if alterado or True:  # sempre salva para registrar logs mesmo sem mudanca de versao
    try:
        with open(STATE_JSON, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=4, ensure_ascii=False)
        log("state.json salvo")
    except Exception as e:
        log(f"Erro ao salvar state.json: {e}", "ERRO")

log("Engine finalizada.")
