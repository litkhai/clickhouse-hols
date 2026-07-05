"""라이브 데모 대시보드 (Flask).

  상단: Start(=resume) / Stop(=pause) / Cleanup + interval 설정 + 상태
  좌하: 4단계 (client → kafka → staging → fact)
  우하: 프리셋 쿼리 버튼 + 결과

로컬:   python webapp/app.py
Docker: docker compose up --build   → http://localhost:8080
"""
import os
import sys
from pathlib import Path

# scripts/ 모듈(config, producer, clickpipe_api, order_generator) 재사용
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from flask import Flask, jsonify, render_template, request

from config import CFG
from demo_state import STATE
from presets import BY_ID, grouped

app = Flask(__name__)


def _client():
    return CFG.ch_client()


@app.route("/")
def index():
    return render_template("index.html", db=CFG.database, topic=CFG.kafka_topic)


@app.route("/api/status")
def api_status():
    try:
        counts = STATE.counts(_client())
    except Exception as e:
        counts = {"error": f"{type(e).__name__}: {str(e)[:120]}"}
    return jsonify({
        "producer": STATE.status(),
        "pipe": STATE.pipe_state(),
        "counts": counts,
        "meta": {"database": CFG.database, "topic": CFG.kafka_topic,
                 "host": CFG.ch_host},
    })


@app.route("/api/stages")
def api_stages():
    try:
        return jsonify(STATE.stages(_client()))
    except Exception as e:
        return jsonify({"error": f"{type(e).__name__}: {str(e)[:150]}"}), 500


@app.route("/api/start", methods=["POST"])
def api_start():
    interval = (request.json or {}).get("interval")
    return jsonify(STATE.start_producer(interval))


@app.route("/api/stop", methods=["POST"])
def api_stop():
    return jsonify(STATE.stop_producer())


@app.route("/api/interval", methods=["POST"])
def api_interval():
    interval = (request.json or {}).get("interval", 3)
    return jsonify(STATE.set_interval(interval))


@app.route("/api/cleanup", methods=["POST"])
def api_cleanup():
    try:
        return jsonify({"ok": True, "truncated": STATE.cleanup(_client())})
    except Exception as e:
        return jsonify({"ok": False, "error": f"{type(e).__name__}: {str(e)[:150]}"}), 500


@app.route("/api/presets")
def api_presets():
    return jsonify(grouped())


@app.route("/api/query", methods=["POST"])
def api_query():
    pid = (request.json or {}).get("id")
    preset = BY_ID.get(pid)
    if not preset:
        return jsonify({"error": f"unknown preset '{pid}'"}), 400
    try:
        return jsonify(STATE._rows(_client(), preset["sql"]))
    except Exception as e:
        return jsonify({"error": f"{type(e).__name__}: {str(e)[:200]}"}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port, threaded=True)
