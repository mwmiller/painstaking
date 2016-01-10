defmodule PainStakingTest do
  use ExUnit.Case
  doctest PainStaking

  test "simple kelly_size" do
    assert PainStaking.kelly_size(15000, {[prob: 0.55], [us: "-110"]})   == {:ok,  825.00}, "Bet a bit with decent return"
    assert PainStaking.kelly_size(15000, {[prob: 0.55], [us: -120]})     == {:ok,  150.00}, "Drops with a price increase"
    assert PainStaking.kelly_size(15000, {[prob: "0.60"], [us: "-120"]}) == {:ok, 1800.00}, "Shoots up with a better winning estimate"
    assert PainStaking.kelly_size(15000, {[prob: "0.50"], [us: -110]})   == {:error,   "This is not an advantage situation."}, "Cannot beat the vig with coin-flips"
  end

  test "simple arb_size" do
    assert PainStaking.arb_size(1000, [[us: "-110"]])                               ==  {:error, "No arbitrage exists for these events."}, "No arbitrage exists on a single outcome"
    assert PainStaking.arb_size(1000, [[us: "-110"], [us: "-110"]])                 ==  {:error, "No arbitrage exists for these events."}, "Standard US odds exhibit no arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-107"], [us: "+110"]])                 ==  {:ok, [516.91, 476.19], 6.90}, "Can make a small profit on small arbitrage"
    assert PainStaking.arb_size(1000, [[us: "-161"], [us: "+350"], [us: "+632"]])   ==  {:ok, [616.86, 222.22, 136.61], 24.31}, "Multi-ways are harder to spot so may exhibit more profit"
  end

end
