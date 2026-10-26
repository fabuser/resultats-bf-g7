# RÉSULTATS-BF — plateforme résiliente et scalable décrite en code

Projet de groupe 7 du module *DevOps et infrastructures reproductibles* (M1 Informatique, IBAM / UJKZ — Dr SOMDA).
Une infrastructure de consultation de résultats d'examens, **entièrement reconstructible** avec `vagrant up`,
qui survit à la panne d'un serveur applicatif, d'une base ou d'un répartiteur, et qui passe à l'échelle
en changeant **une seule valeur** (`NB_APP`).

```
Hôte ──► lb1 (HAProxy + keepalived) ──► app1 … appN (Python, sans état) ──► bdd1 (PostgreSQL primaire)
          lb2 (E1, VIP .5)                                                     │ réplication en flux
          obs (E2 : Prometheus + Grafana)                                      ▼
                                                                              bdd2 (réplique, promouvable)
```

## 1. Prérequis (poste de 8 Go minimum)

| Outil | Version testée / exigée |
|---|---|
| VirtualBox | ≥ 6.1.28 (plage hôte-seul `192.168.56.0/21` autorisée par défaut) |
| Vagrant | ≥ 2.3 |
| Git | toute version récente (Windows : Git for Windows, qui fournit `bash`, `curl`, `date` GNU) |
| `ab` (apache2-utils) | pour le scénario V3 (sinon lancer les tests depuis une VM) |

Boîte imposée : `bento/ubuntu-24.04`, version épinglée dans le `Vagrantfile` (identique pour tout le groupe).
Aucune ressource payante, aucun compte cloud. Le premier `vagrant up` télécharge la boîte et les paquets :
prévoir une connexion correcte une fois ; les `apt-get install` sont groupés pour limiter le volume.

### Poste Windows (11)
- Lancer **toutes** les commandes dans **Git Bash** (les scripts `bin/` et `tests/` sont en Bash). La syntaxe du sujet `NB_APP=4 vagrant up` est du Bash ; en **PowerShell** : `$env:NB_APP=4; vagrant up`.
- Fins de ligne : `git config --global core.autocrlf false` avant de cloner ; le `.gitattributes` force déjà LF.
- VirtualBox et Hyper-V / WSL2 / « Intégrité de la mémoire » peuvent entrer en conflit (VM très lentes ou refus de démarrer) : à vérifier **avant** les mesures.
- `ab` n'existe pas nativement : installer les binaires Apache pour Windows et ajouter `ab.exe` au `PATH` de Git Bash, ou lancer V3 depuis une VM en le **déclarant** dans le dossier.

## 2. Démarrage rapide (sans autre geste manuel)

```bash
git clone <url-du-depot> resultats-bf && cd resultats-bf
cp .env.exemple .env        # puis changer les mots de passe dans .env (jamais versionné)
vagrant up                  # construit bdd1, bdd2, app1, app2, lb1  (~3 Go de RAM)
curl http://localhost:8080/info                          # via le port exposé par lb1
curl "http://localhost:8080/resultat?matricule=M012345"  # un résultat, en JSON
```

Variante réseau privé (recommandée pour les mesures, évite la redirection NAT) : `http://192.168.62.11/...`
(groupe 7 ; en général `192.168.(55+GROUPE).11`).

## 3. Paramètres (fichier `.env`, ou variables d'environnement qui l'emportent)

| Variable | Rôle | Exemple |
|---|---|---|
| `GROUPE` | numéro de groupe 1..8 → sous-réseau `192.168.(55+G).0/24` | `7` → `192.168.62.0/24` |
| `NB_APP` | nombre de serveurs applicatifs (2..9) | `4` |
| `EXTENSIONS` | extensions actives : `E1` (lb2 + VRRP), `E2` (obs) | `E1,E2` |
| `DB_*`, `REPL_PASSWORD`, `VRRP_PASSWORD`, `GRAFANA_PASSWORD` | secrets | voir `.env.exemple` |

Mémoire : socle (N=2) = 3072 Mo ; +E1 = +512 Mo ; +E2 = +768 Mo. **Activez les extensions une par une** pendant le développement.

## 4. Procédures d'exploitation

**Ajouter / retirer des serveurs applicatifs** (une seule valeur change : `NB_APP`)
```bash
bin/scale.sh 4        # modifie NB_APP, crée app3/app4, régénère la configuration HAProxy
bin/scale.sh 2        # détruit app3/app4, régénère la configuration HAProxy
```
Équivalent manuel : mettre `NB_APP=4` dans `.env` (ou `NB_APP=4 vagrant up` en Bash), puis `vagrant provision lb1` (Vagrant ne
re-provisionne pas une VM déjà démarrée ; le répartiteur est donc reprovisionné explicitement).
La configuration du répartiteur est **engendrée** depuis `config/noeuds.yml` (lui-même écrit par le `Vagrantfile`) :
aucune adresse d'application n'est écrite en dur.

