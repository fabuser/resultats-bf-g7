#!/usr/bin/env bash
# bdd1 : PostgreSQL primaire (lecture + écriture) — idempotent.
# Si bdd2 a été promue pendant une panne, bdd1 revient en RÉPLIQUE de bdd2 (pas de split-brain).
source /vagrant/scripts/lib.sh
MOI="$(ip_de bdd1)"; BDD2="$(ip_de bdd2)"; RESEAU_CIDR="${MOI%.*}.0/24"
PGVER=16; CONF="/etc/postgresql/$PGVER/main"; DATA="/var/lib/postgresql/$PGVER/main"
PGPASSFILE=/var/lib/postgresql/.pgpass

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

# Identifiants pour interroger bdd2 et copier depuis elle (lus par l'utilisateur postgres).
MODE=0600 ecrire_si_different "$PGPASSFILE" <<PGPASS || true
$BDD2:5432:$DB_NAME:$DB_USER:$DB_PASSWORD
$BDD2:5432:replication:replicator:$REPL_PASSWORD
PGPASS
chown postgres:postgres "$PGPASSFILE"

# Garde de démarrage : refuse de lancer bdd1 en primaire si bdd2 est déjà primaire.
MODE=0755 ecrire_si_different /usr/local/bin/garde-primaire.sh <<SCRIPT || true
#!/usr/bin/env bash
[[ -f "$DATA/standby.signal" ]] && exit 0   # bdd1 est une réplique : aucun risque
r=\$(runuser -u postgres -- env PGPASSFILE=$PGPASSFILE psql "host=$BDD2 dbname=$DB_NAME user=$DB_USER connect_timeout=3" -tAc 'SELECT pg_is_in_recovery()' 2>/dev/null)
if [[ "\$r" == "f" ]]; then
  echo "bdd2 est primaire : démarrage de bdd1 en primaire REFUSÉ (split-brain). Lancer : vagrant provision bdd1" >&2
  exit 1
fi
exit 0
SCRIPT
mkdir -p "/etc/systemd/system/postgresql@$PGVER-main.service.d"
ecrire_si_different "/etc/systemd/system/postgresql@$PGVER-main.service.d/garde.conf" <<UNIT || true
[Service]
ExecStartPre=+/usr/local/bin/garde-primaire.sh
UNIT
systemctl daemon-reload

# Si bdd2 a pris le relais, bdd1 devient sa réplique au lieu de redémarrer en primaire.
bdd2_est_primaire() {
  [[ "$(sudo -u postgres env PGPASSFILE="$PGPASSFILE" psql \
        "host=$BDD2 dbname=$DB_NAME user=$DB_USER connect_timeout=5" \
        -tAc 'SELECT pg_is_in_recovery()' 2>/dev/null)" == "f" ]]
}
if [[ ! -f "$DATA/standby.signal" ]] && bdd2_est_primaire; then
  log "bdd2 est primaire : reconstruction de bdd1 en réplique de bdd2"
  systemctl stop postgresql
  find "$DATA" -mindepth 1 -delete
  sudo -u postgres env PGPASSFILE="$PGPASSFILE" \
    pg_basebackup -h "$BDD2" -U replicator -D "$DATA" -X stream -R -c fast \
    || { log "ÉCHEC du pg_basebackup depuis bdd2"; exit 1; }
fi

systemctl enable postgresql >/dev/null 2>&1
if [[ $CHANGE -eq 1 ]]; then systemctl restart postgresql; else systemctl start postgresql; fi
until sudo -u postgres pg_isready -q; do sleep 1; done

# En réplique, la base est en lecture seule : on ne rejoue pas schema.sql.
if [[ -f "$DATA/standby.signal" ]]; then
  log "bdd1 : réplique de bdd2 (en réplication = $(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'))"
  exit 0
fi

# Rôles, base, slot, table et 50 000 lignes : rejouable sans doublon.
# (la redirection est lue par root, volontairement : postgres n'a pas besoin de lire /vagrant)
# shellcheck disable=SC2024
sudo -u postgres --preserve-env=DB_USER,DB_NAME,DB_PASSWORD,REPL_PASSWORD \
  psql -q -v ON_ERROR_STOP=1 -f - < /vagrant/config/schema.sql >/dev/null
log "bdd1 prête : $(sudo -u postgres psql -tA -d "$DB_NAME" -c 'SELECT count(*) FROM resultats') lignes"