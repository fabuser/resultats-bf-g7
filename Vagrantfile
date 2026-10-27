# -*- mode: ruby -*-
# RÉSULTATS-BF — infrastructure résiliente et scalable décrite en code.
# Source unique de vérité : la table NOEUDS ci-dessous. Elle décrit les VM
# ET est écrite dans config/noeuds.yml, lue par tous les scripts (dont celui du répartiteur).
require 'fileutils'

# ---------- 1. Paramètres : .env (jamais versionné) puis variables d'environnement ----------
def lire_env(chemin)
  h = {}
  return h unless File.exist?(chemin)
  File.readlines(chemin, encoding: 'UTF-8').each do |l|
    l = l.scrub.sub(/\s+#.*$/, '').strip            # retire commentaires de fin de ligne
    next if l.empty? || l.start_with?('#') || !l.include?('=')
    k, v = l.split('=', 2)
    h[k.strip] = v.strip.gsub(/\A["']|["']\z/, '')
  end
  h
end

DOTENV = lire_env(File.join(__dir__, '.env'))
def param(nom, defaut = nil)
  ENV[nom] || DOTENV[nom] || defaut
end

if !File.exist?(File.join(__dir__, '.env')) && %w[up provision reload].include?(ARGV[0])
  abort "Fichier .env absent : exécutez  cp .env.exemple .env  puis adaptez les valeurs."
end

GROUPE     = param('GROUPE', 7).to_i                  # 1..8
NB_APP     = param('NB_APP', 4).to_i                  # nombre de serveurs applicatifs
EXTENSIONS = param('EXTENSIONS', '').split(',').map(&:strip).reject(&:empty?)
abort "GROUPE doit être compris entre 1 et 8"      unless (1..8).cover?(GROUPE)
abort "NB_APP doit être compris entre 2 et 9"      unless (2..9).cover?(NB_APP)

RESEAU  = "192.168.#{55 + GROUPE}"                    # plage imposée par le sujet (§7.1)
BOITE   = "bento/ubuntu-24.04"
VERSION = "202510.26.0"                               # version épinglée, identique pour tout le groupe

# ---------- 2. Source unique de vérité ----------
NOEUDS = []
NOEUDS << { nom: "bdd1", ip: "#{RESEAU}.31", mem: 768, role: "bdd" }
NOEUDS << { nom: "bdd2", ip: "#{RESEAU}.32", mem: 768, role: "replique" }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: 512, role: "app" }
end
NOEUDS << { nom: "lb1", ip: "#{RESEAU}.11", mem: 512, role: "lb" }
NOEUDS << { nom: "lb2", ip: "#{RESEAU}.12", mem: 512, role: "lb" }
NOEUDS << { nom: "obs", ip: "#{RESEAU}.41", mem: 768, role: "obs" }
NOEUDS << { nom: "lb2", ip: "#{RESEAU}.12", mem: 512, role: "lb" }   if EXTENSIONS.include?("E1")
NOEUDS << { nom: "obs", ip: "#{RESEAU}.41", mem: 768, role: "obs" } if EXTENSIONS.include?("E2")
VIP = "#{RESEAU}.5"                                    # IP virtuelle VRRP (E1)

# Fichier lu par les scripts : /vagrant/config/noeuds.yml (écrit en binaire => LF même sous Windows)
yaml = NOEUDS.map { |n| "- nom: #{n[:nom]}\n  ip: #{n[:ip]}\n  role: #{n[:role]}\n" }.join
yaml << "- nom: vip\n  ip: #{VIP}\n  role: vip\n"
FileUtils.mkdir_p(File.join(__dir__, "config"))
File.binwrite(File.join(__dir__, "config", "noeuds.yml"), yaml)

# Variables transmises aux scripts de provisionnement (jamais écrites dans le dépôt)
ENV_VM = {
  "EXTENSIONS"       => EXTENSIONS.join(","),
  "DB_NAME"          => param("DB_NAME", "resultats"),
  "DB_USER"          => param("DB_USER", "appuser"),
  "DB_PASSWORD"      => param("DB_PASSWORD", ""),
  "REPL_PASSWORD"    => param("REPL_PASSWORD", ""),
  "VRRP_PASSWORD"    => param("VRRP_PASSWORD", ""),
  "GRAFANA_PASSWORD" => param("GRAFANA_PASSWORD", ""),
}

# ---------- 3. Définition des machines ----------
Vagrant.configure("2") do |config|
  config.vm.box = BOITE
  config.vm.box_version = VERSION
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant", type: "virtualbox"

  NOEUDS.each do |n|
    config.vm.define n[:nom] do |m|
      m.vm.hostname = n[:nom]
      m.vm.network "private_network", ip: n[:ip]          # R8 : trafic interne = réseau privé
      # R8 : seuls les répartiteurs exposent un port vers l'hôte
      m.vm.network "forwarded_port", guest: 80, host: 8080, id: "http" if n[:nom] == "lb1"
      m.vm.network "forwarded_port", guest: 80, host: 8081, id: "http" if n[:nom] == "lb2"
      m.vm.provider "virtualbox" do |vb|
        vb.name   = "g#{GROUPE}-#{n[:nom]}"
        vb.memory = n[:mem]
        vb.cpus   = 1
        vb.linked_clone = true if Gem::Version.new(Vagrant::VERSION) >= Gem::Version.new("1.8")
      end
      m.vm.provision "shell", path: "scripts/#{n[:role]}.sh", env: ENV_VM
    end
  end
end
