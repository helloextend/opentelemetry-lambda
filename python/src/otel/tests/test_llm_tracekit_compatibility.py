import os
import subprocess
import sys
import venv
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
LAYER_REQUIREMENTS = REPO_ROOT / "otel_sdk" / "requirements.txt"
LAYER_CONSTRAINTS = REPO_ROOT / "otel_sdk" / "constraints.txt"


def _python_from_venv(venv_dir: Path) -> Path:
    if sys.platform == "win32":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def _pip(python_executable: Path, *args: str, env: dict | None = None) -> None:
    pip_env = {
        **os.environ,
        "PIP_DISABLE_PIP_VERSION_CHECK": "1",
    }
    if env:
        pip_env.update(env)
    subprocess.run(
        [str(python_executable), "-m", "pip", *args],
        check=True,
        env=pip_env,
    )


def test_llm_tracekit_is_compatible_with_layer_requirements(tmp_path):
    """Installs layer deps + llm-tracekit in a clean venv to catch version conflicts."""

    venv_dir = tmp_path / "llm-tracekit-compat-env"
    venv.EnvBuilder(with_pip=True, clear=True).create(venv_dir)
    venv_python = _python_from_venv(venv_dir)

    pip_config_path = tmp_path / "pip.conf"
    pip_config_path.write_text(
        "[global]\n"
        f"constraint = {LAYER_CONSTRAINTS}\n",
        encoding="utf-8",
    )
    pip_env = {"PIP_CONFIG_FILE": str(pip_config_path)}

    _pip(venv_python, "install", "--upgrade", "pip", "setuptools", "wheel", env=pip_env)
    _pip(venv_python, "install", "-r", str(LAYER_REQUIREMENTS), env=pip_env)
    _pip(venv_python, "install", "llm-tracekit", env=pip_env)
    _pip(venv_python, "check", env=pip_env)
