#!/usr/bin/env bash
# Fonctions communes à tous les scripts de provisionnement (sourcé, jamais exécuté seul).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

NOEUDS="${NOEUDS:-/vagrant/config/noeuds.yml}"   # engendré par le Vagrantfile : source unique de vérité

log() { echo "[$(hostname)] $*"; }

# ip_de <nom>  -> adresse IP du nœud (vide si le nœud n'existe pas)
ip_de() { awk -v n="$1" '/^- nom:/{nom=$3} /^  ip:/{if(nom==n)print $2}' "$NOEUDS"; }

# liste_app -> une ligne "nom ip" par serveur applicatif
liste_app() { awk '/^- nom:/{nom=$3} /^  ip:/{ip=$2} /^  role:/{if($2=="app")print nom, ip}' "$NOEUDS"; }

# ext_active E1 -> succès si l'extension est listée dans $EXTENSIONS
ext_active() { [[ ",${EXTENSIONS:-}," == *",$1,"* ]]; }

# ecrire_si_different <destination> : lit le contenu sur stdin ; n'écrit que s'il change.
# Retourne 0 si le fichier a été modifié, 1 sinon  => idempotence (R2) et rechargements ciblés.
ecrire_si_different() {
  local dest="$1" tmp
  tmp="$(mktemp)"; cat > "$tmp"
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 1; fi
  install -D -m "${MODE:-0644}" "$tmp" "$dest"; rm -f "$tmp"; return 0
}

# installer_paquets p1 p2 ... : un seul apt-get, mise à jour de l'index au plus une fois par heure
installer_paquets() {
  if [[ -z "$(find /var/lib/apt/lists -maxdepth 1 -type f -mmin -60 2>/dev/null | head -1)" ]]; then
    apt-get update -qq
  fi
  apt-get install -y -qq --no-install-recommends "$@" >/dev/null
}

# attendre_port <ip> <port> [secondes]
attendre_port() {
  local ip="$1" port="$2" max="${3:-90}" i=0
  until timeout 2 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; do
    i=$((i+1)); [[ $i -ge $max ]] && { log "ERREUR : $ip:$port injoignable après ${max}s"; return 1; }
    sleep 1
  done
}

# Paquet prometheus-node-exporter : seulement si l'extension E2 (observabilité) est active
installer_node_exporter() {
  if ext_active E2; then
    installer_paquets prometheus-node-exporter
    systemctl enable --now prometheus-node-exporter >/dev/null 2>&1
  fi
}
