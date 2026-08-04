# Dependency audit

Audit date: 2026-08-03.

## Results

- `pip install --require-hashes --no-deps -r backend/requirements.lock` succeeded under Python 3.12.
- `pip-audit 2.x` reported: `No known vulnerabilities found` for all fully pinned entries in the lock file.
- Package metadata contained no GPL, AGPL, SSPL, noncommercial, or unknown license expression.
- The Core ML pack passed its independent path, byte-count, SHA-256, class-order, source-hash, and license-field verification.

`--no-deps` is correct for this audit because `pip-compile` already resolved and hash-pinned the full transitive graph; it avoids resolving a second, platform-dependent graph during the audit.

## Resolved Python licenses

| Package | Version | Declared expression |
| --- | ---: | --- |
| annotated-doc | 0.0.5 | MIT |
| annotated-types | 0.8.0 | MIT |
| anyio | 4.14.2 | MIT |
| certifi | 2026.7.22 | MPL-2.0 |
| click | 8.4.2 | BSD-3-Clause |
| fastapi | 0.141.1 | MIT |
| h11 | 0.16.0 | MIT |
| httpcore | 1.0.9 | BSD-3-Clause |
| httpx | 0.28.1 | BSD-3-Clause |
| idna | 3.18 | BSD-3-Clause |
| pillow | 12.3.0 | MIT-CMU |
| pydantic | 2.13.4 | MIT |
| pydantic-core | 2.46.4 | MIT |
| pydantic-settings | 2.14.2 | MIT |
| python-dotenv | 1.2.2 | BSD-3-Clause |
| python-multipart | 0.0.32 | Apache-2.0 |
| starlette | 1.3.1 | BSD-3-Clause |
| typing-extensions | 4.16.0 | PSF-2.0 |
| typing-inspection | 0.4.2 | MIT |
| uvicorn | 0.52.1 | BSD-3-Clause |

## Remaining image-level check

This Mac does not currently have Docker or an authenticated Daytona CLI, so the final built Linux image could not be scanned here. The Dockerfile pins its Python base image by digest and avoids OS package installation, but that does not prove the Debian base layers have zero known CVEs. Run Daytona’s final image scan (or Trivy/Grype against the built image) immediately after the first authenticated build and before treating the image as release-clean.

Vulnerability databases change continuously. Re-run the audit whenever the lock file or base-image digest changes and immediately before distribution.
