defmodule PainStakingTest do
  use ExUnit.Case
  doctest PainStaking

  test "simple kelly_size" do
    assert PainStaking.kelly_size(15000, [prob: 0.55], [us: "-110"])   ==  825.00, "Bet a bit with decent return"
    assert PainStaking.kelly_size(15000, [prob: 0.55], [us: -120])     ==  150.00, "Drops with a price increase"
    assert PainStaking.kelly_size(15000, [prob: "0.60"], [us: "-120"]) == 1800.00, "Shoots up with a better winning estimate"
    assert PainStaking.kelly_size(15000, [prob: "0.50"], [us: -110])   ==    0.00, "Cannot beat the vig with coin-flips"
  end

end
