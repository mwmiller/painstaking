defmodule PainStakingTest do
  use PowerAssert
  import PainStaking
  doctest PainStaking

  test "single kelly" do
    no_edge     = {"no edge",     [prob: "0.50"], [us: -110]}
    small_edge  = {"small edge",  [prob: 0.55],   [us: -120]}
    decent_edge = {"decent edge", [prob: 0.55],   [us: "-110"]}
    no_payout   = {"no payout",   [prob: 1],      [eu: 0]}

    assert kelly([no_edge]) == {:error, "No suitable positive expectation edges found."}, "No recommended bet for non-advantage situations"
    assert kelly([small_edge]) == {:ok, [{"small edge", 1.00}]}, "Small bets for small edges"
    assert kelly([decent_edge]) == {:ok, [{"decent edge", 5.50}]}, "Bet a bit with decent return"
    assert kelly([no_payout]) == {:error, "No suitable positive expectation edges found."}, "Never bet if we won't get paid."
  end

  test "many horses kelly" do
    chalk = {"chalk", [prob: 0.75], [uk: "3/5"]}
    stalk = {"stalk", [prob: 0.20], [uk: "7/2"]}
    dark  = {"dark", [prob: 0.04], [uk: "30/1"]}
    glue  = {"glue", [prob: 0.01], [uk: "100/1"]}

    assert kelly([chalk, stalk, dark, glue]) == {:ok, [{"dark", 4.00}, {"chalk", 75.00}, {"glue", 1.00}, {"stalk", 20.00}]}, "stalking horse is included"
    assert kelly([stalk]) == {:error, "No suitable positive expectation edges found."}, "Even though it is negative EV when considered alone"
    assert kelly([chalk, dark, glue]) == {:ok, [{"dark", 2.06}, {"chalk", 37.44}, {"glue", 0.41}]}, "Leaving it off wildly changes the results"
    assert kelly([chalk, stalk, dark]) == {:ok, [{"dark", 3.73}, {"chalk", 69.81}, {"stalk", 18.16}]}, "Where dropping a positive EV unlikely winner is less dramatic"
  end

  test "simultaneous independent kelly" do
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

    assert kelly(events, [independent: true]) == {:ok, [{"1", 11.67}, {"2", 6.0}, {"3", 4.67}, {"4", 3.4}, {"5", 3.13}, {"6", 2.67}, {"7", 2.67}, {"8", 2.39}, {"9", 2.25}, {"10", 2.1}, {"11", 0.1}, {"12", 0.14}]}, "Naive kelly sizing without algorithm"
  end

  test "simple arb" do
    no_arb_error = {:error, "No arbitrage exists for these events."}
    assert arb([{"lions", [prob: 0.85], [us: "-110"]}]) ==  no_arb_error, "No arbitrage exists on a single, even positive EV  outcome"
    assert arb([{"lions", [prob: 0.85], [us: "-110"]}, {"bears", [prob: 0.15], [us: "-110"]}]) ==  no_arb_error, "Standard US odds exhibit no arbitrage"
    assert arb([{"lions", [prob: 0.85], [us: "-107"]}, {"bears", [prob: 0.15], [us: "+110"]}]) ==  {:ok, [{"lions", 51.69}, {"bears", 47.62}], 0.69}, "Can make a small profit on small arbitrage"
    assert arb([{"nadal", [prob: 0.50], [us: "-161"]}, {"murray", [prob: 0.25], [us: "+350"]}, {"becker", [prob: 0.01],  [us: "+632"]}]) ==  {:ok, [{"nadal", 61.69}, {"murray", 22.22}, {"becker", 13.66}], 2.43}, "Multi-ways are harder to spot so may exhibit more profit"
  end

  test "simultaneous independent sim_win" do
    small_edge = {"small edge", [prob: "0.55"], [us: -110]}
    unlikely = {"prolly not", [prob: 0.05], [uk: "30/1"]}
    always_win = {"always win", [prob: 1], [us: -110]}
    always_lose = {"always lose", [roi: 0], [us: -110]}

    {:ok, win} = sim_win([small_edge])
    assert win <= 1.00, "A small edge on a small bankroll cannot make a ton of money"
    {:ok, win} = sim_win([unlikely, small_edge])
    assert win <= 50.00, "Bigger variance when you include an unlikely result"
    assert sim_win([always_win], 1) == {:ok, 90.91}, "If the result is known, you get full value."
    assert sim_win([always_win]) == {:ok, 90.91}, "Even when you repeat it many times"
    assert sim_win([always_win, always_lose], 100) == {:ok, 90.91}, "Same when you add one which cannot win"
  end

  test "many horses sim_win" do
    chalk = {"chalk", [prob: 0.75], [uk: "3/5"]}
    stalk = {"stalk", [prob: 0.20], [uk: "7/2"]}
    dark  = {"dark", [prob: 0.04], [uk: "30/1"]}
    glue  = {"glue", [prob: 0.01], [uk: "100/1"]}

    {:ok, win} = sim_win([chalk,dark,glue], 100, independent: false)
    assert win <= 10.00, "Get a simulated win with only the positive expectation results"
    {:ok, win} = sim_win([chalk,stalk,dark,glue], 100, independent: false)
    assert win >= 10.00, "But a larger one when we add in the negative EV but still bettable"

    biased_coin = [ {"heads", [prob: 0.499], [eu: 2.00]},
                    {"tails", [prob: 0.501], [eu: 2.00]}
                  ]
    {:ok, win} = sim_win(biased_coin, 1000, bankroll: 100_000, independent: false)
    assert win >= 10.00, "We can make some money flipping biased coins."
  end

  test "simple ev" do
    neg_ev = {"no edge", [prob: "0.50"], [us: -110]}
    pos_ev = {"small edge", [prob: "0.55"], [us: -110]}

    assert ev([neg_ev, pos_ev]) == {:ok, [{"no edge", 95.45454545454545}, {"small edge", 105.00}]}, "Difference from 100 is the expected win"
  end

end
