#!/usr/bin/env bash
# bdd1 : PostgreSQL primaire (lecture + écriture) — idempotent.
source /vagrant/scripts/lib.sh
MOI="$(ip_de bdd1)"; RESEAU_CIDR="${MOI%.*}.0/24"
PGVER=16; CONF="/etc/postgresql/$PGVER/main"

installer_paquets postgresql
installer_node_exporter

# Écoute sur toutes les interfaces (piège n°1 : 127.0.0.1 = injoignable) + paramètres de réplication.
CHANGE=0
ecrire_si_different "$CONF/conf.d/90-resultats.conf" <<CFG && CHANGE=1
listen_addresses = '*'
wal_level = replica
max_wal_senders = 5
wal_keep_size = 256MB
hot_standby = on
password_encryption = scram-sha-256
CFG

# Contrôle d'accès : réseau privé du groupe uniquement, et uniquement pour les rôles nécessaires (R8).
MODE=0640 ecrire_si_different "$CONF/pg_hba.conf" <<HBA && CHANGE=1
local   all           postgres                      peer
local   all           all                           peer
host    all           all           127.0.0.1/32    scram-sha-256
host    $DB_NAME      $DB_USER      $RESEAU_CIDR    scram-sha-256
host    replication   replicator    $RESEAU_CIDR    scram-sha-256
HBA
chown postgres:postgres "$CONF/pg_hba.conf"

systemctl enable postgresql >/dev/null 2>&1
if [[ $CHANGE -eq 1 ]]; then systemctl restart postgresql; else systemctl start postgresql; fi
until sudo -u postgres pg_isready -q; do sleep 1; done

# Rôles, base, slot, table et 50 000 lignes : rejouable sans doublon.
# (la redirection est lue par root, volontairement : postgres n'a pas besoin de lire /vagrant)
# shellcheck disable=SC2024
sudo -u postgres --preserve-env=DB_USER,DB_NAME,DB_PASSWORD,REPL_PASSWORD \
  psql -q -v ON_ERROR_STOP=1 -f - < /vagrant/config/schema.sql >/dev/null
log "bdd1 prête : $(sudo -u postgres psql -tA -d "$DB_NAME" -c 'SELECT count(*) FROM resultats') lignes"
