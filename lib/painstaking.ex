defmodule PainStaking do
  require Exoddic
  use Bitwise

  @moduledoc """
  Calculate stakes in advantage betting situations
  """

  @typedoc """
  A keyword list with a single pair.

  The key should be one of the atoms for a supported odds format from Exoddic.
  The value should be an appropriate representation for that key.

  Examples:

  - Probability: `[prob: 0.50]`
  - Moneyline:   `[us: "+120"]`
  - Decimal:     `[eu: 2.25]`
  - Traditional: `[uk: "4/1"]`

  """
  @type wager_price :: [atom: number|String.t]
  @typedoc """
  A tuple which represents a supposed advantage wagering situation.

  - a proposition description
  - the estimate of the fair (or actual) odds of winning
  - the odds offered by the counter-party to the wager
  """
  @type edge :: {String.t, wager_price, wager_price}
  @typedoc """
  A tuple with a description and number

  Primarily used to make it easier to collate results.
  """
  @type tagged_number :: {String.t, number}
  @typedoc  """
  A keyword list which configures optional parameters for staking calculators

  - `bankroll`: the total amount available for wagering; defaults to `100`
  - `independent`: independent or mutually-exclusive simultaneous events; defaults to `false`
  """
  @type staking_options :: [bankroll: number, independent: boolean]

  @spec extract_staking_options(staking_options) :: {number, boolean}
  defp extract_staking_options(opts) do
      {Keyword.get(opts, :bankroll, 100), Keyword.get(opts, :independent, false)}
  end

  @doc """
  How much to stake on advantage situations based on the Kelly Criterion

  The output list may be in a different order or have fewer elements than the input list.

  Mutually exclusive bets are staked as if they were not simultaneous. This leads to
  over-betting.  The difference is negligible on small sets of wagers.
  """
  @spec kelly([edge], staking_options) :: {:ok, [tagged_number]} | {:error, String.t}
  def kelly(edges, opts \\ []) do
    {bankroll, independent} = extract_staking_options(opts)
    {rr, set} = if not independent or Enum.count(edges) == 1 do
      optimal_set = edges |> Enum.sort_by(fn(x) -> single_ev(x, 1) end, &>=/2) |> pick_optimal_set([])
      {rr(optimal_set), optimal_set}
    else
      {nil, edges} # More work to be done here.
    end
    pretty_sizes = set |> Enum.map(fn({d, p, o}) -> {d, kelly_fraction({d, p, o}, rr)} end)
                       |> resize_fracs
                       |> fracs_display(bankroll, [])
    case Enum.count(pretty_sizes) do
      0 -> {:error, "No suitable positive expectation edges found."}
      _ -> {:ok, pretty_sizes}
    end
  end

  @spec pick_optimal_set([tuple], [tuple]) :: [tuple]
  defp pick_optimal_set([], acc), do: Enum.reverse acc
  defp pick_optimal_set([this|rest], acc) do
    if single_ev(this, 1) > rr(acc), do: pick_optimal_set(rest, [this|acc]), else: pick_optimal_set([], acc)
  end

  @spec resize_fracs([tuple]) :: [tuple]
  defp resize_fracs(fracs) do
    winners = Enum.filter(fracs, fn({_d, x}) -> x > 0 end)
    total = winners |> Enum.reduce(0, fn({_d, x}, acc) -> x + acc end)
    if total > 1, do: winners |> Enum.map(fn({d, x}) -> {d, x / total} end), else: winners
  end

  @spec fracs_display([tuple], number, list) :: [tagged_number]
  defp fracs_display([], _b, acc), do: Enum.reverse acc
  defp fracs_display([{d, f}|t], b, acc), do: fracs_display(t, b, [{d, Float.round(f * b, 2)}|acc])

  # The "reserve rate" above which any additions to the set must be
  # in order to be included in the optimal set
  @spec rr([edge]) :: float
  defp rr([]), do: 1.0 # First must merely be positive expectation
  defp rr(included) do
    {prob_factor, pay_factor} = included |> Enum.reduce({1, 1}, fn({_d, p, o}, {x, y}) ->
                                    {x - extract_price_value(p, :prob), y - 1 / extract_price_value(o, :eu)}
                                    end)
    prob_factor /  pay_factor
  end

  @spec extract_price_value(wager_price, atom) :: float
  defp extract_price_value(kwl, into) do
    [type|_none] = Keyword.keys(kwl)
    Exoddic.convert(kwl[type], from: type, to: into, for_display: false)
  end

  @spec kelly_fraction(edge, float | nil) :: float
  defp kelly_fraction({_, fair, offered}, rr) do
    case {extract_price_value(offered, :eu), extract_price_value(fair, :prob), rr} do
      {0.0, _p, _r} -> 0.0
      {o, p, nil}   -> (p * o - 1) / (o - 1)
      {o, p, r}     -> p - (r / o)
    end
  end

  @doc """
  How much to stake in an arbitrage situation.

  The `bankroll` option can be used to set the maximum amount available to
  bet on these outcomes.

  The payouts may not all be exactly the same because of rounding to the
  nearest cent.  This may cause a slight variation in the expected profit.
  """
  @spec arb([edge], staking_options) :: {:ok, [tagged_number], float} | {:error, String.t}
  def arb(edges, opts \\ []) do
    {bankroll, independent} = extract_staking_options(opts)
    all_offers_prob = all_offers_prob(edges)
    if Enum.count(edges) > 1 and not independent and all_offers_prob < 1 do
      to_pay = Float.round(bankroll / all_offers_prob, 2)
      sizes = edges |> Enum.map(fn({d, _p, o}) -> {d, size_to_collect(o, to_pay)} end)
      {:ok, sizes, sizes |> Enum.reduce(to_pay, fn({_d, x}, acc) -> acc - x end) |> Float.round(2)}
    else
      {:error, "No arbitrage exists for these events."}
    end
  end

  @spec all_offers_prob([edge]) :: float
  defp all_offers_prob(edges), do: edges |> Enum.reduce(0, fn({_d, _p, o}, acc) -> extract_price_value(o, :prob) + acc end)

  @spec size_to_collect(wager_price, float) :: float
  defp size_to_collect(offer, goal), do: Float.round(goal / (offer |> extract_price_value(:eu)), 2)

  @typep cdf :: [{[float], float}]
  @spec edge_cdf([edge], boolean) :: cdf
  defp edge_cdf(edges, independent) do
    payoffs = edges |> Enum.map(fn({_d, p, o}) -> {extract_price_value(o, :eu), extract_price_value(p, :prob)} end)
    vals = case independent do
      true -> 0..(2 |> :math.pow(Enum.count(payoffs)) |> :erlang.float_to_binary([decimals: 0]) |> String.to_integer |> Kernel.-(1))
              |> Enum.map(fn(x) -> pick_combo(x, payoffs, {[], 1}) end)
      false -> 0..(Enum.count(payoffs) - 1)
              |> Enum.map(fn(x) -> zero_except(x, payoffs, {[], 0}) end)
    end
    map_prob(vals, [], 0)
  end

  @spec zero_except(non_neg_integer, [tuple], tuple) :: tuple
  defp zero_except(_n, [], {v, p}), do: {Enum.reverse(v), p}
  defp zero_except(n, [{v, p}|t], {vals, j}) do
    {newval, newprob} = case Enum.count(vals) do
                          ^n  -> {v, p}
                          _   -> {0, 0}
                        end
    zero_except(n, t, {[newval|vals], j + newprob})
  end

  @spec pick_combo(non_neg_integer, [tuple], tuple) :: tuple
  defp pick_combo(_n, [], {v, p}), do: {Enum.reverse(v), p}
  defp pick_combo(n, [{v, p}|t], {vals, j}) do
    {newval, newprob} = case ((n >>> Enum.count(vals) &&& 1)) do
                          0   -> {v, p}
                          _   -> {0, 1 - p}
                        end
    pick_combo(n, t, {[newval|vals], j * newprob})
  end

  @spec map_prob([{number, float}], list, number) :: [{[number], number}]
  defp map_prob([], acc, _j), do: Enum.reverse acc
  defp map_prob([{l, p}|t], acc, j) do
    limit = j + p
    map_prob(t, [{l, limit}|acc], limit)
  end

  @doc """
  Simulate a repeated edge situation for the average amount won

  `iterations` sets the number of simulated outcomes
  """
  @spec sim_win([edge], pos_integer, staking_options) :: {:ok, float} | {:error, String.t}
  def sim_win(edges, iterations \\ 100, opts \\ []) do
    {_roll, independent} = extract_staking_options(opts)
    sedges           = edges |> Enum.sort_by(fn(x) -> single_ev(x, 1) end, &>=/2)
    {:ok, wagers}    = kelly(sedges, opts)
    ev               = sedges |> edge_cdf(independent) |> sample_ev(wagers, iterations)

    {:ok, ev - (wagers |> Enum.map(fn({_d, a}) -> a end) |> Enum.sum) |> Float.round(2)}
  end

  @spec sample_ev(cdf, [tagged_number], pos_integer) :: float
  defp sample_ev(cdf, fracs, iters) do
      total = cdf |> gather_results(iters, []) |>  Enum.reduce(0, fn(x, a) -> add_result_row(x, fracs, a) end)
      total / iters
  end

  @doc """
  The mathematical expectations for a list of supposed edges

  A losing proposition will have an EV below the `bankroll`
  """
  @spec ev([edge], staking_options) :: {:ok, [tagged_number]}
  def ev(edges, opts \\ []) do
    {mult, _ind} = extract_staking_options(opts)
    {:ok, ev_loop(edges, mult, [])}
  end

  @spec ev_loop([edge], float, list) :: [tagged_number]
  defp ev_loop([], _m, acc), do: Enum.reverse acc
  defp ev_loop([{d, p, o}|t], m, acc), do: ev_loop(t, m, [{d, single_ev({d, p, o}, m)}|acc])

  @spec single_ev(edge, number) :: float
  defp single_ev({_, p, o}, m), do: m * extract_price_value(p, :prob) * extract_price_value(o, :eu)

  @spec gather_results(cdf, non_neg_integer, list) ::  list
  defp gather_results(_cdf, 0, acc), do: Enum.reverse acc
  defp gather_results(cdf, n, acc), do: gather_results(cdf, n - 1, [sample_result(cdf)|acc])

  @spec add_result_row(cdf, [tagged_number], float) :: float
  defp add_result_row(_list, [], acc), do: acc
  defp add_result_row([h|t], [{_, f}|r], acc), do: add_result_row(t, r, h * f + acc)

  @spec sample_result(cdf) :: [number]
  defp sample_result(cdf) do
    pick = :rand.uniform
    case cdf |> Enum.split_while(fn({_d, plim}) -> pick > plim end) do
      {_d, [{r, _l}|_rest]}  -> r
      _                     -> proper_loss(cdf)
    end
  end

  @spec proper_loss(cdf) :: [number]
  defp proper_loss([{list, _lim}|_rest]), do: zeroed(list, [])

  @spec zeroed(list, [0]) :: [0]
  defp zeroed([], acc), do: acc
  defp zeroed([_h|t], acc), do: zeroed(t, [0|acc])

end
