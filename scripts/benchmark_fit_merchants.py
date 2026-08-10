#!/usr/bin/env python3
"""Discover and benchmark real merchant size-chart pages without storing secrets.

The report separates network reachability, chart-text retention, structured
extraction, literal-number grounding, and measurement plausibility. API keys
are read only from the process environment and never written to output.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import html as html_module
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path


MERCHANTS = [
    ("Nike", "nike.com"), ("Adidas", "adidas.com"), ("Levi's", "levi.com"),
    ("Uniqlo", "uniqlo.com"), ("Zara", "zara.com"), ("H&M", "hm.com"),
    ("Gap", "gap.com"), ("Old Navy", "oldnavy.gap.com"),
    ("Banana Republic", "bananarepublic.gap.com"), ("J.Crew", "jcrew.com"),
    ("Madewell", "madewell.com"), ("Anthropologie", "anthropologie.com"),
    ("Free People", "freepeople.com"), ("ASOS", "asos.com"),
    ("Nordstrom", "nordstrom.com"), ("Macy's", "macys.com"),
    ("Target", "target.com"), ("Walmart", "walmart.com"),
    ("Lululemon", "lululemon.com"), ("Athleta", "athleta.gap.com"),
    ("Under Armour", "underarmour.com"), ("Puma", "puma.com"),
    ("Reebok", "reebok.com"), ("New Balance", "newbalance.com"),
    ("Columbia", "columbia.com"), ("The North Face", "thenorthface.com"),
    ("Patagonia", "patagonia.com"), ("Arc'teryx", "arcteryx.com"),
    ("Marmot", "marmot.com"), ("REI", "rei.com"),
    ("Lands' End", "landsend.com"), ("L.L.Bean", "llbean.com"),
    ("Brooks Brothers", "brooksbrothers.com"), ("Ralph Lauren", "ralphlauren.com"),
    ("Tommy Hilfiger", "tommy.com"), ("Calvin Klein", "calvinklein.us"),
    ("Hollister", "hollisterco.com"), ("Abercrombie", "abercrombie.com"),
    ("American Eagle", "ae.com"), ("Aerie", "ae.com"),
    ("Express", "express.com"), ("Forever 21", "forever21.com"),
    ("Urban Outfitters", "urbanoutfitters.com"), ("PacSun", "pacsun.com"),
    ("Torrid", "torrid.com"), ("Lane Bryant", "lanebryant.com"),
    ("Talbots", "talbots.com"), ("Chico's", "chicos.com"),
    ("Everlane", "everlane.com"), ("Quince", "quince.com"),
    ("Buck Mason", "buckmason.com"), ("Vuori", "vuoriclothing.com"),
    ("Outdoor Voices", "outdoorvoices.com"), ("Gymshark", "gymshark.com"),
    ("Alo Yoga", "aloyoga.com"), ("SKIMS", "skims.com"),
    ("Fabletics", "fabletics.com"), ("Spanx", "spanx.com"),
    ("Carhartt", "carhartt.com"), ("Dickies", "dickies.com"),
    ("Wrangler", "wrangler.com"), ("Lee", "lee.com"),
    ("Guess", "guess.com"), ("Diesel", "diesel.com"),
    ("AllSaints", "allsaints.com"), ("COS", "cos.com"),
    ("Massimo Dutti", "massimodutti.com"), ("Mango", "shop.mango.com"),
    ("Aritzia", "aritzia.com"), ("Revolve", "revolve.com"),
    ("Net-a-Porter", "net-a-porter.com"), ("Farfetch", "farfetch.com"),
    ("SSENSE", "ssense.com"), ("Mytheresa", "mytheresa.com"),
    ("Bloomingdale's", "bloomingdales.com"), ("Saks Fifth Avenue", "saksfifthavenue.com"),
    ("Neiman Marcus", "neimanmarcus.com"), ("Dillard's", "dillards.com"),
    ("Kohl's", "kohls.com"), ("JCPenney", "jcpenney.com"),
    ("Belk", "belk.com"), ("Boscov's", "boscovs.com"),
    ("Foot Locker", "footlocker.com"), ("Finish Line", "finishline.com"),
    ("Champs Sports", "champssports.com"), ("Journeys", "journeys.com"),
    ("Zappos", "zappos.com"), ("DSW", "dsw.com"),
    ("Steve Madden", "stevemadden.com"), ("Coach", "coach.com"),
    ("Kate Spade", "katespade.com"), ("Michael Kors", "michaelkors.com"),
    ("Tory Burch", "toryburch.com"), ("Gucci", "gucci.com"),
    ("Prada", "prada.com"), ("Burberry", "burberry.com"),
    ("Boohoo", "boohoo.com"), ("PrettyLittleThing", "prettylittlething.us"),
    ("Nasty Gal", "nastygal.com"), ("Club Monaco", "clubmonaco.com"),
    ("Theory", "theory.com"), ("Vineyard Vines", "vineyardvines.com"),
]

KEYWORDS = (
    "size chart", "size guide", "measurement", "measurements", "bust", "chest",
    "waist", "hip", "inseam", "shoulder", "sleeve", "length",
)
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
)


@dataclass
class PageResult:
    merchant: str
    domain: str
    url: str | None
    status: str
    http_status: int | None = None
    latency_ms: int | None = None
    condensed_characters: int = 0
    numeric_tokens: int = 0
    extracted: bool = False
    grounded: bool = False
    plausible: bool = False
    basis: str | None = None
    measurement_form: str | None = None
    size_count: int = 0
    error: str | None = None
    ungrounded_values: list[str] | None = None


def request(url: str, *, data: bytes | None = None, headers: dict[str, str] | None = None, timeout: int = 25):
    merged = {"User-Agent": USER_AGENT, "Accept": "text/html,application/json", **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=merged)
    return urllib.request.urlopen(req, timeout=timeout)


def discover_one(item: tuple[str, str], api_key: str) -> list[dict[str, str | None]]:
    merchant, domain = item
    body = json.dumps({
        "q": f"site:{domain} size chart measurements chest waist hip",
        "num": 5,
    }).encode()
    try:
        with request(
            "https://google.serper.dev/search",
            data=body,
            headers={"Content-Type": "application/json", "X-API-KEY": api_key},
        ) as response:
            root = json.load(response)
        urls = [row.get("link") for row in root.get("organic", [])]
        valid = []
        seen = set()
        for value in urls:
            if not value or domain not in urllib.parse.urlparse(value).netloc or value in seen:
                continue
            seen.add(value)
            valid.append({"merchant": merchant, "domain": domain, "url": value})
        return valid[:5]
    except Exception:
        return [{"merchant": merchant, "domain": domain, "url": None}]


def strip_tags(value: str) -> str:
    value = re.sub(r"<br[^>]*>|</p>|</div>|</li>|</h[1-6]>", "\n", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html_module.unescape(value)
    value = re.sub(r"[ \t]{2,}", " ", value)
    return re.sub(r"\n{2,}", "\n", value).strip()


def condense(source: str) -> str:
    working = re.sub(r"<(script|style|svg|noscript)[^>]*>[\s\S]*?</\1>", " ", source, flags=re.I)
    sections: list[str] = []
    for table in re.findall(r"<table[^>]*>[\s\S]*?</table>", working, flags=re.I)[:14]:
        rows = []
        for row in re.findall(r"<tr[^>]*>([\s\S]*?)</tr>", table, flags=re.I)[:40]:
            rows.append(strip_tags(re.sub(r"</t[dh]>", " | ", row, flags=re.I)))
        grid = "\n".join(rows)
        if len(grid) > 40:
            sections.append("TABLE:\n" + grid[:5000])
    plain = strip_tags(working)
    for keyword in KEYWORDS:
        for hit in list(re.finditer(re.escape(keyword), plain, flags=re.I))[:4]:
            sections.append("TEXT:\n" + plain[max(0, hit.start() - 400):hit.end() + 600])
    return "\n\n".join(sections)[:22000].strip()


def numbers(value: str) -> set[str]:
    return {token.lstrip("0") or "0" for token in re.findall(r"(?<!\w)\d+(?:\.\d+)?", value)}


def grounding_violations(payload: dict, source: str) -> list[str]:
    """Return output numbers that are neither literal nor range midpoints."""
    permitted = numbers(source)
    for lower, upper in re.findall(r"(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)", source):
        midpoint = (float(lower) + float(upper)) / 2
        rendered = f"{midpoint:.6f}".rstrip("0").rstrip(".")
        permitted.add(rendered.lstrip("0") or "0")
    measurement_rows = [
        {key: value for key, value in row.items() if key != "label"}
        for row in payload.get("sizes", [])
    ]
    output_numbers = numbers(json.dumps(measurement_rows))
    return sorted(output_numbers - permitted, key=lambda value: (float(value), value))


def extract_chart(condensed: str, merchant: str, api_key: str, model: str) -> dict:
    prompt = f"""Extract a published per-size chart from this {merchant} page.
