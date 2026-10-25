#!/bin/bash
set -e

echo "[BDD] Installation de PostgreSQL..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y postgresql postgresql-contrib prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

echo "[BDD] Attente de la disponibilité de l'utilisateur postgres..."
until id "postgres" &>/dev/null; do
    sleep 1
done

systemctl enable postgresql
systemctl start postgresql

echo "[BDD] Configuration pour le réseau privé 192.168.62.0/24..."
PG_CONF="/etc/postgresql/*/main/postgresql.conf"
PG_HBA="/etc/postgresql/*/main/pg_hba.conf"

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF

# 1. Autorisation de connexion classique pour le réseau privé
echo "host    all             all             192.168.62.0/24         md5" >> $PG_HBA

# 2. AJOUT : Autorisation spécifique pour la réplication (nécessaire pour bdd2)
echo "host    replication     replicator      192.168.62.0/24         trust" >> $PG_HBA

systemctl restart postgresql

echo "[BDD] Création de l'utilisateur, de la base, de l'utilisateur de réplication et des 50 000 lignes de test..."
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'admin') THEN
      CREATE ROLE admin LOGIN PASSWORD 'M0t2p@ss';
   END IF;
   
   -- AJOUT : Création du rôle de réplication pour bdd2
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
      CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';
   END IF;
END
\$\$;

DROP DATABASE IF EXISTS resultats_db;
CREATE DATABASE resultats_db OWNER admin;
EOF

sudo -u postgres psql -d resultats_db <<EOF
CREATE TABLE IF NOT EXISTS resultats (
    matricule VARCHAR(20) PRIMARY KEY,
    nom VARCHAR(100),
    serie VARCHAR(10),
    moyenne NUMERIC(4,2),
    admis BOOLEAN
);

INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT 
    'MAT' || lpad(i::text, 6, '0'),
    'Candidat ' || i,
    CASE (i % 4) WHEN 0 THEN 'A' WHEN 1 THEN 'C' WHEN 2 THEN 'D' ELSE 'G2' END,
    round((random() * 12 + 6)::numeric, 2),
    (random() >= 0.5)
FROM generate_series(1, 50000) AS i
ON CONFLICT (matricule) DO NOTHING;
EOF

echo "[BDD] Base de données et réplication configurées avec succès."