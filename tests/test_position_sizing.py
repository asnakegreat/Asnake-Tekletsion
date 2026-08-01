from app.position_sizing import calculate_position_size
import pytest


def test_basic_size():
    size = calculate_position_size(10000, 0.01, 1.0895, 1.087)
    # risk_amount = 100, stop_distance = 0.0025 -> size = 40000
    assert pytest.approx(size, rel=1e-3) == 40000


def test_invalid_balance():
    with pytest.raises(ValueError):
        calculate_position_size(0, 0.01, 1.1, 1.09)


def test_invalid_risk():
    with pytest.raises(ValueError):
        calculate_position_size(10000, 1.5, 1.1, 1.09)


def test_zero_stop_distance():
    with pytest.raises(ValueError):
        calculate_position_size(10000, 0.01, 1.1, 1.1)
