#!/usr/bin/env bash
# V6 (E1) — Panne du répartiteur actif : le service reste joignable à la même adresse (IP virtuelle).
source "$(dirname "$0")/lib.sh"; demarrer V6
DUREE="${DUREE:-30}"; AVANT="${AVANT:-8}"; JOURNAL="$(mktemp)"
echo "Adresse testée : $VIP_URL (IP virtuelle) ; panne de lb1 à t=${AVANT}s ; charge ~20 req/s pendant ${DUREE}s"
(
  fin=$((SECONDS + DUREE))
  while (( SECONDS < fin )); do
    t=$(now); c=$(curl -s -o /dev/null -m 1 -w '%{http_code}' "$VIP_URL/info" || true); echo "$t ${c:-000}" >> "$JOURNAL"; sleep 0.05
  done
) & CHARGE=$!
sleep "$AVANT"; T_PANNE=$(now); vagrant halt lb1; wait "$CHARGE"
awk -v tp="$T_PANNE" '
  { n++; if ($2 != 200) { e++; if (!f) f = $1; l = $1 } }
  END { printf "Requêtes : %d | échecs : %d\n", n, e
        if (e > 0) printf "Temps de reprise (première à dernière erreur) : %.2f s | première erreur à t_panne%+.2f s\n", l - f, f - tp
        else print "Aucun échec observé (bascule VRRP imperceptible à ce pas d'\''échantillonnage)." }' "$JOURNAL"
echo "Restauration : vagrant up lb1"; vagrant up lb1 >/dev/null 2>&1 || true
