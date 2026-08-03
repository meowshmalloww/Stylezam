#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python_bin=${PYTHON_BIN:-python3}

if [ ! -x "$project_root/.venv/bin/python" ]; then
    "$python_bin" -m venv "$project_root/.venv"
fi

"$project_root/.venv/bin/python" -m pip install --upgrade pip
"$project_root/.venv/bin/python" -m pip install -e "$project_root/backend[dev]"

echo "Backend environment ready at $project_root/.venv"

