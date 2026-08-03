from __future__ import annotations

import json
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def dump_json(value: Any) -> Optional[str]:
    if value is None:
        return None
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def load_json(value: Optional[str], default: Any) -> Any:
    if not value:
        return default
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return default


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.RLock()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(str(self.path), timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        return connection

    def initialize(self) -> None:
        schema = """
        CREATE TABLE IF NOT EXISTS search_jobs (
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            phase TEXT NOT NULL,
            progress REAL NOT NULL,
            query TEXT,
            input_media_path TEXT,
            input_image_url TEXT,
            selected_region_json TEXT,
            analysis_json TEXT,
            provider_warnings_json TEXT NOT NULL DEFAULT '[]',
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_search_jobs_created_at ON search_jobs(created_at DESC);

        CREATE TABLE IF NOT EXISTS search_results (
            id TEXT PRIMARY KEY,
            search_id TEXT NOT NULL REFERENCES search_jobs(id) ON DELETE CASCADE,
            provider TEXT NOT NULL,
            provider_result_id TEXT,
            title TEXT NOT NULL,
            brand TEXT,
            category TEXT,
            color TEXT,
            image_url TEXT,
            product_url TEXT NOT NULL,
            merchant TEXT NOT NULL,
            price_amount REAL,
            price_currency TEXT,
            price_display TEXT,
            match_tier TEXT NOT NULL,
            score REAL NOT NULL,
            rating REAL,
            review_count INTEGER,
            attributes_json TEXT NOT NULL DEFAULT '{}',
            offers_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_search_results_search_score
          ON search_results(search_id, score DESC);

        CREATE TABLE IF NOT EXISTS tryon_jobs (
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            phase TEXT NOT NULL,
            progress REAL NOT NULL,
            person_media_path TEXT NOT NULL,
            person_image_url TEXT NOT NULL,
            product_image_url TEXT NOT NULL,
            garment_category TEXT NOT NULL,
            result_image_url TEXT,
            provider_task_id TEXT,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_tryon_jobs_created_at ON tryon_jobs(created_at DESC);

        CREATE TABLE IF NOT EXISTS provider_usage (
            provider TEXT NOT NULL,
            period TEXT NOT NULL,
            used INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (provider, period)
        );
        """
        with self._lock, self.connect() as connection:
            connection.executescript(schema)

    def create_search(
        self,
        *,
        job_id: str,
        query: Optional[str],
        input_media_path: Optional[str],
        input_image_url: Optional[str],
        selected_region: Optional[Dict[str, Any]],
    ) -> None:
        now = utc_now()
        with self._lock, self.connect() as connection:
            connection.execute(
                """
                INSERT INTO search_jobs (
                    id, status, phase, progress, query, input_media_path,
                    input_image_url, selected_region_json, created_at, updated_at
                ) VALUES (?, 'queued', 'queued', 0, ?, ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    query,
                    input_media_path,
                    input_image_url,
                    dump_json(selected_region),
                    now,
                    now,
                ),
            )

    def update_search(self, job_id: str, **values: Any) -> None:
        allowed = {
            "status",
            "phase",
            "progress",
            "analysis_json",
            "provider_warnings_json",
            "error_code",
            "error_message",
        }
        unknown = set(values) - allowed
        if unknown:
            raise ValueError("Unknown search fields: %s" % ", ".join(sorted(unknown)))
        values["updated_at"] = utc_now()
        assignments = ", ".join("%s = ?" % key for key in values)
        parameters = list(values.values()) + [job_id]
        with self._lock, self.connect() as connection:
            connection.execute(
                "UPDATE search_jobs SET %s WHERE id = ?" % assignments,
                parameters,
            )

    def get_search(self, job_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT j.*, COUNT(r.id) AS result_count
                FROM search_jobs j
                LEFT JOIN search_results r ON r.search_id = j.id
                WHERE j.id = ?
                GROUP BY j.id
                """,
                (job_id,),
            ).fetchone()
        return self._search_row(row) if row else None

    def get_search_internal(self, job_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM search_jobs WHERE id = ?", (job_id,)
            ).fetchone()
        if not row:
            return None
        value = dict(row)
        value["selected_region"] = load_json(value.get("selected_region_json"), None)
        value["analysis"] = load_json(value.get("analysis_json"), None)
        value["provider_warnings"] = load_json(
            value.get("provider_warnings_json"), []
        )
        return value

    def list_recoverable_searches(self) -> List[str]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT id FROM search_jobs WHERE status IN ('queued', 'processing')"
            ).fetchall()
        return [str(row["id"]) for row in rows]

    def replace_results(self, search_id: str, results: Iterable[Dict[str, Any]]) -> None:
        with self._lock, self.connect() as connection:
            connection.execute("DELETE FROM search_results WHERE search_id = ?", (search_id,))
            for result in results:
                price = result.get("price") or {}
                connection.execute(
                    """
                    INSERT INTO search_results (
                        id, search_id, provider, provider_result_id, title, brand,
                        category, color, image_url, product_url, merchant,
                        price_amount, price_currency, price_display, match_tier,
                        score, rating, review_count, attributes_json, offers_json,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        result["id"],
                        search_id,
                        result["provider"],
                        result.get("provider_result_id"),
                        result["title"],
                        result.get("brand"),
                        result.get("category"),
                        result.get("color"),
                        result.get("image_url"),
                        result["product_url"],
                        result["merchant"],
                        price.get("amount"),
                        price.get("currency"),
                        price.get("display"),
                        result["match_tier"],
                        result["score"],
                        result.get("rating"),
                        result.get("review_count"),
                        dump_json(result.get("attributes") or {}),
                        dump_json(result.get("offers") or []),
                        utc_now(),
                    ),
                )

    def get_results(self, search_id: str) -> List[Dict[str, Any]]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT * FROM search_results WHERE search_id = ? ORDER BY score DESC",
                (search_id,),
            ).fetchall()
        return [self._result_row(row) for row in rows]

    def delete_search(self, job_id: str) -> Optional[str]:
        with self._lock, self.connect() as connection:
            row = connection.execute(
                "SELECT input_media_path FROM search_jobs WHERE id = ?", (job_id,)
            ).fetchone()
            if not row:
                return None
            connection.execute("DELETE FROM search_jobs WHERE id = ?", (job_id,))
        value = row["input_media_path"]
        return str(value) if value else ""

    def create_tryon(
        self,
        *,
        job_id: str,
        person_media_path: str,
        person_image_url: str,
        product_image_url: str,
        garment_category: str,
    ) -> None:
        now = utc_now()
        with self._lock, self.connect() as connection:
            connection.execute(
                """
                INSERT INTO tryon_jobs (
                    id, status, phase, progress, person_media_path, person_image_url,
                    product_image_url, garment_category, created_at, updated_at
                ) VALUES (?, 'queued', 'queued', 0, ?, ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    person_media_path,
                    person_image_url,
                    product_image_url,
                    garment_category,
                    now,
                    now,
                ),
            )

    def update_tryon(self, job_id: str, **values: Any) -> None:
        allowed = {
            "status",
            "phase",
            "progress",
            "result_image_url",
            "provider_task_id",
            "error_code",
            "error_message",
        }
        unknown = set(values) - allowed
        if unknown:
            raise ValueError("Unknown try-on fields: %s" % ", ".join(sorted(unknown)))
        values["updated_at"] = utc_now()
        assignments = ", ".join("%s = ?" % key for key in values)
        parameters = list(values.values()) + [job_id]
        with self._lock, self.connect() as connection:
            connection.execute(
                "UPDATE tryon_jobs SET %s WHERE id = ?" % assignments,
                parameters,
            )

    def get_tryon(self, job_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM tryon_jobs WHERE id = ?", (job_id,)
            ).fetchone()
        return dict(row) if row else None

    def delete_tryon(self, job_id: str) -> Optional[Dict[str, Any]]:
        with self._lock, self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM tryon_jobs WHERE id = ?", (job_id,)
            ).fetchone()
            if not row:
                return None
            connection.execute("DELETE FROM tryon_jobs WHERE id = ?", (job_id,))
        return dict(row)

    def list_recoverable_tryons(self) -> List[str]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT id FROM tryon_jobs WHERE status IN ('queued', 'processing')"
            ).fetchall()
        return [str(row["id"]) for row in rows]

    def claim_provider_call(self, provider: str, monthly_cap: int) -> bool:
        if monthly_cap <= 0:
            return False
        period = datetime.now(timezone.utc).strftime("%Y-%m")
        with self._lock, self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT used FROM provider_usage WHERE provider = ? AND period = ?",
                (provider, period),
            ).fetchone()
            used = int(row["used"]) if row else 0
            if used >= monthly_cap:
                connection.rollback()
                return False
            connection.execute(
                """
                INSERT INTO provider_usage (provider, period, used, updated_at)
                VALUES (?, ?, 1, ?)
                ON CONFLICT(provider, period) DO UPDATE SET
                    used = used + 1,
                    updated_at = excluded.updated_at
                """,
                (provider, period, utc_now()),
            )
            connection.commit()
        return True

    def provider_usage(self, provider: str) -> int:
        period = datetime.now(timezone.utc).strftime("%Y-%m")
        with self.connect() as connection:
            row = connection.execute(
                "SELECT used FROM provider_usage WHERE provider = ? AND period = ?",
                (provider, period),
            ).fetchone()
        return int(row["used"]) if row else 0

    @staticmethod
    def _search_row(row: sqlite3.Row) -> Dict[str, Any]:
        value = dict(row)
        value["selected_region"] = load_json(value.pop("selected_region_json"), None)
        value["analysis"] = load_json(value.pop("analysis_json"), None)
        value["provider_warnings"] = load_json(
            value.pop("provider_warnings_json"), []
        )
        value.pop("input_media_path", None)
        return value

    @staticmethod
    def _result_row(row: sqlite3.Row) -> Dict[str, Any]:
        value = dict(row)
        price = None
        if value.get("price_amount") is not None and value.get("price_currency"):
            price = {
                "amount": value.pop("price_amount"),
                "currency": value.pop("price_currency"),
                "display": value.pop("price_display"),
            }
        else:
            value.pop("price_amount", None)
            value.pop("price_currency", None)
            value.pop("price_display", None)
        value["price"] = price
        value["attributes"] = load_json(value.pop("attributes_json"), {})
        value["offers"] = load_json(value.pop("offers_json"), [])
        value.pop("created_at", None)
        return value
