#!/usr/bin/env bash
# V4 — Panne de la base primaire : 503 propre, puis bascule sur bdd2 chronométrée.
source "$(dirname "$0")/lib.sh"; demarrer V4
APP1="http://$RESEAU.21:3000"
echo "--- Avant la panne"; echo "GET $LB_URL/sante -> $(curl -s -m 3 -w ' [%{http_code}]' "$LB_URL/sante")"
echo "--- Panne : vagrant halt bdd1"; T0=$(now); vagrant halt bdd1
echo "--- Attente de l'éviction des serveurs applicatifs par le répartiteur (max 20 s)"
for _ in $(seq 1 40); do
  C=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$LB_URL/sante" || true); [[ "$C" == "503" ]] && break; sleep 0.5
done
echo "Via le répartiteur : GET /sante -> code $C (+$(awk -v a="$T0" -v b="$(now)" 'BEGIN{printf "%.1f", b-a}') s après le lancement de la panne)"
echo "Réponse brute du serveur applicatif (diagnostic direct) : $(curl -s -m 3 -w ' [%{http_code}]' "$APP1/sante")"
echo "Requête métier : $(curl -s -m 3 -w ' [%{http_code}]' "$LB_URL/resultat?matricule=M000042" | head -c 200)"
echo "--- Bascule sur bdd2"
bash scripts/hote/bascule.sh
