from scripts import capacity_forecast as cf
from scripts import wifi_survey_report as wifi


def test_survey_flags_floor2_top_left():
    rows = wifi.load(wifi.Path("network/wireless/site-survey-results.csv"))
    s = wifi.summarise(rows)
    assert not s["passed"]
    assert [r["area"] for r in s["failing"]] == ["Top Left"]
    assert s["floors"][1]["worst_rssi"] == -67


def test_classify():
    assert wifi.classify(-55) == "Excellent"
    assert wifi.classify(-67) == "Good"
    assert wifi.classify(-70) == "Moderate"
    assert wifi.classify(-80) == "Poor"


def test_linear_fit_exact():
    slope, intercept = cf.linear_fit([10, 20, 30, 40])
    assert slope == 10 and intercept == 10


def test_months_until():
    assert cf.months_until([10, 20, 30], 60) == 3
    assert cf.months_until([10, 10, 10], 60) is None
    assert cf.months_until([10, 70], 60) == 0


def test_add_months_rolls_year():
    assert cf.add_months(cf.date(2026, 11, 1), 3) == cf.date(2027, 2, 1)
