# Providers and hard limits

Checked against official vendor information on 2026-08-03. Vendor pricing, quotas, models, and retention can change; confirm the linked source before deployment.

## Provider roles

Stylezam keeps product retrieval and image understanding separate. A vision model extracts factual garment attributes; it does not manufacture shopping results. SerpApi and eBay remain backend-managed retrieval infrastructure, while OpenAI, Fireworks, and Qwen are interchangeable backend-only image-understanding routes.

| Layer | Provider | Role | Stylezam default hard stop |
|---|---|---|---|
| Product text + image retrieval | SerpApi Shopping/Lens | Structured shopping and visual-search records | 250 calls per UTC month |
| Secondary retrieval | eBay Browse | Keyword and Base64 image search against real listings | 5,000 calls per UTC month |
| Image understanding | OpenAI Responses API | Structured visual attributes from image input | 100 calls per UTC month |
| Image understanding fallback | Fireworks AI | OpenAI-compatible multimodal chat with JSON Schema output | 100 calls per UTC month |
| Image understanding fallback | Qwen Model Studio | OpenAI-compatible visual chat completion | 100 calls per UTC month |
| Segmentation/reranking | Grounding DINO + SAM2 + CLIP | Optional GPU-backed detection, masking, and similarity | Local inference |
| Virtual try-on | YouCam AI Clothes v3 | Optional asynchronous appearance preview | 20 jobs per UTC month |

OpenAI’s current model catalog says the latest GPT-5.6 family accepts image input and supports structured outputs. Stylezam defaults to the cost-sensitive `gpt-5.6-luna` route and uses the Responses API: [OpenAI model catalog](https://developers.openai.com/api/docs/models), [model comparison](https://developers.openai.com/api/docs/models/compare).

Fireworks documents image URL and Base64 data-URL inputs through its OpenAI-compatible Chat Completions endpoint. It also supports JSON Schema response formatting. Stylezam defaults to the documented vision example model `accounts/fireworks/models/kimi-k2p5`: [Fireworks vision models](https://docs.fireworks.ai/guides/querying-vision-language-models), [structured outputs](https://docs.fireworks.ai/structured-responses/structured-response-formatting).

Qwen Model Studio documents OpenAI-compatible Chat Completions with mixed text and `image_url` content, including Base64 data URLs. The base URL depends on the account’s region; the repository defaults to the US endpoint and `qwen3.7-plus`: [Qwen vision models](https://www.alibabacloud.com/help/en/model-studio/vision-model), [OpenAI-compatible Chat Completions](https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions).

These Stylezam caps are local safety limits, not claims about vendor billing. Set them at or below the maximum number of calls you intend to permit. A cap prevents more Stylezam requests after it is reached; it does not change a provider account’s plan or protect calls made outside Stylezam.

## Vision fallback order

For an image search, Stylezam tries configured providers in this order:

1. OpenAI
2. Fireworks AI
3. Qwen

Each attempted request atomically claims one call from that provider’s separate cap. If a configured provider fails or has reached its cap, the pipeline records a warning and continues to the next configured route. Local Grounding DINO/SAM2 detection can run before hosted understanding, and its detected boxes are merged into the successful provider’s structured attributes.

## Configure credentials and caps

```dotenv
STYLEZAM_OPENAI_API_KEY=
STYLEZAM_OPENAI_VISION_MODEL=gpt-5.6-luna
STYLEZAM_OPENAI_MONTHLY_CAP=100

STYLEZAM_FIREWORKS_API_KEY=
STYLEZAM_FIREWORKS_VISION_MODEL=accounts/fireworks/models/kimi-k2p5
STYLEZAM_FIREWORKS_MONTHLY_CAP=100

STYLEZAM_QWEN_API_KEY=
STYLEZAM_QWEN_VISION_MODEL=qwen3.7-plus
STYLEZAM_QWEN_MONTHLY_CAP=100

STYLEZAM_SERPAPI_API_KEY=
STYLEZAM_SERPAPI_MONTHLY_CAP=250
STYLEZAM_EBAY_CLIENT_ID=
STYLEZAM_EBAY_CLIENT_SECRET=
STYLEZAM_EBAY_MONTHLY_CAP=5000

STYLEZAM_YOUCAM_API_KEY=
STYLEZAM_YOUCAM_MONTHLY_CAP=20
```

All keys stay on the backend. Never put them in the Xcode project, an `.xcconfig` committed to source control, or the iPhone app bundle. The iPhone Developer Debug page edits only the Stylezam backend address and optional service token; it reads provider capability status without receiving provider secrets.

The usage ledger lives in `backend/.data/stylezam.sqlite3`. Claims are atomic, periods reset on the first request in a new UTC calendar month, and a cap of `0` blocks that route even when credentials are present.

## Retrieval and try-on notes

SerpApi currently advertises fixed monthly search tiers, and eBay documents Browse keyword and image retrieval. These providers remain deployment infrastructure, so their names and credentials are intentionally absent from consumer Settings: [SerpApi pricing](https://serpapi.com/pricing), [eBay Browse overview](https://developer.ebay.com/api-docs/buy/static/api-browse.html).

SerpApi Lens must fetch the search image from an HTTPS URL. Set `STYLEZAM_PUBLIC_BASE_URL` to the public origin of the backend. eBay image search sends Base64 image content and does not need public ingress.

Perfect Corp documents AI Clothes v3 as upload, task-create, and task-poll operations. Stylezam keeps YouCam optional and reports it only in Developer Debug until enabled. The local cap counts submitted jobs rather than provider units: [AI Clothes v3 documentation](https://docs.perfectcorp.com/reference/ai_clothes/section/overview), [YouCam API FAQ](https://docs.perfectcorp.com/develop/faq).
