# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder
# python:3.12-slim is the official Python image based on Debian.
# "slim" means it excludes unnecessary packages, keeping the image smaller.
# We are using a two-stage build — this first stage installs dependencies,
# the second stage copies only what is needed to run the app.
# This results in a significantly smaller final image.

WORKDIR /app
# Sets the working directory inside the container.
# All subsequent commands run from /app.

COPY requirements.txt .
# Copy requirements first — before copying app code.
# This is intentional: Docker caches each layer.
# If requirements.txt hasn't changed, Docker reuses the cached
# pip install layer even if your app code changed.
# This makes rebuilds much faster during development.

RUN pip install --upgrade pip && \
    pip install --no-cache-dir --user -r requirements.txt
# --no-cache-dir: don't store pip's download cache in the image
# --user: installs to ~/.local instead of system Python
# These two flags reduce the final image size.

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime



RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
# Create a non-root user to run the application.
# Running as root inside a container is a security risk —
# if the app is compromised the attacker has root inside the container.
# This user has no password and no shell — it can only run the app.
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy the installed Python packages from the builder stage.
COPY --from=builder /root/.local /home/appuser/.local

# Copy the application code.
COPY app.py analyzer.py graph_builder.py secret_manager.py ./

# Set ownership so the non-root user can read the files.
RUN chown -R appuser:appgroup /app

# Switch to the non-root user.
USER appuser

# Add the user's local Python bin to PATH so gunicorn is found.
ENV PATH=/home/appuser/.local/bin:$PATH

# Tell Docker that the container listens on port 5000.
# This is documentation only — it does not actually publish the port.
# The actual port mapping is done at runtime with -p 5000:5000.
EXPOSE 5000

# Environment variables with safe defaults.
ENV PYTHONUNBUFFERED=1
# PYTHONUNBUFFERED=1 means Python output is sent directly to the terminal
# without buffering. Without this, logs may appear delayed or not at all
# in docker logs output.

ENV PYTHONDONTWRITEBYTECODE=1
# Prevents Python from writing .pyc compiled bytecode files.
# These serve no purpose in a container and waste space.

ENV FLASK_ENV=production
ENV PORT=5000
ENV GIT_PYTHON_REFRESH=quiet
# Health check — Docker itself will periodically call this endpoint.
# If it fails several times, Docker marks the container as unhealthy.
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1
# --interval=30s: check every 30 seconds
# --timeout=10s: fail the check if it takes longer than 10 seconds
# --start-period=10s: wait 10 seconds before starting checks (app startup time)
# --retries=3: mark as unhealthy after 3 consecutive failures

# Start the app with gunicorn — the production WSGI server.
# Never use Flask's built-in server in production.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
# --bind 0.0.0.0:5000: accept connections from any IP on port 5000
# --workers 2: two worker processes handle requests concurrently
# --timeout 120: workers that take longer than 120s are killed and restarted
#   (repo cloning can take a while so we give it 2 minutes)
# --access-logfile -: write access logs to stdout (visible in docker logs)
# --error-logfile -: write error logs to stdout
# app:app: the module is app.py, the Flask instance is named app
