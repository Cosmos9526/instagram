"""Live check of the real price lookup on the server (read-only, no database writes).

    docker compose -p postyar exec -T api python -m app.admin_price_check --sites parspremium.ir,cafearz.com \
        --products "ChatGPT Plus,Claude Pro,Claude Max"

Prints: site | product | status | name | price | url"""

import argparse

from .admin_price_probe import DEFAULT_PRODUCTS, SEED_SITES
from .price_search import lookup


def check(sites: list[str], products: list[str]) -> list[str]:
    lines = ["site | product | status | name | price | url"]
    for site in sites:
        host = site.removeprefix("https://").removeprefix("http://").strip("/")
        for q in products:
            try:
                row = lookup({"id": host, "name": host, "website": site}, q)
            except Exception as e:  # noqa: BLE001
                lines.append(f"{host} | {q} | error | {e} | - | -")
                continue
            for m in row["matches"] or [{}]:
                price = m.get("price")
                lines.append(f"{host} | {q} | {row['status']} | {m.get('name', '-')} | "
                             f"{price if price is None else format(price, ',')} | {m.get('url', '-')}")
    return lines


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sites", default="")
    ap.add_argument("--products", default=",".join(DEFAULT_PRODUCTS))
    a = ap.parse_args(argv)
    sites = [s.strip() for s in a.sites.split(",") if s.strip()] or SEED_SITES
    print("\n".join(check(sites, [p.strip() for p in a.products.split(",") if p.strip()])))


if __name__ == "__main__":
    main()
