#!/usr/bin/env bash
# lb1 / lb2 : HAProxy (+ keepalived si l'extension E1 est active) — idempotent.
# La liste des serveurs applicatifs est ENGENDRÉE depuis config/noeuds.yml : aucune adresse en dur.
source /vagrant/scripts/lib.sh

generer_haproxy() {
  local moi="$1"
  cat <<CFG
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    mode http
    timeout connect 2s
    timeout client  10s
    timeout server  10s
    timeout check   1s
    retries 2
    option redispatch

frontend entree
    bind *:80
    default_backend apps

backend apps
    balance roundrobin
    option httpchk
    http-check send meth GET uri /sante
    http-check expect status 200
    default-server inter 500ms fall 2 rise 2
CFG
  while read -r nom ip; do
    echo "    server $nom $ip:3000 check"
  done < <(liste_app)
  cat <<CFG

listen stats
    bind $moi:8404
    stats enable
    stats uri /
    stats refresh 5s
CFG
  if ext_active E2; then
    cat <<CFG

frontend metriques
    bind $moi:8405
    http-request use-service prometheus-exporter if { path /metrics }
    no log
CFG
  fi
}

generer_keepalived() {   # <moi> <pair> <vip> <interface>
  local moi="$1" pair="$2" vip="$3" iface="$4" etat prio
  if [[ "$(hostname)" == "lb1" ]]; then etat=MASTER; prio=150; else etat=BACKUP; prio=100; fi
  cat <<CFG
vrrp_script chk_haproxy {
    script "/usr/bin/systemctl is-active --quiet haproxy"
    interval 1
    fall 2
    rise 2
}

vrrp_instance VI_1 {
    state $etat
    interface $iface
    virtual_router_id 51
    priority $prio
    advert_int 1
    unicast_src_ip $moi
    unicast_peer {
        $pair
    }
    authentication {
        auth_type PASS
        auth_pass ${VRRP_PASSWORD:0:8}
    }
    virtual_ipaddress {
        $vip/24
    }
    track_script {
        chk_haproxy
    }
}
CFG
}

principal() {
  local moi; moi="$(ip_de "$(hostname)")"
  installer_paquets haproxy
  installer_node_exporter

  # --- HAProxy : on valide la configuration AVANT de l'installer, et on ne recharge que si elle change ---
  local tmp; tmp="$(mktemp)"
  generer_haproxy "$moi" > "$tmp"
  haproxy -c -q -f "$tmp"
  if ecrire_si_different /etc/haproxy/haproxy.cfg < "$tmp"; then
    systemctl enable haproxy >/dev/null 2>&1
    systemctl reload-or-restart haproxy
    log "HAProxy : configuration mise à jour ($(liste_app | wc -l) serveurs applicatifs)"
  else
    systemctl enable --now haproxy >/dev/null 2>&1
    log "HAProxy : configuration inchangée"
  fi
  rm -f "$tmp"

  # --- E1 : répartiteur redondant (keepalived + IP virtuelle) si lb2 existe dans la source de vérité ---
  local lb1 lb2 vip pair iface
  lb1="$(ip_de lb1)"; lb2="$(ip_de lb2)"; vip="$(ip_de vip)"
  if [[ -n "$lb2" ]]; then
    installer_paquets keepalived
    if [[ "$(hostname)" == "lb1" ]]; then pair="$lb2"; else pair="$lb1"; fi
    iface="$(ip -o -4 addr show | awk -v ip="$moi" '$4 ~ "^"ip"/" {print $2}')"
    if MODE=0600 ecrire_si_different /etc/keepalived/keepalived.conf < <(generer_keepalived "$moi" "$pair" "$vip" "$iface"); then
      systemctl enable keepalived >/dev/null 2>&1
      systemctl restart keepalived
      log "keepalived : configuré (VIP $vip sur $iface)"
    else
      systemctl enable --now keepalived >/dev/null 2>&1
    fi
  fi
}

# Permet de tester les fonctions de génération sans les exécuter (source ... sans main)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then principal; fi
