import os
import tempfile
import shutil
from pathlib import Path
from git import Repo
from secret_manager import get_github_token


# Maps file extensions to language names.
# You will expand this as you test with more repos.
LANGUAGE_MAP = {
    ".py": "Python",
    ".js": "JavaScript",
    ".ts": "TypeScript",
    ".go": "Go",
    ".java": "Java",
    ".rb": "Ruby",
    ".rs": "Rust",
    ".cs": "C#",
    ".cpp": "C++",
    ".c": "C",
    ".php": "PHP",
    ".swift": "Swift",
    ".kt": "Kotlin",
}

# Maps specific filenames to the framework or tool they indicate.
FRAMEWORK_MAP = {
    "package.json": "Node.js",
    "requirements.txt": "Python",
    "Pipfile": "Python/Pipenv",
    "go.mod": "Go",
    "pom.xml": "Java/Maven",
    "build.gradle": "Java/Gradle",
    "Gemfile": "Ruby",
    "Cargo.toml": "Rust",
    "Dockerfile": "Docker",
    "docker-compose.yml": "Docker Compose",
    "docker-compose.yaml": "Docker Compose",
    ".github": "GitHub Actions",
    "terraform": "Terraform",
    "helmfile.yaml": "Helm",
    "Chart.yaml": "Helm",
    "k8s": "Kubernetes",
    "kubernetes": "Kubernetes",
    ".gitlab-ci.yml": "GitLab CI",
    "Jenkinsfile": "Jenkins",
    "serverless.yml": "Serverless Framework",
}


def clone_repo(repo_url: str) -> str:
    """
    Clone a GitHub repository into a temporary directory.
    Returns the path to the cloned repo.
    The caller is responsible for deleting the temp dir when done.
    """
    token = get_github_token()

    # Inject the token into the URL so git can authenticate.
    # Format: https://TOKEN@github.com/user/repo.git
    # The token never appears in logs because we build the URL in memory.
    if "github.com" in repo_url:
        authenticated_url = repo_url.replace(
            "https://github.com",
            f"https://{token}@github.com"
        )
    else:
        authenticated_url = repo_url

    # Create a temporary directory that gets cleaned up automatically.
    temp_dir = tempfile.mkdtemp(prefix="gitflow-")

    try:
        Repo.clone_from(
            authenticated_url,
            temp_dir,
            depth=1,
            # depth=1 is a shallow clone — only gets the latest commit.
            # A full clone of a large repo could be gigabytes.
            # For analysis you only need the current file structure.
        )
        return temp_dir
    except Exception as e:
        # Clean up the temp dir if cloning fails.
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise ValueError(f"Failed to clone repository: {str(e)}")


def detect_languages(repo_path: str) -> dict:
    """
    Walk the repo directory tree and count files by language.
    Returns a dict of language name to file count.
    """
    language_counts = {}

    for root, dirs, files in os.walk(repo_path):
        # Skip hidden directories and common non-source folders.
        dirs[:] = [
            d for d in dirs
            if not d.startswith(".")
            and d not in ["node_modules", "vendor", "__pycache__", "dist", "build"]
        ]

        for file in files:
            ext = Path(file).suffix.lower()
            if ext in LANGUAGE_MAP:
                lang = LANGUAGE_MAP[ext]
                language_counts[lang] = language_counts.get(lang, 0) + 1

    # Sort by count descending so the primary language is first.
    return dict(sorted(language_counts.items(), key=lambda x: x[1], reverse=True))


def detect_frameworks(repo_path: str) -> list:
    """
    Check for the presence of known config files and directories
    that indicate specific frameworks and tools.
    Returns a list of detected framework names.
    """
    detected = []
    repo = Path(repo_path)

    for filename, framework in FRAMEWORK_MAP.items():
        # Check both files and directories.
        if (repo / filename).exists():
            if framework not in detected:
                detected.append(framework)

    return detected


def analyze_repo(repo_url: str) -> dict:
    """
    Main entry point for the analyzer.
    Clones the repo, runs all detection, cleans up, returns results.
    """
    repo_path = None
    try:
        repo_path = clone_repo(repo_url)

        languages = detect_languages(repo_path)
        frameworks = detect_frameworks(repo_path)

        return {
            "repo_url": repo_url,
            "languages": languages,
            "frameworks": frameworks,
            "status": "success"
        }

    finally:
        # Always clean up the temp directory even if analysis fails.
        # Without this every analysis leaks disk space on the server.
        if repo_path:
            shutil.rmtree(repo_path, ignore_errors=True)
