"""mDNS/Bonjour service advertisement so clients can auto-discover the server.

The server advertises ``_vesnai._tcp.local.``; the app browses for it on the LAN
and offers the discovered URL, with manual-URL entry as a fallback. The
``build_service_info`` helper is pure and unit-testable without touching the
network.
"""

from __future__ import annotations

import socket
from typing import Any

SERVICE_TYPE = "_vesnai._tcp.local."


def build_service_info(name: str, host: str, port: int, *, https: bool = True):
    """Construct a zeroconf ServiceInfo for the VesnAI service."""
    from zeroconf import ServiceInfo

    safe_name = name.replace(".", "-")
    addr = host if host not in ("0.0.0.0", "127.0.0.1", "::") else lan_ip()
    return ServiceInfo(
        SERVICE_TYPE,
        f"{safe_name}.{SERVICE_TYPE}",
        addresses=[socket.inet_aton(addr)],
        port=port,
        properties={"scheme": "https" if https else "http", "path": "/v1"},
        server=f"{safe_name}.local.",
    )


def lan_ip() -> str:
    """Best-effort primary LAN IPv4 address for this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


# Backwards-compatible private alias.
_lan_ip = lan_ip


class ServiceAdvertiser:
    def __init__(self, name: str, host: str, port: int, *, https: bool = True) -> None:
        self.info = build_service_info(name, host, port, https=https)
        self._zc: Any = None

    def start(self) -> None:
        from zeroconf import Zeroconf

        self._zc = Zeroconf()
        self._zc.register_service(self.info)

    def stop(self) -> None:
        if self._zc is not None:
            self._zc.unregister_service(self.info)
            self._zc.close()
            self._zc = None
