"""
Convert Ultralytics YOLO11 models to CoreML.

Examples:
  python convert_yolo11_to_coreml.py --size l --imgsz 640 --half --nms
  python convert_yolo11_to_coreml.py --weights /path/to/custom.pt --imgsz 640 --half

Output: <name>.mlpackage saved in the current directory.
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export YOLO11 to CoreML (.mlpackage)")
    parser.add_argument("--size", type=str, default="l", choices=["n", "s", "m", "l", "x"], help="YOLO11 size variant")
    parser.add_argument("--weights", type=str, default="", help="Optional explicit path to .pt weights")
    parser.add_argument("--imgsz", type=int, default=640, help="Inference image size (square)")
    parser.add_argument("--half", action=argparse.BooleanOptionalAction, default=True, help="Use FP16 (half-precision)")
    parser.add_argument("--nms", action=argparse.BooleanOptionalAction, default=True, help="Include NMS in exported model")
    parser.add_argument("--output", type=str, default="", help="Optional output .mlpackage filename")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    try:
        from ultralytics import YOLO
    except Exception as exc:  # noqa: BLE001
        print("Ultralytics not installed in this environment. Activate venv and install ultralytics.", file=sys.stderr)
        raise

    weights_path = args.weights or f"yolo11{args.size}.pt"

    print(f"Loading YOLO11 weights: {weights_path}")
    model = YOLO(weights_path)  # will download if not present

    # Determine output name
    if args.output:
        output_name = pathlib.Path(args.output).with_suffix("").name
    else:
        output_name = pathlib.Path(weights_path).with_suffix("").name

    print(
        f"Exporting to CoreML (.mlpackage) as: {output_name}.mlpackage | "
        f"imgsz={args.imgsz} half={args.half} nms={args.nms}"
    )

    export_result = model.export(
        format="coreml",
        nms=bool(args.nms),
        imgsz=int(args.imgsz),
        half=bool(args.half),
        # Ultralytics handles output naming; we keep current cwd clean
    )

    print("Export complete.")
    print(export_result)


if __name__ == "__main__":
    main()


