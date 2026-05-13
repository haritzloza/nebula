"""Tools de control del sistema: volumen, brillo, Hyprland, lanzar apps.

Allowlist estricta. Nunca shell=True. Argumentos siempre como lista.
"""
from __future__ import annotations

import asyncio
import os
from typing import Literal

from pydantic import BaseModel, Field, conint

from . import REGISTRY, ToolError, register

# Lista de apps permitidas (sobreescribible desde config.toml en futuro)
ALLOWED_APPS: set[str] = {
    "firefox",
    "kitty",
    "code",
    "obsidian",
    "spotify",
    "nautilus",
    "thunar",
    "yazi",
    "discord",
}
ALLOWED_HYPR: set[str] = {
    "workspace",
    "togglefloating",
    "fullscreen",
    "movetoworkspace",
    "killactive",
}


async def _run(cmd: list[str], timeout: float = 5.0) -> str:
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError as e:
        proc.kill()
        raise ToolError(f"timeout ejecutando {cmd[0]}") from e
    if proc.returncode != 0:
        raise ToolError(stderr.decode("utf-8", "ignore").strip() or f"{cmd[0]} fallo")
    return stdout.decode("utf-8", "ignore").strip()


# ───────────────────────────── volumen ─────────────────────────────
class SetVolumeArgs(BaseModel):
    """Establece el volumen maestro a un valor absoluto (0-100)."""

    level: conint(ge=0, le=100) = Field(..., description="Volumen 0-100")  # type: ignore[valid-type]


@register("set_volume", SetVolumeArgs, "Establece el volumen del sistema (0-100).")
async def set_volume(args: SetVolumeArgs) -> str:
    await _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{args.level / 100:.2f}"])
    return f"Volumen al {args.level}%"


class ChangeVolumeArgs(BaseModel):
    """Cambia el volumen relativamente (delta -50..+50)."""

    delta: conint(ge=-50, le=50) = Field(..., description="Cambio relativo en puntos %")  # type: ignore[valid-type]


@register("change_volume", ChangeVolumeArgs, "Sube o baja el volumen (delta entre -50 y +50).")
async def change_volume(args: ChangeVolumeArgs) -> str:
    sign = "+" if args.delta >= 0 else "-"
    await _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{abs(args.delta)}%{sign}"])
    return f"Volumen {sign}{abs(args.delta)}%"


# ──────────────────────────── brillo ────────────────────────────
class SetBrightnessArgs(BaseModel):
    """Establece el brillo de pantalla (0-100)."""

    level: conint(ge=0, le=100) = Field(..., description="Brillo 0-100")  # type: ignore[valid-type]


@register("set_brightness", SetBrightnessArgs, "Ajusta el brillo de pantalla (0-100).")
async def set_brightness(args: SetBrightnessArgs) -> str:
    await _run(["brightnessctl", "set", f"{args.level}%"])
    return f"Brillo al {args.level}%"


# ──────────────────────────── hyprland ────────────────────────────
class WorkspaceArgs(BaseModel):
    """Cambia al workspace indicado (1-10)."""

    number: conint(ge=1, le=10) = Field(..., description="Workspace 1-10")  # type: ignore[valid-type]


@register("hyprland_workspace", WorkspaceArgs, "Cambia al workspace 1-10 de Hyprland.")
async def hyprland_workspace(args: WorkspaceArgs) -> str:
    await _run(["hyprctl", "dispatch", "workspace", str(args.number)])
    return f"Workspace {args.number}"


class HyprToggleArgs(BaseModel):
    """Hace toggle sobre la ventana activa."""

    action: Literal["fullscreen", "floating", "pseudo"] = Field(
        ..., description="Qué togglear sobre la ventana activa"
    )


@register("hyprland_toggle", HyprToggleArgs, "Toggle fullscreen / floating / pseudo en la ventana activa.")
async def hyprland_toggle(args: HyprToggleArgs) -> str:
    mapping = {
        "fullscreen": ("fullscreen", "0"),
        "floating": ("togglefloating",),
        "pseudo": ("pseudo",),
    }
    parts = mapping[args.action]
    await _run(["hyprctl", "dispatch", *parts])
    return f"{args.action} aplicado"


# ──────────────────────────── apps ────────────────────────────
class LaunchAppArgs(BaseModel):
    """Lanza una aplicación de la lista permitida."""

    name: Literal[
        "firefox", "kitty", "code", "obsidian", "spotify", "nautilus", "thunar", "yazi", "discord"
    ] = Field(..., description="Nombre del binario a lanzar")


@register("launch_app", LaunchAppArgs, "Lanza una app permitida (firefox, kitty, code, etc.).")
async def launch_app(args: LaunchAppArgs) -> str:
    if args.name not in ALLOWED_APPS:
        raise ToolError(f"app '{args.name}' no está en la allowlist")
    # `setsid` para desligar del proceso del daemon
    cmd = ["setsid", "-f", args.name] if _has("setsid") else [args.name]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
        start_new_session=True,
    )
    # No esperamos al proceso: app lanzada en background
    _ = proc
    return f"Abriendo {args.name}"


def _has(binary: str) -> bool:
    return any(
        os.access(os.path.join(p, binary), os.X_OK) for p in os.environ.get("PATH", "").split(":")
    )


__all__ = ["REGISTRY", "ToolError"]
