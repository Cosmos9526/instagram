"""Shared safe HTTP GET for any user-supplied URL (business analysis, competitor scans): blocks SSRF by
allowing only http/https, resolving DNS and rejecting private/loopback/link-local/multicast/reserved
addresses, and re-checking the target after every redirect hop. Streams and stops reading at MAX_BYTES
instead of loading the whole body."""

import ipaddress
import re
import socket
from urllib.parse import urlparse

import httpx

MAX_BYTES = 2_000_000
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


class Response:
    """Minimal response wrapper: only what callers need, with the body already capped."""

    def __init__(self, status_code: int, url: str, content: bytes, headers) -> None:
        self.status_code = status_code
        self.url = url
        self.headers = headers
        self._content = content

    @property
    def text(self) -> str:
        m = re.search(r"charset=([\w-]+)", self.headers.get("content-type", ""))
        charset = m.group(1) if m else "utf-8"
        try:
            return self._content.decode(charset, errors="replace")
        except LookupError:
            return self._content.decode("utf-8", errors="replace")


def get(url: str, timeout: float = 15, max_redirects: int = 5, headers: dict | None = None,
        client: httpx.Client | None = None, connect_timeout: float = 5.0) -> Response:
    """GET with the SSRF guard re-applied on every hop. Raises UnsafeURLError for a disallowed target.
    Streams the body and stops after MAX_BYTES rather than loading the whole response."""
    hdrs = {**UA, **(headers or {})}
    owns = client is None
    to = httpx.Timeout(connect_timeout, read=timeout, write=timeout, pool=timeout)
    cl = client or httpx.Client(timeout=to)
    cl.follow_redirects = False  # a caller-supplied client must never silently bypass the redirect guard
    try:
        current = url
        for _ in range(max_redirects + 1):
            _check_url(current)
            with cl.stream("GET", current, headers=hdrs) as r:
                if r.status_code in (301, 302, 303, 307, 308) and r.headers.get("location"):
                    current = str(httpx.URL(current).join(r.headers["location"]))
                    continue
                chunks: list[bytes] = []
                total = 0
                for chunk in r.iter_bytes():
                    chunks.append(chunk)
                    total += len(chunk)
                    if total >= MAX_BYTES:
                        break
                return Response(r.status_code, str(r.url), b"".join(chunks), r.headers)
        raise UnsafeURLError("too many redirects")
    finally:
        if owns:
            cl.close()


def text(url: str, timeout: float = 15, client: httpx.Client | None = None, connect_timeout: float = 5.0) -> tuple[str, str]:
    """Returns (final_url, text), or ('', '') on any failure — never raises."""
    try:
        r = get(url, timeout=timeout, client=client, connect_timeout=connect_timeout)
        if r.status_code < 400:
            return str(r.url), r.text
    except (UnsafeURLError, httpx.HTTPError):
        pass
    return url, ""
