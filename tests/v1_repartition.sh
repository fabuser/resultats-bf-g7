#!/usr/bin/env bash
# V1 — Répartition : 20 appels successifs à /info ; écart entre serveur le plus et le moins sollicité (< 20 %).
source "$(dirname "$0")/lib.sh"; demarrer V1
TOTAL=20
echo "Commande : for i in 1..$TOTAL; do curl $LB_URL/info; done"
: > /tmp/v1_hotes.txt
for _ in $(seq "$TOTAL"); do
  curl -s -m 3 "$LB_URL/info" | sed -n 's/.*"hote": *"\([^"]*\)".*/\1/p' >> /tmp/v1_hotes.txt
done
APPS=$(awk '/^- nom:/{nom=$3} /^  role:/{if($2=="app")print nom}' "$NOEUDS" | tr '\n' ' ')
echo "Résultat brut (serveur : nombre de réponses) :"
awk -v apps="$APPS" -v total="$TOTAL" '
  { c[$1]++ }
  END {
    n = split(apps, a, " "); min = total; max = 0
    for (i = 1; i <= n; i++) { v = c[a[i]] + 0; printf "  %-6s %d\n", a[i], v; if (v < min) min = v; if (v > max) max = v }
    ec = (max - min) * 100 / total
    printf "Écart (plus - moins sollicité) = %.1f %% du total  ->  %s (seuil 20 %%)\n", ec, (ec < 20 ? "CONFORME" : "NON CONFORME")
  }' /tmp/v1_hotes.txt
