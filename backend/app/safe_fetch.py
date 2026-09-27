"""Shared safe HTTP GET for any user-supplied URL (business analysis, competitor scans): blocks SSRF by
allowing only http/https, resolving DNS and rejecting private/loopback/link-local/multicast/reserved
addresses, and re-checking the target after every redirect hop."""

import ipaddress
import socket
from urllib.parse import urlparse

import httpx

MAX_CHARS = 2_000_000
UA = {"User-Agent": "Mozilla/5.0 (compatible; PostyarBot/1.0; +https://postyar.app)", "Accept-Language": "fa,en;q=0.8"}


class UnsafeURLError(RuntimeError):
    pass


def _check_url(url: str) -> None:
    p = urlparse(url)
    if p.scheme not in ("http", "https"):
        raise UnsafeURLError(f"scheme not allowed: {p.scheme!r}")
    host = p.hostname
    if not host:
        raise UnsafeURLError("no hostname")
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror as e:
        raise UnsafeURLError(f"cannot resolve {host}") from e
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_reserved or ip.is_unspecified:
            raise UnsafeURLError(f"{host} resolves to a non-public address ({ip})")


def get(url: str, timeout: float = 15, max_redirects: int = 5, headers: dict | None = None,
        client: httpx.Client | None = None) -> httpx.Response:
    """GET with the SSRF guard re-applied on every hop. Raises UnsafeURLError for a disallowed target."""
    hdrs = {**UA, **(headers or {})}
    owns = client is None
    cl = client or httpx.Client(follow_redirects=False, timeout=timeout)
    try:
        current = url
        for _ in range(max_redirects + 1):
            _check_url(current)
            r = cl.get(current, headers=hdrs)
            if r.status_code in (301, 302, 303, 307, 308) and r.headers.get("location"):
                current = str(httpx.URL(current).join(r.headers["location"]))
                continue
            return r
        raise UnsafeURLError("too many redirects")
    finally:
        if owns:
            cl.close()


def text(url: str, timeout: float = 15, client: httpx.Client | None = None) -> tuple[str, str]:
    """Returns (final_url, text) capped to MAX_CHARS, or ('' , '') on any failure — never raises."""
    try:
        r = get(url, timeout=timeout, client=client)
        if r.status_code < 400:
            return str(r.url), r.text[:MAX_CHARS]
    except (UnsafeURLError, httpx.HTTPError):
        pass
    return url, ""
