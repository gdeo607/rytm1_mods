"""The m68k binutils this project calls, whichever prefix is installed.

macOS (brew install m68k-elf-binutils) gives m68k-elf-*; Debian/Ubuntu
(apt install binutils-m68k-linux-gnu) gives m68k-linux-gnu-*. Both assemble the
same bytes for ColdFire. M68K_PREFIX overrides the search.
"""
import os
import shutil


def prefix() -> str:
    env = os.environ.get("M68K_PREFIX")
    if env:
        return env
    for p in ("m68k-elf-", "m68k-linux-gnu-"):
        if shutil.which(p + "as"):
            return p
    raise SystemExit("no m68k binutils found: brew install m68k-elf-binutils "
                     "(macOS) or apt install binutils-m68k-linux-gnu (Linux)")


def tool(name: str) -> str:
    return prefix() + name
