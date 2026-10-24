#!/usr/bin/env bash
# Exécuté DANS une VM applicative par scripts/hote/bascule.sh : pointe l'application vers la nouvelle primaire.
# Usage : sudo /vagrant/scripts/bascule-app.sh <ip_nouvelle_primaire>
set -euo pipefail
NOUVEAU="${1:?usage: bascule-app.sh <ip>}"
sed -i "s/^DB_HOST=.*/DB_HOST=$NOUVEAU/" /etc/resultats/app.env
systemctl restart resultats-app
