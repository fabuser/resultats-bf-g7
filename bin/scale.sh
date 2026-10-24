#!/usr/bin/env bash
# Change le nombre de serveurs applicatifs d'un seul geste : bin/scale.sh <N>
# (équivalent de NB_APP=<N> vagrant up, puis régénération de la configuration du répartiteur).
# Raison du 2e temps : Vagrant ne re-provisionne pas une VM déjà démarrée (lb1 reste "running").
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: bin/scale.sh <N entre 2 et 9>}"
[[ "$NEW" =~ ^[2-9]$ ]] || { echo "N doit être compris entre 2 et 9"; exit 1; }
[[ -f .env ]] || cp .env.exemple .env
CUR=$(sed -n 's/^NB_APP=\([0-9]*\).*/\1/p' .env | head -1); CUR="${CUR:-2}"

# Retrait : on détruit les VM en trop AVANT de modifier .env (le Vagrantfile doit encore les connaître).
if (( NEW < CUR )); then
  for k in $(seq $((NEW+1)) "$CUR"); do vagrant destroy -f "app$k" || true; done
fi

# Une seule valeur à changer : NB_APP dans .env
if grep -q '^NB_APP=' .env; then
  awk -v n="$NEW" '/^NB_APP=/{sub(/=[0-9]+/, "=" n)} {print}' .env > .env.tmp && mv .env.tmp .env
else
  echo "NB_APP=$NEW" >> .env
fi

vagrant up                                   # crée les nouvelles VM applicatives (et lance leur provisionnement)
LBS=$(awk '/^- nom:/{nom=$3} /^  role:/{if($2=="lb")print nom}' config/noeuds.yml)
# shellcheck disable=SC2086
vagrant provision $LBS                       # régénère la configuration HAProxy depuis config/noeuds.yml
echo "OK : $NEW serveurs applicatifs. Vérifiez la répartition : tests/v1_repartition.sh"
