# Providers and hard limits

Checked against official vendor information on 2026-08-03. Vendor plans and policies can change; follow the linked source before purchasing.

## Recommended search stack

| Layer | Provider | Why it is here | Vendor limit model | Stylezam default hard stop |
|---|---|---|---|---|
| Product text + image retrieval | SerpApi Shopping/Lens | Broad structured shopping results and Lens visual matches | Fixed searches per month; a free monthly allocation is available | 250 API calls per UTC calendar month |
| Second retrieval source | eBay Browse | Real listings, keyword search, and Base64 image search | Default application call quota | 5,000 API calls per UTC calendar month |
| Image understanding | Ollama `gemma3:4b` | Local factual attributes and visible text | Local hardware; no API call bill | No external cap needed |
| Segmentation/reranking | Grounding DINO + SAM2 + CLIP | Local object isolation and visual comparison | Local hardware; no API call bill | No external cap needed |
| Virtual try-on | YouCam AI Clothes v3 | Fashion-specific asynchronous try-on | Pre-purchased units; feature costs vary | 20 submitted jobs per UTC calendar month |

SerpApi currently advertises a free 250-search monthly plan and fixed monthly tiers. Only successful searches count according to its pricing FAQ. If avoiding variable charges is important, leave automatic early renewal disabled in the provider account and keep Stylezam’s cap at or below the plan allocation: [SerpApi plans and pricing](https://serpapi.com/pricing).

eBay documents keyword and image retrieval in Browse API and currently lists a default 5,000-call-per-day Browse API quota. Buy APIs require an additional license, so approval—not cost—is the main external constraint: [Browse API overview](https://developer.ebay.com/api-docs/buy/static/api-browse.html), [API call limits](https://developer.ebay.com/develop/get-started/api-call-limits).

Perfect Corp documents AI Clothes v3 as a file-upload, task-create, task-poll flow. Its unit system is prepaid and different operations can deduct different unit amounts; therefore Stylezam’s cap counts submitted try-on jobs, not vendor units. Set the cap conservatively after checking the feature cost in the YouCam dashboard: [AI Clothes v3 documentation](https://docs.perfectcorp.com/reference/ai_clothes/section/overview), [YouCam API FAQ](https://docs.perfectcorp.com/develop/faq).

The published Clothes v3 OpenAPI operations currently contain no early-delete call. Perfect Corp’s June 2026 API terms state that user submissions are automatically deleted after one day and generated content after 30 days. Stylezam therefore removes its own server copies promptly but documents the provider retention instead of pretending to delete data it cannot address: [YouCam API terms](https://www.perfectcorp.com/perfectbeauty/youcam/terms-of-service-api).

Ollama accepts images through its local API. The implemented adapter uses structured output and defaults to `gemma3:4b`: [Ollama vision documentation](https://docs.ollama.com/capabilities/vision).

## Configure caps

```dotenv
STYLEZAM_SERPAPI_MONTHLY_CAP=250
STYLEZAM_EBAY_MONTHLY_CAP=5000
STYLEZAM_YOUCAM_MONTHLY_CAP=20
```

The ledger lives in `backend/.data/stylezam.sqlite3`. Claims are atomic, so simultaneous jobs cannot exceed the configured local cap. Periods reset naturally on the first request in a new UTC calendar month. Set a cap to `0` to block that provider entirely even if credentials are present.

For a combined text-and-image request, Stylezam may call both SerpApi Shopping and Lens, consuming two SerpApi calls. eBay keyword and image routes are counted separately for the same reason. A YouCam job claims its local slot before the person photo is uploaded.

The Settings screen reads live usage from `GET /v1/capabilities`. Reaching a cap produces `monthly_cap_reached`; Stylezam does not fall through to invented results.

## Credential variables

```dotenv
STYLEZAM_SERPAPI_API_KEY=
STYLEZAM_EBAY_CLIENT_ID=
STYLEZAM_EBAY_CLIENT_SECRET=
STYLEZAM_YOUCAM_API_KEY=
```

All keys stay on the backend. Never put them in the Xcode project, an `.xcconfig` committed to source control, or the iPhone app bundle.

## Public image ingress

SerpApi Lens must fetch the search image from an HTTPS URL. Set `STYLEZAM_PUBLIC_BASE_URL` to the public origin of the backend. eBay image search sends a Base64 image in the API request and does not need public ingress. Text search works without a public media URL.

Use a protected production deployment. A temporary HTTPS tunnel is appropriate only for development because anyone with the generated media URL can fetch that image while the tunnel and file exist.
