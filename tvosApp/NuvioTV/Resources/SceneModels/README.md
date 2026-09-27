# Scene face models

`YuNet.mlpackage` and `SFace.mlpackage` are Core ML conversions of the OpenCV
Zoo `face_detection_yunet_2023mar.onnx` and
`face_recognition_sface_2021dec.onnx` weights. The checked source hashes and
rebuild procedure are in `tvosApp/Scripts/convert_scene_models.py`.

YuNet's directory is MIT licensed; SFace's directory declares Apache 2.0 for
all its files. Their license texts are included here. The OpenCV Zoo issue
about the SFace weight's training-data provenance remains open:
https://github.com/opencv/opencv_zoo/issues/313

The packages are converted with float32 weights and validated numerically
against the ONNX models before copying into this directory. Face recognition
thresholds still require calibration on actual film frames and cast portraits.
