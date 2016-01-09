defmodule PainStaking do
  require Exoddic
  @moduledoc """
  Calculate stakes in advantage betting situations
  """

  @doc """
  Determine the amount to stake on a single advantage situation based on the
  estimated edge and the Kelly Criterion

  `bankroll` is the total amount available for wagering
  `estimate` is the estimated actual odds on the event occurring
  `offered`  is the odds offered by the counter-party

  `estimate` and `odds` should be entered as atoms and numbers which can be
  interpreted by the `Exoddic` module. Examples include:

  `[prob: 0.50]` as a probability
  `[us: "+120"]` as moneyline-style odds
  `[eu: 2.25]`   as decimal-style odds

  Returns {whether an edge exists, amount to wager}
  """
  @spec kelly_size(number, [atom: number], [atom: number]) :: {boolean, float}
  def kelly_size(bankroll, estimate, offered) do
    prob = extract_value(estimate, :prob)
    win = extract_value(offered, :uk)
    amount = Float.round(bankroll * kelly_fraction(prob, win), 2)
    {amount != 0.0, amount}
  end
  @doc """
  Determine how much to bet on each of a set of mutually exclusive outcomes in
  an arbitrage situation.

  `max_outlay` is the maximum available to stake on this set of outcomes.
  The smaller the arbitrage, the closer your outlay will be to this number.

  `mutually_exclusives` is a list of mutually exclusive outcomes and the odds
  offered on each.  Each element of the list should be an atom-number keyword list
  which can be interpreted by `Exoddic`. For example, `[us: "-120"]`

  Returns {whether an arb exists, [stake on each outcome], expected profit}

  The expected profit may suffer from small rounding errors.
  """
  @spec arb_size(number, [[atom: number]]) :: {boolean, [float], float}
  def arb_size(max_outlay, mutually_exclusives) do
    if arb_exists(mutually_exclusives) do
      sizes = mutually_exclusives |> Enum.map(fn(x) -> size_to_collect(x, max_outlay) end)
      {true, sizes, max_outlay - Enum.sum(sizes) |> Float.round(2)}
    else
      {false, List.duplicate(0.00, Enum.count(mutually_exclusives)), 0.0}
    end
  end

  defp extract_value(kwl, into) do
    [type|_] = Keyword.keys(kwl)
    Exoddic.convert(kwl[type], from: type, to: into, for_display: false)
  end

  defp size_to_collect(offer, goal), do: (goal / (offer |> extract_value(:eu))) |> Float.round(2)
  defp arb_exists(mutually_exclusives), do: Enum.count(mutually_exclusives) > 1 and mutually_exclusives |> Enum.map(fn(x) -> extract_value(x,:prob) end) |> Enum.sum < 1

  defp kelly_fraction(prob,payoff) do
    # Presume we cannot get the other side at the same odds
    # This must, then, be bounded at 0.  The bounding at 1 is
    # somewhat redundant, but makes things clear if we get bad input
    Enum.max([0.0,Enum.min([1.0,(prob * (payoff + 1) - 1)/payoff])]);
  end

end
