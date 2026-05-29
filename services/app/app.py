import os
import logging
from flask import Flask, request, jsonify
from analyzer import analyze_repo
from graph_builder import build_graph

# Configure logging so every request and error is visible in the container logs.
# On EC2 you read these with: docker logs <container_name>
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger(__name__)

app = Flask(__name__)


@app.route("/health", methods=["GET"])
def health():
    """
    Health check endpoint.
    EC2, load balancers, and later Kubernetes use this to know
    if the app is running correctly.
    Must return 200 OK when the app is healthy.
    """
    return jsonify({"status": "healthy", "service": "gitflow-analyzer"}), 200


@app.route("/analyze", methods=["POST"])
def analyze():
    """
    Main analysis endpoint.
    
    Accepts: POST with JSON body {"repo_url": "https://github.com/user/repo"}
    Returns: JSON with detected languages, frameworks, and dependency graph
    """
    data = request.get_json()

    # Validate the request has what we need
    if not data or "repo_url" not in data:
        return jsonify({
            "error": "Missing repo_url in request body",
            "example": {"repo_url": "https://github.com/user/repo"}
        }), 400

    repo_url = data["repo_url"].strip()

    # Basic validation — must be a GitHub URL
    if "github.com" not in repo_url:
        return jsonify({
            "error": "Only GitHub repositories are supported",
            "provided": repo_url
        }), 400

    logger.info(f"Starting analysis for: {repo_url}")

    try:
        # Run both analysis and graph building
        analysis_result = analyze_repo(repo_url)
        graph_result = build_graph(repo_url)

        return jsonify({
            "repo_url": repo_url,
            "languages": analysis_result["languages"],
            "frameworks": analysis_result["frameworks"],
            "graph": {
                "nodes": graph_result["nodes"],
                "edges": graph_result["edges"],
                "node_count": graph_result["node_count"],
                "edge_count": graph_result["edge_count"]
            },
            "status": "success"
        }), 200

    except ValueError as e:
        # Expected errors — bad URL, private repo, auth failure
        logger.warning(f"Analysis failed for {repo_url}: {str(e)}")
        return jsonify({"error": str(e), "status": "failed"}), 400

    except Exception as e:
        # Unexpected errors — log fully for debugging
        logger.error(f"Unexpected error analyzing {repo_url}: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error", "status": "failed"}), 500


@app.route("/", methods=["GET"])
def index():
    """
    Root endpoint — useful for confirming the API is reachable.
    """
    return jsonify({
        "service": "GitFlow Analyzer",
        "version": "1.0.0",
        "endpoints": {
            "health": "GET /health",
            "analyze": "POST /analyze"
        }
    }), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    debug = os.environ.get("FLASK_ENV") == "development"
    # debug=True only in development — never in production.
    # Debug mode exposes an interactive debugger that can execute arbitrary code.
    app.run(host="0.0.0.0", port=port, debug=debug)
    # host="0.0.0.0" means accept connections from any IP.
    # Without this Flask only accepts connections from localhost
    # which means nothing outside the container can reach it.
