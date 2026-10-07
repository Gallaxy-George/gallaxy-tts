"""Shared validation and narrowly scoped compatibility for the pinned runtime."""
from importlib.metadata import PackageNotFoundError, version

REQUIRED_RUNTIME_VERSIONS = {
    "mlx-audio": "0.4.4",
    "misaki": "0.9.4",
    "soundfile": "0.14.0",
    "Pillow": "12.3.0",
    "setuptools": "83.0.0",
    "torch": "2.13.0",
}


def validate_runtime_versions():
    problems = []
    for package, required in REQUIRED_RUNTIME_VERSIONS.items():
        try:
            installed = version(package)
        except PackageNotFoundError:
            problems.append(f"{package} is missing")
            continue
        if installed != required:
            problems.append(f"{package} is {installed}; expected {required}")
    if problems:
        raise RuntimeError(
            "Kokoro runtime needs an update. Run scripts/download_kokoro_assets.sh. "
            + "; ".join(problems)
        )


def apply_runtime_compatibility():
    # MLX Audio #803: 0.4.4's interpolation round trip can return one extra
    # upsample hop, making Kokoro's harmonic and noise branches incompatible.
    # Keep the workaround in this worker process; never edit the installed package.
    # https://github.com/Blaizzy/mlx-audio/issues/803
    if version("mlx-audio") != "0.4.4":
        return
    from mlx_audio.tts.models.kokoro.istftnet import SineGen

    original = SineGen._f02sine
    if getattr(original, "_gallaxy_length_guard", False):
        return

    def length_preserving_sine(self, f0_values):
        output = original(self, f0_values)
        expected = f0_values.shape[1]
        extra = output.shape[1] - expected
        if extra < 0 or extra > self.upsample_scale:
            raise RuntimeError("Unexpected Kokoro harmonic length; update the runtime compatibility guard.")
        return output[:, :expected, :]

    length_preserving_sine._gallaxy_length_guard = True
    SineGen._f02sine = length_preserving_sine
