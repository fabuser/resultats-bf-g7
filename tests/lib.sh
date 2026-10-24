#!/usr/bin/env bash
# Fonctions communes aux scénarios de validation (sourcé). Exécuter depuis n'importe où.
# Prérequis hôte : bash (Git Bash / WSL / Linux / macOS avec GNU date), curl, ab (apache2-utils), vagrant.
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE" || exit 1

lire_env() { ( [[ -f .env ]] && sed -n "s/^$1=\([^#]*\).*/\1/p" .env | head -1 | tr -d '\r[:space:]' ) || true; }
GROUPE="${GROUPE:-$(lire_env GROUPE)}"; GROUPE="${GROUPE:-7}"
RESEAU="192.168.$((55 + GROUPE))"
LB_URL="${LB_URL:-http://$RESEAU.11}"        # joindre lb1 par le réseau privé (évite la redirection NAT)
VIP_URL="${VIP_URL:-http://$RESEAU.5}"
NOEUDS="$RACINE/config/noeuds.yml"
NB_APP_REEL=$(awk '/^  role:/{if($2=="app")n++} END{print n+0}' "$NOEUDS" 2>/dev/null || echo "?")
now() { date +%s.%N; }

# demarrer <scenario> : ouvre results/<scenario>-<horodatage>.txt et y recopie tout l'affichage
demarrer() {
  mkdir -p results
  SORTIE="results/$1-$(date +%Y%m%d-%H%M%S).txt"
  exec > >(tee "$SORTIE") 2>&1
  echo "=== Scénario $1 — $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "Groupe=$GROUPE  N(serveurs applicatifs)=$NB_APP_REEL  commit=$(git rev-parse --short HEAD 2>/dev/null || echo n/a)"
  echo "Hôte : $(uname -sr) | CPU logiques : $(nproc 2>/dev/null || echo ?) | VirtualBox : $(VBoxManage --version 2>/dev/null || echo ?)"
  echo
}
