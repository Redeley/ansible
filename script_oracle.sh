#!/bin/bash

set -uo pipefail

OS=""
PACKAGE_MANAGER=""

# Detecta distribuição
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Não foi possível detectar o sistema operacional."
    exit 1
fi

echo "Sistema detectado: $OS"

# Define gerenciador de pacotes
case "$OS" in
    ubuntu|debian)
        PACKAGE_MANAGER="apt"
        ;;
    ol|oracle|centos|rhel|rocky)
        PACKAGE_MANAGER="yum"
        ;;
    *)
        echo "Distribuição $OS não suportada por este script."
        exit 1
        ;;
esac

echo "=== Parando serviços do Kaspersky ==="
systemctl stop klnagent64 2>/dev/null
systemctl stop kesl 2>/dev/null

echo "=== Removendo pacotes ==="
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    apt purge -y klnagent klnagent64 kesl
    dpkg --remove --force-remove-reinstreq klnagent64
    apt autoremove -y --purge
else
    yum remove -y klnagent klnagent64 kesl
fi

echo "=== Removendo diretórios residuais ==="
rm -rf /opt/kaspersky /var/opt/kaspersky /etc/opt/kaspersky /var/log/kaspersky

echo "=== Verificando possíveis binários remanescentes ==="
rm -f /usr/bin/kesl-control /usr/bin/klnagent

echo "✅ Remoção completa finalizada."

echo '================================Atualizando Kernel e Instalando Pacotes====================================='
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    apt update
    apt install -y wget --install-recommends linux-generic-hwe-20.04 netplan mtr nmtui nload net-tools network-manager
else
    yum update -y
    yum install -y wget kernel mtr nmtui nload net-tools NetworkManager || echo "Alguns pacotes podem não estar disponíveis."
fi

systemctl daemon-reexec

echo "==================== Excluindo pacote anterior ===================="

RPM_FILE="/tmp/klnagent64-15.1.0-20748.x86_64.rpm"
rm -f "$RPM_FILE"

echo '===============================Instalando Kaspersky===================================='

if [ "$PACKAGE_MANAGER" = "apt" ]; then
    FILE_PATH="/tmp/klnagent64_15.1.0-20748_amd64.deb"
    DOWNLOAD_URL="https://downloads.hsprevent.com.br/klnagent64_15.1.0-20748_amd64.deb"
else
    FILE_PATH="$RPM_FILE"
    DOWNLOAD_URL="https://downloads.hsprevent.com.br/klnagent64-15.1.0-20748.x86_64.rpm"
fi

# Verifica se wget está disponível
if ! command -v wget >/dev/null 2>&1; then
    echo "Erro: wget não está instalado. Abortando."
    exit 1
fi

# Baixa o pacote se não existir
if [ ! -f "$FILE_PATH" ]; then
    echo "Baixando pacote..."
    wget -O "$FILE_PATH" "$DOWNLOAD_URL"
else
    echo "Pacote já existe: $FILE_PATH. Pulando o download."
fi

# Confirma se o arquivo foi baixado corretamente
if [ ! -f "$FILE_PATH" ]; then
    echo "Erro: o arquivo $FILE_PATH não foi baixado corretamente."
    exit 1
fi

# Instala o pacote
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    chmod +x "$FILE_PATH"
    dpkg -i "$FILE_PATH" || { echo "Erro ao instalar o .deb"; exit 1; }
else
    yum install -y "$FILE_PATH" || { echo "Erro ao instalar o .rpm"; exit 1; }
fi

SESSION_NAME="kaspersky"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
fi

tmux new-session -d -s $SESSION_NAME

tmux send-keys -t $SESSION_NAME "cd /opt/kaspersky/klnagent64/lib/bin/setup" Enter
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
tmux send-keys "cd /opt/kaspersky/klnagent64/bin" Enter
sleep 30
tmux send-keys "./klmover -address 172.40.0.3" Enter
sleep 90

systemctl restart klnagent64
sleep 10
systemctl status klnagent64 --no-pager

echo "Removendo pacote: $FILE_PATH"
rm -f "$FILE_PATH"

tmux kill-session -t kaspersky

echo '===============================Kaspersky finalizado===================================='
sleep 3
