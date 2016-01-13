defmodule PainStakingTest do
  use ExUnit.Case
  doctest PainStaking

  test "simple kelly_size" do
    no_edge     = {[prob: "0.50"], [us: -110]}
    small_edge  = {[prob: 0.55], [us: -120]}
    decent_edge = {[prob: 0.55], [us: "-110"]}

    assert PainStaking.kelly_size(15000, [no_edge]) == [0.00], "Recommend 0 bet for non-advantage situations"
    assert PainStaking.kelly_size(15000, [small_edge]) == [150.00], "Small bets for small edges"
    assert PainStaking.kelly_size(15000, [decent_edge])== [825.00], "Bet a bit with decent return"
    assert PainStaking.kelly_size(15000, [small_edge, decent_edge]) == [150.00, 825.0], "Not treated as exactly simultaneous"
    assert PainStaking.kelly_size(15000, [decent_edge, small_edge]) == [825.0, 150.0], "Which means order matters"
    assert PainStaking.kelly_size(15000, [decent_edge, no_edge, small_edge]) == [825.0, 0.0, 150.0], "But skipping no-edge situations in the middle doesn't change much"
  end

  test "simple arb_size" do
    no_arb_error = {:error, "No arbitrage exists for these events."}
    assert PainStaking.arb_size(1000, [[us: "-110"]]) ==  no_arb_error, "No arbitrage exists on a single outcome"
    assert PainStaking.arb_size(1000, [[us: "-110"], [us: "-110"]]) ==  no_arb_error, "Standard US odds exhibit no arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-107"], [us: "+110"]]) ==  {:ok, [516.91, 476.19], 6.90}, "Can make a small profit on small arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-161"], [us: "+350"], [us: "+632"]]) ==  {:ok, [616.86, 222.22, 136.61], 24.31}, "Multi-ways are harder to spot so may exhibit more profit"
  end

  test "simple sim_win_for" do
    assert PainStaking.sim_win_for(100, [ {[prob: "0.50"], [us: -110]}], 1) == 0.00, "Single wager which kelly does not recommend making does not make money"
    assert PainStaking.sim_win_for(100, [ {[prob: "0.50"], [us: -110]}], 100) == 0.00, "Even if you do it 100 times"
    assert PainStaking.sim_win_for(100, [ {[prob: "0.55"], [us: -110]}], 100) <= 1.00, "A small edge on a small bankroll cannot make a ton of money"
    assert PainStaking.sim_win_for(100, [ {[prob: 1], [us: -110]}], 1) == 90.91, "If the result is known, you get full value."
    assert PainStaking.sim_win_for(100, [ {[prob: 1], [us: -110]}], 100) == 90.91, "Even when you repeat it many times"
  end

end
