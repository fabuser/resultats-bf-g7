#!/usr/bin/env bash
# appN : serveur applicatif sans état — idempotent.
source /vagrant/scripts/lib.sh
BDD1="$(ip_de bdd1)"

installer_paquets python3 python3-psycopg2
installer_node_exporter
id resultats >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin resultats

# Le code est copié hors du dossier synchronisé, puis redémarré seulement s'il a changé.
APP_CHANGE=0
ecrire_si_different /opt/resultats/app.py < /vagrant/app/app.py && APP_CHANGE=1

# Secrets : fichier root:root 0600, lu par systemd (EnvironmentFile) — jamais dans le dépôt.
# DB_HOST n'est PAS écrit en dur : il vient de la source de vérité (bascule : voir scripts/bascule-app.sh).
if [[ -f /etc/resultats/app.env ]]; then
  DB_HOST_ACTUEL="$(sed -n 's/^DB_HOST=//p' /etc/resultats/app.env)"   # conserve un éventuel basculement
else
  DB_HOST_ACTUEL=""
fi
MODE=0600 ecrire_si_different /etc/resultats/app.env <<ENV && APP_CHANGE=1
DB_HOST=${DB_HOST_ACTUEL:-$BDD1}
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
PORT=3000
ENV

ecrire_si_different /etc/systemd/system/resultats-app.service <<UNIT && { systemctl daemon-reload; APP_CHANGE=1; }
[Unit]
Description=RESULTATS-BF application (sans etat)
After=network-online.target

[Service]
User=resultats
EnvironmentFile=/etc/resultats/app.env
ExecStart=/usr/bin/python3 /opt/resultats/app.py
Restart=always
RestartSec=1
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable resultats-app >/dev/null 2>&1
if [[ $APP_CHANGE -eq 1 ]] || ! systemctl is-active --quiet resultats-app; then
  systemctl restart resultats-app
fi
log "application démarrée (DB_HOST=$(sed -n 's/^DB_HOST=//p' /etc/resultats/app.env))"
