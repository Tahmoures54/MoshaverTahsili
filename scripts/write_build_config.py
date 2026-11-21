
#!/usr/bin/env python3
"""Write Flutter compiler inputs outside the repository without logging secrets."""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile

from pathlib import Path


DEFAULT_API_ENDPOINT = "https://api.avalai.ir/v1"
DEFAULT_AI_MODEL = "deepseek-chat"

PUBSPEC_PATH = Path("pubspec.yaml")

VERSION_PATTERN = re.compile(
    r"""(?m)^\s*version\s*:\s*
    ["']?
    (?P<version>[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)
    \+(?P<build>[0-9]+)
    ["']?\s*(?:\#.*)?$
    """,
    re.VERBOSE,
)

SECRET_ENVIRONMENT_VARIABLES = (
    "AI_API_KEY",
    "DEEPSEEK_API_KEY",
    "BAZAAR_RSA_PUBLIC_KEY",
)


class ConfigurationError(Exception):
    """Raised when build configuration cannot be prepared."""


def repository_root() -> Path:
    """Resolve the current Git repository root."""

    try:
        import subprocess

        result = subprocess.run(
            [
                "git",
                "rev-parse",
                "--show-toplevel",
            ],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as error:
        raise ConfigurationError(
            "Git executable was not found."
        ) from error
    except subprocess.CalledProcessError as error:
        raise ConfigurationError(
            "Could not determine the Git repository root."
        ) from error

    return Path(result.stdout.strip()).resolve()


def read_app_version(root: Path) -> tuple[str, str]:
    """Read app version and build number from pubspec.yaml."""

    pubspec = root / PUBSPEC_PATH

    try:
        content = pubspec.read_text(
            encoding="utf-8",
        )
    except (OSError, UnicodeError) as error:
        raise ConfigurationError(
            "Could not read pubspec.yaml."
        ) from error

    match = VERSION_PATTERN.search(content)

    if not match:
        raise ConfigurationError(
            "Invalid pubspec version. Expected version: x.y.z+build."
        )

    version = match.group("version")
    build_number = match.group("build")

    return version, build_number


def environment_value(*names: str) -> str:
    """Return the first non-empty environment value."""

    for name in names:
        value = os.environ.get(name, "").strip()

        if value:
            return value

    return ""


def parse_boolean(name: str) -> bool:
    """Parse a boolean environment variable."""

    value = os.environ.get(name, "").strip().lower()

    return value in {
        "true",
        "1",
        "yes",
        "on",
    }


def validate_output_path(
    requested_path: str,
    root: Path,
) -> Path:
    """Ensure the compiler input is written outside the repository."""

    if not requested_path.strip():
        raise ConfigurationError(
            "Output path cannot be empty."
        )

    output = Path(requested_path).expanduser()

    if not output.is_absolute():
        output = Path.cwd() / output

    output = output.resolve()
    repository = root.resolve()

    try:
        output.relative_to(repository)
    except ValueError:
        pass
    else:
        raise ConfigurationError(
            "Build configuration must be stored outside the repository."
        )

    if output.exists() and not output.is_file():
        raise ConfigurationError(
            "Output path exists but is not a regular file."
        )

    return output


def build_configuration(root: Path) -> dict[str, object]:
    """Create compiler configuration without exposing its values."""

    version, build_number = read_app_version(root)

    api_key = environment_value(
        "AI_API_KEY",
        "DEEPSEEK_API_KEY",
    )

    endpoint = environment_value(
        "AI_API_ENDPOINT",
        "DEEPSEEK_API_ENDPOINT",
    ) or DEFAULT_API_ENDPOINT

    model = environment_value(
        "AI_MODEL",
        "DEEPSEEK_MODEL",
    ) or DEFAULT_AI_MODEL

    bazaar_public_key = environment_value(
        "BAZAAR_RSA_PUBLIC_KEY",
    )

    if endpoint and not re.match(
        r"^https://",
        endpoint,
        re.IGNORECASE,
    ):
        raise ConfigurationError(
            "AI API endpoint must use HTTPS."
        )

    if not model:
        raise ConfigurationError(
            "AI model name cannot be empty."
        )

    return {
        "APP_VERSION": version,
        "APP_BUILD_NUMBER": build_number,
        "AI_API_KEY": api_key,
        "AI_API_ENDPOINT": endpoint,
        "AI_MODEL": model,
        "BAZAAR_RSA_PUBLIC_KEY": bazaar_public_key,
        "BAZAAR_CATALOG_CONFIRMED": parse_boolean(
            "BAZAAR_CATALOG_CONFIRMED"
        ),
    }


def write_private_json(
    output: Path,
    config: dict[str, object],
) -> None:
    """Atomically write JSON with restrictive file permissions."""

    try:
        output.parent.mkdir(
            parents=True,
            exist_ok=True,
        )
    except OSError as error:
        raise ConfigurationError(
            "Could not create the configuration output directory."
        ) from error

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=output.parent,
            prefix=".build-config-",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

            # Restrict access before writing sensitive content.
            try:
                os.chmod(temporary_path, 0o600)
            except OSError as error:
                raise ConfigurationError(
                    "Could not restrict temporary configuration permissions."
                ) from error

            json.dump(
                config,
                temporary,
                ensure_ascii=False,
                separators=(",", ":"),
            )

            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())

        os.replace(
            temporary_path,
            output,
        )

        temporary_path = None

        try:
            os.chmod(output, 0o600)
        except OSError as error:
            raise ConfigurationError(
                "Could not restrict final configuration permissions."
            ) from error

    except OSError as error:
        raise ConfigurationError(
            "Could not write build configuration."
        ) from error

    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: python3 tool/prepare_build_config.py "
            "<absolute-output-path>",
            file=sys.stderr,
        )
        return 2

    try:
        root = repository_root()

        output = validate_output_path(
            sys.argv[1],
            root,
        )

        config = build_configuration(root)

        write_private_json(
            output,
            config,
        )

        print(
            "Build configuration prepared outside the source tree."
        )

        if not config["AI_API_KEY"]:
            print(
                "::warning::AI API key is not configured. "
                "AI requests may not work in this build."
            )

        if not config["BAZAAR_RSA_PUBLIC_KEY"]:
            print(
                "::warning::Bazaar RSA public key is not configured."
            )

        if not config["BAZAAR_CATALOG_CONFIRMED"]:
            print(
                "::warning::Bazaar catalog has not been confirmed."
            )

        return 0

    except ConfigurationError as error:
        print(
            f"::error::{error}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
