#!/usr/bin/env bash
# =====================================================================
#  Instalação do Docker Engine + Compose no Ubuntu (repositório oficial)
#  Uso:  sudo ./install-docker.sh [usuario_deploy]
#
#  Variáveis opcionais:
#    DOCKER_ADDR_POOL=10.200.0.0/16   faixa das redes Docker (evita
#                                     conflito com a rede corporativa)
# =====================================================================
set -euo pipefail

DEPLOY_USER="${1:-}"
DOCKER_ADDR_POOL="${DOCKER_ADDR_POOL:-}"

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------------
# Pré-checagens
# ---------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Rode como root (sudo)."
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "Script feito para Ubuntu (detectado: ${ID:-?})."
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
log "Ubuntu $VERSION_ID ($CODENAME)"

if [ -n "$DEPLOY_USER" ] && ! id "$DEPLOY_USER" &>/dev/null; then
  die "Usuário '$DEPLOY_USER' não existe."
fi

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------
# 1. Remove pacotes conflitantes (docker.io da Canonical, podman-docker...)
# ---------------------------------------------------------------------
log "Removendo pacotes conflitantes (se houver)"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg -s "$pkg" &>/dev/null; then
    apt-get remove -y "$pkg"
  fi
done

# ---------------------------------------------------------------------
# 2. Repositório oficial da Docker
# ---------------------------------------------------------------------
log "Configurando repositório oficial"
apt-get update -q
apt-get install -y -q ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<SRC
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $CODENAME
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SRC
rm -f /etc/apt/sources.list.d/docker.list   # formato antigo, se existir

# ---------------------------------------------------------------------
# 3. Instalação
# ---------------------------------------------------------------------
log "Instalando Docker Engine, CLI, containerd, Buildx e Compose"
apt-get update -q
apt-get install -y -q \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# ---------------------------------------------------------------------
# 4. daemon.json — rotação de logs e live-restore
# ---------------------------------------------------------------------
DAEMON=/etc/docker/daemon.json
if [ -f "$DAEMON" ]; then
  cp "$DAEMON" "$DAEMON.bak.$(date +%Y%m%d%H%M%S)"
  warn "daemon.json existente salvo como backup"
fi

POOL_JSON=""
if [ -n "$DOCKER_ADDR_POOL" ]; then
  POOL_JSON=",
  \"default-address-pools\": [ { \"base\": \"$DOCKER_ADDR_POOL\", \"size\": 24 } ]"
  log "Redes Docker usarão a faixa $DOCKER_ADDR_POOL"
fi

cat > "$DAEMON" <<JSON
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" },
  "live-restore": true$POOL_JSON
}
JSON

# ---------------------------------------------------------------------
# 5. Serviço
# ---------------------------------------------------------------------
log "Habilitando e reiniciando serviços"
systemctl enable --now containerd docker
systemctl restart docker

# ---------------------------------------------------------------------
# 6. Usuário de deploy (opcional)
# ---------------------------------------------------------------------
if [ -n "$DEPLOY_USER" ]; then
  usermod -aG docker "$DEPLOY_USER"
  warn "'$DEPLOY_USER' adicionado ao grupo docker (equivale a acesso root). Faça logout/login."
fi

# ---------------------------------------------------------------------
# 7. Verificação
# ---------------------------------------------------------------------
log "Verificando"
docker version --format 'Engine: {{.Server.Version}}  (API {{.Server.APIVersion}})'
docker compose version
systemctl is-active --quiet docker && log "Docker ativo"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  warn "UFW ativo: portas publicadas pelo Docker IGNORAM as regras do UFW."
  warn "Na stack do GLPI só o Traefik publica portas (80/443) — é o esperado."
fi

log "Concluído."
