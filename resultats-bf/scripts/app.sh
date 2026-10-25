#!/bin/bash
set -e

echo "[APP] Installation de Python et des dépendances..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-pip python3-venv libpq-dev prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

APP_DIR="/vagrant/app"
# On crée le venv dans /opt pour éviter les verrous de fichiers du dossier partagé Windows
VENV_DIR="/opt/venv"

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv $VENV_DIR
fi

$VENV_DIR/bin/pip install --upgrade pip
$VENV_DIR/bin/pip install -r $APP_DIR/requirements.txt

echo "[APP] Création du service systemd..."
cat <<EOF > /etc/systemd/system/resultats-app.service
[Unit]
Description=Service Applicatif Résultats-BF
After=network.target

[Service]
User=root
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/gunicorn --bind 0.0.0.0:3000 app:app
Restart=always
Environment=DB_HOST=192.168.62.31
Environment=DB_PORT=5432
Environment=DB_NAME=resultats_db
Environment=DB_USER=admin
Environment=DB_PASSWORD=M0t2p@ss

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable resultats-app
systemctl restart resultats-app

echo "[APP] Application configurée et démarrée avec succès."