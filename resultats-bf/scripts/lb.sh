#!/bin/bash
set -e

HOSTNAME=$(hostname)
echo "[LB] Installation de HAProxy et Keepalived sur $HOSTNAME..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y haproxy keepalived python3-yaml prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Génération dynamique des backends HAProxy depuis noeuds.yml de manière sécurisée
python3 - << 'EOF'
import yaml
with open('/vagrant/config/noeuds.yml', 'r') as f:
    noeuds = yaml.safe_load(f)

# On filtre les nœuds en vérifiant que la clé 'role' existe
app_nodes = [n for n in noeuds if isinstance(n, dict) and n.get('role') == 'app']

haproxy_config = """
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

frontend http_in
    bind *:80
    default_backend app_backend

backend app_backend
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
    default-server inter 2s fall 2 rise 2
"""

for app in app_nodes:
    haproxy_config += f"    server {app['nom']} {app['ip']}:3000 check\n"

with open('/etc/haproxy/haproxy.cfg', 'w') as f:
    f.write(haproxy_config)
EOF

systemctl restart haproxy

# Configuration Keepalived (VRRP - Extension E1)
if [ "$HOSTNAME" = "lb1" ]; then
    STATE="MASTER"
    PRIORITY=101
else
    STATE="BACKUP"
    PRIORITY=100
fi

VIP="192.168.62.5"

cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state $STATE
    interface eth1
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass bf_resultats_secret
    }
    virtual_ipaddress {
        $VIP
    }
    track_script {
        check_haproxy
    }
}
EOF

systemctl enable keepalived
systemctl restart keepalived

echo "[LB] Répartiteur et HA/VRRP configurés avec succès."