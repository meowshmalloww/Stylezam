from pathlib import Path

from stylezam_api.database import Database


def test_search_and_results_round_trip(tmp_path: Path) -> None:
    database = Database(tmp_path / "stylezam.sqlite3")
    database.initialize()
    database.create_search(
        job_id="search-1",
        query="black leather jacket",
        input_media_path=None,
        input_image_url=None,
        selected_region=None,
    )
    database.replace_results(
        "search-1",
        [
            {
                "id": "result-1",
                "provider": "provider",
                "title": "Leather jacket",
                "product_url": "https://shop.example/jacket",
                "merchant": "Shop",
                "price": {"amount": 120.0, "currency": "USD", "display": "$120"},
                "match_tier": "likely",
                "score": 0.8,
                "attributes": {"sourceExact": False},
                "offers": [],
            }
        ],
    )

    search = database.get_search("search-1")
    results = database.get_results("search-1")

    assert search is not None
    assert search["result_count"] == 1
    assert results[0]["price"]["amount"] == 120.0
    assert results[0]["attributes"]["sourceExact"] is False

