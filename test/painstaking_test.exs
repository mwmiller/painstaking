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
    assert PainStaking.kelly_size(15000, [small_edge, decent_edge]) == [150.00, 816.75], "Not treated as exactly simultaneous"
    assert PainStaking.kelly_size(15000, [decent_edge, small_edge]) == [825.0, 141.75], "Which means order matters"
    assert PainStaking.kelly_size(15000, [decent_edge, no_edge, small_edge]) == [825.0, 0.0, 141.75], "But skipping no-edge situations in the middle doesn't change much"
  end

  test "simple arb_size" do
    no_arb_error = {:error, "No arbitrage exists for these events."}
    assert PainStaking.arb_size(1000, [[us: "-110"]]) ==  no_arb_error, "No arbitrage exists on a single outcome"
    assert PainStaking.arb_size(1000, [[us: "-110"], [us: "-110"]]) ==  no_arb_error, "Standard US odds exhibit no arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-107"], [us: "+110"]]) ==  {:ok, [516.91, 476.19], 6.90}, "Can make a small profit on small arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-161"], [us: "+350"], [us: "+632"]]) ==  {:ok, [616.86, 222.22, 136.61], 24.31}, "Multi-ways are harder to spot so may exhibit more profit"
  end

end
