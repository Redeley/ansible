#!/bin/bash

set -uo pipefail

echo "=== Parando serviços do Kaspersky ==="
systemctl stop klnagent64 2>/dev/null
systemctl stop kesl 2>/dev/null

echo "=== Removendo pacotes ==="
yum remove -y klnagent klnagent64 kesl

echo "=== Removendo diretórios residuais ==="
rm -rf /opt/kaspersky
rm -rf /var/opt/kaspersky
rm -rf /etc/opt/kaspersky
rm -rf /var/log/kaspersky

echo "=== Verificando possíveis binários remanescentes ==="
rm -f /usr/bin/kesl-control
rm -f /usr/bin/klnagent

echo "✅ Remoção completa finalizada."

echo "================== Atualizando Sistema e Kernel ======================"
yum update -y

# Instalar kernel mais recente disponível para Oracle Linux (UEK padrão)
echo "Instalando kernel mais recente disponível (UEK)"
yum install -y kernel-uek || yum install -y kernel

# Instalar ferramentas de rede e utilitários
yum install -y network-manager netplan mtr nmtui nload net-tools

# Reexecuta daemon systemd
systemctl daemon-reexec

echo "==================== Excluindo .rpm anterior ===================="
RPM_FILE="/tmp/klnagent64-15.1.0-20748.x86_64.rpm"
rm -f "$RPM_FILE"

echo "================== Verificando dependências =================="

# Garante que wget esteja instalado
if ! command -v wget &>/dev/null; then
  echo "wget não encontrado. Instalando..."
  yum install -y wget || { echo "❌ Erro ao instalar wget. Encerrando."; exit 1; }
fi

# Garante que tmux esteja instalado
if ! command -v tmux &>/dev/null; then
  echo "tmux não encontrado. Instalando..."
  yum install -y tmux || { echo "❌ Erro ao instalar tmux. Encerrando."; exit 1; }
fi

echo "======================= Baixando e Instalando Kaspersky ======================="
DOWNLOAD_URL="https://downloads.hsprevent.com.br/klnagent64-15.1.0-20748.x86_64.rpm"

if [ -f "$RPM_FILE" ]; then
  echo "Arquivo .rpm já existe: $RPM_FILE. Pulando o download."
else
  echo "Baixando arquivo .rpm para /tmp..."
  wget -O "$RPM_FILE" "$DOWNLOAD_URL" || { echo "❌ Falha ao baixar o pacote. Encerrando."; exit 1; }
fi

chmod +x "$RPM_FILE"

echo "Instalando pacote $RPM_FILE..."
if ! yum install -y "$RPM_FILE"; then
  echo "❌ Erro ao instalar o pacote .rpm. Encerrando script."
  exit 1
fi

echo "======================= Iniciando configuração via tmux ======================="
SESSION_NAME="kaspersky"

# Encerra a sessão tmux existente, se houver
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Sessão tmux '$SESSION_NAME' já existe. Encerrando..."
  tmux kill-session -t "$SESSION_NAME"
fi

# Verifica se o diretório de setup existe antes de tentar usar
SETUP_PATH="/opt/kaspersky/klnagent64/lib/bin/setup"
if [ ! -d "$SETUP_PATH" ]; then
  echo "❌ Diretório de setup não encontrado: $SETUP_PATH"
  exit 1
fi

tmux new-session -d -s "$SESSION_NAME"

tmux send-keys -t "$SESSION_NAME" "cd $SETUP_PATH" Enter
sleep 5
tmux send-keys "./postinstall.pl" Enter
sleep 2
tmux send-keys C-c
sleep 2
tmux send-keys y
sleep 2
tmux send-keys Enter
sleep 2
tmux send-keys 172.40.0.3
sleep 2
tmux send-keys Enter
sleep 2
tmux send-keys 14000
sleep 2
tmux send-keys Enter
sleep 2
tmux send-keys 13000
sleep 2
tmux send-keys Enter
sleep 2
tmux send-keys y
sleep 2
tmux send-keys Enter
sleep 2
tmux send-keys 2
sleep 2
tmux send-keys Enter
sleep 2

BINARY_PATH="/opt/kaspersky/klnagent64/bin"
if [ -d "$BINARY_PATH" ]; then
  tmux send-keys "cd $BINARY_PATH" Enter
  sleep 30
  tmux send-keys "./klmover -address 172.40.0.3" Enter
else
  echo "❌ Diretório de binários não encontrado: $BINARY_PATH"
  exit 1
fi

sleep 90
systemctl restart klnagent64
sleep 10
systemctl status klnagent64 --no-pager

echo "Removendo arquivo .rpm: $RPM_FILE"
rm -f "$RPM_FILE"

tmux kill-session -t "$SESSION_NAME"

echo '===============================✅ Kaspersky finalizado com sucesso ==============================='
sleep 3
