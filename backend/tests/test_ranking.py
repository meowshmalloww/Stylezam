from stylezam_api.providers.base import ProviderPrice, ProviderProduct
from stylezam_api.services.ranking import canonical_url, rank_products


def test_tracking_parameters_are_removed() -> None:
    assert (
        canonical_url("https://SHOP.example/item/1?utm_source=x&size=m")
        == "https://shop.example/item/1?size=m"
    )


def test_exact_provider_evidence_can_produce_exact_tier() -> None:
    products = [
        ProviderProduct(
            provider="lens",
            title="Acme black leather moto jacket",
            product_url="https://shop.example/jacket",
            merchant="Shop",
            price=ProviderPrice(199, "USD", "$199"),
            source_score=0.9,
            source_exact=True,
        )
    ]

    ranked = rank_products(
        search_id="search-1",
        products=products,
        query="Acme black leather moto jacket",
        analysis=None,
    )

    assert ranked[0]["match_tier"] == "exact"
    assert ranked[0]["score"] > 0.8

