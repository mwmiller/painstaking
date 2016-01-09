defmodule PainStaking do
  require Exoddic

  def kelly_size(bankroll, estimate, offered) do
    prob = extract_value(estimate, :prob)
    win = extract_value(offered, :uk)
    amount = Float.round(bankroll * kelly_fraction(prob, win), 2)
    {amount != 0.0, amount}
  end

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
