#!/bin/bash
set -e

echo "[OBS] Installation de Prometheus et des prérequis pour Grafana..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y prometheus python3-yaml curl apt-transport-https software-properties-common gpg

systemctl enable prometheus
systemctl start prometheus

echo "[OBS] Ajout du dépôt officiel Grafana..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install -y grafana

systemctl enable grafana-server
systemctl start grafana-server

echo "[OBS] Génération dynamique de la configuration Prometheus..."
python3 - << 'EOF'
import yaml

with open('/vagrant/config/noeuds.yml', 'r') as f:
    noeuds = yaml.safe_load(f)

# Extraction des IP et ajout du port 9100 (node_exporter)
targets = [f"{n['ip']}:9100" for n in noeuds if isinstance(n, dict) and 'ip' in n]

# Construction propre de la configuration au format YAML
prom_config = {
    'global': {
        'scrape_interval': '15s'
    },
    'scrape_configs': [
        {
            'job_name': 'resultats-bf-cluster',
            'static_configs': [
                {
                    'targets': targets
                }
            ]
        }
    ]
}

with open('/etc/prometheus/prometheus.yml', 'w') as f:
    yaml.dump(prom_config, f, default_flow_style=False)
EOF

systemctl restart prometheus
echo "[OBS] Supervision configurée avec succès sur obs (.41)."