#!/usr/bin/env bash
# R2 — Idempotence : vagrant provision rejoué deux fois ne modifie rien (empreintes des fichiers de configuration).
source "$(dirname "$0")/lib.sh"; demarrer R2
VMS=$(awk '/^- nom:/{nom=$3} /^  role:/{if($2!="vip")print nom}' "$NOEUDS")
EMPREINTE='sudo find /etc/haproxy /etc/keepalived /etc/postgresql /etc/resultats /etc/prometheus /etc/grafana/provisioning /etc/systemd/system/resultats-app.service -type f -exec md5sum {} + 2>/dev/null | sort; sudo -u postgres psql -d resultats -tAc "SELECT count(*) FROM resultats" 2>/dev/null || true'
snap() { for v in $VMS; do echo "## $v"; vagrant ssh "$v" -c "$EMPREINTE" 2>/dev/null | tr -d '\r'; done; }
echo "Empreinte avant rejeu"; snap > /tmp/r2_0.txt
for i in 1 2; do
  echo "vagrant provision (passage $i)"
  if vagrant provision >"/tmp/r2_prov_$i.log" 2>&1; then echo "  -> succès"; else echo "  -> ÉCHEC (voir /tmp/r2_prov_$i.log)"; exit 1; fi
  snap > "/tmp/r2_$i.txt"
done
if diff -q /tmp/r2_0.txt /tmp/r2_2.txt >/dev/null && diff -q /tmp/r2_1.txt /tmp/r2_2.txt >/dev/null; then
  echo "RÉSULTAT : empreintes identiques avant / après 2 rejeux -> idempotent"
else echo "RÉSULTAT : DIFFÉRENCES détectées :"; diff /tmp/r2_0.txt /tmp/r2_2.txt || true; fi
