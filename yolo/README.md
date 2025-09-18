## YOLO11 to CoreML (iOS/macOS)

This folder contains scripts and instructions to download Ultralytics YOLO11 weights and export them to CoreML for iOS/macOS apps.

### 0) Prerequisites

- macOS with Homebrew
- Apple Silicon or Intel (both supported; commands below assume Apple Silicon default Homebrew paths)
- Python 3.11 installed via Homebrew:
  - Install: `brew install python@3.11`
  - Verify: `which python3.11` should be `/opt/homebrew/bin/python3.11` (Apple Silicon)
  - Optional: add convenience shims to PATH so `python3` maps to 3.11:
    - `echo 'export PATH="/opt/homebrew/opt/python@3.11/libexec/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc`

### 1) Environment Setup

From the `yolo/` directory (recommended exact versions for smooth CoreML export):

```bash
python3.11 -m venv .venv311
source .venv311/bin/activate
python -m pip install --upgrade pip
pip install 'torch==2.5.0' 'torchvision==0.20.0' --extra-index-url https://download.pytorch.org/whl/cpu
pip install ultralytics 'coremltools>=8.0'

# Verify versions
python - <<'PY'
import sys, torch, coremltools
print('Python', sys.version)
print('Torch', torch.__version__)
print('CoreMLTools', coremltools.__version__)
PY
```

Notes:
- Using Python 3.11 is recommended for compatibility with `coremltools` and Ultralytics export.
- The scripts here assume the virtualenv `.venv311` exists in this folder.

### 2) Quickstart (Wrapper Script)

No setup needed beyond Homebrew Python; the script will create `.venv311` and install deps automatically:

```bash
./convert_yolo11.sh --size l --imgsz 640 --half --nms
```

This will download `yolo11l.pt` if needed and export `yolo11l.mlpackage`.

### 3) Download a YOLO11 Model (Manual)

You can download any YOLO11 variant using the Python helper or the shell wrapper.

Variants: `n`, `s`, `m`, `l`, `x` (nano → extra‑large)

Examples:

```bash
# Activate venv
source .venv311/bin/activate

# Python helper (downloads & exports)
python convert_yolo11_to_coreml.py --size l --imgsz 640 --half --nms

# Or just trigger a weights download explicitly
python -c "from ultralytics import YOLO; YOLO('yolo11l.pt')"

# Shell wrapper (defaults to large)
./convert_yolo11.sh --size l --imgsz 640 --half --nms
```

This will download `yolo11l.pt` and, when using the conversion scripts, export `yolo11l.mlpackage`.

### 4) Export to CoreML (Manual)

Use either the Python or shell helper:

```bash
# Python
source .venv311/bin/activate
python convert_yolo11_to_coreml.py --size n|s|m|l|x --imgsz 640 --half --nms

# Shell wrapper
./convert_yolo11.sh --size l --imgsz 640 --half --nms
```

Flags:
- `--size`: YOLO11 variant (default `l`).
- `--weights`: optional explicit path to a `.pt` file.
- `--imgsz`: input size (square). Default `640`.
- `--half/--no-half`: FP16 vs FP32. FP16 is faster on-device.
- `--nms/--no-nms`: include NMS in the exported model. Default enabled.
- `--output`: optional custom output name for the `.mlpackage`.

### 5) Add to Xcode

Drag the exported `.mlpackage` into your Xcode target. Xcode will build a `.mlmodelc`. In Swift, find and load `yolo11*.mlmodelc` from the app bundle and use Vision `VNCoreMLRequest` as in `TennisObjectDetector`.

### 6) Troubleshooting

- CoreML export errors on Python 3.12/3.13 (e.g., "BlobWriter not loaded"): use Python 3.11.
  - Remove conflicting envs: `rm -rf .venv .venv311 && python3.11 -m venv .venv311`
  - Reinstall deps using steps in section 1 or just use `./convert_yolo11.sh`.
- Ultralytics auto-upgraded `coremltools` and asks to rerun: simply rerun the export command.
- On Intel Macs, Homebrew path may be `/usr/local` instead of `/opt/homebrew` — adjust paths accordingly.
- If `python3.11` is not found: `brew install python@3.11` and ensure PATH shims from prerequisites are applied.

- For visualization of the exported model: open it at `https://netron.app`.
- Downloaded weights (`*.pt`), local venvs (`.venv*`), and exported bundles (`*.mlpackage`) are ignored by Git via the repository `.gitignore`.


