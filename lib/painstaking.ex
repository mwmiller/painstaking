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
  @typedoc  """
  A keyword list which configures optional parameters for staking calculators

  - `bankroll` is the total amount available for wagering, defaults to `100`.
  - `independent` chooses between mutually exclusive and independent simultaneous events, defaults to `false`
  """
  @type staking_options :: [bankroll: number, independent: boolean]
  @doc """
  Determine the amount to stake on advantage situations based on the
  estimated edge and the Kelly Criterion

  Returns {:ok, list of amounts to wager on each}.
  The list will be sorted in expectation order.
  """
  @spec kelly([edge], staking_options) :: {:ok, [tagged_number]} | {:error, String.t}
  def kelly(advantages, opts \\ []) do
    {bankroll, independent} = extract_staking_options(opts)
    if Enum.count(advantages) > 1 and independent do
      {:error, "Cannot handle multiple independent events, yet."}
    else
      opt_set = advantages
              |> Enum.sort_by(fn(x) -> single_ev(x,1) end, &>=/2)
              |> pick_set_loop([])
      if Enum.count(opt_set) != 0 do
        rr = rr(opt_set)
        sizes = opt_set |> Enum.map(fn({d,p,o}) -> {d, Float.round(kelly_fraction(rr,{d,p,o})*bankroll,2)} end)
        {:ok, sizes}
      else
        {:error, "No suitable positive expectation edges found."}
      end
    end
  end

  defp extract_staking_options(opts) do
      {Keyword.get(opts, :bankroll, 100), Keyword.get(opts, :independent, false)}
  end

  defp pick_set_loop([], acc), do: Enum.reverse acc
  defp pick_set_loop([this|rest], acc) do
    if single_ev(this,1) > rr(acc) do
        pick_set_loop(rest, [this|acc])
    else
        pick_set_loop([], acc)
    end
  end

  # The "reserve rate" above which any additions to the set must be
  # in order to be included in the optimal set
  defp rr([]), do: 1.0 # First must merely be positive expectation
  defp rr(included) do

    probs = included |> Enum.map(fn({_,p,_}) -> extract_value(p,:prob) end) |> Enum.sum
    payoffs = included |> Enum.map(fn({_,_,o}) -> 1/extract_value(o,:eu) end) |> Enum.sum

    (1 - probs) / (1 - payoffs)
  end

  defp kelly_fraction(rr, {_,p,o}), do: extract_value(p, :prob) - (rr/extract_value(o, :eu))

  @doc """
  Determine how much to bet on each of a set of mutually exclusive outcomes in
  an arbitrage situation.

  The optional `bankroll` can be used to set the maximum amount available to
  bet on these outcomes.  The smaller the arbitrage, the closer your outlay will be to this number.

  `mutually_exclusives` is a list of mutually exclusive outcomes and the odds
  offered on each.

  Successful return: {:ok, [stake on each outcome], expected profit}

  The payouts may not all be exactly the same because of rounding to the
  nearest cent.  This may cause a slight variation in the expected profit.
  """
  @spec arb([wager_price], staking_options) :: {:ok, [float], float} | {:error, String.t}
  def arb(mutually_exclusives, opts \\ []) do
    {max_outlay, independent} = extract_staking_options(opts)
    if arb_exists(mutually_exclusives) and not independent do
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

  `edges` is a list of simultaneous events
  `iter` is the number of simulation iterations to run

  Returns the average win, assuming wagers are staked according
  to the `kelly`
  """
  @spec sim_win([edge], non_neg_integer, staking_options) :: float
  def sim_win(edges, iter, opts \\ []) do
    sedges        = edges |> Enum.sort_by(fn(x) -> single_ev(x,1) end, &>=/2)
    {:ok, wagers} = kelly(sedges, opts)
    cdf           = edge_cdf(sedges)
    ev            = sample_ev(cdf, wagers, iter)
    ev - (wagers |> Enum.map(fn({_,a}) -> a end) |> Enum.sum) |> Float.round(2)
  end

  @doc """
  The mathematical expectations for a list of supposed edges

  A losing proposition will have an EV below the supplied `bankroll`

  The return values will be tagged with the provided edge descriptions
  """
  @spec ev([edge], staking_options) :: {:ok, [tagged_number]}
  def ev(edges, opts \\ []) do
    {mult, _ } = extract_staking_options(opts)
    {:ok, ev_loop(edges,mult,[])}
  end
  defp ev_loop([],_, acc), do: Enum.reverse acc
  defp ev_loop([{d,p,o}|t],m, acc), do: ev_loop(t, m, [{d, single_ev({d,p,o},m)}|acc])
  defp single_ev({_,p,o},m), do: m * extract_value(p, :prob) * extract_value(o, :eu)

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
