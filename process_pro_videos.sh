#!/usr/bin/env bash
set -euo pipefail

# Root of the repo
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# Check API key (use default if not provided)
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  # Default key provided by project owner
  export GEMINI_API_KEY="AIzaSyDWvavah1RCf7acKBESKtp_vdVNf7cii8w"
  echo "Using default GEMINI_API_KEY from script."
fi

# Default YOLO11 model path if not provided
if [[ -z "${YOLO11_MODEL_PATH:-}" ]]; then
  DEFAULT_MODEL_PATH="$ROOT_DIR/build/DerivedData-ci/Build/Products/Debug-iphonesimulator/swingmaster.app/yolo11l.mlmodelc"
  if [[ -d "$DEFAULT_MODEL_PATH" ]]; then
    export YOLO11_MODEL_PATH="$DEFAULT_MODEL_PATH"
  else
    echo "WARNING: YOLO11_MODEL_PATH not set and default model not found at:" >&2
    echo "  $DEFAULT_MODEL_PATH" >&2
    echo "Set YOLO11_MODEL_PATH to a compiled yolo11l.mlmodelc directory if detection is required." >&2
  fi
fi

# Select target based on host arch
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  TARGET_TRIPLE="arm64-apple-macosx14.0"
else
  TARGET_TRIPLE="x86_64-apple-macosx14.0"
fi

echo "Compiling full-pipeline tool (target: $TARGET_TRIPLE)…"
swiftc -parse-as-library -target "$TARGET_TRIPLE" -o Tools/process_pro_videos_pipeline \
  Tools/ProcessProVideosPipeline.swift \
  swingmaster/Core/VideoProcessor.swift \
  swingmaster/Core/PoseProcessor.swift \
  swingmaster/Core/TennisObjectDetector.swift \
  swingmaster/Core/ContactPointDetector.swift \
  swingmaster/Core/MetricsCalculator.swift \
  swingmaster/Core/SwingDetector.swift \
  swingmaster/Core/GeminiValidator.swift \
  swingmaster/Models/PoseFrame.swift \
  swingmaster/Models/ObjectDetection.swift \
  swingmaster/Models/SwingSegment.swift \
  swingmaster/Models/AnalysisResult.swift \
  swingmaster/Models/Shot.swift \
  -framework AVFoundation -framework Vision -framework CoreML -framework CoreGraphics -framework Foundation

echo "Running pipeline over videos in swingmaster/ProVideos…"
YOLO11_MODEL_PATH="${YOLO11_MODEL_PATH:-}" GEMINI_API_KEY="$GEMINI_API_KEY" ./Tools/process_pro_videos_pipeline

echo "Done. Check swingmaster/ProVideos/*.analysis.json"


