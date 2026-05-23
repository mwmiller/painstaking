defmodule PainStaking.CombinationsTest do
  use ExUnit.Case
  alias PainStaking.Combinations
  doctest PainStaking.Combinations

  test "parlay calculation" do
    leg1 = {"Lions", [prob: 0.5], [eu: 2.0]}
    leg2 = {"Bears", [prob: 0.5], [eu: 2.0]}
    parlay = PainStaking.parlay([leg1, leg2])

    {_desc, [prob: p], [eu: o]} = parlay
    assert p == 0.25
    assert o == 4.0
  end

  test "generate combinations" do
    e1 = {"1", [prob: 0.5], [eu: 2.0]}
    e2 = {"2", [prob: 0.5], [eu: 2.0]}
    e3 = {"3", [prob: 0.5], [eu: 2.0]}

    combos = Combinations.generate([e1, e2, e3], [1, 2])
    # 3 straights + 3 parlays
    assert Enum.count(combos) == 6

    # Check one parlay
    {{desc, [prob: p], [eu: o]}, indices} = Enum.at(combos, 3)
    assert String.contains?(desc, "+")
    assert p == 0.25
    assert o == 4.0
    assert Enum.count(indices) == 2
  end

  test "optimal kelly with correlation" do
    # Two independent events with 10% edge each
    # EV = 1.1
    e1 = {"Team A", [prob: 0.5], [eu: 2.2]}
    # EV = 1.1
    e2 = {"Team B", [prob: 0.5], [eu: 2.2]}

    base = [e1, e2]
    # Generate straights (1) and parlay (2)
    candidates = Combinations.generate(base, [1, 2])

    {:ok, results} = Combinations.kelly(base, candidates, bankroll: 1000)

    # Should have 3 results: Team A, Team B, and Team A + Team B
    assert Enum.count(results) == 3

    # Ensure they are sized reasonably (fractions of bankroll)
    total_staked = results |> Enum.map(fn {_, amt} -> amt end) |> Enum.sum()
    assert total_staked > 0
    assert total_staked <= 1000

    # Check names
    names = results |> Enum.map(fn {n, _} -> n end)
    assert "Team A" in names
    assert "Team B" in names
    assert "Team A + Team B" in names
  end

  test "no edge situation" do
    # Two independent events with NO edge (EV = 1.0)
    e1 = {"Team A", [prob: 0.5], [eu: 2.0]}
    e2 = {"Team B", [prob: 0.5], [eu: 2.0]}

    base = [e1, e2]
    candidates = Combinations.generate(base, [1, 2])

    {:ok, results} = Combinations.kelly(base, candidates, bankroll: 1000)

    # Should have no recommendations for zero-EV bets
    assert results == []
  end

  test "large parlay combinations" do
    base = for i <- 1..5, do: {"#{i}", [prob: 0.5], [eu: 2.2]}
    # Generate all combinations from 1 to 5 legs
    combos = Combinations.generate(base, 1..5)
    # sum(5Ci for i=1..5) = 5 + 10 + 10 + 5 + 1 = 31
    assert Enum.count(combos) == 31
  end
end
