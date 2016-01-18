defmodule PainStaking do
  require Exoddic
  use Bitwise

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
  @typedoc """
  A tuple which represents a supposed advantage wagering situation.

  The first element is an edge description
  The second element is the estimate of the fair (or actual) odds of winning.
  The third element is the odds offered by the counter-party to the wager.
  """
  @type edge :: {String.t, wager_price, wager_price}
  @typedoc """
  A number tagged with a description to make collating results easier.
  """
  @type tagged_number :: {String.t, number}
  @doc """
  Determine the amount to stake on advantage situations based on the
  estimated edge and the Kelly Criterion

  `bankroll` is the total amount available for wagering
  `advantages` is a description of the situations as `edge`s.

  Returns {:ok, list of amounts to wager on each}.
  The list will be sorted in expectation order.
  """
  @spec kelly_size(number, [edge]) :: {:ok, [tagged_number]}
  def kelly_size(bankroll, advantages) do
    sizes = advantages
            |> Enum.sort_by(&PainStaking.ev/1)
            |> kelly_fractions_loop([])
            |> Enum.map(fn({d,x}) -> {d, Float.round(x*bankroll,2)} end)
    {:ok, sizes}
  end

  defp kelly_fractions_loop([], acc), do: Enum.reverse acc
  defp kelly_fractions_loop([{desc,fair,offered}|rest], acc) do
    prob = extract_value(fair, :prob)
    win = extract_value(offered, :uk)
    kelly_fractions_loop(rest, [{desc,kelly_fraction(prob, win)}|acc])
  end
  @doc """
  Determine how much to bet on each of a set of mutually exclusive outcomes in
  an arbitrage situation.

  `max_outlay` is the maximum available to stake on this set of outcomes.
  The smaller the arbitrage, the closer your outlay will be to this number.

  `mutually_exclusives` is a list of mutually exclusive outcomes and the odds
  offered on each.

  Successful return: {:ok, [stake on each outcome], expected profit}

  The payouts may not all be exactly `max_outlay` because of rounding to the
  nearest cent.  This may cause a slight variation in the expected profit.
  """
  @spec arb_size(number, [wager_price]) :: {:ok, [float], float} | {:error, String.t}
  def arb_size(max_outlay, mutually_exclusives) do
    if arb_exists(mutually_exclusives) do
      sizes = mutually_exclusives |> Enum.map(fn(x) -> size_to_collect(x, max_outlay) end)
      {:ok, sizes, max_outlay - Enum.sum(sizes) |> Float.round(2)}
    else
      {:error, "No arbitrage exists for these events."}
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

  # This seems way more complex than it ought to be.
  @spec edge_cdf([edge]) :: [{[float], float}]
  defp edge_cdf(advantages) do
     payoffs = advantages |> Enum.map(fn({_,p,o}) -> {extract_value(o, :eu), extract_value(p, :prob)} end)
     last = :math.pow(2, Enum.count(payoffs)) |> Float.to_string([decimals: 0]) |> String.to_integer |> - 1
     0..last |> Enum.map(fn(x) -> pick_combo(x, payoffs, {[],1}) end) |> map_prob([],0)
  end
  defp pick_combo(_, [], acc), do: acc
  defp pick_combo(n,[{v,p}|t],{vals,j}) do
    {newval, newprob} = if ((n >>> Enum.count(vals) &&& 1)) != 0, do: {v,p}, else: {0,1-p}
    pick_combo(n,t,{Enum.into([newval], vals), j * newprob})
  end
  defp map_prob([], acc, _), do: acc
  defp map_prob([{l,p}|t], acc, j) do
    limit = j+p
    map_prob(t, Enum.into([{l, limit}], acc), limit)
  end

  @doc """
  Simulate a repeated edge situation and see the average amount won.

  `bankroll` is the starting bankroll when the bets are placed
  `edges` is a list of simultaneous events
  `iter` is the number of simulation iterations to run

  Returns the average win, assuming wagers are staked according
  to the `kelly_size`
  """
  @spec sim_win_for(number, [edge], non_neg_integer) :: float
  def sim_win_for(bankroll, edges, iter) do
    sedges        = edges |> Enum.sort_by(&PainStaking.ev/1)
    {:ok, wagers} = kelly_size(bankroll, sedges)
    cdf           = edge_cdf(sedges)
    ev            = sample_ev(cdf, wagers, iter)
    ev - (wagers |> Enum.map(fn({_,a}) -> a end) |> Enum.sum) |> Float.round(2)
  end

  @doc """
  The mathematical expectations for a list of supposed edges

  An `edge` which turns out to be a losing proposition will have an EV below 1.

  The return values will be tagged with the provided edge descriptions
  """
  @spec ev_per_unit([edge]) :: {:ok, [tagged_number]}
  def ev_per_unit(edges), do: {:ok, ev_loop(edges,[])}
  defp ev_loop([], acc), do: Enum.reverse acc
  defp ev_loop([{d,p,o}|t], acc), do: ev_loop(t, [{d, ev({d,p,o})}|acc])
  def ev({_,p,o}), do: extract_value(p, :prob) * extract_value(o, :eu)

  defp sample_ev(cdf, fracs, iters) do
      total = gather_results(cdf, iters, []) |>  Enum.reduce(0, fn(x, a) -> add_row(x,fracs,a) end)
      total / iters
  end

  defp gather_results(_, 0, acc), do: Enum.reverse acc
  defp gather_results(cdf, n, acc), do: gather_results(cdf, n-1, [sample_result(cdf)|acc])

  defp add_row([],[],acc), do: acc
  defp add_row([h|t],[{_,f}|r], acc), do: add_row(t,r, h*f+acc)

  defp sample_result(cdf) do
    pick = :random.uniform
    {_, [{r,_}|_]} = cdf |> Enum.split_while(fn({_,plim}) -> pick > plim end)
    r
  end

end
