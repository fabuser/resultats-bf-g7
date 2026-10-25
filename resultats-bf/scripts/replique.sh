#!/bin/bash
set -e

PRIMARY_IP="192.168.62.31"
PG_VER="16"
PG_DIR="/var/lib/postgresql/${PG_VER}/main"

echo "[REPLIQUE] Installation de PostgreSQL et Node Exporter..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y postgresql-${PG_VER} postgresql-contrib-${PG_VER} prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

echo "[REPLIQUE] Configuration automatique du nœud secondaire bdd2..."

# 1. Arrêt de PostgreSQL
systemctl stop postgresql-@${PG_VER}-main 2>/dev/null || systemctl stop postgresql 2>/dev/null || true

# 2. Nettoyage total du répertoire de données
rm -rf "${PG_DIR}"

# 3. Clonage depuis le primaire bdd1 via pg_basebackup
sudo -u postgres pg_basebackup -h "${PRIMARY_IP}" -U replicator -D "${PG_DIR}" -P --wal-method=stream

# 4. Activation du mode standby (réplique)
sudo -u postgres touch "${PG_DIR}/standby.signal"

# 5. Démarrage de PostgreSQL (Démarré AVANT le psql pour que le socket existe)
systemctl start postgresql

# 6. Injection automatique du paramètre de connexion au primaire
sudo -u postgres psql -c "ALTER SYSTEM SET primary_conninfo = 'host=${PRIMARY_IP} port=5432 user=replicator application_name=bdd2';"

# Redémarrage final pour s'assurer que tout est bien pris en compte
systemctl restart postgresql

echo "[REPLIQUE] Nœud réplique et agent de supervision configurés avec succès !"