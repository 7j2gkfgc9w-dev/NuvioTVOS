"""Rebuild the bundled YuNet and SFace Core ML models from OpenCV Zoo weights.

Run with Python 3.11 and coremltools 9.0, onnx 1.23.0, onnx2torch 1.5.15,
onnxruntime 1.30.0, torch 2.14.0, and numpy 2.4.6. The ONNX downloads are
SHA-256 verified and each conversion is compared numerically with ONNX Runtime.
"""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
from pathlib import Path

import coremltools as ct
import numpy as np
import onnx
import onnxruntime as ort
import torch
from onnx2torch import convert


MODELS = (
    (
        "YuNet",
        "face_detection_yunet/face_detection_yunet_2023mar.onnx",
        "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4",
        (1, 3, 640, 640),
        "frame_input",
        12,
    ),
    (
        "SFace",
        "face_recognition_sface/face_recognition_sface_2021dec.onnx",
        "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
        (1, 3, 112, 112),
        "face_input",
        1,
    ),
)
BASE_URL = "https://github.com/opencv/opencv_zoo/raw/refs/heads/main/models/"
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "NuvioTV/Resources/SceneModels"


def rebuild_model(spec: tuple, scratch: Path) -> None:
    name, relative_url, expected_hash, shape, input_name, output_count = spec
    onnx_path = scratch / f"{name}.onnx"
    with urllib.request.urlopen(BASE_URL + relative_url) as response:
        onnx_path.write_bytes(response.read())
    actual_hash = hashlib.sha256(onnx_path.read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError(f"{name} SHA-256 mismatch: {actual_hash}")

    source_model = onnx.load(str(onnx_path))
    network = convert(source_model).eval()
    sample = np.random.default_rng(7).uniform(0, 255, shape).astype(np.float32)
    with torch.no_grad():
        torch_outputs = network(torch.from_numpy(sample))
    if not isinstance(torch_outputs, tuple):
        torch_outputs = (torch_outputs,)
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    onnx_outputs = session.run(None, {"data" if name == "SFace" else "input": sample})
    if len(onnx_outputs) != output_count or len(torch_outputs) != output_count:
        raise ValueError(f"{name} output count changed")
    for expected, actual in zip(onnx_outputs, torch_outputs):
        np.testing.assert_allclose(actual.numpy(), expected, rtol=1e-4, atol=1e-4)

    traced = torch.jit.trace(network, torch.from_numpy(sample))
    converted = ct.convert(
        traced,
        source="pytorch",
        convert_to="mlprogram",
        inputs=[ct.TensorType(name=input_name, shape=shape)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
    )
    if len(converted.get_spec().description.output) != output_count:
        raise ValueError(f"{name} Core ML output count changed")
    predictions = converted.predict({input_name: sample})
    for output_description, expected in zip(converted.get_spec().description.output, onnx_outputs):
        np.testing.assert_allclose(
            predictions[output_description.name], expected, rtol=1e-4, atol=1e-4
        )

    package = scratch / f"{name}.mlpackage"
    converted.save(str(package))
    destination = OUTPUT_DIR / package.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(package, destination)
    print(f"{name}: {expected_hash}; wrote {destination}")


if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nuvio-scene-models-") as directory:
        for model_spec in MODELS:
            rebuild_model(model_spec, Path(directory))
