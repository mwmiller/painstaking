defmodule PainStaking.Combinations do
  @moduledoc """
  Generate and size combinations of wagers (straights and parlays).
  """

  @type size_spec :: [integer()] | Range.t() | :all

  @iterations 500
  @learning_rate 0.01
  @convergence_threshold 1.0e-7

  @doc """
  Generate combinations of bets based on the provided sizes.

  `sizes` can be a list of integers, a range, or the atom `:all`.
  Returns a list of `{edge, [indices]}` where indices are the positions in base_edges.

  ## Examples

      iex> e1 = {"1", [prob: 0.5], [eu: 2.0]}
      iex> e2 = {"2", [prob: 0.5], [eu: 2.0]}
      iex> combos = PainStaking.Combinations.generate([e1, e2], :all)
      iex> Enum.count(combos)
      3

  """
  @spec generate([PainStaking.edge()], size_spec()) :: [{PainStaking.edge(), [integer()]}]
  def generate(base_edges, :all), do: generate(base_edges, 1..Enum.count(base_edges))

  def generate(base_edges, sizes) do
    indexed_edges = Enum.with_index(base_edges)

    sizes
    |> Enum.flat_map(fn k -> combinations(indexed_edges, k) end)
    |> Enum.map(fn combo ->
      {edges, indices} = Enum.unzip(combo)
      {PainStaking.parlay(edges), indices}
    end)
  end

  @doc """
  Calculate optimal Kelly stakes for a set of correlated bets.

  This function accounts for the correlations between parlays and their underlying legs
  by maximizing expected logarithmic growth across the joint distribution.

  ## Examples

      iex> e1 = {"A", [prob: 0.5], [eu: 2.2]}
      iex> e2 = {"B", [prob: 0.5], [eu: 2.2]}
      iex> base = [e1, e2]
      iex> candidates = PainStaking.Combinations.generate(base, [1, 2])
      iex> {:ok, results} = PainStaking.Combinations.kelly(base, candidates)
      iex> Enum.count(results)
      3
      iex> Enum.all?(results, fn {name, amt} -> is_binary(name) and is_float(amt) end)
      true

  """
  @spec kelly([PainStaking.edge()], [{PainStaking.edge(), [integer()]}], keyword()) ::
          {:ok, [PainStaking.tagged_number()]}
  def kelly(base_edges, candidates_with_indices, opts \\ []) do
    bankroll = Keyword.get(opts, :bankroll, 100)

    scenarios =
      base_edges
      |> PainStaking.edge_cdf(true)
      |> scenario_probabilities()

    candidate_payoffs =
      Enum.map(candidates_with_indices, fn {candidate, indices} ->
        calculate_payoffs_per_scenario(candidate, indices, scenarios)
      end)

    # Pre-calculate transposed payoffs for faster scenario-based wealth calculation
    payoffs_by_scenario =
      candidate_payoffs
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)

    initial_fs = Enum.map(candidates_with_indices, fn _ -> 0.0 end)

    optimal_fs =
      optimize(initial_fs, candidate_payoffs, payoffs_by_scenario, scenarios, @iterations)

    results =
      candidates_with_indices
      |> Enum.zip(optimal_fs)
      |> Enum.map(fn {{{desc, _, _}, _}, f} -> {desc, Float.round(f * bankroll, 2)} end)
      |> Enum.filter(fn {_, amount} -> amount > 0 end)

    {:ok, results}
  end

  defp scenario_probabilities(cdf) do
    cdf
    |> Enum.reduce({[], 0.0}, fn {vals, cum}, {acc, last_cum} ->
      {[{vals, cum - last_cum} | acc], cum}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp calculate_payoffs_per_scenario({_desc, _fair, offered}, indices, scenarios) do
    odds = PainStaking.extract_price_value(offered, :eu)
    net_odds = odds - 1.0

    Enum.map(scenarios, fn {base_vals, _prob} ->
      # Convert to tuple for O(1) access if many legs, though usually few
      vals = List.to_tuple(base_vals)
      win? = Enum.all?(indices, fn idx -> elem(vals, idx) > 0 end)
      if win?, do: net_odds, else: -1.0
    end)
  end

  defp optimize(fs, _payoffs, _payoffs_by_scenario, _scenarios, 0), do: fs

  defp optimize(fs, payoffs, payoffs_by_scenario, scenarios, iterations) do
    grads = calculate_gradients(fs, payoffs, payoffs_by_scenario, scenarios)

    new_fs =
      fs
      |> Enum.zip(grads)
      |> Enum.map(fn {f, g} -> max(0.0, f + g * @learning_rate) end)

    # Constrain total sum < 1.0 (Bankroll constraint)
    total = Enum.sum(new_fs)
    constrained_fs = if total > 1.0, do: Enum.map(new_fs, fn f -> f / total end), else: new_fs

    # Convergence check
    diff =
      fs
      |> Enum.zip(constrained_fs)
      |> Enum.reduce(0.0, fn {old, new}, acc -> acc + abs(old - new) end)

    if diff < @convergence_threshold do
      constrained_fs
    else
      optimize(constrained_fs, payoffs, payoffs_by_scenario, scenarios, iterations - 1)
    end
  end

  defp calculate_gradients(fs, payoffs, payoffs_by_scenario, scenarios) do
    # Pre-calculate scenario wealths efficiently
    scenario_wealths =
      calculate_all_scenario_wealths(scenarios, payoffs_by_scenario, fs, [])

    # Calculate gradient for each candidate
    Enum.map(payoffs, fn payoffs_i ->
      calculate_candidate_gradient(scenario_wealths, payoffs_i, 0.0)
    end)
  end

  defp calculate_all_scenario_wealths([], [], _fs, acc), do: Enum.reverse(acc)

  defp calculate_all_scenario_wealths(
         [{_vals, prob} | rest_s],
         [s_payoffs | rest_sp],
         fs,
         acc
       ) do
    profit = calculate_scenario_profit(fs, s_payoffs, 0.0)
    calculate_all_scenario_wealths(rest_s, rest_sp, fs, [{prob, 1.0 + profit} | acc])
  end

  defp calculate_scenario_profit([], [], acc), do: acc

  defp calculate_scenario_profit([f | rest_f], [p | rest_p], acc) do
    calculate_scenario_profit(rest_f, rest_p, acc + f * p)
  end

  defp calculate_candidate_gradient([], [], acc), do: acc

  defp calculate_candidate_gradient([{prob, wealth} | rest_w], [p | rest_p], acc) do
    calculate_candidate_gradient(rest_w, rest_p, acc + prob * (p / wealth))
  end

  # Helper: Generate all k-combinations of a list
  defp combinations(_list, 0), do: [[]]
  defp combinations([], _k), do: []

  defp combinations([h | t], k) do
    for(subset <- combinations(t, k - 1), do: [h | subset]) ++ combinations(t, k)
  end
end
