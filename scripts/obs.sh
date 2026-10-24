#!/usr/bin/env bash
# obs : Prometheus + Grafana (extension E2) — idempotent.
# Les cibles de collecte sont ENGENDRÉES depuis config/noeuds.yml (comme le répartiteur).
source /vagrant/scripts/lib.sh

generer_prometheus() {
  cat <<CFG
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: node
    static_configs:
      - targets:
CFG
  awk '/^  ip:/{ip=$2} /^  role:/{if($2!="vip") print "          - \"" ip ":9100\""}' "$NOEUDS"
  cat <<CFG
  - job_name: haproxy
    static_configs:
      - targets:
CFG
  awk '/^  ip:/{ip=$2} /^  role:/{if($2=="lb") print "          - \"" ip ":8405\""}' "$NOEUDS"
}

principal() {
  if ! ext_active E2; then log "Extension E2 inactive (EXTENSIONS=$EXTENSIONS) : rien à faire"; exit 0; fi
  installer_paquets prometheus prometheus-node-exporter ca-certificates gnupg wget apt-transport-https

  # Prometheus (paquet Ubuntu)
  if ecrire_si_different /etc/prometheus/prometheus.yml < <(generer_prometheus); then
    systemctl restart prometheus
  fi
  systemctl enable --now prometheus prometheus-node-exporter >/dev/null 2>&1

  # Grafana : dépôt officiel (absent des dépôts Ubuntu)
  if ! dpkg -s grafana >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
    apt-get update -qq
    installer_paquets grafana
  fi
  MODE=0600 ecrire_si_different /etc/default/grafana-server <<ENV || true
GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD
ENV
  ecrire_si_different /etc/grafana/provisioning/datasources/prometheus.yml < /vagrant/config/grafana/datasource.yml || true
  ecrire_si_different /etc/grafana/provisioning/dashboards/resultats.yml  < /vagrant/config/grafana/provider.yml   || true
  ecrire_si_different /var/lib/grafana/dashboards/resultats.json          < /vagrant/config/grafana/dashboard.json || true
  chown -R grafana:grafana /var/lib/grafana/dashboards
  systemctl enable grafana-server >/dev/null 2>&1
  systemctl restart grafana-server
  # Le mot de passe admin n'est lu qu'à la création de la base Grafana : on le réaligne explicitement.
  for _ in $(seq 1 30); do curl -s -o /dev/null http://localhost:3000/api/health && break; sleep 1; done
  grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD" >/dev/null 2>&1 || true
  log "Grafana : http://$(ip_de obs):3000 (utilisateur admin) — Prometheus : http://$(ip_de obs):9090"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then principal; fi
