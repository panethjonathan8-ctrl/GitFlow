import os
import logging
import requests
from flask import Flask, request, jsonify
from prometheus_flask_exporter import PrometheusMetrics

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
metrics = PrometheusMetrics(app, excluded_paths=["/health"])
metrics.info("app_info", "Application info", service="result-api")

# Service URLs — configurable via environment variables.
# In docker-compose these use service names.
# In Kubernetes these use cluster DNS names.
ANALYZER_URL    = os.environ.get("ANALYZER_URL", "http://analyzer:5001")
GRAPH_BUILDER_URL = os.environ.get("GRAPH_BUILDER_URL", "http://graph-builder:5002")


@app.route("/health", methods=["GET"])
def health():
    """
    Health check for this service only.
    Does not check downstream services — that would make this
    health check dependent on two other services which adds fragility.
    """
    return jsonify({"status": "healthy", "service": "result-api"}), 200


@app.route("/", methods=["GET"])
def index():
    return jsonify({
        "service": "GitFlow Analyzer",
        "version": "2.0.0",
        "architecture": "microservices",
        "endpoints": {
            "health": "GET /health",
            "analyze": "POST /analyze"
        }
    }), 200


@app.route("/analyze", methods=["POST"])
def analyze():
    """
    Main endpoint. Orchestrates the analyzer and graph-builder services.
    Users send requests here. This service calls the others internally.
    """
    data = request.get_json()

    if not data or "repo_url" not in data:
        return jsonify({
            "error": "Missing repo_url",
            "example": {"repo_url": "https://github.com/user/repo"}
        }), 400

    repo_url = data["repo_url"].strip()

    if "github.com" not in repo_url:
        return jsonify({"error": "Only GitHub repos supported"}), 400

    logger.info(f"Orchestrating analysis for: {repo_url}")

    try:
        # Call analyzer service
        logger.info(f"Calling analyzer at {ANALYZER_URL}")
        analyzer_response = requests.post(
            f"{ANALYZER_URL}/analyze",
            json={"repo_url": repo_url},
            timeout=120
        )
        analyzer_response.raise_for_status()
        analysis = analyzer_response.json()

        # Call graph-builder service
        logger.info(f"Calling graph-builder at {GRAPH_BUILDER_URL}")
        graph_response = requests.post(
            f"{GRAPH_BUILDER_URL}/build-graph",
            json={"repo_url": repo_url},
            timeout=120
        )
        graph_response.raise_for_status()
        graph = graph_response.json()

        # Combine and return results
        return jsonify({
            "repo_url":   repo_url,
            "languages":  analysis.get("languages", {}),
            "frameworks": analysis.get("frameworks", []),
            "graph": {
                "nodes":      graph.get("nodes", []),
                "edges":      graph.get("edges", []),
                "node_count": graph.get("node_count", 0),
                "edge_count": graph.get("edge_count", 0)
            },
            "status": "success"
        }), 200

    except requests.exceptions.ConnectionError as e:
        logger.error(f"Service connection error: {str(e)}")
        return jsonify({
            "error": "Could not connect to upstream service",
            "detail": str(e)
        }), 503

    except requests.exceptions.Timeout:
        return jsonify({"error": "Upstream service timed out"}), 504

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
