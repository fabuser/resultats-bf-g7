#!/usr/bin/env bash
# V3 — Montée en charge : ab -n 2000 -c 50 ; à lancer pour N=2 puis N=4 (bin/scale.sh 4). 3 passes, on garde la médiane.
source "$(dirname "$0")/lib.sh"; demarrer V3
command -v ab >/dev/null || { echo "ab introuvable : installez apache2-utils (ou lancez ce script depuis une VM)"; exit 1; }
URL="$LB_URL/resultat?matricule=M025000"
echo "Commande : ab -n 2000 -c 50 $URL   (précédée d'un échauffement de 200 requêtes, répétée 3 fois)"
ab -n 200 -c 20 "$URL" >/dev/null 2>&1 || true
RPS=()
for i in 1 2 3; do
  ab -n 2000 -c 50 "$URL" > "/tmp/ab_$i.txt" 2>&1 || true
  r=$(awk '/Requests per second/{print $4}' "/tmp/ab_$i.txt"); f=$(awk '/Failed requests/{print $3}' "/tmp/ab_$i.txt")
  t=$(awk '/Time per request.*\(mean\)$/ && !/across/{print $4}' "/tmp/ab_$i.txt")
  echo "Passe $i : ${r:-?} req/s | requêtes échouées : ${f:-?} | temps moyen par requête : ${t:-?} ms"
  RPS+=("${r:-0}")
done
MED=$(printf '%s\n' "${RPS[@]}" | sort -n | sed -n 2p)
echo "N = $NB_APP_REEL  ->  débit médian = $MED requêtes/s"
cp /tmp/ab_2.txt "results/V3-ab-brut-N${NB_APP_REEL}-$(date +%H%M%S).txt"
