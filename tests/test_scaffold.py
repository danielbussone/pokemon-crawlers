"""Smoke tests for project scaffold."""

from pathlib import Path

from pokemon_crawlers import __version__
from pokemon_crawlers.main import main


def test_version_is_semver_like() -> None:
    parts = __version__.split(".")
    assert len(parts) == 3
    assert all(p.isdigit() for p in parts)


def test_main_exits_when_balance_dir_missing(tmp_path: Path) -> None:
    assert main(["--balance-dir", str(tmp_path / "nope")]) == 1


def test_main_ok_with_project_balance_dir() -> None:
    balance_dir = Path(__file__).resolve().parents[1] / "data" / "balance"
    assert main(["--balance-dir", str(balance_dir)]) == 0
