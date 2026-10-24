#!/usr/bin/env python3
"""Service RÉSULTATS-BF : sans état, tout l'état vit dans la base (PostgreSQL)."""
import json, os, re, socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import psycopg2

DSN = dict(host=os.environ["DB_HOST"], port=5432, dbname=os.environ["DB_NAME"],
           user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"],
           connect_timeout=1, options="-c statement_timeout=2000")
MATRICULE = re.compile(r"^[A-Za-z0-9]{1,20}$")


def requete(sql, params=()):
    """Une connexion par requête : l'application n'a donc aucun état et supporte
    une base absente au démarrage (elle se reconnecte à l'appel suivant)."""
    conn = psycopg2.connect(**DSN)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    def repondre(self, code, corps):
        data = json.dumps(corps, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        try:
            if url.path == "/info":
                return self.repondre(200, {"hote": socket.gethostname()})
            if url.path == "/sante":
                requete("SELECT 1")
                return self.repondre(200, {"etat": "ok"})
            if url.path == "/resultat":
                mat = parse_qs(url.query).get("matricule", [""])[0]
                if not MATRICULE.match(mat):
                    return self.repondre(400, {"erreur": "matricule invalide ou absent"})
                ligne = requete("SELECT matricule, nom, serie, moyenne, admis "
                                "FROM resultats WHERE matricule = %s", (mat,))
                if ligne is None:
                    return self.repondre(404, {"erreur": "matricule inconnu"})
                cles = ("matricule", "nom", "serie", "moyenne", "admis")
                ligne = [float(v) if k == "moyenne" else v for k, v in zip(cles, ligne)]
                return self.repondre(200, dict(zip(cles, ligne)))
            return self.repondre(404, {"erreur": "point d'entrée inconnu"})
        except psycopg2.Error:       # base injoignable ou en erreur : 503 propre, jamais de page blanche
            return self.repondre(503, {"erreur": "base indisponible"})

    def log_message(self, *args):    # pas de journal par requête (coût CPU sous charge)
        pass


class Serveur(ThreadingHTTPServer):
    request_queue_size = 128         # défaut Python = 5 : insuffisant pour ab -c 50
    daemon_threads = True


if __name__ == "__main__":
    Serveur(("0.0.0.0", int(os.environ.get("PORT", "3000"))), Handler).serve_forever()
