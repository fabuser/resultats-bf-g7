#!/usr/bin/env bash
# bdd2 : réplique en flux de bdd1, promouvable — idempotent.
source /vagrant/scripts/lib.sh
PRIMAIRE="$(ip_de bdd1)"; MOI="$(ip_de bdd2)"; RESEAU_CIDR="${MOI%.*}.0/24"
PGVER=16; CONF="/etc/postgresql/$PGVER/main"; DATA="/var/lib/postgresql/$PGVER/main"

installer_paquets postgresql
installer_node_exporter

ecrire_si_different "$CONF/conf.d/90-resultats.conf" <<CFG || true
listen_addresses = '*'
wal_level = replica
max_wal_senders = 5
wal_keep_size = 256MB
hot_standby = on
password_encryption = scram-sha-256
CFG
# Même pg_hba que bdd1 : après promotion, bdd2 doit pouvoir servir les applications.
MODE=0640 ecrire_si_different "$CONF/pg_hba.conf" <<HBA || true
local   all           postgres                      peer
local   all           all                           peer
host    all           all           127.0.0.1/32    scram-sha-256
host    $DB_NAME      $DB_USER      $RESEAU_CIDR    scram-sha-256
host    replication   replicator    $RESEAU_CIDR    scram-sha-256
HBA
chown postgres:postgres "$CONF/pg_hba.conf"

# Garde-fou : une promotion supprime standby.signal. Si le marqueur d'initialisation existe sans
# standby.signal, bdd2 est devenue primaire : un "vagrant provision" ne doit surtout pas l'écraser.
MARQUEUR=/var/lib/postgresql/.bdd2_initialisee
if [[ -f "$MARQUEUR" && ! -f "$DATA/standby.signal" ]]; then
  log "ATTENTION : bdd2 a été promue (primaire). On ne la reconstruit PAS en réplique."
  exit 0
fi

if [[ ! -f "$DATA/standby.signal" ]]; then
  log "Initialisation de la réplique depuis $PRIMAIRE (pg_basebackup)"
  attendre_port "$PRIMAIRE" 5432 120
  systemctl stop postgresql
  find "$DATA" -mindepth 1 -delete
  sudo -u postgres env PGPASSWORD="$REPL_PASSWORD" \
    pg_basebackup -h "$PRIMAIRE" -U replicator -D "$DATA" -X stream -S bdd2_slot -R -c fast
  touch "$MARQUEUR"
fi

systemctl enable postgresql >/dev/null 2>&1
systemctl restart postgresql
until sudo -u postgres pg_isready -q; do sleep 1; done
log "bdd2 : en réplication = $(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()') (t = réplique)"
