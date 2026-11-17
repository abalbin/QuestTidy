#!/usr/bin/env python3
"""Build the installable QuestTidy archive from the addon's TOC."""

import argparse
import re
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "QuestTidy.toc"
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"


def package(output_dir, tag):
    lines = TOC.read_text(encoding="utf-8-sig").splitlines()
    versions = re.findall(r"^##\s*Version:\s*(.*?)\s*$", "\n".join(lines), re.MULTILINE)
    if len(versions) != 1 or not re.fullmatch(VERSION, versions[0]):
        raise ValueError("QuestTidy.toc must declare one X.Y.Z version")
    version = versions[0]
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"tag {tag!r} does not match QuestTidy.toc (expected v{version})")

    names = {PurePosixPath(TOC.name), PurePosixPath("LICENSE")}
    for line in lines:
        entry = line.strip()
        if entry and not entry.startswith("#"):
            names.add(PurePosixPath(entry.replace("\\", "/")))

    files = {}
    for name in sorted(names):
        source = ROOT / Path(name)
        if name.is_absolute() or ".." in name.parts or not source.resolve().is_relative_to(ROOT):
            raise ValueError(f"TOC file path must stay inside the addon: {name}")
        if not source.is_file():
            raise ValueError(f"addon file is missing: {name}")
        files[f"QuestTidy/{name.as_posix()}"] = source.read_bytes()

    archive = output_dir / f"QuestTidy-{version}.zip"
    output_dir.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output_dir) as directory:
        staged = Path(directory) / archive.name
        with ZipFile(staged, "w") as zip_file:
            for name, contents in files.items():
                zip_file.writestr(ZipInfo(name), contents, compress_type=ZIP_DEFLATED)
        with ZipFile(staged) as zip_file:
            if zip_file.testzip() is not None or zip_file.namelist() != list(files):
                raise ValueError("ZIP verification failed")
        staged.replace(archive)
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--tag", help="Require a release tag matching the TOC version")
    args = parser.parse_args()
    try:
        print(package(args.output_dir, args.tag))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()
