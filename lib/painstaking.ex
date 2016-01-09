defmodule PainStaking do
  require Exoddic

  def kelly_size(bankroll, estimate, offered) do
    prob = extract_value(estimate, :prob)
    win = extract_value(offered, :uk)
    Float.round(bankroll * kelly_fraction(prob, win), 2)
  end

  defp extract_value(kwl, into) do
    [type|_] = Keyword.keys(kwl)
    Exoddic.convert(kwl[type], from: type, to: into, for_display: false)
  end

  defp kelly_fraction(prob,payoff) do
    # Presume we cannot get the other side at the same odds
    # This must, then, be bounded at 0.  The bounding at 1 is
    # somewhat redundant, but makes things clear if we get bad input
    Enum.max([0.0,Enum.min([1.0,(prob * (payoff + 1) - 1)/payoff])]);
  end

end
