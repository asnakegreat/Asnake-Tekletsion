def calculate_position_size(account_balance: float, risk_percent: float, entry: float, stop: float) -> float:
    """
    Simplified position size calculation (units) for demo purposes.

    size = risk_amount / stop_distance
    where risk_amount = account_balance * risk_percent
    and stop_distance = abs(entry - stop)

    Returns a floating point number representing units (not lots).
    """
    if account_balance <= 0:
        raise ValueError("account_balance must be positive")
    if not (0 < risk_percent < 1):
        raise ValueError("risk_percent must be between 0 and 1")
    stop_distance = abs(entry - stop)
    if stop_distance <= 0:
        raise ValueError("stop distance must be positive")
    risk_amount = account_balance * risk_percent
    size = risk_amount / stop_distance
    return size
