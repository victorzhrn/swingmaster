#!/usr/bin/env bash
set -euo pipefail

# Simple wrapper to export YOLO11 to CoreML using the local Python helper.
# Usage examples:
#   ./convert_yolo11.sh --size l --imgsz 640 --half --nms
#   ./convert_yolo11.sh --weights /path/to/custom.pt --imgsz 640 --no-nms

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -d .venv311 ]]; then
  echo "Python 3.11 venv (.venv311) not found. Creating..."
  /opt/homebrew/bin/python3.11 -m venv .venv311
fi

source .venv311/bin/activate

# Ensure deps exist
python -m pip install --upgrade pip >/dev/null
pip install -q ultralytics 'torch==2.5.0' 'torchvision==0.20.0' --extra-index-url https://download.pytorch.org/whl/cpu >/dev/null
pip install -q 'coremltools>=8.0' >/dev/null

python convert_yolo11_to_coreml.py "$@"


