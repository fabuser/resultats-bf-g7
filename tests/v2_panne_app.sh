#!/usr/bin/env bash
# V2 — Panne d'un serveur applicatif pendant une charge : requêtes perdues et durée de la période dégradée.
# MODE=halt (défaut, arrêt propre : vagrant halt app1) ou MODE=poweroff (coupure brutale via VBoxManage).
source "$(dirname "$0")/lib.sh"; demarrer V2
MODE="${MODE:-halt}"; DUREE="${DUREE:-40}"; CIBLE="${CIBLE:-app1}"; AVANT="${AVANT:-10}"
JOURNAL="$(mktemp)"
echo "Charge : 1 requête /resultat toutes les ~50 ms pendant ${DUREE}s ; panne de $CIBLE (mode $MODE) à t=${AVANT}s"
(
  fin=$((SECONDS + DUREE))
  while (( SECONDS < fin )); do
    t=$(now); c=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$LB_URL/resultat?matricule=M000042" || true)
    echo "$t ${c:-000}" >> "$JOURNAL"; sleep 0.05
  done
) & CHARGE=$!
sleep "$AVANT"
T_PANNE=$(now)
if [[ "$MODE" == "poweroff" ]]; then VBoxManage controlvm "g${GROUPE}-${CIBLE}" poweroff; else vagrant halt "$CIBLE"; fi
wait "$CHARGE"
awk -v tp="$T_PANNE" '
  { n++; if ($2 == 200) ok++; else { e++; if (!f) f = $1; l = $1; codes[$2]++ } }
  END {
    printf "Requêtes envoyées : %d | réussies : %d | perdues (non-200) : %d\n", n, ok, e
    if (e > 0) { printf "Première erreur : t_panne%+.2f s | dernière erreur : t_panne%+.2f s | période dégradée : %.2f s\n", f - tp, l - tp, l - f
                 for (k in codes) printf "  code %s : %d\n", k, codes[k] }
    else printf "Aucune erreur observée.\n"
  }' "$JOURNAL"
cp "$JOURNAL" "results/V2-journal-brut-$(date +%H%M%S).log"
echo "État des serveurs (HAProxy) :"; curl -s "http://$RESEAU.11:8404/;csv" | awk -F, '$1=="apps" && $2 ~ /^app/ {print "  " $2 ": " $18}'
echo "Restauration : vagrant up $CIBLE"; vagrant up "$CIBLE" >/dev/null 2>&1 || true
