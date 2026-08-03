from __future__ import annotations

import math
import re
import uuid
from difflib import SequenceMatcher
from typing import Dict, Iterable, List, Optional, Sequence, Set
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from ..providers.base import ProviderProduct
from ..schemas import MatchTier, VisualAttributes


TRACKING_QUERY_KEYS = {
    "affid",
    "campaign",
    "fbclid",
    "gclid",
    "ref",
    "source",
    "utm_campaign",
    "utm_content",
    "utm_medium",
    "utm_source",
    "utm_term",
}


def normalized_tokens(value: str) -> Set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9]+", value.lower())
        if len(token) > 1
    }


def lexical_similarity(title: str, query: str) -> float:
    if not query.strip():
        return 0.5
    title_tokens = normalized_tokens(title)
    query_tokens = normalized_tokens(query)
    overlap = len(title_tokens & query_tokens) / max(len(query_tokens), 1)
    sequence = SequenceMatcher(None, title.lower(), query.lower()).ratio()
    return max(0.0, min(1.0, overlap * 0.72 + sequence * 0.28))


def canonical_url(value: str) -> str:
    try:
        parts = urlsplit(value)
        query = [
            (key, item)
            for key, item in parse_qsl(parts.query, keep_blank_values=True)
            if key.lower() not in TRACKING_QUERY_KEYS
            and not key.lower().startswith("utm_")
        ]
        return urlunsplit(
            (parts.scheme.lower(), parts.netloc.lower(), parts.path.rstrip("/"), urlencode(query), "")
        )
    except ValueError:
        return value


def match_tier(score: float, source_exact: bool) -> MatchTier:
    if source_exact and score >= 0.76:
        return MatchTier.exact
    if score >= 0.73:
        return MatchTier.likely
    if score >= 0.54:
        return MatchTier.similar
    return MatchTier.inspired


def rank_products(
    *,
    search_id: str,
    products: Sequence[ProviderProduct],
    query: str,
    analysis: Optional[VisualAttributes],
    visual_scores: Optional[Sequence[Optional[float]]] = None,
    limit: int = 40,
) -> List[Dict[str, object]]:
    ranked: List[Dict[str, object]] = []
    for index, product in enumerate(products):
        lexical = lexical_similarity(product.title, query)
        visual = visual_scores[index] if visual_scores and index < len(visual_scores) else None
        if visual is None:
            score = product.source_score * 0.70 + lexical * 0.30
        else:
            score = product.source_score * 0.38 + visual * 0.48 + lexical * 0.14
        if product.source_exact:
            score += 0.08
        if analysis and analysis.brand and product.brand:
            if analysis.brand.lower() == product.brand.lower():
                score += 0.04
        score = max(0.0, min(1.0, score))
        url = canonical_url(product.product_url)
        stable_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "%s|%s|%s" % (search_id, product.provider, url)))
        offers = list(product.offers)
        if not offers and product.price:
            offers.append(
                {
                    "merchant": product.merchant,
                    "url": product.product_url,
                    "price": product.price.as_dict(),
                }
            )
        ranked.append(
            {
                "id": stable_id,
                "search_id": search_id,
                "provider": product.provider,
                "provider_result_id": product.provider_result_id,
                "title": product.title.strip(),
                "brand": product.brand,
                "category": product.category or (analysis.category if analysis else None),
                "color": product.color,
                "image_url": product.image_url,
                "product_url": product.product_url,
                "merchant": product.merchant,
                "price": product.price.as_dict() if product.price else None,
                "match_tier": match_tier(score, product.source_exact).value,
                "score": round(score, 5),
                "rating": product.rating,
                "review_count": product.review_count,
                "attributes": {
                    **product.attributes,
                    "sourceExact": product.source_exact,
                    "sourceScore": round(product.source_score, 5),
                    "lexicalScore": round(lexical, 5),
                    **({"visualScore": round(visual, 5)} if visual is not None else {}),
                },
                "offers": offers,
            }
        )
    ranked.sort(key=lambda item: float(item["score"]), reverse=True)
    return _deduplicate(ranked)[:limit]


def _deduplicate(rows: Iterable[Dict[str, object]]) -> List[Dict[str, object]]:
    kept: List[Dict[str, object]] = []
    keys: Set[str] = set()
    for row in rows:
        url_key = canonical_url(str(row["product_url"]))
        title_key = " ".join(sorted(normalized_tokens(str(row["title"]))))
        merchant_key = str(row["merchant"]).strip().lower()
        key = url_key or "%s|%s" % (merchant_key, title_key)
        if key in keys:
            continue
        # Merchant feeds sometimes vary only their tracking URL. Catch nearly identical listings.
        duplicate = False
        for existing in kept:
            if str(existing["merchant"]).strip().lower() != merchant_key:
                continue
            if SequenceMatcher(
                None,
                str(existing["title"]).lower(),
                str(row["title"]).lower(),
            ).ratio() >= 0.94:
                duplicate = True
                break
        if duplicate:
            continue
        keys.add(key)
        kept.append(row)
    return kept

