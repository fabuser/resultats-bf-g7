-- Rôles, base et jeu de données. Rejouable sans effet de bord (idempotent).
-- Exécuté sur bdd1 uniquement ; bdd2 reçoit tout par réplication.
-- Les secrets viennent de l'environnement (\getenv) : rien en clair dans ce fichier.
\set ON_ERROR_STOP on
\getenv db_user DB_USER
\getenv db_name DB_NAME
\getenv db_pwd DB_PASSWORD
\getenv repl_pwd REPL_PASSWORD

SELECT format('CREATE ROLE %I LOGIN', :'db_user')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'db_user', :'db_pwd') \gexec

SELECT 'CREATE ROLE replicator REPLICATION LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') \gexec
SELECT format('ALTER ROLE replicator PASSWORD %L', :'repl_pwd') \gexec

SELECT format('CREATE DATABASE %I', :'db_name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec

-- Slot de réplication physique : la primaire conserve les WAL tant que bdd2 ne les a pas reçus.
SELECT pg_create_physical_replication_slot('bdd2_slot')
 WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'bdd2_slot');

\c :db_name
CREATE TABLE IF NOT EXISTS resultats (
  matricule text PRIMARY KEY,
  nom       text NOT NULL,
  serie     text NOT NULL,
  moyenne   numeric(4,2) NOT NULL,
  admis     boolean NOT NULL
);
SELECT format('GRANT SELECT ON resultats TO %I', :'db_user') \gexec

-- 50 000 lignes engendrées par generate_series, graine fixée => jeu de données reproductible.
SELECT setseed(0.42);
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT matricule, nom, serie, moyenne, moyenne >= 10
FROM (SELECT 'M' || lpad(i::text, 6, '0')            AS matricule,
             'Candidat ' || i                         AS nom,
             (ARRAY['A','C','D','E'])[1 + i % 4]      AS serie,
             round((random() * 20)::numeric, 2)       AS moyenne
      FROM generate_series(1, 50000) AS i) t
WHERE NOT EXISTS (SELECT 1 FROM resultats);
