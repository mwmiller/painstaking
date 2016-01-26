defmodule PainStakingTest do
  use ExUnit.Case
  doctest PainStaking

  test "single kelly" do
    no_edge     = {"no edge",     [prob: "0.50"], [us: -110]}
    small_edge  = {"small edge",  [prob: 0.55],   [us: -120]}
    decent_edge = {"decent edge", [prob: 0.55],   [us: "-110"]}
    no_payout   = {"no payout",   [prob: 1],      [eu: 0]}

    assert PainStaking.kelly([no_edge]) == {:error, "No suitable positive expectation edges found."}, "No recommended bet for non-advantage situations"
    assert PainStaking.kelly([small_edge]) == {:ok, [{"small edge", 1.00}]}, "Small bets for small edges"
    assert PainStaking.kelly([decent_edge]) == {:ok, [{"decent edge", 5.50}]}, "Bet a bit with decent return"
    assert PainStaking.kelly([no_payout]) == {:error, "No suitable positive expectation edges found."}, "Never bet if we won't get paid."
  end

  test "many horses" do
    chalk = {"chalk", [prob: 0.75], [uk: "3/5"]}
    stalk = {"stalk", [prob: 0.20], [uk: "7/2"]}
    dark  = {"dark", [prob: 0.04], [uk: "30/1"]}
    glue  = {"glue", [prob: 0.01], [uk: "100/1"]}

    assert PainStaking.kelly([chalk, stalk, dark, glue]) == {:ok, [{"dark", 4.00}, {"chalk", 75.00}, {"glue", 1.00}, {"stalk", 20.00}]}, "stalking horse is included"
    assert PainStaking.kelly([stalk]) == {:error, "No suitable positive expectation edges found."}, "Even though it is negative EV when considered alone"
    assert PainStaking.kelly([chalk, dark, glue]) == {:ok, [{"dark", 2.06}, {"chalk", 37.44}, {"glue", 0.41}]}, "Leaving it off wildly changes the results"
    assert PainStaking.kelly([chalk, stalk, dark]) == {:ok, [{"dark", 3.73}, {"chalk", 69.81}, {"stalk", 18.16}]}, "Where dropping a positive EV unlikely winner is less dramatic"
  end
  test "simultaneous independent" do
    # Events from the Whitrow, 2007 paper plus 13 as a negative EV example
    events = [ {"1", [prob: 0.470], [eu: 2.50]},
               {"2", [prob: 0.530], [eu: 2.00]},
               {"3", [prob: 0.480], [eu: 2.20]},
               {"4", [prob: 0.310], [eu: 3.50]},
               {"5", [prob: 0.255], [eu: 4.33]},
               {"6", [prob: 0.270], [eu: 4.00]},
               {"7", [prob: 0.270], [eu: 4.00]},
               {"8", [prob: 0.311], [eu: 3.40]},
               {"9", [prob: 0.310], [eu: 3.40]},
              {"10", [prob: 0.466], [eu: 2.20]},
              {"11", [prob: 0.371], [eu: 2.70]},
              {"12", [prob: 0.304], [eu: 3.30]},
              {"13", [prob: 0.204], [eu: 3.30]},
             ]

    assert PainStaking.kelly(events, [independent: true]) == {:ok, [{"1", 11.67}, {"2", 6.0}, {"3", 4.67}, {"4", 3.4}, {"5", 3.13}, {"6", 2.67}, {"7", 2.67}, {"8", 2.39}, {"9", 2.25}, {"10", 2.1}, {"11", 0.1}, {"12", 0.14}]}, "Naive kelly sizing without algorithm"
  end

  test "simple arb" do
    no_arb_error = {:error, "No arbitrage exists for these events."}
    assert PainStaking.arb([[us: "-110"]]) ==  no_arb_error, "No arbitrage exists on a single outcome"
    assert PainStaking.arb([[us: "-110"], [us: "-110"]]) ==  no_arb_error, "Standard US odds exhibit no arbitrage"
    assert PainStaking.arb([[us: "-107"], [us: "+110"]]) ==  {:ok, [51.69, 47.62], 0.69}, "Can make a small profit on small arbitrage"
    assert PainStaking.arb([[us: "-161"], [us: "+350"], [us: "+632"]]) ==  {:ok, [61.69, 22.22, 13.66], 2.43}, "Multi-ways are harder to spot so may exhibit more profit"
  end

  test "simple sim_win" do
    small_edge = {"small edge", [prob: "0.55"], [us: -110]}
    unlikely = {"prolly not", [prob: 0.05], [uk: "30/1"]}
    always_win = {"always win", [prob: 1], [us: -110]}
    always_lose = {"always lose", [prob: 0], [us: -110]}

    {:ok, win} = PainStaking.sim_win([small_edge], 100, [independent: true])
    assert win <= 1.00, "A small edge on a small bankroll cannot make a ton of money"
    {:ok, win} = PainStaking.sim_win([unlikely, small_edge], 100, [independent: true])
    assert win <= 50.00, "Bigger variance when you include an unlikely result"
    {:ok, win} = PainStaking.sim_win([unlikely, small_edge], 100, [independent: false])
    assert win <= 5.00, "Mutally exclusive is somewhat different"
    assert PainStaking.sim_win([always_win], 1, [independent: true]) == {:ok, 90.91}, "If the result is known, you get full value."
    assert PainStaking.sim_win([always_win], 100, [independent: true]) == {:ok, 90.91}, "Even when you repeat it many times"
    assert PainStaking.sim_win([always_win, always_lose], 100, [independent: true]) == {:ok, 90.91}, "Same when you add one which cannot win"
  end

  test "simple ev" do
    neg_ev = {"no edge", [prob: "0.50"], [us: -110]}
    pos_ev = {"small edge", [prob: "0.55"], [us: -110]}

    assert PainStaking.ev([neg_ev, pos_ev]) == {:ok, [{"no edge", 95.45454545454545}, {"small edge", 105.00}]}, "Difference from 100 is the expected win"
  end
end
