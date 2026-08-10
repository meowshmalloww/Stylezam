# Fit and measurements validation

## Scope

The August 9, 2026 qualification used live merchant pages rather than synthetic
JSON fixtures. It had three deliberately separate passes:

1. a breadth pass across the first 100 brands in the benchmark catalog;
2. a 350-page discovery/fetch pass to measure real-world bot and JavaScript
   failure behavior; and
3. a deterministic 100-page extraction corpus of official, localized Nike size
   guides across men's, women's, and children's categories.

The breadth pass discovered 95 of 100 brand pages, fetched 47, and retained
usable chart text from 33. Expanding discovery to 350 candidate merchant pages
fetched 175 and retained chart text from 122. These are availability results,
not extraction accuracy: many merchants block ordinary server fetches or render
the chart only in client JavaScript.

## Findings and fixes

All 100 pages in the deterministic extraction corpus returned HTTP 200. The
first full extraction run exposed a real failure boundary: 67 large charts hit
the 3,000-token Fireworks output ceiling, 33 produced structured charts, and 26
passed both literal-number grounding and physical plausibility checks.

That result led to production changes rather than a relaxed benchmark:

- the prompt selects one product-relevant chart and returns at most 20
  contiguous rows instead of combining regions, genders, ages, or categories;
- structured extraction disables reasoning and has a 5,000-token ceiling;
- unsupported JSON Schema array-size keywords were removed;
- flat one-side garment widths are distinguished from full circumferences and
  only chest, waist, and hip flat widths are doubled;
- every extracted measurement must occur literally in retained merchant text,
  or equal the midpoint of a literal published range;
- converted values outside dimension-specific physical ranges are discarded;
- the UI calls the score a **measurement match**, not proof of fit.

The focused post-fix regression re-runs pages that previously ended at the
output ceiling. Its final result is recorded below by the verification run.

| Regression | Reachable | Structured | Grounded | Plausible | Accepted |
|---|---:|---:|---:|---:|---:|
| Former output-limit pages (10) | 10 | 10 | 4 | 10 | 4 |

The six rejected charts returned plausible-looking measurement numbers that
could not be reproduced from the retained merchant evidence. Production now
rejects that entire extraction rather than showing a confident recommendation.

## Reproduce

The tool reads ignored environment variables and never writes a credential to
its report. Page-only validation can run concurrently; Fireworks extraction is
intentionally sequential.

```bash
python3 scripts/benchmark_fit_merchants.py \
  --discover \
  --manifest /tmp/stylezam-fit-pages.json \
  --output /tmp/stylezam-fit-fetch-report.json \
  --limit 100 \
  --page-limit 350

python3 scripts/benchmark_fit_merchants.py \
  --manifest /tmp/stylezam-fit-pages.json \
  --output /tmp/stylezam-fit-extraction-report.json \
  --extract \
  --page-limit 100 \
  --model accounts/fireworks/models/qwen3p7-plus
```

## Boundary

This benchmark verifies page access, structured extraction, numerical
grounding, unit handling, and plausibility. It does not prove that a merchant's
published chart is correct, that two brands grade sizes consistently, or that a
recommended garment will fit a particular body. Stylezam therefore preserves
the source link and evidence basis and presents the result as guidance.
