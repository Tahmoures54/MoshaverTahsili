#!/usr/bin/env python3
"""Build the bundled vehicle catalog for Smart Mechanic.

Reads tool/seed_cars.json (current backend list), enriches metadata, then
adds Iranian-market cars, motorcycles, trucks, buses, tractors and heavy
machinery. Output: assets/data/cars.json
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = Path(__file__).with_name("seed_cars.json")
OUT = ROOT / "assets" / "data" / "cars.json"

# ── defaults / issue templates ──────────────────────────────────────────────
ISSUES = {
    "iran_econ": ["استهلاک جلوبندی", "مشکلات برقی", "کیفیت مونتاژ", "مصرف سوخت"],
    "turbo": ["حساسیت توربو به بنزین", "داغ کردن", "نوسان دور موتور"],
    "al4": ["تقه گیربکس AL4", "خرابی یونیت گیربکس", "تأخیر در تعویض دنده"],
    "suv_cn": ["مصرف سوخت بالا", "سروصدای کابین", "استهلاک جلوبندی"],
    "pickup": ["زنگ‌زدگی اتاق بار", "استهلاک کمک‌فنر", "ضعف ترمز با بار"],
    "moto": ["خرابی CDI", "ضعف ترمز عقب", "استهلاک زنجیر و خودرو"],
    "scooter": ["خرابی واریاتور", "ضعف باتری", "گرفتگی کاربراتور/انژکتور"],
    "diesel_truck": ["خرابی توربو", "گرفتگی فیلتر گازوئیل", "نشتی سیستم هوا"],
    "bus": ["استهلاک سیستم تعلیق", "خرابی کمپرسور باد", "ضعف کولر"],
    "tractor": ["نشتی هیدرولیک", "خرابی پمپ انژکتور", "ضعف کلاچ"],
    "heavy": ["نشتی هیدرولیک", "خرابی پمپ اصلی", "استهلاک شیلنگ و سیلندر"],
    "import": ["گرانی قطعات", "حساسیت به بنزین", "سنسورها و کاتالیزور"],
}


def _slug(*parts: str) -> str:
    raw = "-".join(p.strip() for p in parts if p and p.strip())
    raw = unicodedata.normalize("NFKC", raw)
    raw = re.sub(r"\s+", "-", raw)
    raw = re.sub(r"[^0-9A-Za-z\u0600-\u06FF\-]+", "", raw)
    return raw.lower()[:80] or "veh"


def car(
    brand: str,
    model: str,
    engine: str,
    category: str,
    *,
    fuel: str | None = "gasoline",
    trans: str | None = "manual",
    popular: bool = False,
    region: str | None = "ایران",
    country: str | None = None,
    aliases: list[str] | None = None,
    issues: list[str] | None = None,
    cid: str | None = None,
    electric: bool = False,
    year: str = "",
) -> dict:
    if electric:
        fuel = "electric"
    item = {
        "id": cid or _slug(brand, model, engine),
        "brand": brand,
        "model": model,
        "engine": engine,
        "year": year,
        "category": category,
        "isPopular": popular,
        "isElectric": electric,
        "isActive": True,
    }
    if fuel:
        item["fuelType"] = fuel
    if trans:
        item["transmission"] = trans
    if region:
        item["region"] = region
    if country:
        item["countryOfOrigin"] = country
    if aliases:
        item["aliases"] = aliases
    if issues:
        item["commonIssues"] = issues
    return item


def infer_meta(brand: str, model: str, engine: str) -> dict:
    b, m, e = brand, model, (engine or "")
    text = f"{b} {m} {e}".lower()
    cat = "sedan"
    fuel = "gasoline"
    trans = "manual"
    region = "ایران"
    country = "ایران"
    popular = False
    aliases: list[str] = []
    issues = ISSUES["iran_econ"]

    suv_keys = (
        "سانتافه", "توسان", "اسپورتیج", "موهاوی", "پرادو", "لندکروزر", "هایلندر",
        "قشقایی", "پاترول", "اوتلندر", "پاجرو", "تیگوان", "کولئوس", "هاوال",
        "تیگو", "جتور", "فیدلیتی", "دیگنیتی", "ریرا", "x22", "x33", "x55",
        "s5", "s7", "s8", "cx-", "q3", "q5", "q7", "x1", "x3", "x5", "gla",
        "glc", "gle", "cr-v", "hr-v", "rav", "dargo", "jolion", "tugella",
        "coolray", "اطلس پرو", "bj40", "هایما", "شاین", "fx", "اکستریم",
        "id.4", "یونیکس", "سانگ پلاس", "هان", "tang", "لندمارک", "لوکانو",
        "vv7",
    )
    hatch_keys = (
        "206", "207", "تیبا 2", "هاچ", "کوییک", "گلف", "پیکانتو", "i10",
        "i20", "یاریس", "208", "c3", "رانا", "seagul", "dolphin",
    )
    pickup_keys = ("پیکاپ", "وانت", "tunland", "t8", "t9", "t60")
    van_keys = ("هایس", "ون ", "h1")
    coupe_keys = ("mx-5", "کوپه")

    if any(k in text for k in pickup_keys):
        cat = "pickup"
        issues = ISSUES["pickup"]
    elif any(k in text for k in van_keys):
        cat = "van"
    elif any(k in text for k in coupe_keys):
        cat = "coupe"
    elif any(k in text for k in suv_keys) or re.search(r"\bx[0-9]", text):
        cat = "suv"
        issues = ISSUES["suv_cn"] if any(x in b for x in ("ام وی ام", "مدیران", "جک", "چری", "فونیکس")) else ISSUES["import"]
    elif any(k in text for k in hatch_keys):
        cat = "hatchback"

    if any(k in text for k in ("دیزل", "diesel", "ev", "برقی")):
        if "دیزل" in e or "diesel" in text:
            fuel = "diesel"
        if any(k in text for k in ("ev", "برقی", "id.4", "یونیکس", "seagull", "dolphin")):
            fuel = "electric"
    if any(k in text for k in ("هیبرید", "hybrid", "dmi", "dm-i")):
        fuel = "hybrid"
    if any(k in text for k in ("اتومات", "automatic", "cvt", "at ", "al4")):
        trans = "automatic"
    if "دوکلاچه" in text or "dct" in text:
        trans = "dct"
    if "توربو" in text or "tc" in e.lower() or "turbo" in text:
        issues = ISSUES["turbo"]
    if "al4" in text:
        issues = ISSUES["al4"]

    popular_models = (
        "پراید 131", "تیبا", "کوییک", "ساینا", "شاهین", "پژو 206 تیپ 2",
        "پژو پارس", "سمند", "دنا پلاس", "تارا", "تندر 90", "پژو 207",
    )
    popular = any(p in f"{b} {m}" for p in popular_models)

    if m in ("پژو 206 تیپ 2", "پژو 206 تیپ 5"):
        aliases += ["۲۰۶", "206"]
    if "تندر" in m or "ال 90" in m:
        aliases += ["ال۹۰", "L90", "ال90", "Logan"]
    if "پراید" in m:
        aliases += ["پراید", "Pride"]
    if brand in ("هیوندای", "کیا", "تویوتا", "بنز", "مرسدس بنز", "بی‌ام‌و", "آئودی"):
        country = {"هیوندای": "کره جنوبی", "کیا": "کره جنوبی", "تویوتا": "ژاپن",
                   "بنز": "آلمان", "مرسدس بنز": "آلمان", "بی‌ام‌و": "آلمان",
                   "آئودی": "آلمان"}.get(brand, country)
        region = "وارداتی"
        if issues == ISSUES["iran_econ"]:
            issues = ISSUES["import"]

    return dict(
        category=cat, fuelType=fuel, transmission=trans, region=region,
        countryOfOrigin=country, isPopular=popular, aliases=aliases,
        commonIssues=issues,
    )


def enrich_seed(seed: list[dict]) -> list[dict]:
    out = []
    for raw in seed:
        meta = infer_meta(raw["brand"], raw["model"], raw.get("engine", ""))
        item = {
            "id": raw["id"],
            "brand": raw["brand"],
            "model": raw["model"],
            "engine": raw.get("engine", ""),
            "year": raw.get("year", ""),
            **meta,
            "isElectric": meta.get("fuelType") == "electric",
            "isActive": True,
        }
        if raw.get("commonIssues"):
            item["commonIssues"] = raw["commonIssues"]
        if not item.get("aliases"):
            item.pop("aliases", None)
        out.append(item)
    return out


def key_of(c: dict) -> str:
    return re.sub(r"\s+", " ", f"{c['brand']}|{c['model']}|{c.get('engine','')}".strip()).lower()


# ═══════════════════════════════════════════════════════════════════════════
# Extra catalog — compact tuples:
# brand, model, engine, category, fuel, trans, popular, aliases, issues_key
# ═══════════════════════════════════════════════════════════════════════════

def extras() -> list[dict]:
    rows: list[dict] = []

    def add(brand, model, engine, cat, fuel="gasoline", trans="manual",
            popular=False, aliases=None, issues=None, country="ایران",
            region="ایران", electric=False, cid=None):
        issue_list = ISSUES.get(issues, issues) if isinstance(issues, str) else issues
        rows.append(car(
            brand, model, engine, cat, fuel=fuel, trans=trans, popular=popular,
            aliases=aliases, issues=issue_list, country=country, region=region,
            electric=electric, cid=cid,
        ))

    # ── ایران خودرو ────────────────────────────────────────────────────────
    ikco = "ایران خودرو"
    for m, e, cat, pop, als, iss in [
        ("پیکان جوانان", "1600", "sedan", False, ["پیکان", "Paykan"], "iran_econ"),
        ("پیکان وانت بنزینی", "1600", "pickup", True, ["وانت پیکان"], "pickup"),
        ("پیکان وانت دیزل", "2.5L دیزل", "pickup", False, ["وانت پیکان دیزل"], "pickup"),
        ("آردی", "XU7", "sedan", False, ["RD", "Roa"], "iran_econ"),
        ("روآ", "XU7", "sedan", False, ["Roa"], "iran_econ"),
        ("پژو 405 GLXi", "XU7", "sedan", False, ["۴۰۵"], "iran_econ"),
        ("پژو 405 SLX دوگانه", "XU7 CNG", "sedan", False, ["۴۰۵ دوگانه"], "iran_econ"),
        ("پژو پارس ELX", "XU7", "sedan", True, ["پارس ELX"], "iran_econ"),
        ("پژو پارس XU7P", "XU7P", "sedan", True, ["پارس جدید"], "iran_econ"),
        ("پژو پارس TU5", "TU5", "sedan", True, ["پارس TU5"], "iran_econ"),
        ("پژو 206 تیپ 1", "TU3A", "hatchback", False, ["۲۰۶"], "iran_econ"),
        ("پژو 206 تیپ 6", "TU5", "hatchback", False, ["۲۰۶ تیپ ۶"], "iran_econ"),
        ("پژو 206 SD V8", "TU3A", "sedan", True, ["۲۰۶ صندوق‌دار"], "iran_econ"),
        ("پژو 206 SD V9", "TU5", "sedan", False, ["۲۰۶ صندوقدار V9"], "iran_econ"),
        ("پژو 207i دنده‌ای", "TU5", "hatchback", True, ["۲۰۷"], "iran_econ"),
        ("پژو 207i پانوراما", "TU5", "hatchback", True, ["۲۰۷ پانوراما"], "al4"),
        ("پژو 207 MC", "TU5P", "hatchback", False, ["۲۰۷ MC"], "iran_econ"),
        ("پژو 207 SD", "TU5", "sedan", False, ["۲۰۷ صندوق‌دار"], "iran_econ"),
        ("پژو 2008", "TU5", "suv", True, ["۲۰۰۸"], "iran_econ"),
        ("پژو 301", "TU5", "sedan", False, ["۳۰۱"], "iran_econ"),
        ("پژو 508", "1.6T", "sedan", False, ["۵۰۸"], "import"),
        ("سمند SE", "XU7", "sedan", False, ["Samand"], "iran_econ"),
        ("سمند LX EF7", "EF7", "sedan", True, ["سمند EF7"], "iran_econ"),
        ("سمند سورن پلاس", "EF7", "sedan", True, ["سورن پلاس"], "iran_econ"),
        ("سورن پلاس توربو", "EF7 TC", "sedan", True, ["سورن توربو"], "turbo"),
        ("دنا پلاس ۶ دنده", "EF7", "sedan", True, ["دنا ۶ دنده"], "iran_econ"),
        ("دنا پلاس توربو اتوماتیک", "EF7 TC", "sedan", True, ["دنا توربو AT"], "turbo"),
        ("تارا دنده‌ای V1", "TU5P", "sedan", True, ["تارا V1"], "iran_econ"),
        ("تارا اتوماتیک LX", "TU5P", "sedan", True, ["تارا LX"], "iran_econ"),
        ("رانا پلاس پانوراما", "TU5P", "hatchback", False, ["رانا پانوراما"], "iran_econ"),
        ("هایما S5 CVT", "1.5T", "suv", False, ["Haima S5"], "suv_cn"),
        ("هایما S7 پلاس", "1.8T", "suv", False, ["Haima S7"], "suv_cn"),
        ("هایما 7X", "1.6T", "suv", False, ["Haima 7X"], "suv_cn"),
        ("هایما 8S", "1.6T", "suv", False, ["Haima 8S"], "suv_cn"),
        ("ریرا توربو", "1.5T", "suv", True, ["Reyra", "ری‌را"], "turbo"),
        ("لاماری ایما", "1.5T", "suv", True, ["Lamari Eama", "ایما"], "suv_cn"),
        ("لاماری ایما X", "1.5T", "suv", False, ["ایما X"], "suv_cn"),
        ("آریسان 2", "XU7", "pickup", False, ["Arisun", "آریسان"], "pickup"),
        ("فوتون تونلند G7 بنزینی", "2.0T", "pickup", False, ["Tunland G7"], "pickup"),
        ("فوتون تونلند G7 دیزل", "2.0T دیزل", "pickup", False, ["Tunland دیزل"], "pickup"),
        ("پژو 405 دوگانه سوز", "XU7 CNG", "sedan", False, ["۴۰۵ گازسوز"], "iran_econ"),
        ("سمند دوگانه سوز", "XU7 CNG", "sedan", False, ["سمند CNG"], "iran_econ"),
        ("دنا جوانان", "EF7", "sedan", False, ["دنا معمولی"], "iran_econ"),
        ("پژو پارس سال", "XU7", "sedan", True, ["پارس سال"], "iran_econ"),
        ("تارا V4 هیبرید", "TU5P HEV", "sedan", False, ["تارا هیبرید"], "import"),
    ]:
        add(ikco, m, e, cat, popular=pop, aliases=als, issues=iss,
            fuel="cng" if "CNG" in e else ("diesel" if "دیزل" in e else ("hybrid" if "HEV" in e else "gasoline")),
            trans="automatic" if any(x in m for x in ("اتومات", "CVT", "LX")) and "دنده‌ای" not in m else "manual")

    # ── سایپا / پارس خودرو / زامیاد ───────────────────────────────────────
    saipa = "سایپا"
    for m, e, cat, pop, als in [
        ("پراید 141", "M13", "sedan", False, ["Pride 141"]),
        ("پراید SE", "M13", "sedan", False, ["پراید اس‌ای"]),
        ("پراید صندوق‌پران", "M13", "hatchback", False, ["پراید هاچ‌بک"]),
        ("تیبا EX", "M15", "sedan", True, ["Tiba"]),
        ("تیبا SX", "M15", "sedan", False, []),
        ("ساینا EX", "M15", "sedan", False, ["Saina"]),
        ("ساینا GX", "M15", "sedan", False, []),
        ("ساینا اتوماتیک", "M15", "sedan", False, ["ساینا CVT"]),
        ("کوییک GX", "M15", "hatchback", True, ["Quik"]),
        ("کوییک اتوماتیک", "M15", "hatchback", True, ["کوییک CVT"]),
        ("کوییک R پلاس", "M15", "hatchback", True, []),
        ("شاهین G", "M15 TC", "sedan", True, ["Shahin"]),
        ("شاهین پلاس", "ME16", "sedan", True, ["شاهین TU5"]),
        ("شاهین CVT", "M15 TC", "sedan", True, ["شاهین اتومات"]),
        ("اطلس اتوماتیک", "M15", "hatchback", False, ["Atlas"]),
        ("آریا دنده‌ای", "M15", "suv", False, ["آریا کراس"]),
        ("چانگان CS35", "1.6L", "suv", False, ["CS35 سایپا"]),
        ("کیا سراتو سایپا", "1.6L / 2.0L", "sedan", True, ["سراتو سایپا"]),
        ("رنو اسکالا", "1.6L", "sedan", False, ["Fluence", "اسکالا"]),
        ("سایپا 131 دوگانه", "M13 CNG", "sedan", False, ["پراید گازسوز"]),
        ("سایپا 151 پلاس", "M13", "pickup", True, ["وانت پراید", "پراید وانت"]),
        ("کرس", "1.6L", "pickup", False, ["Ceres", "وانت کرس"]),
        ("نسیم", "M13", "sedan", False, ["پراید نسیم"]),
        ("صبا", "M13", "sedan", False, ["پراید صبا"]),
        ("مینیاتور", "M15", "hatchback", False, []),
    ]:
        add(saipa, m, e, cat, popular=pop, aliases=als, issues="turbo" if "TC" in e else "iran_econ",
            fuel="cng" if "CNG" in e else "gasoline",
            trans="automatic" if any(x in m for x in ("اتومات", "CVT")) else "manual")

    for m, e, cat, pop, als in [
        ("تندر 90 E2", "K4M", "sedan", True, ["ال۹۰ E2", "L90"]),
        ("تندر 90 اتوماتیک", "K4M", "sedan", True, ["ال۹۰ اتومات"]),
        ("تندر 90 پارس تندر", "K4M", "sedan", False, ["پارس تندر"]),
        ("رنو مگان 1600", "1.6L", "sedan", False, ["Megane"]),
        ("رنو مگان 2000", "2.0L", "sedan", False, []),
        ("برلیانس H220", "1.5L", "hatchback", False, ["H220"]),
        ("برلیانس H320", "1.5L", "sedan", False, ["H320"]),
        ("برلیانس V5", "1.5T", "suv", False, ["V5"]),
        ("نیسان ماکسیما قدیمی", "VQ30", "sedan", False, ["Maxima"]),
        ("نیسان سرانزا", "1.6L", "sedan", False, ["Almera"]),
    ]:
        add("پارس خودرو", m, e, cat, popular=pop, aliases=als, issues="iran_econ",
            trans="automatic" if "اتومات" in m else "manual")

    for m, e, cat, pop, als in [
        ("نیسان وانت Z24", "Z24", "pickup", True, ["زامیاد", "وانت نیسان", "Z24"]),
        ("نیسان وانت دیزل", "2.5L دیزل", "pickup", True, ["نیسان دیزل"]),
        ("پادرا", "2.4L", "pickup", True, ["Padra"]),
        ("پادرا پلاس", "2.4L", "pickup", True, ["Padra Plus"]),
        ("کینگ کونگ", "2.2L", "pickup", False, ["King Kong"]),
        ("شوکا", "2.4L", "pickup", False, ["Shoka"]),
        ("کارون", "2.4L", "pickup", False, []),
        ("دیزل پادرا", "2.5L دیزل", "pickup", False, []),
    ]:
        add("زامیاد", m, e, cat, popular=pop, aliases=als, issues="pickup",
            fuel="diesel" if "دیزل" in e else "gasoline")

    # ── کرمان موتور / مدیران / بهمن / سایر مونتاژکاران ───────────────────
    for brand, items in {
        "کرمان موتور": [
            ("جک S3", "1.6L", "suv", False, ["JAC S3"], "suv_cn", "gasoline", "manual"),
            ("جک S5 اتوماتیک", "2.0T", "suv", True, ["JAC S5"], "suv_cn", "gasoline", "dct"),
            ("جک J5", "1.8L", "sedan", False, ["JAC J5"], "iran_econ", "gasoline", "manual"),
            ("کی ام سی A5", "1.5T", "sedan", False, ["KMC A5"], "suv_cn", "gasoline", "dct"),
            ("کی ام سی X7", "1.5T", "suv", False, ["KMC X7"], "suv_cn", "gasoline", "dct"),
            ("کی ام سی T8 پلاس", "2.0T", "pickup", True, ["KMC T8"], "pickup", "gasoline", "manual"),
            ("کی ام سی T9 دیزل", "2.0T دیزل", "pickup", False, ["KMC T9"], "pickup", "diesel", "automatic"),
            ("کی ام سی J7 پلاس", "1.5T", "sedan", False, ["J7"], "suv_cn", "gasoline", "dct"),
            ("کی ام سی K7", "2.0L", "van", False, ["K7 ون"], "iran_econ", "gasoline", "manual"),
            ("لاماری هیما", "1.5T", "suv", False, [], "suv_cn", "gasoline", "dct"),
        ],
        "مدیران خودرو": [
            ("ام وی ام 110S", "1.0L", "hatchback", False, ["QQ", "110 اس"], "iran_econ", "gasoline", "manual"),
            ("ام وی ام 530", "1.6L", "sedan", False, ["530"], "iran_econ", "gasoline", "manual"),
            ("ام وی ام 550", "1.6L", "sedan", False, ["550"], "iran_econ", "gasoline", "automatic"),
            ("ام وی ام X22 پرو", "1.5L", "suv", True, ["X22 Pro"], "suv_cn", "gasoline", "cvt"),
            ("ام وی ام X33 کراس", "1.5L", "suv", False, ["X33 Cross"], "suv_cn", "gasoline", "automatic"),
            ("آریزو 5", "1.5L", "sedan", False, ["Arrizo 5"], "suv_cn", "gasoline", "cvt"),
            ("آریزو 6 پرو", "1.5T", "sedan", False, ["Arrizo 6"], "suv_cn", "gasoline", "dct"),
            ("آریزو 8", "1.6T", "sedan", False, ["Arrizo 8"], "suv_cn", "gasoline", "dct"),
            ("تیگو 5", "2.0L", "suv", False, ["Tiggo 5"], "suv_cn", "gasoline", "automatic"),
            ("تیگو 7 پرو", "1.5T", "suv", True, ["Tiggo 7"], "suv_cn", "gasoline", "dct"),
            ("تیگو 8 پرو مکس", "2.0T", "suv", True, ["Tiggo 8 Pro Max"], "suv_cn", "gasoline", "dct"),
            ("فونیکس آریزو 8", "1.6T", "sedan", False, [], "suv_cn", "gasoline", "dct"),
            ("فونیکس تیگو 7 پرو مکس", "1.6T", "suv", True, ["F7 PRO MAX"], "suv_cn", "gasoline", "dct"),
            ("اکستریم VX", "2.0T", "suv", False, ["Exeed VX"], "suv_cn", "gasoline", "dct"),
            ("اکستریم TXL", "1.6T", "suv", False, ["Exeed TXL"], "suv_cn", "gasoline", "dct"),
            ("اکستریم RX", "1.6T", "suv", False, ["Exeed RX"], "suv_cn", "gasoline", "dct"),
            ("اومودا C5", "1.6T", "suv", False, ["Omoda C5"], "suv_cn", "gasoline", "dct"),
            ("جیکو J7", "1.6T", "suv", False, ["Jaecoo J7"], "suv_cn", "gasoline", "dct"),
            ("جیکو J8", "2.0T", "suv", False, ["Jaecoo J8"], "suv_cn", "gasoline", "dct"),
        ],
        "بهمن موتور": [
            ("فیدلیتی پرایم 7 نفره", "1.5T", "suv", True, ["Fidelity"], "suv_cn", "gasoline", "dct"),
            ("فیدلیتی پرستیژ", "1.5T", "suv", True, ["Fidelity Prestige"], "suv_cn", "gasoline", "dct"),
            ("دیگنیتی پرستیژ", "1.5T", "suv", True, ["Dignity"], "suv_cn", "gasoline", "dct"),
            ("ریسپکت پرایم", "1.5T", "sedan", False, ["Respect"], "suv_cn", "gasoline", "dct"),
            ("مزدا 3 بهمن", "2.0L", "sedan", False, ["Mazda 3"], "import", "gasoline", "automatic"),
            ("مزدا 2", "1.5L", "hatchback", False, ["Mazda 2"], "import", "gasoline", "automatic"),
            ("ایسوزو D-Max", "2.5L دیزل", "pickup", True, ["D-Max", "دی‌مکس"], "pickup", "diesel", "manual"),
            ("کاپرا 2", "2.4L", "pickup", True, ["Capra"], "pickup", "gasoline", "manual"),
            ("کاپرا 2 دیزل", "2.5L دیزل", "pickup", False, [], "pickup", "diesel", "manual"),
            ("بستون T77", "1.5T", "suv", False, ["Bestune T77"], "suv_cn", "gasoline", "automatic"),
            ("بستون B70", "1.5T", "sedan", False, ["Bestune B70"], "suv_cn", "gasoline", "automatic"),
            ("لوکانو L7", "1.6T", "suv", False, ["Lucano"], "suv_cn", "gasoline", "dct"),
            ("اینرودز", "1.5T", "suv", False, ["Inroads"], "suv_cn", "gasoline", "dct"),
            ("هوندا وزل", "1.5T", "suv", False, ["Vezel", "HR-V"], "import", "gasoline", "cvt"),
        ],
        "گروه بهمن": [
            ("هاوال H6 هیبرید", "1.5T HEV", "suv", False, ["H6 HEV"], "import", "hybrid", "dct"),
            ("هاوال H9", "2.0T", "suv", False, ["H9"], "suv_cn", "gasoline", "automatic"),
            ("تانک 300", "2.0T", "suv", False, ["Tank 300"], "suv_cn", "gasoline", "automatic"),
        ],
    }.items():
        for m, e, cat, pop, als, iss, fuel, trans in items:
            add(brand, m, e, cat, popular=pop, aliases=als, issues=iss, fuel=fuel, trans=trans)

    # سایر مونتاژ / واردکننده ایران
    for brand, items in {
        "فردا موتورز": [
            ("sx5", "1.5L", "suv", False, ["Farda SX5"], "suv_cn"),
            ("T5", "1.5T", "suv", False, ["Farda T5"], "suv_cn"),
            ("511", "1.5L", "sedan", False, [], "iran_econ"),
        ],
        "دیار خودرو": [
            ("خودروساز دیار", "1.5L", "sedan", False, ["Diar"], "iran_econ"),
        ],
        "رین": [
            ("هیوندای اکسنت رین", "1.6L", "sedan", False, ["Accent"], "import"),
            ("هیوندای آوانته رین", "1.6L", "sedan", False, ["Avante"], "import"),
        ],
        "مرتکب": [
            ("پاژن", "4.0L", "suv", False, ["Pajan", "Pajero"], "import"),
            ("موسو", "2.9L دیزل", "suv", False, ["Musso"], "import"),
        ],
        "کیش خودرو": [
            ("سیناد", "1.6L", "sedan", False, ["Sinad"], "iran_econ"),
        ],
        "سریر": [
            ("پیکان سریر", "1600", "sedan", False, ["Sarir"], "iran_econ"),
        ],
        "گریت وال": [
            ("وینگل 5", "2.4L", "pickup", True, ["Wingle 5"], "pickup"),
            ("وینگل 7", "2.0T", "pickup", False, ["Wingle 7"], "pickup"),
            ("پوئر", "2.0T", "pickup", False, ["Poer", "Cannon"], "pickup"),
        ],
        "دی اف اس کی": [
            ("گلوری 580", "1.5T", "suv", False, ["Glory 580"], "suv_cn"),
            ("ریچ 6", "2.4L", "pickup", False, ["Rich 6"], "pickup"),
        ],
        "مکسوس": [
            ("T60", "2.8L دیزل", "pickup", False, ["Maxus T60"], "pickup"),
            ("T70", "2.0T", "pickup", False, ["Maxus T70"], "pickup"),
            ("G10", "2.4L", "van", False, ["Maxus G10"], "iran_econ"),
            ("V80", "2.5L دیزل", "van", False, ["Maxus V80"], "diesel_truck"),
        ],
        "سوزوکی": [
            ("ویتارا", "2.4L", "suv", True, ["Vitara", "گرند ویتارا"], "import"),
            ("جیمنی", "1.5L", "suv", False, ["Jimny"], "import"),
            ("سوئیفت", "1.4L", "hatchback", False, ["Swift"], "import"),
            ("کیزاشی", "2.4L", "sedan", False, ["Kizashi"], "import"),
        ],
        "سانگ یانگ": [
            ("کوراندو", "2.0L", "suv", False, ["Korando"], "import"),
            ("اکتیون", "2.0L", "suv", False, ["Actyon"], "import"),
            ("رکستون", "2.7L دیزل", "suv", False, ["Rexton"], "import"),
            ("تیوولی", "1.6L", "suv", False, ["Tivoli"], "import"),
            ("کایرون", "2.0L", "suv", False, ["Kyron"], "import"),
        ],
        "جی ای سی": [
            ("GS3", "1.5T", "suv", False, [], "suv_cn"),
            ("GS4", "1.5T", "suv", False, [], "suv_cn"),
            ("GS8", "2.0T", "suv", False, [], "suv_cn"),
            ("امپو", "1.5T", "sedan", False, ["Empow"], "suv_cn"),
        ],
        "چانگان": [
            ("CS35 پلاس", "1.4T", "suv", False, [], "suv_cn"),
            ("یونی-تی", "1.5T", "suv", False, ["UNI-T"], "suv_cn"),
            ("یونی-کی", "2.0T", "suv", False, ["UNI-K"], "suv_cn"),
            ("آلسوین", "1.5L", "sedan", False, ["Alsvin"], "suv_cn"),
        ],
        "جتور": [
            ("X70", "1.5T", "suv", False, [], "suv_cn"),
            ("داشینگ", "1.6T", "suv", False, ["Dashing"], "suv_cn"),
            ("T1", "2.0T", "suv", False, ["Jetour T1"], "suv_cn"),
            ("T2", "2.0T", "suv", False, ["Jetour T2"], "suv_cn"),
        ],
        "ام جی": [
            ("5", "1.5L", "sedan", False, ["MG 5"], "suv_cn"),
            ("6", "1.5T", "sedan", False, ["MG 6"], "suv_cn"),
            ("RX5", "1.5T", "suv", False, [], "suv_cn"),
            ("ZS", "1.5L", "suv", False, [], "suv_cn"),
        ],
        "بی وای دی": [
            ("F3", "1.5L", "sedan", False, ["BYD F3"], "iran_econ"),
            ("S6", "2.0L", "suv", False, ["BYD S6"], "suv_cn"),
            ("اتو 3", "EV", "suv", False, ["Atto 3"], "import"),
            ("سیل", "EV", "sedan", False, ["Seal"], "import"),
            ("کین پلاس", "1.5 DM-i", "sedan", False, ["Qin"], "import"),
        ],
        "هونگچی": [
            ("H5", "1.5T", "sedan", False, ["Hongqi H5"], "suv_cn"),
            ("HS5", "2.0T", "suv", False, ["Hongqi HS5"], "suv_cn"),
        ],
        "سویفت موتور": [
            ("SWM G01", "1.5T", "suv", False, ["SWM"], "suv_cn"),
            ("SWM G05", "2.0T", "suv", False, [], "suv_cn"),
        ],
    }.items():
        for rec in items:
            m, e, cat, pop, als, iss = rec
            fuel = "electric" if e == "EV" else ("hybrid" if "HEV" in e or "DM" in e else ("diesel" if "دیزل" in e else "gasoline"))
            add(brand, m, e, cat, popular=pop, aliases=als, issues=iss, fuel=fuel,
                trans="automatic" if cat in ("suv",) and "دنده‌ای" not in m else "manual",
                electric=(fuel == "electric"))

    # ── وارداتی پرطرفدار در ایران ─────────────────────────────────────────
    imports = {
        "تویوتا": ("ژاپن", [
            ("کرولا 2008", "1.8L", "sedan", True, ["Corolla"]),
            ("کرولا 2014", "1.8L", "sedan", True, []),
            ("کمری GLX", "2.4L", "sedan", True, ["Camry"]),
            ("کمری هیبرید", "2.5 HEV", "sedan", False, []),
            ("یاریس هاچ‌بک", "1.5L", "hatchback", False, ["Yaris"]),
            ("راو 4", "2.5L", "suv", True, ["RAV4"]),
            ("فورچونر", "2.7L / 4.0L", "suv", True, ["Fortuner"]),
            ("هایلوکس", "2.7L / 2.8 دیزل", "pickup", True, ["Hilux", "هایلوکس"]),
            ("پرادو 4 سیلندر", "2.7L", "suv", True, ["Prado"]),
            ("پرادو 6 سیلندر", "4.0L", "suv", True, []),
            ("لندکروزر GXR", "4.6L V8", "suv", True, ["Land Cruiser", "جی‌ایکس‌آر"]),
            ("لندکروزر 100", "4.7L", "suv", False, ["LC100"]),
            ("پریوس", "1.8 HEV", "hatchback", False, ["Prius"]),
            ("C-HR", "1.2T / HEV", "suv", False, ["CHR"]),
            ("آوالون", "3.5L", "sedan", False, ["Avalon"]),
            ("سکويا", "5.7L", "suv", False, ["Sequoia"]),
            ("تاکوما", "3.5L", "pickup", False, ["Tacoma"]),
            ("هایس دیزل", "3.0L دیزل", "van", True, ["Hiace"]),
        ]),
        "هیوندای": ("کره جنوبی", [
            ("اکسنت", "1.6L", "sedan", True, ["Accent"]),
            ("آوانته MD", "1.6L / 2.0L", "sedan", True, ["Avante", "Elantra MD"]),
            ("آوانته AD", "1.6L", "sedan", False, ["Elantra AD"]),
            ("سوناتا YF", "2.0L / 2.4L", "sedan", True, ["Sonata YF"]),
            ("سوناتا LF", "2.0L / 2.4 GDI", "sedan", True, ["Sonata LF"]),
            ("جنسیس", "3.8L V6", "sedan", False, ["Genesis"]),
            ("توسان jm", "2.0L", "suv", False, ["Tucson JM"]),
            ("توسان ix35", "2.0L / 2.4L", "suv", True, ["ix35"]),
            ("سانتافه CM", "2.4L / 2.7L", "suv", False, []),
            ("سانتافه DM", "2.4 GDI", "suv", True, ["Santa Fe DM"]),
            ("وراکروز", "3.8L", "suv", False, ["Veracruz"]),
            ("پالیسید", "3.8L", "suv", False, ["Palisade"]),
            ("کرتا", "1.5L", "suv", False, ["Creta"]),
            ("ولستر", "1.6T", "hatchback", False, ["Veloster"]),
            ("i40", "2.0L", "wagon", False, []),
            ("استارکس", "2.4L", "van", True, ["Starex", "H1"]),
        ]),
        "کیا": ("کره جنوبی", [
            ("سراتو TD", "1.6L / 2.0L", "sedan", True, ["Cerato"]),
            ("اپتیما TF", "2.0L / 2.4L", "sedan", True, ["Optima"]),
            ("کادنزا", "3.5L", "sedan", False, ["Cadenza"]),
            ("سورنتو XM", "2.4L / 3.5L", "suv", True, ["Sorento"]),
            ("سورنتو UM", "2.4L", "suv", False, []),
            ("اسپورتیج SL", "2.0L / 2.4L", "suv", True, ["Sportage"]),
            ("نیرو", "1.6 HEV", "suv", False, ["Niro"]),
            ("سلتوس", "1.6L", "suv", False, ["Seltos"]),
            ("کارنیوال", "3.3L", "van", False, ["Carnival"]),
            ("ریو هاچ‌بک", "1.4L", "hatchback", False, ["Rio"]),
            ("سول", "1.6L", "hatchback", False, ["Soul"]),
        ]),
        "نیسان": ("ژاپن", [
            ("تیانا", "2.5L / 3.5L", "sedan", False, ["Teana"]),
            ("آلتیما", "2.5L", "sedan", False, ["Altima"]),
            ("جوک", "1.6T", "suv", False, ["Juke"]),
            ("ایکس‌تریل", "2.5L", "suv", False, ["X-Trail"]),
            ("مورانو", "3.5L", "suv", False, ["Murano"]),
            ("ناوارا", "2.5L دیزل", "pickup", True, ["Navara"]),
            ("پاترول 4 در", "4.8L", "suv", True, ["Patrol"]),
            ("سافاری", "4.8L", "suv", False, ["Safari"]),
            ("آرمادا", "5.6L", "suv", False, ["Armada"]),
        ]),
        "مزدا": ("ژاپن", [
            ("مزدا 2", "1.5L", "hatchback", False, []),
            ("مزدا 3 نیو هاچ‌بک", "2.0L", "hatchback", False, []),
            ("مزدا CX-30", "2.0L", "suv", False, ["CX30"]),
            ("مزدا CX-7", "2.3T", "suv", False, []),
            ("مزدا BT-50", "3.2L دیزل", "pickup", False, ["BT50"]),
        ]),
        "هوندا": ("ژاپن", [
            ("سیتی", "1.5L", "sedan", False, ["City"]),
            ("جاز", "1.5L", "hatchback", False, ["Jazz", "Fit"]),
            ("پایلوت", "3.5L", "suv", False, ["Pilot"]),
        ]),
        "میتسوبیشی": ("ژاپن", [
            ("لنسر تک", "1.6L", "sedan", False, ["Lancer"]),
            ("اوتلندر PHEV", "2.4 PHEV", "suv", False, []),
            ("ASX", "2.0L", "suv", False, ["ASX", "RVR"]),
            ("L200", "2.5L دیزل", "pickup", True, ["L200", "ترایتون"]),
            ("پاجرو 2 در", "3.0L", "suv", False, ["Pajero"]),
            ("پاجرو 4 در", "3.8L", "suv", True, []),
            ("پاجرو اسپرت", "2.5L دیزل", "suv", True, ["Pajero Sport"]),
        ]),
        "لکسوس": ("ژاپن", [
            ("IS 250", "2.5L", "sedan", False, ["IS250"]),
            ("IS 300", "3.0L", "sedan", False, []),
            ("NX 200t", "2.0T", "suv", False, ["NX"]),
            ("GX 460", "4.6L", "suv", False, ["GX"]),
            ("LX 570", "5.7L", "suv", True, ["LX570"]),
        ]),
        "سوبارو": ("ژاپن", [
            ("فارستر", "2.0L / 2.5L", "suv", False, ["Forester"]),
            ("ایمبرزا", "2.0L", "sedan", False, ["Impreza"]),
            ("اوت‌بک", "2.5L", "wagon", False, ["Outback"]),
            ("XV", "2.0L", "suv", False, ["Crosstrek"]),
            ("لگاسی", "2.5L", "sedan", False, ["Legacy"]),
        ]),
        "مرسدس بنز": ("آلمان", [
            ("C200 W204", "1.8 کمپرسور", "sedan", True, ["C200"]),
            ("C250 W205", "2.0T", "sedan", False, []),
            ("E200 W212", "2.0T", "sedan", True, ["E200"]),
            ("E250 W213", "2.0T", "sedan", False, []),
            ("S500 W221", "5.5L V8", "sedan", False, ["S کلاس"]),
            ("CLA 200", "1.6T", "sedan", False, ["CLA"]),
            ("A150", "1.5L", "hatchback", False, ["A کلاس"]),
            ("GLK 280", "3.0L", "suv", False, ["GLK"]),
            ("ML 350", "3.5L", "suv", False, ["ML", "GLE قدیمی"]),
            ("G کلاس 350", "3.0 دیزل", "suv", False, ["G-Class", "گه‌واگن"]),
            ("CLS 350", "3.5L", "coupe", False, ["CLS"]),
            ("CLK 200", "1.8 کمپرسور", "coupe", False, ["CLK"]),
        ]),
        "بی‌ام‌و": ("آلمان", [
            ("318i E90", "2.0L", "sedan", False, ["سری 3"]),
            ("320i F30", "2.0T", "sedan", True, []),
            ("328i", "2.0T", "sedan", False, []),
            ("520i F10", "2.0T", "sedan", True, ["سری 5"]),
            ("528i", "2.0T", "sedan", False, []),
            ("730Li", "3.0L", "sedan", False, ["سری 7"]),
            ("X4", "2.0T", "suv", False, []),
            ("X6", "3.0L / 4.4L", "suv", False, []),
            ("Z4", "2.0T / 3.0L", "convertible", False, []),
            ("125i", "2.0T", "hatchback", False, ["سری 1"]),
        ]),
        "آئودی": ("آلمان", [
            ("A5", "2.0T", "coupe", False, []),
            ("A8", "3.0T / 4.2L", "sedan", False, []),
            ("Q2", "1.4T", "suv", False, []),
            ("Q8", "3.0T", "suv", False, []),
            ("TT", "2.0T", "coupe", False, []),
        ]),
        "فولکس واگن": ("آلمان", [
            ("پولو", "1.4L / 1.6L", "hatchback", False, ["Polo"]),
            ("جتا", "1.4T", "sedan", False, ["Jetta"]),
            ("بیتل", "1.4T", "hatchback", False, ["Beetle"]),
            ("توآرگ", "3.6L / 4.2L", "suv", False, ["Touareg"]),
            ("کدی", "1.4T", "van", False, ["Caddy"]),
            ("مولتی‌ون", "2.0T", "van", False, ["Multivan", "T5"]),
        ]),
        "پورشه": ("آلمان", [
            ("کاین", "3.0T / 3.6L", "suv", False, ["Cayenne"]),
            ("ماکان", "2.0T", "suv", False, ["Macan"]),
            ("پانامرا", "3.0T", "sedan", False, ["Panamera"]),
            ("911 کررا", "3.0T", "coupe", False, ["911"]),
            ("باکستر", "2.0T", "convertible", False, ["Boxster"]),
        ]),
        "لندروور": ("بریتانیا", [
            ("رنجروور اسپرت", "3.0L / 5.0L", "suv", False, ["Range Rover Sport"]),
            ("رنجروور اِووک", "2.0T", "suv", False, ["Evoque"]),
            ("دیسکاوری 4", "3.0L", "suv", False, ["Discovery"]),
            ("دیفندر", "3.0L", "suv", False, ["Defender"]),
            ("فری‌لندر 2", "2.2 دیزل", "suv", False, ["Freelander"]),
        ]),
        "جیپ": ("آمریکا", [
            ("رانگلر", "3.6L / 3.8L", "suv", False, ["Wrangler"]),
            ("چروکی", "2.4L / 3.2L", "suv", False, ["Cherokee"]),
            ("گرند چروکی", "3.6L / 5.7L", "suv", False, ["Grand Cherokee"]),
            ("کامپس", "2.4L", "suv", False, ["Compass"]),
        ]),
        "فورد": ("آمریکا", [
            ("فوکوس", "1.6L / 2.0L", "hatchback", False, ["Focus"]),
            ("فیوژن", "2.5L", "sedan", False, ["Fusion"]),
            ("اکسپلورر", "3.5L", "suv", False, ["Explorer"]),
            ("اج", "3.5L", "suv", False, ["Edge"]),
            ("موستانگ", "5.0L", "coupe", False, ["Mustang"]),
            ("رنجر", "2.2 / 3.2 دیزل", "pickup", False, ["Ranger"]),
            ("F-150", "5.0L", "pickup", False, ["F150"]),
        ]),
        "شورولت": ("آمریکا", [
            ("کروز", "1.6L / 1.8L", "sedan", False, ["Cruze"]),
            ("مالیبو", "2.4L", "sedan", False, ["Malibu"]),
            ("کاپتیوا", "2.4L", "suv", True, ["Captiva"]),
            ("کامارو", "3.6L / 6.2L", "coupe", False, ["Camaro"]),
            ("سیلورآدو", "5.3L", "pickup", False, ["Silverado"]),
            ("اورلاندو", "2.0L", "van", False, ["Orlando"]),
        ]),
        "ولوو": ("سوئد", [
            ("XC40", "2.0T", "suv", False, []),
            ("V40", "2.0T", "hatchback", False, []),
            ("S80", "2.5T / 3.2L", "sedan", False, []),
            ("XC70", "2.5T", "wagon", False, []),
        ]),
        "رنو": ("فرانسه", [
            ("مگان هاچ‌بک", "1.6L", "hatchback", False, ["Megane"]),
            ("فلوئنس", "1.6L / 2.0L", "sedan", False, ["Fluence"]),
            ("داستر", "1.6L / 2.0L", "suv", False, ["Duster"]),
            ("کپچر", "1.2T", "suv", False, ["Captur"]),
            ("تالیسمان", "1.6T", "sedan", False, ["Talisman"]),
            ("لاتیتود", "2.0L", "sedan", False, ["Latitude"]),
            ("سیمبل", "1.6L", "sedan", False, ["Symbol", "تندر صندوق"]),
            ("اسکالا", "1.6L", "sedan", False, ["Scala"]),
            ("کولیوس نسل 2", "2.5L", "suv", False, ["Koleos"]),
        ]),
        "پژو": ("فرانسه", [
            ("206 RC", "2.0L", "hatchback", False, []),
            ("407 SW", "2.0L", "wagon", False, []),
            ("2008 وارداتی", "1.2T", "suv", False, []),
            ("پارتنر", "1.6L", "van", False, ["Partner"]),
            ("اکسپرت", "2.0 دیزل", "van", False, ["Expert"]),
            ("باکسر", "2.2 دیزل", "van", False, ["Boxer"]),
        ]),
        "سیتروئن": ("فرانسه", [
            ("زانتیا", "2.0L", "sedan", False, ["Xantia"]),
            ("زارا پیکاسو", "1.6L / 2.0L", "van", False, ["Picasso"]),
            ("برلینگو", "1.6L", "van", False, ["Berlingo"]),
            ("C5 ایرکراس", "1.6T", "suv", False, ["C5 Aircross"]),
        ]),
        "اوپل": ("آلمان", [
            ("آسترا", "1.6L", "hatchback", False, ["Astra"]),
            ("کورسا", "1.4L", "hatchback", False, ["Corsa"]),
            ("اینسیگنیا", "1.6T / 2.0T", "sedan", False, ["Insignia"]),
            ("موکا", "1.4T", "suv", False, ["Mokka"]),
        ]),
        "اشکودا": ("جمهوری چک", [
            ("اکتاویا", "1.4T / 1.8T", "sedan", False, ["Octavia"]),
            ("سوپرب", "2.0T", "sedan", False, ["Superb"]),
            ("کودیاک", "2.0T", "suv", False, ["Kodiaq"]),
        ]),
        "فیات": ("ایتالیا", [
            ("500", "1.4L", "hatchback", False, ["Fiat 500"]),
            ("تیپو", "1.6L", "sedan", False, ["Tipo"]),
        ]),
        "مینی": ("بریتانیا", [
            ("کوپر", "1.6L / 1.5T", "hatchback", False, ["Mini Cooper"]),
            ("کانتریمن", "1.6T", "suv", False, ["Countryman"]),
        ]),
        "اینفینیتی": ("ژاپن", [
            ("Q50", "2.0T / 3.0T", "sedan", False, []),
            ("QX70", "3.7L", "suv", False, ["FX37"]),
            ("QX80", "5.6L", "suv", False, []),
        ]),
        "دوج": ("آمریکا", [
            ("چارجر", "3.6L / 5.7L", "sedan", False, ["Charger"]),
            ("چلنجر", "3.6L / 5.7L", "coupe", False, ["Challenger"]),
            ("دورانگو", "3.6L", "suv", False, ["Durango"]),
        ]),
        "کرایسلر": ("آمریکا", [
            ("300C", "5.7L", "sedan", False, ["300C"]),
            ("پاسیفیکا", "3.6L", "van", False, ["Pacifica"]),
        ]),
        "کادیلاک": ("آمریکا", [
            ("CTS", "3.6L", "sedan", False, []),
            ("اسکالید", "6.2L", "suv", False, ["Escalade"]),
        ]),
        "لینکلن": ("آمریکا", [
            ("MKX", "3.7L", "suv", False, []),
            ("ناویگیتور", "3.5T", "suv", False, ["Navigator"]),
        ]),
        "تسلا": ("آمریکا", [
            ("Model 3", "EV Dual Motor", "sedan", False, ["مدل ۳"]),
            ("Model Y", "EV", "suv", False, ["مدل Y"]),
        ]),
        "دوو": ("کره جنوبی", [
            ("سیلو", "1.5L", "sedan", False, ["Cielo", "سیلو"]),
            ("ماتیز", "0.8L", "hatchback", False, ["Matiz"]),
            ("اسپرو", "2.0L", "sedan", False, ["Espero"]),
            ("پرنس", "2.0L", "sedan", False, ["Prince"]),
        ]),
    }
    for brand, (country, items) in imports.items():
        for m, e, cat, pop, als in items:
            fuel = "electric" if "EV" in e else ("hybrid" if "HEV" in e or "PHEV" in e else ("diesel" if "دیزل" in e else "gasoline"))
            add(brand, m, e, cat, popular=pop, aliases=als, issues="import",
                fuel=fuel, trans="automatic", country=country, region="وارداتی",
                electric=(fuel == "electric"))

    # ── موتورسیکلت و اسکوتر ───────────────────────────────────────────────
    moto_issues = "moto"
    scoot_issues = "scooter"

    iran_moto = {
        "کویر موتور": [
            ("KD 125", "125cc", "motorcycle", True, ["کاویر 125", "کویر ۱۲۵"]),
            ("KD 150", "150cc", "motorcycle", False, []),
            ("KD 200", "200cc", "motorcycle", True, ["کویر ۲۰۰"]),
            ("KD 250", "250cc", "motorcycle", False, ["کویر ۲۵۰"]),
            ("C2 150", "150cc", "motorcycle", False, []),
            ("S2 250", "250cc", "motorcycle", False, []),
            ("آفرود 250", "250cc", "motorcycle", False, ["کویر آفرود"]),
            ("اسکوتر 125", "125cc", "scooter", False, []),
        ],
        "نامی": [
            ("125 CDI", "125cc", "motorcycle", True, ["نامی ۱۲۵"]),
            ("150", "150cc", "motorcycle", False, []),
            ("200", "200cc", "motorcycle", True, ["نامی ۲۰۰"]),
            ("اسکوتر 150", "150cc", "scooter", False, []),
        ],
        "جهانرو": [
            ("CG 125", "125cc", "motorcycle", True, ["جهانرو ۱۲۵"]),
            ("200", "200cc", "motorcycle", False, []),
            ("اسکوتر 125", "125cc", "scooter", False, []),
        ],
        "ایران دوچرخ": [
            ("هوندا CDI 125", "125cc", "motorcycle", True, ["ایران دوچرخ ۱۲۵"]),
            ("CG 125", "125cc", "motorcycle", True, ["CG125 ایرانی"]),
            ("200", "200cc", "motorcycle", False, []),
        ],
        "نیرو موتور": [
            ("125", "125cc", "motorcycle", False, []),
            ("150", "150cc", "motorcycle", False, []),
            ("200", "200cc", "motorcycle", False, []),
        ],
        "پیشرو": [
            ("125", "125cc", "motorcycle", False, ["پیشرو ۱۲۵"]),
            ("150", "150cc", "motorcycle", False, []),
            ("بریج 150", "150cc", "scooter", False, []),
        ],
        "تلاش": [
            ("125", "125cc", "motorcycle", False, []),
            ("200", "200cc", "motorcycle", False, []),
        ],
        "انرژی": [
            ("125", "125cc", "motorcycle", False, []),
            ("اسکوتر برقی", "EV", "scooter", False, ["انرژی برقی"]),
        ],
        "دینو": [
            ("125", "125cc", "motorcycle", False, []),
            ("150", "150cc", "motorcycle", False, []),
        ],
        "رهرو": [
            ("125", "125cc", "motorcycle", False, []),
            ("باری 200", "200cc", "motorcycle", False, ["موتور باری"]),
        ],
        "احسان": [
            ("125", "125cc", "motorcycle", False, []),
            ("200", "200cc", "motorcycle", False, []),
        ],
        "پرواز": [
            ("125", "125cc", "motorcycle", False, []),
        ],
        "ستاره": [
            ("125", "125cc", "motorcycle", False, []),
        ],
    }
    for brand, items in iran_moto.items():
        for m, e, cat, pop, als in items:
            add(brand, m, e, cat, popular=pop, aliases=als,
                issues=scoot_issues if cat == "scooter" else moto_issues,
                fuel="electric" if e == "EV" else "gasoline", trans=None,
                electric=(e == "EV"))

    def add_moto_line(brand, country, models, cat="motorcycle", region="وارداتی"):
        for rec in models:
            if len(rec) == 5:
                m, e, pop, als, c = rec
            else:
                m, e, pop, als = rec
                c = cat
            add(brand, m, e, c, popular=pop, aliases=als, issues=scoot_issues if c == "scooter" else moto_issues,
                fuel="electric" if "EV" in e else "gasoline", trans=None,
                country=country, region=region, electric=("EV" in e))

    add_moto_line("هوندا موتور", "ژاپن", [
        ("CG 125", "125cc", True, ["هوندا ۱۲۵", "سی‌جی ۱۲۵", "CG125"]),
        ("CDI 125", "125cc", True, ["سی‌دی‌آی", "هوندا CDI"]),
        ("Unicorn 150", "150cc", False, []),
        ("Shine 125", "125cc", False, []),
        ("CBR 150R", "150cc", False, ["CBR150"]),
        ("CBR 250R", "250cc", False, ["CBR250"]),
        ("CBR 500R", "500cc", False, []),
        ("CBR 600RR", "600cc", False, []),
        ("CBR 1000RR", "1000cc", False, []),
        ("CB 500X", "500cc", False, []),
        ("CB 650R", "650cc", False, []),
        ("Africa Twin", "1084cc", False, ["CRF1100"]),
        ("CRF 250L", "250cc", False, ["CRF250"]),
        ("CRF 450R", "450cc", False, []),
        ("PCX 125", "125cc", True, ["PCX"], "scooter"),
        ("PCX 160", "160cc", False, [], "scooter"),
        ("SH 150", "150cc", False, [], "scooter"),
        ("Forza 350", "350cc", False, [], "scooter"),
        ("Click 125", "125cc", False, [" کلیک"], "scooter"),
        ("ADV 150", "150cc", False, [], "scooter"),
        ("Wave 110", "110cc", False, []),
        ("Rebel 500", "500cc", False, []),
        ("Gold Wing", "1833cc", False, ["گلدوینگ"]),
        ("NC 750X", "750cc", False, []),
    ])
    add_moto_line("یاماها", "ژاپن", [
        ("YBR 125", "125cc", True, ["YBR", "یاماها ۱۲۵"]),
        ("Crypton", "115cc", False, []),
        ("FZ 150", "150cc", False, []),
        ("FZ 25", "250cc", False, []),
        ("MT-15", "155cc", True, ["MT15"]),
        ("MT-03", "321cc", False, []),
        ("MT-07", "689cc", False, []),
        ("MT-09", "890cc", False, []),
        ("R15", "155cc", True, ["YZF-R15"]),
        ("R3", "321cc", False, ["YZF-R3"]),
        ("R6", "600cc", False, []),
        ("R1", "998cc", False, ["YZF-R1"]),
        ("NMAX 155", "155cc", True, ["NMAX"], "scooter"),
        ("Aerox 155", "155cc", False, [], "scooter"),
        ("XMAX 300", "300cc", False, [], "scooter"),
        ("TMAX 560", "560cc", False, [], "scooter"),
        ("Tenere 700", "689cc", False, ["Ténéré"]),
        ("WR 250", "250cc", False, []),
        ("YZ 250", "250cc", False, []),
        ("Tracer 9", "890cc", False, []),
    ])
    add_moto_line("سوزوکی موتور", "ژاپن", [
        ("GSX-R 150", "150cc", False, ["GSXR150"]),
        ("GSX-R 600", "600cc", False, []),
        ("GSX-R 750", "750cc", False, []),
        ("GSX-S 750", "750cc", False, []),
        ("Hayabusa", "1340cc", False, ["هایابوسا"]),
        ("V-Strom 650", "650cc", False, ["VStrom"]),
        ("DR-Z 400", "400cc", False, []),
        ("Address 110", "110cc", False, [], "scooter"),
        ("Burgman 400", "400cc", False, [], "scooter"),
        ("Intruder 150", "150cc", False, []),
    ])
    add_moto_line("کاواساکی", "ژاپن", [
        ("Ninja 250", "249cc", True, ["نینجا ۲۵۰"]),
        ("Ninja 300", "296cc", False, []),
        ("Ninja 400", "399cc", True, ["نینجا ۴۰۰"]),
        ("Ninja 650", "649cc", False, []),
        ("ZX-6R", "636cc", False, []),
        ("ZX-10R", "998cc", False, []),
        ("Z400", "399cc", False, []),
        ("Z650", "649cc", False, []),
        ("Z900", "948cc", False, []),
        ("Versys 650", "649cc", False, []),
        ("KLX 150", "150cc", False, []),
        ("KLX 250", "250cc", False, []),
        ("KX 250", "250cc", False, []),
        ("Vulcan S", "649cc", False, []),
    ])
    add_moto_line("کی‌تی‌ام", "اتریش", [
        ("Duke 200", "200cc", True, ["دوک ۲۰۰"]),
        ("Duke 250", "250cc", True, ["دوک ۲۵۰"]),
        ("Duke 390", "373cc", True, ["دوک ۳۹۰"]),
        ("Duke 790", "799cc", False, []),
        ("Duke 890", "889cc", False, []),
        ("RC 200", "200cc", False, []),
        ("RC 390", "373cc", False, []),
        ("Adventure 390", "373cc", False, ["390 Adv"]),
        ("Adventure 790", "799cc", False, []),
        ("EXC 250", "250cc", False, []),
        ("SX 250", "250cc", False, []),
    ])
    add_moto_line("باجاج", "هند", [
        ("Boxer 100", "100cc", False, ["باکسر"]),
        ("Boxer 150", "150cc", True, []),
        ("Platina 100", "100cc", False, []),
        ("Discover 125", "125cc", False, []),
        ("Pulsar 135", "135cc", False, ["پالسار"]),
        ("Pulsar 150", "150cc", True, []),
        ("Pulsar 180", "180cc", True, []),
        ("Pulsar 200NS", "200cc", True, ["NS200", "پالسار ۲۰۰"]),
        ("Pulsar 220F", "220cc", False, []),
        ("Pulsar NS160", "160cc", False, []),
        ("Pulsar RS200", "200cc", False, []),
        ("Dominar 250", "248cc", False, []),
        ("Dominar 400", "373cc", False, []),
        ("Avenger 220", "220cc", False, []),
        ("CT 100", "100cc", False, []),
        ("RE سه چرخ", "200cc", False, ["آژاکس", "رکشا"], "motorcycle"),
    ])
    add_moto_line("هیرو", "هند", [
        ("Splendor Plus", "97cc", True, ["اسپلندور"]),
        ("HF Deluxe", "97cc", False, []),
        ("Passion Pro", "110cc", False, []),
        ("Glamour", "125cc", False, []),
        ("Xtreme 160R", "163cc", False, []),
        ("Xpulse 200", "200cc", False, []),
        ("Karizma XMR", "210cc", False, []),
        ("Destini 125", "125cc", False, [], "scooter"),
        ("Pleasure Plus", "110cc", False, [], "scooter"),
    ])
    add_moto_line("تی‌وی‌اس", "هند", [
        ("Apache RTR 160", "160cc", True, ["آپاچی ۱۶۰"]),
        ("Apache RTR 180", "180cc", False, []),
        ("Apache RTR 200 4V", "197cc", True, ["آپاچی ۲۰۰"]),
        ("Raider 125", "125cc", False, []),
        ("Ronin", "225cc", False, []),
        ("Ntorq 125", "125cc", False, [], "scooter"),
        ("Jupiter", "110cc", False, [], "scooter"),
        ("XL 100", "100cc", False, ["موپد"]),
        ("King سه چرخ", "200cc", False, ["تی‌وی‌اس کینگ"]),
    ])
    add_moto_line("رویال انفیلد", "هند", [
        ("Classic 350", "349cc", True, ["کلاسیک ۳۵۰"]),
        ("Bullet 350", "349cc", True, ["بولت"]),
        ("Hunter 350", "349cc", False, []),
        ("Meteor 350", "349cc", False, []),
        ("Himalayan 450", "452cc", False, ["هیمالایان"]),
        ("Interceptor 650", "648cc", False, []),
        ("Continental GT 650", "648cc", False, []),
        ("Super Meteor 650", "648cc", False, []),
    ])
    add_moto_line("وسپا", "ایتالیا", [
        ("Primavera 125", "125cc", False, ["Vespa"], "scooter"),
        ("Sprint 150", "150cc", False, [], "scooter"),
        ("GTS 150", "150cc", True, ["GTS"], "scooter"),
        ("GTS 300", "300cc", False, [], "scooter"),
        ("PX 150", "150cc", False, [], "scooter"),
    ])
    add_moto_line("پیاژیو", "ایتالیا", [
        ("Liberty 150", "150cc", False, [], "scooter"),
        ("Medley 150", "150cc", False, [], "scooter"),
        ("Beverly 300", "300cc", False, [], "scooter"),
        ("MP3 300", "300cc", False, ["سه چرخ"], "scooter"),
        ("Ape", "200cc", False, ["آپه باری"]),
    ])
    add_moto_line("اس‌وای‌ام", "تایوان", [
        ("VF 185", "185cc", True, ["SYM VF185"]),
        ("Jet 14", "125cc", False, [], "scooter"),
        ("Fiddle 125", "125cc", False, [], "scooter"),
        ("Cruisym 300", "300cc", False, [], "scooter"),
        ("Maxsym 400", "400cc", False, [], "scooter"),
        ("NH T 200", "200cc", False, []),
    ])
    add_moto_line("کایمکو", "تایوان", [
        ("Agility 125", "125cc", False, [], "scooter"),
        ("Like 150", "150cc", False, [], "scooter"),
        ("Downtown 350", "350cc", False, [], "scooter"),
        ("AK 550", "550cc", False, [], "scooter"),
        ("Xciting 400", "400cc", False, [], "scooter"),
    ])
    add_moto_line("سی‌اف‌موتو", "چین", [
        ("150NK", "150cc", False, ["CFMoto"]),
        ("250NK", "249cc", True, []),
        ("300NK", "292cc", False, []),
        ("400NK", "400cc", False, []),
        ("650NK", "649cc", False, []),
        ("250SR", "249cc", True, []),
        ("450SR", "449cc", False, []),
        ("650MT", "649cc", False, []),
        ("800MT", "799cc", False, []),
        ("Papio 125", "125cc", False, []),
        ("250CL-X", "249cc", False, []),
        ("CForce 450", "400cc", False, ["ATV"], "atv"),
        ("CForce 800", "800cc", False, [], "atv"),
    ])
    add_moto_line("بنلی", "ایتالیا", [
        ("TNT 15", "150cc", False, ["TNT150"]),
        ("TNT 25", "249cc", False, []),
        ("TNT 249S", "249cc", False, []),
        ("302S", "300cc", False, []),
        ("600i", "600cc", False, []),
        ("TRK 251", "249cc", False, []),
        ("TRK 502", "500cc", True, ["TRK502"]),
        ("Leoncino 250", "249cc", False, []),
        ("Leoncino 500", "500cc", False, []),
        ("Imperiale 400", "374cc", False, []),
    ])
    add_moto_line("زونتس", "چین", [
        ("ZT 125", "125cc", False, ["Zontes"]),
        ("U 155", "155cc", False, []),
        ("V 350", "349cc", False, []),
        ("X 310", "310cc", False, []),
        ("GK 350", "349cc", False, []),
    ])
    add_moto_line("کی‌وی", "چین", [
        ("RKF 125", "125cc", False, ["Keeway"]),
        ("Superlight 150", "150cc", False, []),
        ("Superlight 200", "200cc", False, []),
        ("Vieste 300", "300cc", False, [], "scooter"),
        ("RK 150", "150cc", False, []),
        ("Patagonian Eagle 250", "250cc", False, []),
    ])
    add_moto_line("لیفان موتور", "چین", [
        ("KP 150", "150cc", False, ["Lifan"]),
        ("KPR 200", "200cc", False, []),
        ("LF 250", "250cc", False, []),
        ("سوپر کاب", "125cc", False, ["Cub"]),
    ])
    add_moto_line("هاوجو", "چین", [
        ("HJ 125", "125cc", False, ["Haojue", "سوزوکی کپی"]),
        ("DR 160", "160cc", False, []),
        ("USR 125", "125cc", False, []),
        ("Lucky 110", "110cc", False, []),
    ])
    add_moto_line("دایون", "چین", [
        ("DY 125", "125cc", False, ["Dayun"]),
        ("DY 150", "150cc", False, []),
        ("DY 200", "200cc", False, []),
        ("باری 200", "200cc", False, ["موتور سه چرخ باری"]),
    ])
    add_moto_line("کیو‌جی موتور", "چین", [
        ("SRK 250", "249cc", False, ["QJMotor"]),
        ("SRK 400", "400cc", False, []),
        ("SRT 550", "550cc", False, []),
        ("SRT 700", "700cc", False, []),
    ])
    add_moto_line("ووج", "چین", [
        ("300AC", "300cc", False, ["Voge"]),
        ("300R", "300cc", False, []),
        ("500DS", "500cc", False, []),
        ("500R", "500cc", False, []),
        ("900DS", "895cc", False, []),
    ])
    add_moto_line("آپریلیا", "ایتالیا", [
        ("RS 125", "125cc", False, ["Aprilia"]),
        ("RS 660", "659cc", False, []),
        ("Tuono 660", "659cc", False, []),
        ("SRV 850", "839cc", False, [], "scooter"),
    ])
    add_moto_line("دوکاتی", "ایتالیا", [
        ("Monster 821", "821cc", False, ["Ducati"]),
        ("Panigale V2", "955cc", False, []),
        ("Panigale V4", "1103cc", False, []),
        ("Multistrada V4", "1158cc", False, []),
        ("Scrambler 800", "803cc", False, []),
        ("Diavel", "1262cc", False, []),
        ("Hypermotard", "937cc", False, []),
    ])
    add_moto_line("بی‌ام‌و موتورراد", "آلمان", [
        ("G 310 R", "313cc", False, ["G310R"]),
        ("G 310 GS", "313cc", False, []),
        ("F 750 GS", "853cc", False, []),
        ("F 850 GS", "853cc", True, ["F850GS"]),
        ("R 1250 GS", "1254cc", True, ["GS Adventure"]),
        ("R 1300 GS", "1300cc", False, []),
        ("S 1000 RR", "999cc", False, ["S1000RR"]),
        ("R 18", "1802cc", False, []),
        ("C 400 X", "350cc", False, [], "scooter"),
    ])
    add_moto_line("هارلی دیویدسون", "آمریکا", [
        ("Iron 883", "883cc", False, ["Sportster"]),
        ("Forty-Eight", "1202cc", False, []),
        ("Street 750", "749cc", False, []),
        ("Softail Standard", "1745cc", False, []),
        ("Road King", "1745cc", False, []),
        ("Pan America 1250", "1252cc", False, []),
    ])
    add_moto_line("تریومف", "بریتانیا", [
        ("Street Triple 765", "765cc", False, ["Triumph"]),
        ("Speed Triple 1200", "1160cc", False, []),
        ("Bonneville T120", "1200cc", False, []),
        ("Tiger 900", "888cc", False, []),
        ("Trident 660", "660cc", False, []),
        ("Rocket 3", "2458cc", False, []),
    ])
    add_moto_line("هاسکوارنا", "اتریش", [
        ("Svartpilen 401", "373cc", False, ["Husqvarna"]),
        ("Vitpilen 401", "373cc", False, []),
        ("Norden 901", "889cc", False, []),
        ("TE 300", "300cc", False, []),
    ])
    add_moto_line("یادآ", "چین", [
        ("G5", "EV", False, ["Yadea"], "scooter"),
        ("C1S", "EV", False, [], "scooter"),
        ("T9", "EV", False, [], "scooter"),
    ])
    add_moto_line("نیو", "چین", [
        ("NQi", "EV", False, ["NIU"], "scooter"),
        ("MQi+", "EV", False, [], "scooter"),
    ])
    add_moto_line("سوپر سوکو", "چین", [
        ("TC Max", "EV", False, ["Super Soco"], "scooter"),
        ("CPX", "EV", False, [], "scooter"),
        ("CUx", "EV", False, [], "scooter"),
    ])
    add_moto_line("پولاریس", "آمریکا", [
        ("Sportsman 570", "567cc", False, ["Polaris"], "atv"),
        ("RZR 1000", "999cc", False, [], "atv"),
        ("Ranger 1000", "999cc", False, [], "atv"),
    ])
    add_moto_line("کن‌ام", "کانادا", [
        ("Outlander 650", "650cc", False, ["Can-Am"], "atv"),
        ("Maverick X3", "900cc", False, [], "atv"),
        ("Ryker 900", "900cc", False, []),
        ("Spyder F3", "1330cc", False, ["سه چرخ"]),
    ])
    add_moto_line("هوندا ATV", "ژاپن", [
        ("TRX 420", "420cc", False, ["Honda ATV"], "atv"),
        ("TRX 680", "680cc", False, [], "atv"),
    ])
    add_moto_line("یاماها ATV", "ژاپن", [
        ("Raptor 700", "686cc", False, [], "atv"),
        ("Grizzly 700", "686cc", False, [], "atv"),
    ])

    # ── کامیون، کشنده، خاور ───────────────────────────────────────────────
    def add_truck(brand, country, models, cat="truck"):
        for m, e, pop, als in models:
            fuel = "diesel" if "بنزین" not in e else "gasoline"
            add(brand, m, e, cat, popular=pop, aliases=als, issues="diesel_truck",
                fuel=fuel, trans="manual", country=country,
                region="ایران" if country == "ایران" else "وارداتی")

    add_truck("ایران خودرو دیزل", "ایران", [
        ("مکسول", "دیزل ۶ سیلندر", True, ["Maxon", "خاور ایران خودرو"]),
        ("آتکو", "دیزل", False, ["Ateco"]),
        ("۴۵۷", "OM457", True, ["بنز ۴۵۷ ایرانی"]),
        ("وایستل", "دیزل", False, ["Whistle"]),
        ("مینی‌بوس آرین", "دیزل ۴ سیلندر", False, ["آرین"]),
    ])
    add_truck("شهاب خودرو", "ایران", [
        ("اتوبوس شهری", "دیزل", False, ["Shahab"]),
        ("اتوبوس بین شهری", "دیزل", False, []),
        ("مینی‌بوس", "دیزل", False, []),
    ])
    add_truck("مرسدس بنز کامیون", "آلمان", [
        ("Actros 1845", "OM471", True, ["اکتروس", "کشنده بنز"]),
        ("Actros 2651", "OM471", False, []),
        ("Axor 1843", "OM457", True, ["آکسور"]),
        ("Atego 1224", "OM904", False, ["آتگو"]),
        ("1924", "OM366", True, ["بنز ۱۹۲۴", "خاور ۱۹۲۴"]),
        ("2624", "OM366", False, ["بنز ۲۶۲۴"]),
        ("911", "OM352", True, ["خاور ۹۱۱", "بنز ۹۱۱"]),
        ("809", "OM364", False, ["خاور ۸۰۹"]),
        ("808", "OM314", False, ["خاور ۸۰۸"]),
        ("Sprinter 516", "2.2 دیزل", True, ["اسپرینتر"]),
        ("Vario", "OM904", False, ["واریو"]),
        ("Unimog", "OM904", False, ["یونیماگ"]),
    ])
    add_truck("ولوو کامیون", "سوئد", [
        ("FH12", "D12", True, ["اف‌اچ ۱۲"]),
        ("FH16", "D16", True, ["اف‌اچ ۱۶"]),
        ("FH 460", "D13", True, ["FH460"]),
        ("FH 500", "D13", False, []),
        ("FM 440", "D13", False, ["FM"]),
        ("FL 240", "D7", False, []),
        ("NH12", "D12", False, ["NH"]),
    ])
    add_truck("اسکانیا", "سوئد", [
        ("R 420", "DC12", True, ["اسکانیا R"]),
        ("R 500", "DC13", False, []),
        ("G 410", "DC13", True, ["G410"]),
        ("P 360", "DC9", False, []),
        ("113", "DS11", False, ["اسکانیا ۱۱۳"]),
        ("143", "DS14", False, ["اسکانیا ۱۴۳"]),
        ("124", "DC12", False, []),
    ])
    add_truck("مان", "آلمان", [
        ("TGX 18.480", "D26", True, ["MAN TGX"]),
        ("TGS 41.400", "D26", False, ["کمپرسی مان"]),
        ("TGA 18.430", "D20", False, ["TGA"]),
        ("TGL 12.220", "D08", False, []),
        ("Lion's Coach", "D26", False, []),
    ])
    add_truck("ایوکو", "ایتالیا", [
        ("Stralis 440", "Cursor 13", False, ["استرالیس"]),
        ("Trakker 420", "Cursor 13", False, ["تراکر"]),
        ("Eurocargo 160E", "Tector", False, []),
        ("Daily 50C15", "3.0 دیزل", True, ["دیلی"]),
        ("Daily ون", "2.3 دیزل", False, []),
    ])
    add_truck("داف", "هلند", [
        ("XF 460", "MX-13", False, ["DAF XF"]),
        ("CF 400", "MX-11", False, []),
        ("LF 220", "PX-7", False, []),
    ])
    add_truck("رنو کامیون", "فرانسه", [
        ("Magnum 480", "DXi13", False, ["مگنوم"]),
            ("Premium 440", "DXi11", False, ["پرمیم"]),
        ("T 480", "DTI13", False, ["Renault T"]),
        ("Kerax 380", "DCi11", False, ["کراکس"]),
        ("Master", "2.3 دیزل", False, ["مستر"]),
    ])
    add_truck("ایسوزو", "ژاپن", [
        ("NPR 75", "4HK1", True, ["ایسوزو NPR", "خاور ایسوزو"]),
        ("NQR 90", "4HK1", False, []),
        ("FVR 34", "6HK1", False, []),
        ("ELF", "4JB1", True, ["الف"]),
        ("D-Max کامیونت", "4JJ1", False, []),
    ])
    add_truck("میتسوبیشی فوسو", "ژاپن", [
        ("Canter", "4P10", True, ["کانتر", "فوسو"]),
        ("Fighter", "6M60", False, []),
        ("Super Great", "6R10", False, []),
    ])
    add_truck("هینو", "ژاپن", [
        ("300 سری", "N04C", False, ["Hino 300"]),
        ("500 سری", "J08E", False, ["Hino 500"]),
        ("700 سری", "E13C", False, ["Hino 700"]),
    ])
    add_truck("هیوندای کامیون", "کره جنوبی", [
        ("Mighty", "D4CB", True, ["مایتی"]),
        ("HD65", "D4DD", False, []),
        ("HD78", "D4GA", False, []),
        ("HD120", "D6GA", False, []),
        ("Xcient", "D6CC", False, ["اکسینت"]),
        ("County", "D4BB", True, ["کانتی"]),
    ])
    add_truck("کیا کامیون", "کره جنوبی", [
        ("بونگو 3", "J2 / J3", True, ["Bongo", "کیا ۲۷۰۰"]),
        ("کیا 4200", "دیزل", False, ["۴۲۰۰"]),
        ("کیا 2700", "J2", True, ["۲۷۰۰"]),
    ])
    add_truck("هوو", "چین", [
        ("A7 375", "WD615", True, ["HOWO", "سینوتراک", "هوو ۳۷۵"]),
        ("A7 420", "WD615", False, []),
        ("T5G", "MC11", False, []),
        ("T7H 440", "MC13", False, []),
        ("کمپرسی 6x4", "WD615", True, ["هوو کمپرسی"]),
        ("تانکر سوخت", "WD615", False, []),
    ])
    add_truck("شاکمان", "چین", [
        ("F2000", "WP10", False, ["Shacman"]),
        ("F3000 375", "WP10", True, ["F3000", "شاکمان کمپرسی"]),
        ("F3000 420", "WP12", True, []),
        ("X3000", "WP13", False, []),
        ("H3000", "WP10", False, []),
    ])
    add_truck("کاماز", "روسیه", [
        ("4308", "Cummins", False, ["Kamaz"]),
        ("53212", "740", False, []),
        ("55111 کمپرسی", "740", True, ["کاماز کمپرسی"]),
        ("65115", "740", True, []),
        ("5490 نئو", "Mercedes", False, ["Kamaz 5490"]),
        ("6520", "740", False, []),
    ])
    add_truck("ماز", "بلاروس", [
        ("5440", "دیزل", False, ["MAZ"]),
        ("6312", "دیزل", False, []),
        ("کمپرسی 5516", "دیزل", False, []),
    ])
    add_truck("اورال", "روسیه", [
        ("4320", "دیزل", True, ["Ural", "اورال نظامی"]),
        ("5557", "دیزل", False, []),
    ])
    add_truck("گاز", "روسیه", [
        ("غزال", "2.9L بنزین / دیزل", True, ["Gazelle", "غزال روسی"]),
        ("Next", "2.8 دیزل", False, ["Gazelle Next"]),
        ("Valdai", "دیزل", False, []),
        ("3307", "بنزین", False, ["گاز آبی"]),
    ])
    add_truck("فاو کامیون", "چین", [
        ("J6 420", "CA6DM2", False, ["FAW J6"]),
        ("Tiger V", "دیزل", False, []),
        ("Auman", "دیزل", False, ["Foton Auman"]),
    ])
    add_truck("دانگ‌فنگ کامیون", "چین", [
        ("Kinland 420", "دیزل", False, ["Dongfeng"]),
        ("Captain", "دیزل", False, []),
        ("KR کمپرسی", "دیزل", False, []),
    ])
    add_truck("جک کامیون", "چین", [
        ("N56", "2.8 دیزل", False, ["JAC N56"]),
        ("N75", "دیزل", False, []),
        ("N120", "دیزل", False, []),
        ("Sunray", "2.8 دیزل", False, ["سان‌ری ون"]),
    ])
    add_truck("فوتون کامیون", "چین", [
        ("Auman GTL", "Cummins", False, []),
        ("Aumark", "دیزل", False, []),
        ("View C2", "2.8 دیزل", False, ["ون فوتون"]),
    ])
    add_truck("ماک", "آمریکا", [
        ("Anthem", "MP8", False, ["Mack"]),
        ("Granite", "MP7", False, []),
    ])
    add_truck("فریت‌لاینر", "آمریکا", [
        ("Cascadia", "DD15", False, ["Freightliner"]),
        ("M2 106", "Cummins", False, []),
    ])

    # اتوبوس / مینی‌بوس
    buses = {
        "ایران خودرو دیزل": [
            ("سیتارو شهری", "OM457", "bus", True, ["Citaro"]),
            ("اتوبوس ۴۵۷ بین شهری", "OM457", "bus", True, ["۴۵۷"]),
            ("اتوبوس O303", "OM447", "bus", False, []),
            ("مینی‌بوس آرین پلاس", "دیزل ۴ سیلندر", "minibus", False, []),
        ],
        "اسکانیا اتوبوس": [
            ("K 410", "DC13", "bus", False, []),
            ("OmniLink", "DC9", "bus", False, []),
            ("Touring", "DC13", "bus", False, []),
        ],
        "ولوو اتوبوس": [
            ("B7R", "D7", "bus", False, []),
            ("B12B", "D12", "bus", False, []),
            ("9700", "D11", "bus", False, []),
        ],
        "یوتونگ": [
            ("ZK6122", "دیزل", "bus", True, ["Yutong", "یوتونگ"]),
            ("ZK6118", "دیزل", "bus", False, []),
            ("مینی‌بوس ZK6608", "دیزل", "minibus", False, []),
        ],
        "کینگ لانگ": [
            ("XMQ6127", "دیزل", "bus", False, ["King Long"]),
            ("XMQ6900", "دیزل", "bus", False, []),
        ],
        "ژونگ‌تونگ": [
            ("LCK6127", "دیزل", "bus", False, ["Zhongtong"]),
        ],
        "گلدن دراگون": [
            ("XML6125", "دیزل", "bus", False, ["Golden Dragon"]),
        ],
        "هایگر": [
            ("KLQ6129", "دیزل", "bus", False, ["Higer"]),
        ],
        "سترا": [
            ("S 415 HD", "OM457", "bus", False, ["Setra"]),
            ("S 516 HDH", "OM470", "bus", False, []),
        ],
        "نئوپلن": [
            ("Cityliner", "دیزل", "bus", False, ["Neoplan"]),
            ("Skyliner", "دیزل", "bus", False, []),
        ],
        "مرسدس اتوبوس": [
            ("Tourismo", "OM470", "bus", False, []),
            ("Travego", "OM457", "bus", False, []),
            ("Citaro C2", "OM936", "bus", False, []),
            ("Sprinter Travel", "2.2 دیزل", "minibus", True, []),
        ],
        "تویوتا اتوبوس": [
            ("Coaster", "4.0L / 3.0 دیزل", "minibus", True, ["کوستر"]),
            ("Hiace Commuter", "2.7L", "minibus", True, ["هایس مسافری"]),
        ],
        "میتسوبیشی اتوبوس": [
            ("Rosa", "4D34", "minibus", False, ["روزا"]),
        ],
        "ایسوزو اتوبوس": [
            ("NPR مینی‌بوس", "4HG1", "minibus", False, []),
            ("NQR شهری", "4HK1", "minibus", False, []),
        ],
        "هیوندای اتوبوس": [
            ("County", "D4BB", "minibus", True, ["کانتی"]),
            ("Universe", "D6CA", "bus", False, []),
            ("H350", "2.5 دیزل", "minibus", False, []),
        ],
        "اوتوکار": [
            ("Navigo", "دیزل", "minibus", False, ["Otokar"]),
            ("Kent", "دیزل", "bus", False, []),
        ],
        "تمسا": [
            ("Safari", "دیزل", "bus", False, ["Temsa"]),
            ("Avenue", "دیزل", "bus", False, []),
        ],
        "مارال": [
            ("اتوبوس بین‌شهری", "دیزل", "bus", False, ["Maral"]),
        ],
        "ون فوتون": [
            ("View CS2", "2.8 دیزل", "minibus", False, []),
        ],
        "جک ون": [
            ("Sunray 8 نفره", "2.8 دیزل", "minibus", False, []),
            ("Sunray 15 نفره", "2.8 دیزل", "van", False, []),
        ],
        "کیا ون": [
            ("کارنیوال نسل قدیم", "2.9 دیزل", "van", False, []),
            ("پرجیو", "2.7 دیزل", "van", False, ["Pregio"]),
            ("بستا", "2.7 دیزل", "van", False, ["Besta"]),
        ],
        "فورد ون": [
            ("Transit 350", "2.2 دیزل", "van", False, ["ترنزیت"]),
            ("Transit Custom", "2.0 دیزل", "van", False, []),
        ],
        "فولکس ون": [
            ("Crafter", "2.0 دیزل", "van", False, []),
            ("Transporter T6", "2.0T", "van", False, ["T6"]),
        ],
        "مرسدس ون": [
            ("Vito 115", "2.2 دیزل", "van", True, ["ویتو"]),
            ("V-Class", "2.0T", "van", False, []),
            ("Sprinter 313", "2.2 دیزل", "van", True, []),
        ],
        "نیسان ون": [
            ("Urvan", "2.5L", "van", False, ["اورون"]),
            ("Cabstar", "3.0 دیزل", "truck", False, []),
        ],
    }
    for brand, items in buses.items():
        country = "ایران" if "ایران" in brand or brand in ("شهاب خودرو", "مارال") else {
            "یوتونگ": "چین", "کینگ لانگ": "چین", "ژونگ‌تونگ": "چین", "گلدن دراگون": "چین",
            "هایگر": "چین", "ون فوتون": "چین", "جک ون": "چین",
            "اسکانیا اتوبوس": "سوئد", "ولوو اتوبوس": "سوئد",
            "سترا": "آلمان", "نئوپلن": "آلمان", "مرسدس اتوبوس": "آلمان", "مرسدس ون": "آلمان", "فولکس ون": "آلمان",
            "تویوتا اتوبوس": "ژاپن", "میتسوبیشی اتوبوس": "ژاپن", "ایسوزو اتوبوس": "ژاپن", "نیسان ون": "ژاپن",
            "هیوندای اتوبوس": "کره جنوبی", "کیا ون": "کره جنوبی",
            "اوتوکار": "ترکیه", "تمسا": "ترکیه", "فورد ون": "آمریکا",
        }.get(brand, "وارداتی")
        for rec in items:
            m, e, cat, pop, als = rec
            add(brand, m, e, cat, popular=pop, aliases=als, issues="bus",
                fuel="diesel" if "بنزین" not in e and "T" not in e[-2:] else "gasoline",
                trans="manual", country=country,
                region="ایران" if country == "ایران" else "وارداتی")

    # ── تراکتور ────────────────────────────────────────────────────────────
    def add_ag(brand, country, models):
        for m, e, pop, als in models:
            add(brand, m, e, "tractor", popular=pop, aliases=als, issues="tractor",
                fuel="diesel", trans="manual", country=country,
                region="ایران" if country == "ایران" else "وارداتی")

    add_ag("تراکتورسازی تبریز", "ایران", [
        ("ITM 285", "76 hp", True, ["تراکتور ۲۸۵", "ITM285", "مسی ۲۸۵ ایرانی"]),
        ("ITM 399", "110 hp", True, ["تراکتور ۳۹۹", "ITM399"]),
        ("ITM 299", "82 hp", False, []),
        ("ITM 240", "50 hp", False, ["ITM240"]),
        ("ITM 470", "120 hp", False, []),
        ("ITM 750", "75 hp", False, []),
        ("ITM 800", "80 hp", False, []),
        ("ITM 850", "85 hp", False, []),
        ("ITM 1050", "105 hp", False, []),
        ("ITM 399 جفت", "110 hp 4WD", True, ["۳۹۹ جفت دیفرانسیل"]),
        ("ITM 285 جفت", "76 hp 4WD", True, ["۲۸۵ جفت"]),
        ("ITM 1500", "150 hp", False, []),
        ("ITM 399 باغی", "110 hp", False, []),
    ])
    add_ag("مسی فرگوسن", "بریتانیا", [
        ("MF 285", "75 hp", True, ["مسی ۲۸۵", "فرگوسن ۲۸۵"]),
        ("MF 399", "110 hp", True, ["مسی ۳۹۹"]),
        ("MF 165", "62 hp", False, ["مسی ۱۶۵"]),
        ("MF 135", "47 hp", False, ["مسی ۱۳۵"]),
        ("MF 440", "82 hp", False, []),
        ("MF 290", "82 hp", False, []),
        ("MF 299", "82 hp", False, []),
        ("MF 8690", "370 hp", False, []),
        ("MF 6713", "130 hp", False, []),
    ])
    add_ag("نیوهلند", "ایتالیا", [
        ("TD 5.110", "110 hp", False, ["New Holland"]),
        ("TT 75", "75 hp", False, []),
        ("TT 55", "55 hp", False, []),
        ("T6.180", "180 hp", False, []),
        ("T7.210", "210 hp", False, []),
        ("T8.410", "410 hp", False, []),
        ("Boomer 50", "50 hp", False, ["باغی"]),
    ])
    add_ag("جان دیر", "آمریکا", [
        ("3140", "100 hp", False, ["John Deere"]),
        ("3350", "115 hp", False, []),
        ("4455", "140 hp", False, []),
        ("6J 210", "210 hp", False, []),
        ("8R 370", "370 hp", False, []),
        ("5E 90", "90 hp", False, []),
        ("5075E", "75 hp", False, []),
    ])
    add_ag("بلاروس", "بلاروس", [
        ("MTZ 80", "80 hp", True, ["MTZ", "بلاروس ۸۰"]),
        ("MTZ 82", "82 hp", True, ["بلاروس ۸۲", "جفت"]),
        ("MTZ 1221", "130 hp", False, []),
        ("MTZ 1523", "150 hp", False, []),
        ("MTZ 2022", "210 hp", False, []),
        ("MTZ 50", "50 hp", False, []),
    ])
    add_ag("کیس آی‌اچ", "آمریکا", [
        ("JXT 75", "75 hp", False, ["Case IH"]),
        ("Maxxum 125", "125 hp", False, []),
        ("Puma 165", "165 hp", False, []),
        ("Magnum 340", "340 hp", False, []),
        ("Farmall 90", "90 hp", False, []),
    ])
    add_ag("کلاس", "آلمان", [
        ("Arion 630", "165 hp", False, ["Claas"]),
        ("Axion 850", "235 hp", False, []),
        ("Xerion 4000", "400 hp", False, []),
    ])
    add_ag("فنت", "آلمان", [
        ("716 Vario", "160 hp", False, ["Fendt"]),
        ("724 Vario", "240 hp", False, []),
        ("942 Vario", "415 hp", False, []),
    ])
    add_ag("دوتس فاهر", "آلمان", [
        ("Agrotron 6155", "155 hp", False, ["Deutz-Fahr"]),
        ("5115", "115 hp", False, []),
    ])
    add_ag("کوبوتا", "ژاپن", [
        ("L4508", "45 hp", False, ["Kubota"]),
        ("M7040", "70 hp", False, []),
        ("M135GX", "135 hp", False, []),
        ("B2650", "26 hp", False, ["باغی کوبوتا"]),
    ])
    add_ag("یانمار", "ژاپن", [
        ("YM 357", "35 hp", False, ["Yanmar"]),
        ("YT 359", "59 hp", False, []),
    ])
    add_ag("والترا", "فنلاند", [
        ("N134", "135 hp", False, ["Valtra"]),
        ("T174", "175 hp", False, []),
        ("S394", "400 hp", False, []),
    ])
    add_ag("لاندینی", "ایتالیا", [
        ("5-110", "110 hp", False, ["Landini"]),
        ("6-130", "130 hp", False, []),
    ])
    add_ag("اورسوس", "لهستان", [
        ("C-360", "52 hp", False, ["Ursus"]),
        ("C-385", "85 hp", False, []),
    ])

    add_ag("همت تراکتور", "ایران", [
        ("همت 75", "75 hp", False, []),
        ("همت 90", "90 hp", False, []),
    ])

    # ── ماشین‌آلات سنگین / راه‌سازی ───────────────────────────────────────
    def add_heavy(brand, country, models):
        for m, e, pop, als in models:
            add(brand, m, e, "heavy", popular=pop, aliases=als, issues="heavy",
                fuel="diesel", trans="automatic", country=country,
                region="ایران" if country == "ایران" else "وارداتی")

    add_heavy("هپکو", "ایران", [
        ("HB 215 LC", "بیل مکانیکی", True, ["هپکو ۲۱۵", "بیل هپکو"]),
        ("HB 220 LC", "بیل مکانیکی", False, []),
        ("HB 300 LC", "بیل مکانیکی", False, ["هپکو ۳۰۰"]),
        ("HB 320 LC", "بیل مکانیکی", False, []),
        ("HL 760", "لودر", True, ["لودر هپکو ۷۶۰"]),
        ("HL 770", "لودر", False, []),
        ("HD 16", "بولدوزر", False, ["بولدوزر هپکو"]),
        ("HG 140", "گریدر", False, ["گریدر هپکو"]),
        ("HR 12", "غلطک", False, []),
    ])
    add_heavy("ماشین‌سازی اراک", "ایران", [
        ("لودر MSA", "لودر", False, []),
        ("جرثقیل MSA", "جرثقیل", False, []),
    ])
    add_heavy("کاترپیلار", "آمریکا", [
        ("320D", "بیل مکانیکی", True, ["CAT 320", "بیل کاترپیلار"]),
        ("330D", "بیل مکانیکی", True, ["CAT 330"]),
        ("336", "بیل مکانیکی", False, []),
        ("349", "بیل مکانیکی", False, []),
        ("D6R", "بولدوزر", True, ["D6", "بولدوزر کاترپیلار"]),
        ("D8T", "بولدوزر", True, ["D8"]),
        ("D9T", "بولدوزر", False, ["D9"]),
        ("950H", "لودر", True, ["لودر ۹۵۰"]),
        ("966H", "لودر", True, ["لودر ۹۶۶"]),
        ("980H", "لودر", False, []),
        ("140G", "گریدر", True, ["گریدر ۱۴۰"]),
        ("140K", "گریدر", False, []),
        ("CS533E", "غلطک", False, ["غلطک کاترپیلار"]),
        ("773G", "دامپتراک", False, ["دامپ ۷۷۳"]),
        ("777G", "دامپتراک", False, []),
        ("416E", "بکهو", False, ["بکهو کاترپیلار"]),
        ("308E CR", "مینی بیل", False, []),
    ])
    add_heavy("کوماتسو", "ژاپن", [
        ("PC200-8", "بیل مکانیکی", True, ["بیل کوماتسو ۲۰۰"]),
        ("PC220-8", "بیل مکانیکی", True, []),
        ("PC300-8", "بیل مکانیکی", False, []),
        ("PC400-8", "بیل مکانیکی", False, []),
        ("D65PX", "بولدوزر", True, ["D65"]),
        ("D85ESS", "بولدوزر", False, ["D85"]),
        ("D155A", "بولدوزر", False, []),
        ("WA380", "لودر", False, []),
        ("WA470", "لودر", True, ["لودر کوماتسو"]),
        ("WA500", "لودر", False, []),
        ("GD655", "گریدر", False, ["گریدر کوماتسو"]),
        ("HD785", "دامپتراک", False, []),
        ("HB205", "بیل هیبرید", False, []),
        ("PC55MR", "مینی بیل", False, []),
    ])
    add_heavy("هیتاچی", "ژاپن", [
        ("ZX200-5", "بیل مکانیکی", True, ["بیل هیتاچی"]),
        ("ZX240-5", "بیل مکانیکی", False, []),
        ("ZX330-5", "بیل مکانیکی", False, []),
        ("ZX350-5", "بیل مکانیکی", False, []),
        ("ZX490", "بیل مکانیکی", False, []),
        ("ZW220", "لودر", False, []),
        ("ZW310", "لودر", False, []),
    ])
    add_heavy("ولوو راه‌سازی", "سوئد", [
        ("EC210B", "بیل مکانیکی", True, ["بیل ولوو"]),
        ("EC240B", "بیل مکانیکی", False, []),
        ("EC290B", "بیل مکانیکی", False, []),
        ("EC480D", "بیل مکانیکی", False, []),
        ("L90F", "لودر", False, []),
        ("L120F", "لودر", True, ["لودر ولوو"]),
        ("L150H", "لودر", False, []),
        ("L220H", "لودر", False, []),
        ("A30F", "دامپ آرتیکوله", False, ["A30"]),
        ("A40F", "دامپ آرتیکوله", False, ["A40"]),
        ("G940", "گریدر", False, []),
    ])
    add_heavy("هیوندای راه‌سازی", "کره جنوبی", [
        ("R220LC-9S", "بیل مکانیکی", True, ["بیل هیوندای ۲۲۰"]),
        ("R320LC-9", "بیل مکانیکی", False, []),
        ("R480LC-9", "بیل مکانیکی", False, []),
        ("HL757-9", "لودر", False, []),
        ("HL770-9", "لودر", True, ["لودر هیوندای"]),
        ("HL780", "لودر", False, []),
    ])
    add_heavy("دوسان", "کره جنوبی", [
        ("DX225LC", "بیل مکانیکی", True, ["بیل دوسان"]),
        ("DX300LC", "بیل مکانیکی", False, []),
        ("DX340LC", "بیل مکانیکی", False, []),
        ("DL250", "لودر", False, []),
        ("DL300", "لودر", False, []),
        ("DL420", "لودر", False, []),
    ])
    add_heavy("جی‌سی‌بی", "بریتانیا", [
        ("3CX", "بکهو لودر", True, ["JCB 3CX", "بکهو"]),
        ("4CX", "بکهو لودر", False, []),
        ("JS200", "بیل مکانیکی", False, []),
        ("JS220", "بیل مکانیکی", False, []),
        ("456 ZX", "لودر", False, []),
        ("540-170", "تلسکوپی", False, ["telehandler"]),
        ("535-95", "تلسکوپی", False, []),
        ("1CX", "مینی بکهو", False, []),
    ])
    add_heavy("لیبهر", "آلمان", [
        ("R 926", "بیل مکانیکی", False, ["Liebherr"]),
        ("R 956", "بیل مکانیکی", False, []),
        ("L 550", "لودر", False, []),
        ("L 580", "لودر", False, []),
        ("PR 736", "بولدوزر", False, []),
        ("LTM 1100", "جرثقیل موبایل", True, ["جرثقیل لیبهر"]),
        ("LTM 1250", "جرثقیل موبایل", False, []),
        ("LR 1300", "جرثقیل خزنده", False, []),
    ])
    add_heavy("کیس", "آمریکا", [
        ("580 Super N", "بکهو", True, ["Case 580"]),
        ("590 Super N", "بکهو", False, []),
        ("CX210D", "بیل مکانیکی", False, []),
        ("CX300D", "بیل مکانیکی", False, []),
        ("721G", "لودر", False, []),
        ("821G", "لودر", False, []),
    ])
    add_heavy("نیوهلند راه‌سازی", "ایتالیا", [
        ("B115B", "بکهو", False, []),
        ("E215C", "بیل مکانیکی", False, []),
        ("W170D", "لودر", False, []),
    ])
    add_heavy("بابکت", "آمریکا", [
        ("S650", "مینی لودر", True, ["Bobcat", "اسکیدلودر"]),
        ("S770", "مینی لودر", False, []),
        ("T650", "تراک لودر", False, []),
        ("E35", "مینی بیل", False, []),
        ("E50", "مینی بیل", False, []),
        ("E85", "مینی بیل", False, []),
    ])
    add_heavy("تیکوچی", "ژاپن", [
        ("TB240", "مینی بیل", False, ["Takeuchi"]),
        ("TB290", "مینی بیل", False, []),
        ("TL12", "اسکیدلودر", False, []),
    ])
    add_heavy("اکس‌سی‌ام‌جی", "چین", [
        ("XE215C", "بیل مکانیکی", True, ["XCMG", "بیل XCMG"]),
        ("XE370CA", "بیل مکانیکی", False, []),
        ("LW500KN", "لودر", True, ["لودر XCMG"]),
        ("LW300KN", "لودر", False, []),
        ("GR165", "گریدر", False, []),
        ("XS223", "غلطک", False, []),
        ("QY25K5", "جرثقیل ۲۵ تن", True, ["جرثقیل XCMG"]),
        ("QY50K", "جرثقیل ۵۰ تن", False, []),
        ("QY70K", "جرثقیل ۷۰ تن", False, []),
    ])
    add_heavy("سانی", "چین", [
        ("SY215C", "بیل مکانیکی", True, ["Sany", "بیل سانی"]),
        ("SY365H", "بیل مکانیکی", False, []),
        ("SY500H", "بیل مکانیکی", False, []),
        ("STC250", "جرثقیل ۲۵ تن", True, ["جرثقیل سانی"]),
        ("STC500", "جرثقیل ۵۰ تن", False, []),
        ("SYM5330", "پمپ بتن", True, ["پمپ بتن سانی"]),
        ("SR225", "غلطک", False, []),
    ])
    add_heavy("زوم‌لاین", "چین", [
        ("ZE215E", "بیل مکانیکی", False, ["Zoomlion"]),
        ("ZE370E", "بیل مکانیکی", False, []),
        ("QY25V", "جرثقیل ۲۵ تن", False, []),
        ("QY50V", "جرثقیل ۵۰ تن", False, []),
        ("پمپ بتن 47X", "پمپ بتن", False, []),
    ])
    add_heavy("لیوگانگ", "چین", [
        ("CLG922E", "بیل مکانیکی", False, ["LiuGong"]),
        ("CLG936E", "بیل مکانیکی", False, []),
        ("CLG856H", "لودر", False, []),
        ("CLG862H", "لودر", False, []),
    ])
    add_heavy("اس‌دی‌ال‌جی", "چین", [
        ("LG936L", "لودر", False, ["SDLG"]),
        ("LG958L", "لودر", True, ["لودر SDLG"]),
        ("E215C", "بیل مکانیکی", False, []),
    ])
    add_heavy("شانتویی", "چین", [
        ("SD16", "بولدوزر", True, ["Shantui", "بولدوزر شانتویی"]),
        ("SD22", "بولدوزر", True, []),
        ("SD32", "بولدوزر", False, []),
        ("SL50W", "لودر", False, []),
        ("SG16-3", "گریدر", False, []),
    ])
    add_heavy("اس‌ای‌ام", "چین", [
        ("655D", "لودر", False, ["SEM", "کاترپیلار چین"]),
        ("822D", "بولدوزر", False, []),
        ("922F", "گریدر", False, []),
    ])
    add_heavy("لونکینگ", "چین", [
        ("CDM856", "لودر", False, ["Lonking"]),
        ("CDM922", "بیل مکانیکی", False, []),
    ])
    add_heavy("تادانو", "ژاپن", [
        ("GT-550E", "جرثقیل ۵۵ تن", False, ["Tadano"]),
        ("ATF 70G-4", "جرثقیل ۷۰ تن", False, []),
        ("GR-500EX", "جرثقیل ۵۰ تن", False, []),
    ])
    add_heavy("کاتو", "ژاپن", [
        ("NK-500E", "جرثقیل ۵۰ تن", False, ["Kato"]),
        ("NK-250E", "جرثقیل ۲۵ تن", False, []),
        ("CR-200", "جرثقیل ۲۰ تن", False, []),
    ])
    add_heavy("گروو", "آمریکا", [
        ("GMK 3050", "جرثقیل ۵۰ تن", False, ["Grove"]),
        ("GMK 4100", "جرثقیل ۱۰۰ تن", False, []),
        ("RT 540E", "جرثقیل آفرود", False, []),
    ])
    add_heavy("پوتن", "فرانسه", [
        ("MCT 205", "تاورکرین", False, ["Potain", "جرثقیل برجی"]),
        ("MDT 219", "تاورکرین", False, []),
        ("MR 418", "تاورکرین", False, []),
    ])
    add_heavy("پوتسمایستر", "آلمان", [
        ("M36-4", "پمپ بتن", True, ["Putzmeister"]),
        ("M42-5", "پمپ بتن", False, []),
        ("M56-5", "پمپ بتن", False, []),
    ])
    add_heavy("شویینگ", "آلمان", [
        ("S 36 X", "پمپ بتن", False, ["Schwing"]),
        ("S 43 SX", "پمپ بتن", False, []),
    ])
    add_heavy("بوماگ", "آلمان", [
        ("BW 213 D", "غلطک", True, ["Bomag"]),
        ("BW 226 DH", "غلطک", False, []),
        ("BF 800 C", "فینیشر", False, ["فینیشر آسفالت"]),
    ])
    add_heavy("هام", "آلمان", [
        ("HD 110", "غلطک", False, ["Hamm"]),
        ("HC 200i", "غلطک", False, []),
    ])
    add_heavy("دایناپک", "سوئد", [
        ("CA2500D", "غلطک", False, ["Dynapac"]),
        ("CC2200", "غلطک آسفالت", False, []),
        ("SD2550C", "فینیشر", False, []),
    ])
    add_heavy("ویرتگن", "آلمان", [
        ("W 200 Fi", "میلینگ آسفالت", False, ["Wirtgen"]),
        ("W 210 Fi", "میلینگ", False, []),
        ("SP 64", "اسلیپ‌فرم", False, []),
    ])
    add_heavy("وگل", "آلمان", [
        ("Super 1800-3", "فینیشر آسفالت", False, ["Vögele"]),
        ("Super 2100-3", "فینیشر", False, []),
    ])
    add_heavy("کوبلکو", "ژاپن", [
        ("SK200-10", "بیل مکانیکی", False, ["Kobelco"]),
        ("SK260-10", "بیل مکانیکی", False, []),
        ("SK350-10", "بیل مکانیکی", False, []),
    ])
    add_heavy("سومیتومو", "ژاپن", [
        ("SH210-6", "بیل مکانیکی", False, ["Sumitomo"]),
        ("SH240-6", "بیل مکانیکی", False, []),
    ])
    add_heavy("کاتو جرثقیل", "ژاپن", [
        ("CR-130", "جرثقیل ۱۳ تن", False, []),
    ])
    add_heavy("هیاب", "سوئد", [
        ("X-HiPro 192", "جرثقیل پشت کامیونی", False, ["Hiab"]),
        ("X-HiPro 548", "جرثقیل پشت کامیونی", False, []),
    ])
    add_heavy("پالفینگر", "اتریش", [
        ("PK 18.001", "جرثقیل پشت کامیونی", False, ["Palfinger"]),
        ("PK 33.002", "جرثقیل پشت کامیونی", False, []),
        ("PK 50.002", "جرثقیل پشت کامیونی", False, []),
    ])
    add_heavy("سوسان", "کره جنوبی", [
        ("SRS 335", "جرثقیل پشت کامیونی", False, ["Soosan"]),
        ("SRS 506", "جرثقیل پشت کامیونی", False, []),
    ])
    add_heavy("کانگلیم", "کره جنوبی", [
        ("KS 1256", "جرثقیل پشت کامیونی", False, ["Kanglim"]),
        ("KS 2056", "جرثقیل پشت کامیونی", False, []),
    ])
    add_heavy("اپیروک", "سوئد", [
        ("FlexiROC T35", "دریل حفاری", False, ["Epiroc", "Atlas Copco"]),
        ("SmartROC T40", "دریل حفاری", False, []),
        ("XAS 185", "کمپرسور", False, ["کمپرسور اطلس"]),
    ])
    add_heavy("سندویک", "سوئد", [
        ("DX800", "دریل حفاری", False, ["Sandvik"]),
        ("Pantera DP1500i", "دریل", False, []),
    ])
    add_heavy("اینگرسول رند", "آمریکا", [
        ("SD-100", "غلطک", False, ["Ingersoll Rand"]),
        ("XP 750", "کمپرسور", False, []),
    ])
    add_heavy("بلز", "بلاروس", [
        ("7547", "دامپتراک", False, ["BELAZ"]),
        ("7513", "دامپتراک", False, []),
        ("7530", "دامپتراک معدن", False, []),
    ])

    # ── Priority catalog pack: high-demand cars + site equipment ─────────────
    # Keep aliases broad so Persian/English user searches resolve reliably.
    add("تویوتا", "کرولا", "1.6L / 1.8L", "sedan", "gasoline", "automatic", True, ["Corolla", "کرولا"], "import", country="ژاپن", region="وارداتی")
    add("تویوتا", "کمری", "2.5L", "sedan", "gasoline", "automatic", True, ["Camry", "کمری"], "import", country="ژاپن", region="وارداتی")
    add("تویوتا", "لندکروزر", "4.0L / 4.6L", "suv", "gasoline", "automatic", True, ["Land Cruiser", "LandCruiser", "لندکروزر"], "import", country="ژاپن", region="وارداتی")
    add("تویوتا", "پرادو", "2.7L / 4.0L", "suv", "gasoline", "automatic", True, ["Prado", "Land Cruiser Prado", "پرادو"], "import", country="ژاپن", region="وارداتی")
    add("تویوتا", "هایلوکس", "2.4L / 2.7L", "pickup", "gasoline", "automatic", True, ["Hilux", "هایلوکس"], "pickup", country="ژاپن", region="وارداتی")
    add("هوندا", "CR-V", "1.5T / 2.0L", "suv", "gasoline", "automatic", True, ["Honda CRV", "CRV", "سی آر وی"], "import", country="ژاپن", region="وارداتی")
    add("هوندا", "Civic", "1.5T / 2.0L", "sedan", "gasoline", "automatic", False, ["سیویک"], "import", country="ژاپن", region="وارداتی")
    add("نیسان", "پاترول", "4.0L / 5.6L", "suv", "gasoline", "automatic", True, ["Patrol", "Nissan Patrol", "پاترول"], "import", country="ژاپن", region="وارداتی")
    add("نیسان", "X-Trail", "2.5L", "suv", "gasoline", "automatic", True, ["XTrail", "اکس تریل", "ایکس تریل"], "import", country="ژاپن", region="وارداتی")
    add("نیسان", "ناوارا", "2.3D / 2.5L", "pickup", "diesel", "automatic", True, ["Navara", "Nissan Navara", "ناوارا"], "pickup", country="ژاپن", region="وارداتی")
    add("ایسوزو", "NPR", "3.0L دیزل", "truck", "diesel", "manual", True, ["NPR", "ایسوزو NPR", "NPR75"], "diesel_truck", country="ژاپن", region="وارداتی")
    add("ایسوزو", "NQR", "5.2L دیزل", "truck", "diesel", "manual", True, ["NQR", "ایسوزو NQR"], "diesel_truck", country="ژاپن", region="وارداتی")
    add("هینو", "300", "4.0L دیزل", "truck", "diesel", "manual", True, ["Hino 300", "هینو 300"], "diesel_truck", country="ژاپن", region="وارداتی")
    add("هینو", "500", "7.7L دیزل", "truck", "diesel", "manual", True, ["Hino 500", "هینو 500"], "diesel_truck", country="ژاپن", region="وارداتی")
    add("مرسدس بنز", "Actros", "12.8L / 15.6L دیزل", "truck", "diesel", "automatic", True, ["آکتروس", "اکتروس", "Mercedes Actros"], "diesel_truck", country="آلمان", region="وارداتی")
    add("ولوو", "FH", "12.8L / 16.1L دیزل", "truck", "diesel", "automatic", True, ["Volvo FH", "اف اچ", "ولوو FH"], "diesel_truck", country="سوئد", region="وارداتی")
    add("تادانو", "GR-250N", "جرثقیل ۲۵ تن", "heavy", "diesel", "automatic", True, ["Tadano GR-250N", "تادانو GR-250N", "جرثقیل تادانو ۲۵ تن", "تادانو 25 تن", "Tadano 25 ton"], "heavy", country="ژاپن", region="وارداتی")
    add("تادانو", "TR-250M", "جرثقیل ۲۵ تن", "heavy", "diesel", "automatic", True, ["Tadano TR-250M", "تادانو TR-250M", "جرثقیل تادانو ۲۵ تن"], "heavy", country="ژاپن", region="وارداتی")
    add("کاترپیلار", "320", "بیل مکانیکی", "heavy", "diesel", "automatic", True, ["CAT 320", "Caterpillar 320", "کاترپیلار 320", "بیل کاترپیلار"], "heavy", country="آمریکا", region="وارداتی")
    add("کاترپیلار", "950M", "لودر", "heavy", "diesel", "automatic", True, ["CAT 950M", "Caterpillar 950M", "لودر کاترپیلار"], "heavy", country="آمریکا", region="وارداتی")
    add("کوماتسو", "PC210", "بیل مکانیکی", "heavy", "diesel", "automatic", True, ["Komatsu PC210", "کوماتسو PC210", "بیل کوماتسو"], "heavy", country="ژاپن", region="وارداتی")
    add("کوماتسو", "WA380", "لودر", "heavy", "diesel", "automatic", True, ["Komatsu WA380", "کوماتسو WA380", "لودر کوماتسو"], "heavy", country="ژاپن", region="وارداتی")
    add("ولوو ماشین‌آلات", "EC210", "بیل مکانیکی", "heavy", "diesel", "automatic", True, ["Volvo EC210", "ولوو EC210", "بیل ولوو"], "heavy", country="سوئد", region="وارداتی")
    add("ولوو ماشین‌آلات", "L120", "لودر", "heavy", "diesel", "automatic", True, ["Volvo L120", "لودر ولوو"], "heavy", country="سوئد", region="وارداتی")
    add("دوسان", "DX225LC", "بیل مکانیکی", "heavy", "diesel", "automatic", True, ["Doosan DX225", "دوسان DX225", "بیل دوسان"], "heavy", country="کره جنوبی", region="وارداتی")
    add("لیبهر", "LTM 1025", "جرثقیل ۲۵ تن", "heavy", "diesel", "automatic", True, ["Liebherr LTM 1025", "لیبهر ۲۵ تن", "جرثقیل لیبهر ۲۵ تن"], "heavy", country="آلمان", region="وارداتی")
    add("تویوتا", "یاریس", "1.3L / 1.5L", "hatchback", "gasoline", "automatic", False, ["Yaris", "یاریس"], "import", country="ژاپن", region="وارداتی")
    add("کیا", "اسپورتیج", "2.0L / 2.4L", "suv", "gasoline", "automatic", True, ["Sportage", "اسپورتیج"], "import", country="کره جنوبی", region="وارداتی")
    add("هیوندای", "توسان", "2.0L / 1.6T", "suv", "gasoline", "automatic", True, ["Tucson", "توسان"], "import", country="کره جنوبی", region="وارداتی")

    # unique-ify ids if collision
    seen_ids: dict[str, int] = {}
    for r in rows:
        i = r["id"]
        seen_ids[i] = seen_ids.get(i, 0) + 1
        if seen_ids[i] > 1:
            r["id"] = f"{i}-{seen_ids[i]}"
    return rows


def merge(seed: list[dict], extra: list[dict]) -> list[dict]:
    by_key = {}
    by_id = {}
    ordered = []
    for c in seed + extra:
        k = key_of(c)
        cid = c["id"]
        if cid in by_id or k in by_key:
            continue
        by_id[cid] = c
        by_key[k] = c
        ordered.append(c)
    return ordered


def stats(cars: list[dict]) -> None:
    from collections import Counter
    cats = Counter(c.get("category") or "?" for c in cars)
    brands = Counter(c["brand"] for c in cars)
    print(f"total={len(cars)} brands={len(brands)}")
    for k, n in cats.most_common():
        print(f"  {k}: {n}")


def main() -> None:
    seed_raw = json.loads(SEED.read_text(encoding="utf-8"))
    seed = enrich_seed(seed_raw)
    extra = extras()
    cars = merge(seed, extra)
    # stable sort: popular first is handled in UI; here brand+model
    cars.sort(key=lambda c: (c["brand"], c["model"], c.get("engine", "")))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(cars, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    stats(cars)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
