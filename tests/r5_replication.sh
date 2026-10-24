#!/usr/bin/env bash
# R5 — Une écriture sur bdd1 est visible sur bdd2 (réplique en flux).
source "$(dirname "$0")/lib.sh"; demarrer R5
M="TEST$(date +%s)"
echo "Insertion sur bdd1 : $M"
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -qtA -c \"INSERT INTO resultats VALUES ('$M','Test replication','A',12.5,true)\"" 2>/dev/null
sleep 1
echo "Lecture sur bdd2 :"
vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats -tA -c \"SELECT * FROM resultats WHERE matricule='$M'\"" 2>/dev/null
echo "bdd2 en recovery (t = réplique) : $(vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery()'" 2>/dev/null | tr -d '\r')"
echo "État de la réplication vu depuis bdd1 :"
vagrant ssh bdd1 -c "sudo -u postgres psql -c 'SELECT client_addr, state, sync_state, replay_lsn FROM pg_stat_replication'" 2>/dev/null
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -qtA -c \"DELETE FROM resultats WHERE matricule='$M'\"" >/dev/null 2>&1
