#!/usr/bin/env bash
# Procédure de bascule de la base : promotion de bdd2 + repointage des applications (R6, scénario V4).
# À exécuter depuis la racine du dépôt, sur l'hôte, APRÈS la panne de bdd1.
# Usage : scripts/hote/bascule.sh        (le chronométrage de chaque phase est affiché)
set -euo pipefail
cd "$(dirname "$0")/../.."
NOEUDS=config/noeuds.yml
[[ -f $NOEUDS ]] || { echo "config/noeuds.yml absent : lancez d'abord 'vagrant status'"; exit 1; }
ip_de()  { awk -v n="$1" '/^- nom:/{nom=$3} /^  ip:/{if(nom==n)print $2}' "$NOEUDS"; }
apps()   { awk '/^- nom:/{nom=$3} /^  role:/{if($2=="app")print nom}' "$NOEUDS"; }
LB_URL="${LB_URL:-http://$(ip_de lb1)}"
now()    { date +%s.%N; }
dt()     { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }

T0=$(now)
echo "[1/4] Promotion de bdd2 (réplique -> primaire)"
vagrant ssh bdd2 -c "sudo pg_ctlcluster 16 main promote" >/dev/null 2>&1
for _ in $(seq 1 30); do
  R=$(vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'" 2>/dev/null | tr -d '\r[:space:]')
  [[ "$R" == "f" ]] && break; sleep 1
done
[[ "$R" == "f" ]] || { echo "ERREUR : bdd2 est toujours en recovery"; exit 1; }
T1=$(now); echo "      bdd2 est primaire (+$(dt "$T0" "$T1") s)"

echo "[2/4] Repointage des serveurs applicatifs vers $(ip_de bdd2)"
for a in $(apps); do
  vagrant ssh "$a" -c "sudo bash /vagrant/scripts/bascule-app.sh $(ip_de bdd2)" >/dev/null 2>&1 &
done
wait
T2=$(now); echo "      applications repointées (+$(dt "$T0" "$T2") s)"

echo "[3/4] Attente du retour du service via le répartiteur ($LB_URL/sante)"
for _ in $(seq 1 60); do
  C=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$LB_URL/sante" || true)
  [[ "$C" == "200" ]] && break; sleep 0.5
done
T3=$(now)
[[ "$C" == "200" ]] || { echo "ERREUR : service toujours indisponible (dernier code : $C)"; exit 1; }

echo "[4/4] Vérification fonctionnelle"
curl -s -m 3 "$LB_URL/resultat?matricule=M000042"; echo
echo "------------------------------------------------------------"
echo "Promotion de la base      : $(dt "$T0" "$T1") s"
echo "Repointage des apps       : $(dt "$T1" "$T2") s"
echo "Retour du service (200)   : $(dt "$T2" "$T3") s"
echo "TEMPS TOTAL DE BASCULE    : $(dt "$T0" "$T3") s   (depuis le lancement de la procédure)"
echo "Rappel : ne PAS relancer 'vagrant up bdd1' tel quel (risque de deux primaires)."
