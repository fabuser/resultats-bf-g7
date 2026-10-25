import os
import socket
from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "192.168.62.31") # IP de bdd1 pour le groupe 7
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "resultats_db")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "M0t2p@ss")

def get_db_connection():
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        cursor_factory=RealDictCursor
    )
    return conn

@app.route("/resultat", methods=["GET"])
def get_resultat():
    matricule = request.args.get("matricule")
    if not matricule:
        return jsonify({"erreur": "Paramètre 'matricule' manquant"}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT matricule, nom, serie, moyenne, admis FROM resultats WHERE matricule = %s;",
            (matricule,)
        )
        row = cur.fetchone()
        cur.close()
        conn.close()

        if row:
            return jsonify(row), 200
        else:
            return jsonify({"erreur": "Candidat non trouvé"}), 404

    except Exception as e:
        return jsonify({"erreur": str(e)}), 500

@app.route("/sante", methods=["GET"])
def sante():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()
        cur.close()
        conn.close()
        return "OK", 200
    except Exception:
        return "Base de données injoignable", 503

@app.route("/info", methods=["GET"])
def info():
    return jsonify({
        "hostname": socket.gethostname()
    }), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)