**Bascule de la base** (panne de bdd1) — scénario V4, chronométrée
```bash
vagrant halt bdd1               # (ou panne réelle)
scripts/hote/bascule.sh         # promeut bdd2, repointe les applications, attend le retour du 200
```
Après une bascule, **ne relancez pas** `vagrant up bdd1` tel quel (deux primaires) : voir le dossier d'architecture §Limites.
`vagrant provision bdd2` est neutre après promotion (garde-fou dans `scripts/replique.sh`).

**Extensions**
- E1 : `EXTENSIONS=E1` dans `.env`, puis `vagrant up lb2 && vagrant provision lb1`. Adresse stable : `http://192.168.62.5` (VIP).
- E2 : `EXTENSIONS=E2`, puis `vagrant up obs && vagrant provision` (les nœuds installent `node_exporter`).
  Grafana : `http://192.168.62.41:3000` (utilisateur `admin`, mot de passe `GRAFANA_PASSWORD`), Prometheus `:9090`.
  Non exposés vers l'hôte via NAT : accès par le réseau privé uniquement (R8).

## 5. Scénarios de validation (résultats bruts écrits dans `results/`)

| Scénario | Commande | Pré-requis |
|---|---|---|
| R2 idempotence | `tests/r2_idempotence.sh` | plateforme up |
| R5 réplication | `tests/r5_replication.sh` | plateforme up |
| V1 répartition | `tests/v1_repartition.sh` | plateforme up |
| V2 panne d'un serveur applicatif | `tests/v2_panne_app.sh` (`MODE=poweroff` pour une coupure brutale) | plateforme up |
| V3 montée en charge | `tests/v3_charge.sh` à N=2 puis `bin/scale.sh 4` et `tests/v3_charge.sh` | `ab` installé |
| V4 panne de la base primaire | `tests/v4_panne_bdd.sh` | plateforme up |
| V5 reconstruction | `tests/v5_reconstruction.sh` | détruit tout |
| V6 panne du répartiteur (E1) | `tests/v6_panne_lb.sh` | `EXTENSIONS=E1` |

Chaque script écrit `results/<scénario>-<horodatage>.txt` (commande, mesures brutes, version du dépôt, machine hôte).
Ne jamais retoucher ces fichiers à la main : ils sont la preuve que les mesures ne sont pas inventées.

## 6. Structure du dépôt

```
Vagrantfile          source unique de vérité (table NOEUDS) -> VM + config/noeuds.yml
.env.exemple         modèle des paramètres et secrets (le vrai .env n'est jamais versionné)
.gitattributes       fins de ligne LF (un script CRLF échoue dans la VM)
app/app.py           service HTTP Python (< 100 lignes, sans état)
config/schema.sql    rôles, base, slot de réplication, table et 50 000 lignes (generate_series)
config/grafana/      datasource, provider et tableau de bord (E2)
scripts/             provisionnement des VM (lib.sh, bdd.sh, replique.sh, app.sh, lb.sh, obs.sh)
scripts/hote/        procédure de bascule exécutée depuis l'hôte
bin/scale.sh         changer le nombre de serveurs applicatifs
tests/               scénarios R2, R5, V1 à V6
results/             résultats bruts des mesures
docs/                dossier d'architecture, journal de bord, plan de démonstration
```

## 7. Dépannage rapide

| Symptôme | Cause probable | Remède |
|---|---|---|
| `vagrant up` : « Fichier .env absent » | `.env` non créé | `cp .env.exemple .env` |
| `E_ACCESSDENIED` / plage d'adresses refusée | VirtualBox < 6.1.28 ou mauvais `GROUPE` | vérifier `GROUPE` (1..8) ; ne **jamais** modifier `/etc/vbox/networks.conf` |
| Script de VM : `\r: command not found` | fins de ligne CRLF | `git config core.autocrlf false` puis re-cloner (le `.gitattributes` force LF) |
| `/sante` renvoie 503 après le démarrage | base pas encore prête ou mot de passe `.env` ≠ celui du premier `up` | `vagrant provision bdd1 app1 app2` ; au besoin `vagrant destroy -f` et `vagrant up` |
| Une app absente de la répartition | VM éteinte ou sonde en échec | `curl http://192.168.62.11:8404/` (page de statistiques HAProxy, réseau privé) |
| `ab` introuvable (Windows) | non installé | lancer V3 depuis une VM (`vagrant ssh lb1`) et le **déclarer** dans le dossier |

## 8. Sécurité (R7, R8)
Aucun secret dans l'historique : `.env` est ignoré, `.env.exemple` ne contient que des valeurs d'exemple.
Les secrets sont transmis aux VM par variables d'environnement du provisionnement, puis écrits dans des fichiers
`root:root 0600` (`/etc/resultats/app.env`, `/etc/default/grafana-server`). PostgreSQL n'accepte que le réseau privé du groupe
(`pg_hba.conf` engendré), uniquement pour les rôles `appuser` (base `resultats`) et `replicator`.
Seuls les répartiteurs ont une redirection de port vers l'hôte (`8080` pour lb1, `8081` pour lb2).
