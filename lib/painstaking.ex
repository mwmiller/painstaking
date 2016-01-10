defmodule PainStaking do
  require Exoddic
  @moduledoc """
  Calculate stakes in advantage betting situations
  """

  @typedoc """
  A keyword list with a single pair.
  The key should be one of the atoms for a supported odds format from Exoddic.
  The value should be a supported way for expressing the odds for that key.

  Examples:

  - Probability: `[prob: 0.50]`
  - Moneyline:   `[us: "+120"]`
  - Decimal:     `[eu: 2.25]`
  - Traditional: `[uk: "4/1"]`

  """
  @type wager_price :: [atom: number|String.t]
  @doc """
  Determine the amount to stake on a single advantage situation based on the
  estimated edge and the Kelly Criterion

  `bankroll` is the total amount available for wagering
  `estimate` is the estimated actual odds on the event occurring
  `offered`  is the odds offered by the counter-party

  Returns {whether an edge exists, amount to wager}
  """
  @spec kelly_size(number, wager_price, wager_price) :: {boolean, float}
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
  offered on each.

  Returns {whether an arb exists, [stake on each outcome], expected profit}

  The payouts may not all be exactly `max_outlay` because of rounding to the
  nearest cent.  This may cause a slight variation in the expected profit.
  """
  @spec arb_size(number, [wager_price]) :: {boolean, [float], float}
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