Only report numbers literally present. Range values must use their midpoint.
basis: garment, body, or unknown. measurementForm: flat_width only for one-side
garment widths such as pit-to-pit; circumference for full around-body values;
otherwise unknown. unit: cm or in. Map bust to chest and hip to hips. Choose one
coherent chart and return no more than 20 contiguous size rows; do not combine
regions, genders, ages, or categories. Use null for missing dimensions. Return
found=false if no per-size numeric chart exists.

PAGE TEXT:\n{condensed}"""
    number_or_null = {"anyOf": [{"type": "number"}, {"type": "null"}]}
    size_properties = {"label": {"type": "string"}}
    for name in ("chest", "waist", "hips", "shoulders", "length", "sleeve", "inseam"):
        size_properties[name] = number_or_null
    schema = {
        "type": "object",
        "properties": {
            "found": {"type": "boolean"},
            "basis": {"type": "string", "enum": ["garment", "body", "unknown"]},
            "measurementForm": {"type": "string", "enum": ["circumference", "flat_width", "unknown"]},
            "unit": {"type": "string", "enum": ["cm", "in"]},
            "sizes": {"type": "array", "items": {
                "type": "object", "properties": size_properties,
                "required": list(size_properties), "additionalProperties": False,
            }},
            "note": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        },
        "required": ["found", "basis", "measurementForm", "unit", "sizes", "note"],
        "additionalProperties": False,
    }
    body = json.dumps({
        "model": model, "reasoning_effort": "none", "temperature": 0, "max_tokens": 5000,
        "response_format": {"type": "json_schema", "json_schema": {"name": "fit_benchmark", "schema": schema}},
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    with request(
        "https://api.fireworks.ai/inference/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        timeout=45,
    ) as response:
        root = json.load(response)
    if root["choices"][0].get("finish_reason") == "length":
        raise ValueError("Fireworks response reached its output limit")
    content = root["choices"][0]["message"]["content"]
    return json.loads(content[content.find("{"):content.rfind("}") + 1])


def plausible(payload: dict) -> bool:
    unit_factor = 2.54 if payload.get("unit") == "in" else 1.0
    basis, form = payload.get("basis"), payload.get("measurementForm")
    ranges = {
        "chest": (35, 260), "waist": (35, 260), "hips": (35, 260),
        "shoulders": (15, 100), "length": (8, 220), "sleeve": (8, 220), "inseam": (8, 220),
    }
    for size in payload.get("sizes", []):
        for dimension, bounds in ranges.items():
            value = size.get(dimension)
            if value is None:
                continue
            cm = value * unit_factor
            if basis == "garment" and form == "flat_width" and dimension in {"chest", "waist", "hips"}:
                cm *= 2
            if not bounds[0] <= cm <= bounds[1]:
                return False
    return True


def benchmark_one(entry: dict, fireworks_key: str | None, model: str) -> PageResult:
    result = PageResult(entry["merchant"], entry["domain"], entry.get("url"), "missing_url")
    if not result.url:
        return result
    started = time.monotonic()
    try:
        with request(result.url) as response:
            source = response.read(3_000_000).decode("utf-8", "replace")
            result.http_status = response.status
        result.latency_ms = round((time.monotonic() - started) * 1000)
        text = condense(source)
        result.condensed_characters = len(text)
        result.numeric_tokens = len(numbers(text))
        if not text or result.numeric_tokens < 4:
            result.status = "no_chart_text"
            return result
        result.status = "chart_text_ready"
        if not fireworks_key:
            return result
        payload = extract_chart(text, result.merchant, fireworks_key, model)
        result.extracted = bool(payload.get("found") and payload.get("sizes"))
        result.basis = payload.get("basis")
        result.measurement_form = payload.get("measurementForm")
        result.size_count = len(payload.get("sizes", []))
        if result.extracted:
            result.ungrounded_values = grounding_violations(payload, text)
            result.grounded = not result.ungrounded_values
            result.plausible = plausible(payload)
        result.status = "passed" if result.extracted and result.grounded and result.plausible else "extraction_review"
    except urllib.error.HTTPError as error:
        result.http_status = error.code
        result.status = "http_error"
        result.error = f"HTTP {error.code}"
    except Exception as error:
        result.status = "error"
        result.error = str(error)[:240]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--discover", action="store_true")
    parser.add_argument("--extract", action="store_true")
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--page-limit", type=int, default=100)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--model", default="accounts/fireworks/models/qwen3-vl-30b-a3b-instruct")
    args = parser.parse_args()

    if args.discover:
        key = os.environ.get("STYLEZAM_SERPER_API_KEY")
        if not key:
            raise SystemExit("STYLEZAM_SERPER_API_KEY is required for discovery")
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(4, args.workers)) as pool:
            discovered_groups = list(pool.map(lambda row: discover_one(row, key), MERCHANTS[:args.limit]))
        # Round-robin ranks so the first page limit represents the whole merchant
        # set instead of being dominated by the first few domains.
        manifest = []
        for rank in range(5):
            for group in discovered_groups:
                if rank < len(group):
                    manifest.append(group[rank])
                if len(manifest) >= args.page_limit:
                    break
            if len(manifest) >= args.page_limit:
                break
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    else:
        manifest = json.loads(args.manifest.read_text())[:args.page_limit]

    fireworks_key = os.environ.get("STYLEZAM_FIREWORKS_API_KEY") if args.extract else None
    if args.extract and not fireworks_key:
        raise SystemExit("STYLEZAM_FIREWORKS_API_KEY is required with --extract")
    # Extraction is intentionally sequential to avoid provider bursts; page-only
    # validation can use bounded concurrency.
    workers = 1 if args.extract else min(8, max(1, args.workers))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        reports = list(pool.map(lambda row: benchmark_one(row, fireworks_key, args.model), manifest))
    summary = {
        "requested": len(manifest),
        "discovered": sum(bool(row.get("url")) for row in manifest),
        "reachable": sum(row.http_status == 200 for row in reports),
        "chart_text_ready": sum(row.status in {"chart_text_ready", "passed", "extraction_review"} for row in reports),
        "extracted": sum(row.extracted for row in reports),
        "grounded": sum(row.grounded for row in reports),
        "plausible": sum(row.plausible for row in reports),
        "passed": sum(row.status == "passed" for row in reports),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"summary": summary, "pages": [asdict(row) for row in reports]}, indent=2) + "\n")
    print(json.dumps(summary, sort_keys=True))
    return 0 if summary["requested"] >= 100 else 2


if __name__ == "__main__":
    raise SystemExit(main())
