#!/usr/bin/env bash
# V5 — Reconstruction : vagrant destroy -f puis vagrant up, sans aucune intervention. Mesure la durée totale.
# ATTENTION : détruit TOUTES les VM du projet. À lancer de préférence sur le poste d'un autre membre du groupe.
source "$(dirname "$0")/lib.sh"; demarrer V5
read -r -p "Détruire et reconstruire toute la plateforme ? [o/N] " R; [[ "$R" =~ ^[oO]$ ]] || exit 0
T0=$(now)
vagrant destroy -f
T1=$(now)
vagrant up
T2=$(now)
echo "Destruction : $(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.0f", b-a}') s | Reconstruction (vagrant up) : $(awk -v a="$T1" -v b="$T2" 'BEGIN{printf "%.0f", b-a}') s | TOTAL : $(awk -v a="$T0" -v b="$T2" 'BEGIN{printf "%.0f", b-a}') s"
echo "Contrôle : GET $LB_URL/sante -> $(curl -s -m 3 -w ' [%{http_code}]' "$LB_URL/sante")"
echo "Contrôle : GET $LB_URL/resultat?matricule=M000001 -> $(curl -s -m 3 "$LB_URL/resultat?matricule=M000001")"
