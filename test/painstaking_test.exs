defmodule PainStakingTest do
  use ExUnit.Case
  doctest PainStaking

  test "simple kelly_size" do
    no_edge     = {"no edge",    [prob: "0.50"], [us: -110]}
    small_edge  = {"small edge", [prob: 0.55],   [us: -120]}
    decent_edge = {"decent edge",[prob: 0.55],   [us: "-110"]}

    assert PainStaking.kelly_size(15000, [no_edge], true) == {:ok, [{"no edge", 0.0}]}, "Recommend 0 bet for non-advantage situations"
    assert PainStaking.kelly_size(15000, [small_edge], false) == {:ok, [{"small edge", 150.0}]}, "Small bets for small edges"
    assert PainStaking.kelly_size(15000, [decent_edge], true)== {:ok, [{"decent edge", 825.0}]}, "Bet a bit with decent return"
    assert PainStaking.kelly_size(15000, [small_edge, decent_edge], false) == {:ok, [{"small edge", 150.0}, {"decent edge", 825.0}]}, "Not treated as exactly simultaneous"
    assert PainStaking.kelly_size(15000, [small_edge, decent_edge], true) == {:error, "Cannot handle multiple independent events, yet."}, "Dependent events first"
  end

  test "simple arb_size" do
    no_arb_error = {:error, "No arbitrage exists for these events."}
    assert PainStaking.arb_size(1000, [[us: "-110"]]) ==  no_arb_error, "No arbitrage exists on a single outcome"
    assert PainStaking.arb_size(1000, [[us: "-110"], [us: "-110"]]) ==  no_arb_error, "Standard US odds exhibit no arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-107"], [us: "+110"]]) ==  {:ok, [516.91, 476.19], 6.90}, "Can make a small profit on small arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-161"], [us: "+350"], [us: "+632"]]) ==  {:ok, [616.86, 222.22, 136.61], 24.31}, "Multi-ways are harder to spot so may exhibit more profit"
  end

  test "simple sim_win_for" do
    no_edge = {"no edge", [prob: "0.50"], [us: -110]}
    small_edge = {"small edge", [prob: "0.55"], [us: -110]}
    always_win = {"always win", [prob: 1], [us: -110]}

    assert PainStaking.sim_win_for(100, [no_edge], 1) == 0.00, "Single wager which kelly does not recommend making does not make money"
    assert PainStaking.sim_win_for(100, [no_edge], 100) == 0.00, "Even if you do it 100 times"
    assert PainStaking.sim_win_for(100, [small_edge], 100) <= 1.00, "A small edge on a small bankroll cannot make a ton of money"
    assert PainStaking.sim_win_for(100, [always_win], 1) == 90.91, "If the result is known, you get full value."
    assert PainStaking.sim_win_for(100, [always_win], 100) == 90.91, "Even when you repeat it many times"
    assert PainStaking.sim_win_for(100, [always_win, no_edge], 100) == 90.91, "Same when you add one which cannot win"
    assert PainStaking.sim_win_for(100, [always_win, no_edge, small_edge], 100) <= 91.91, "Might win a bit more if you add in a small edge"
  end

  test "simple ev_per_unit" do
    neg_ev = {"no edge", [prob: "0.50"], [us: -110]}
    pos_ev = {"small edge", [prob: "0.55"], [us: -110]}

    assert PainStaking.ev_per_unit([neg_ev, pos_ev]) == {:ok, [{"no edge", 0.9545454545454545}, {"small edge", 1.05}]}, "Difference from the unit is the expected win"
  end
end
