from app import admin_price_check as chk


def test_check_prints_rows(monkeypatch):
    monkeypatch.setattr(chk, "lookup", lambda c, q: {"status": "found", "matches": [
        {"name": "Claude Pro", "price": 1234567, "url": "https://a.ir/p"}]})
    lines = chk.check(["a.ir"], ["Claude Pro"])
    assert lines[1] == "a.ir | Claude Pro | found | Claude Pro | 1,234,567 | https://a.ir/p"
