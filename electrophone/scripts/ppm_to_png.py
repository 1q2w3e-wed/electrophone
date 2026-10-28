from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    output = ROOT / "sim" / "output"
    for ppm in output.glob("dashboard_*.ppm"):
        Image.open(ppm).save(ppm.with_suffix(".png"))


if __name__ == "__main__":
    main()
