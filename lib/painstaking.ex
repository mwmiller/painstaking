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

  The elements, in order:
  - an edge description
  - the estimate of the fair (or actual) odds of winning
  - the odds offered by the counter-party to the wager
  """
  @type edge :: {String.t, wager_price, wager_price}
  @typedoc """
  A number tagged with a description

  Primarily used to make it easier to collate results.
  """
  @type tagged_number :: {String.t, number}
  @typedoc  """
  A keyword list which configures optional parameters for staking calculators

  The keywords are:
  - `bankroll`: the total amount available for wagering; defaults to `100`
  - `independent`: mutually exclusive or independent simultaneous events; defaults to `false`
  """
  @type staking_options :: [bankroll: number, independent: boolean]

  @spec extract_staking_options(staking_options) :: {number, boolean}
  defp extract_staking_options(opts) do
      {Keyword.get(opts, :bankroll, 100), Keyword.get(opts, :independent, false)}
  end

  @doc """
  Determine the amount to stake on advantage situations based on the Kelly Criterion

  The output list may be in a different order or have fewer elements than the input list.
  """
  @spec kelly([edge], staking_options) :: {:ok, [tagged_number]} | {:error, String.t}
  def kelly(edges, opts \\ []) do
    {bankroll, independent} = extract_staking_options(opts)
    {rr, set} = if not independent or Enum.count(edges) == 1 do
      optimal_set = edges |> Enum.sort_by(fn(x) -> single_ev(x,1) end, &>=/2) |> pick_optimal_set([])
      {rr(optimal_set), optimal_set}
    else
      {nil, edges} # More work to be done here.
    end
    pretty_sizes = set |> Enum.map(fn({d,p,o}) -> {d, kelly_fraction({d,p,o}, rr)} end)
                       |> resize_fracs
                       |> fracs_display(bankroll,[])
    case Enum.count(pretty_sizes) do
      0 -> {:error, "No suitable positive expectation edges found."}
      _ -> {:ok, pretty_sizes}
    end
  end

  @spec pick_optimal_set([tuple],[tuple]) :: [tuple]
  defp pick_optimal_set([], acc), do: Enum.reverse acc
  defp pick_optimal_set([this|rest], acc) do
    if single_ev(this,1) > rr(acc), do: pick_optimal_set(rest, [this|acc]), else: pick_optimal_set([], acc)
  end

  @spec resize_fracs([tuple]) :: [tuple]
  defp resize_fracs(fracs) do
    winners = Enum.filter(fracs, fn({_,x}) -> x > 0 end)
    total = winners |> Enum.reduce(0, fn({_,x}, acc) -> x+acc end)
    if (total > 1), do: winners |> Enum.map(fn({d,x}) -> {d, x/total} end), else: winners
  end

  @spec fracs_display([tuple], number, list) :: [tagged_number]
  defp fracs_display([], _,acc), do: Enum.reverse acc
  defp fracs_display([{d,f}|t],b, acc), do: fracs_display(t,b,[{d, Float.round(f*b,2)}|acc])

  # The "reserve rate" above which any additions to the set must be
  # in order to be included in the optimal set
  @spec rr([edge]) :: float
  defp rr([]), do: 1.0 # First must merely be positive expectation
  defp rr(included) do
    {prob_factor, pay_factor} = included |> Enum.reduce({1,1}, fn({_,p,o}, {x,y}) ->
                                    {x - extract_price_value(p,:prob), y - 1/extract_price_value(o,:eu)}
                                    end)
    prob_factor /  pay_factor
  end

  @spec extract_price_value(wager_price, atom) :: number
  defp extract_price_value(kwl, into) do
    [type|_] = Keyword.keys(kwl)
    Exoddic.convert(kwl[type], from: type, to: into, for_display: false)
  end

  @spec kelly_fraction(edge, float | nil) :: float
  defp kelly_fraction({_,p,o}, rr) do
    odds = extract_price_value(o, :eu)
    if odds == 0 do
    else if rr, do: extract_price_value(p, :prob) - (rr/odds), else: (extract_price_value(p, :prob)*odds - 1)/(odds - 1)
    end
  end

  @doc """
  Determine how much to bet on each of a set of mutually exclusive outcomes in
  an arbitrage situation.

  The `bankroll` option can be used to set the maximum amount available to
  bet on these outcomes.  The smaller the arbitrage, the closer your outlay will be to this number.

  The payouts may not all be exactly the same because of rounding to the
  nearest cent.  This may cause a slight variation in the expected profit.
  """
  @spec arb([edge], staking_options) :: {:ok, [tagged_number], float} | {:error, String.t}
  def arb(mutually_exclusives, opts \\ []) do
    {max_outlay, independent} = extract_staking_options(opts)
    if arb_exists?(mutually_exclusives) and not independent do
      sizes = mutually_exclusives |> Enum.map(fn({d,_,o}) -> {d, size_to_collect(o, max_outlay)} end)
      {:ok, sizes, sizes |> Enum.reduce(max_outlay, fn({_,x},acc) -> acc - x end) |> Float.round(2)}
    else
      {:error, "No arbitrage exists for these events."}
    end
  end

  @spec size_to_collect(wager_price, number) :: float
  defp size_to_collect(offer, goal), do: (goal / (offer |> extract_price_value(:eu))) |> Float.round(2)
  @spec arb_exists?([edge]) :: boolean
  defp arb_exists?(mutually_exclusives), do: Enum.count(mutually_exclusives) > 1 and mutually_exclusives |> Enum.reduce(0,fn({_,_,o}, acc) -> extract_price_value(o,:prob)+acc end) < 1


  # This seems way more complex than it ought to be.
  @typep cdf :: [{[float], float}]
  @spec edge_cdf([edge], boolean) :: cdf
  defp edge_cdf(edges, independent) do
    payoffs = edges |> Enum.map(fn({_,p,o}) -> {extract_price_value(o, :eu), extract_price_value(p, :prob)} end)
    possibles = if independent do
      last = :math.pow(2, Enum.count(payoffs)) |> Float.to_string([decimals: 0]) |> String.to_integer |> - 1
      0..last |> Enum.map(fn(x) -> pick_combo(x, payoffs, {[],1}) end) |> map_prob([],0)
    else
      last = Enum.count(payoffs) - 1
      0..last |> Enum.map(fn(x) -> zero_except(x, payoffs, {[],0}) end)
    end
    possibles |> map_prob([], 0)
  end

  @spec zero_except(non_neg_integer, [tuple], tuple) :: tuple
  defp zero_except(_,[],acc), do: acc
  defp zero_except(n,[{v,p}|t],{vals,j}) do
    {newval, newprob} = if Enum.count(vals) == n, do: {v,p}, else: {0,0}
    zero_except(n,t,{Enum.into([newval], vals), j + newprob})
  end

  @spec pick_combo(non_neg_integer, [tuple], tuple) :: tuple
  defp pick_combo(_, [], acc), do: acc
  defp pick_combo(n,[{v,p}|t],{vals,j}) do
    {newval, newprob} = if ((n >>> Enum.count(vals) &&& 1)) != 0, do: {v,p}, else: {0,1-p}
    pick_combo(n,t,{Enum.into([newval], vals), j * newprob})
  end
  @spec map_prob([tuple], list, number) :: [tuple]
  defp map_prob([], acc, _), do: acc
  defp map_prob([{l,p}|t], acc, j) do
    limit = j+p
    map_prob(t, Enum.into([{l, limit}], acc), limit)
  end

  @doc """
  Simulate a repeated edge situation and see the average amount won.

  `iter` is the number of simulation iterations to run
  """
  @spec sim_win([edge], non_neg_integer, staking_options) :: {:ok, float} | {:error, String.t}
  def sim_win(edges, iter \\ 100, opts \\ []) do
    {_, independent } = extract_staking_options(opts)
    sedges        = edges |> Enum.sort_by(fn(x) -> single_ev(x,1) end, &>=/2)
    {:ok, wagers} = kelly(sedges, opts)
    cdf           = edge_cdf(sedges, independent)
    ev            = sample_ev(cdf, wagers, iter)
    {:ok, ev - (wagers |> Enum.map(fn({_,a}) -> a end) |> Enum.sum) |> Float.round(2)}
  end

  @spec sample_ev(cdf, [tagged_number], non_neg_integer) :: float
  defp sample_ev(cdf, fracs, iters) do
      total = gather_results(cdf, iters, []) |>  Enum.reduce(0, fn(x, a) -> add_result_row(x,fracs,a) end)
      total / iters
  end

  @doc """
  The mathematical expectations for a list of supposed edges

  A losing proposition will have an EV below the supplied `bankroll`
  """
  @spec ev([edge], staking_options) :: {:ok, [tagged_number]}
  def ev(edges, opts \\ []) do
    {mult, _ } = extract_staking_options(opts)
    {:ok, ev_loop(edges,mult,[])}
  end
  @spec ev_loop([edge], float, list) :: [tagged_number]
  defp ev_loop([],_, acc), do: Enum.reverse acc
  defp ev_loop([{d,p,o}|t],m, acc), do: ev_loop(t, m, [{d, single_ev({d,p,o},m)}|acc])
  @spec single_ev(edge, number) :: float
  defp single_ev({_,p,o},m), do: m * extract_price_value(p, :prob) * extract_price_value(o, :eu)

  @spec gather_results(cdf, non_neg_integer, list) ::  list
  defp gather_results(_, 0, acc), do: Enum.reverse acc
  defp gather_results(cdf, n, acc), do: gather_results(cdf, n-1, [sample_result(cdf)|acc])

  @spec add_result_row(cdf, [tagged_number], float) :: float
  defp add_result_row(_,[],acc), do: acc
  defp add_result_row([h|t],[{_,f}|r],acc), do: add_result_row(t,r,h*f+acc)

  @spec sample_result(cdf) :: [number]
  defp sample_result(cdf) do
    pick = :random.uniform
    case cdf |> Enum.split_while(fn({_,plim}) -> pick > plim end) do
      {_, [{r,_}|_]}  -> r
      _               -> proper_loss(cdf)
    end
  end

  @spec proper_loss(cdf) :: [number]
  defp proper_loss([{list,_}|_]), do: zeroed(list,[])
  @spec zeroed(list, [0]) :: [0]
  defp zeroed([], acc), do: acc
  defp zeroed([_|t], acc), do: zeroed(t, [0|acc])

end
