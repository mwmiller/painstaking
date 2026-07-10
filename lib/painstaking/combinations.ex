defmodule PainStaking.Combinations do
  @moduledoc """
  Generate and size combinations of wagers (straights and parlays).
  """
  import Bitwise

  @type size_spec :: [integer()] | Range.t() | :all

  @iterations 500
  @learning_rate 0.01
  @convergence_threshold 1.0e-7
  @max_exact_ops 800_000
  @qp_iterations 200

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

  For small problems uses exact gradient ascent over all 2^N scenarios.
  For larger problems uses a mean-variance quadratic programming
  approximation which computes all moments analytically — no scenario enumeration.

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

    leg_data = Enum.map(base_edges, fn {_d, p, o} ->
      {PainStaking.extract_price_value(o, :eu), PainStaking.extract_price_value(p, :prob)}
    end)

    {good_data, good_indices} = extract_good_legs(leg_data, 0, [], [])
    n = length(good_data)

    if n == 0 do
      {:ok, []}
    else
      index_map = Enum.zip(good_indices, 0..(n - 1)) |> Map.new()
      good_candidates = filter_candidates(candidates_with_indices, index_map, [])

      if Enum.empty?(good_candidates) do
        {:ok, []}
      else
        leg_probs = good_data |> Enum.map(fn {_eu, p} -> p end) |> List.to_tuple()
        leg_odds = good_data |> Enum.map(fn {eu, _p} -> eu end) |> List.to_tuple()

        candidate_data = Enum.map(good_candidates, fn {candidate, indices} ->
          odds = PainStaking.extract_price_value(elem(candidate, 2), :eu)
          net_odds = odds - 1.0
          mask = Enum.reduce(indices, 0, fn idx, acc -> acc ||| (1 <<< idx) end)
          {net_odds, mask}
        end)
        num_candidates = length(candidate_data)
        num_scenarios = 1 <<< n

        optimal_fs =
          if num_candidates * num_scenarios > @max_exact_ops do
            optimize_qp(candidate_data, leg_probs, leg_odds)
          else
            scenarios = generate_scenarios(good_data, n)

            candidate_payoffs = Enum.map(candidate_data, fn {net_odds, candidate_mask} ->
              Enum.map(scenarios, fn {scenario_mask, _prob} ->
                if (scenario_mask &&& candidate_mask) == candidate_mask, do: net_odds, else: -1.0
              end)
            end)

            payoffs_by_scenario =
              candidate_payoffs
              |> Enum.zip()
              |> Enum.map(&Tuple.to_list/1)

            initial_fs = Enum.map(candidate_data, fn _ -> 0.0 end)
            optimize_exact(initial_fs, candidate_payoffs, payoffs_by_scenario, scenarios, @iterations)
          end

        results =
          good_candidates
          |> Enum.zip(optimal_fs)
          |> Enum.map(fn {{{desc, _, _}, _}, f} -> {desc, Float.round(f * bankroll, 2)} end)
          |> Enum.filter(fn {_, amount} -> amount > 0 end)

        {:ok, results}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-trimming helpers
  # ---------------------------------------------------------------------------

  defp extract_good_legs([], _idx, good_data, good_indices) do
    {Enum.reverse(good_data), Enum.reverse(good_indices)}
  end

  defp extract_good_legs([{eu_odds, prob} | rest], idx, good_data, good_indices) do
    if prob * eu_odds > 1.0 do
      extract_good_legs(rest, idx + 1, [{eu_odds, prob} | good_data], [idx | good_indices])
    else
      extract_good_legs(rest, idx + 1, good_data, good_indices)
    end
  end

  defp filter_candidates([], _index_map, acc), do: Enum.reverse(acc)

  defp filter_candidates([{candidate, indices} | rest], index_map, acc) do
    case remap_indices(indices, index_map, []) do
      {:ok, new_indices} ->
        filter_candidates(rest, index_map, [{candidate, new_indices} | acc])
      :error ->
        filter_candidates(rest, index_map, acc)
    end
  end

  defp remap_indices([], _index_map, acc), do: {:ok, Enum.reverse(acc)}

  defp remap_indices([idx | rest], index_map, acc) do
    case Map.fetch(index_map, idx) do
      {:ok, new_idx} -> remap_indices(rest, index_map, [new_idx | acc])
      :error -> :error
    end
  end

  # ---------------------------------------------------------------------------
  # Exact scenario-based gradient ascent
  # ---------------------------------------------------------------------------

  defp generate_scenarios(good_data, n) do
    win_tup = good_data |> Enum.map(fn {_eu, p} -> p end) |> List.to_tuple()
    lose_tup = good_data |> Enum.map(fn {_eu, p} -> 1.0 - p end) |> List.to_tuple()
    total = 1 <<< n

    Enum.map(0..(total - 1), fn mask ->
      prob = scenario_prob(mask, win_tup, lose_tup, n)
      {mask, prob}
    end)
  end

  defp scenario_prob(mask, win_tup, lose_tup, n) do
    scenario_prob(mask, win_tup, lose_tup, 0, n, 1.0)
  end

  defp scenario_prob(_mask, _wt, _lt, i, n, acc) when i >= n, do: acc

  defp scenario_prob(mask, win_tup, lose_tup, i, n, acc) do
    p = if ((mask >>> i) &&& 1) == 1, do: elem(win_tup, i), else: elem(lose_tup, i)
    scenario_prob(mask, win_tup, lose_tup, i + 1, n, acc * p)
  end

  defp optimize_exact(fs, _payoffs, _payoffs_by_scenario, _scenarios, 0), do: fs

  defp optimize_exact(fs, payoffs, payoffs_by_scenario, scenarios, iterations) do
    grads = calculate_gradients(fs, payoffs, payoffs_by_scenario, scenarios)

    new_fs =
      fs
      |> Enum.zip(grads)
      |> Enum.map(fn {f, g} -> max(0.0, f + g * @learning_rate) end)

    total = Enum.sum(new_fs)
    constrained_fs = if total > 1.0, do: Enum.map(new_fs, fn f -> f / total end), else: new_fs

    diff =
      fs
      |> Enum.zip(constrained_fs)
      |> Enum.reduce(0.0, fn {old, new}, acc -> acc + abs(old - new) end)

    if diff < @convergence_threshold do
      constrained_fs
    else
      optimize_exact(constrained_fs, payoffs, payoffs_by_scenario, scenarios, iterations - 1)
    end
  end

  defp calculate_gradients(fs, payoffs, payoffs_by_scenario, scenarios) do
    scenario_wealths =
      calculate_all_scenario_wealths(scenarios, payoffs_by_scenario, fs, [])

    Enum.map(payoffs, fn payoffs_i ->
      calculate_candidate_gradient(scenario_wealths, payoffs_i, 0.0)
    end)
  end

  defp calculate_all_scenario_wealths([], [], _fs, acc), do: Enum.reverse(acc)

  defp calculate_all_scenario_wealths(
         [{_mask, prob} | rest_s],
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
    w = max(wealth, 1.0e-15)
    calculate_candidate_gradient(rest_w, rest_p, acc + prob * (p / w))
  end

  # ---------------------------------------------------------------------------
  # Mean-variance QP (no 2^N scenario enumeration)
  # ---------------------------------------------------------------------------

  defp optimize_qp(candidate_data, leg_probs, leg_odds) do
    m = length(candidate_data)

    {mu, var} =
      Enum.map(candidate_data, fn {_net_odds, mask} ->
        mu = expected_return(mask, leg_probs, leg_odds)
        e_x2 = expected_product(mask, mask, leg_probs, leg_odds)
        {mu, e_x2 - mu * mu}
      end)
      |> Enum.unzip()

    mu_tup = List.to_tuple(mu)

    cov_pairs =
      Enum.flat_map(1..(m - 1), fn i ->
        {_ni, mask_i} = Enum.at(candidate_data, i)
        mu_i = Enum.at(mu, i)

        Enum.flat_map(0..(i - 1), fn j ->
          {_nj, mask_j} = Enum.at(candidate_data, j)

          if (mask_i &&& mask_j) == 0 do
            []
          else
            mu_j = Enum.at(mu, j)
            e_xy = expected_product(mask_i, mask_j, leg_probs, leg_odds)
            [{i, j, e_xy - mu_i * mu_j}]
          end
        end)
      end)

    fs = List.duplicate(0.0, m)

    optimize_qp_loop(fs, mu_tup, var, cov_pairs, m, 0.01, @qp_iterations)
  end

  defp optimize_qp_loop(fs, _mu, _var, _cov, _m, _lr, 0), do: fs

  defp optimize_qp_loop(fs, mu_tup, var, cov_pairs, m, lr, iter) do
    sigma_f = compute_sigma_f(fs, var, cov_pairs, m)

    new_fs =
      fs
      |> Enum.zip(sigma_f)
      |> Enum.with_index()
      |> Enum.map(fn {{f, sf}, i} ->
        max(0.0, f + lr * (elem(mu_tup, i) - sf))
      end)

    total = Enum.sum(new_fs)
    constrained_fs = if total > 1.0, do: Enum.map(new_fs, fn f -> f / total end), else: new_fs

    diff =
      fs
      |> Enum.zip(constrained_fs)
      |> Enum.reduce(0.0, fn {old, new}, acc -> acc + abs(old - new) end)

    if diff < 1.0e-10 do
      constrained_fs
    else
      optimize_qp_loop(constrained_fs, mu_tup, var, cov_pairs, m, lr, iter - 1)
    end
  end

  defp compute_sigma_f(fs, var, cov_pairs, m) do
    base = Enum.zip(fs, var) |> Enum.map(fn {f, v} -> f * v end) |> List.to_tuple()

    updates =
      Enum.reduce(cov_pairs, :array.new(m, {:default, 0.0}), fn {i, j, cov}, acc ->
        contrib = cov * Enum.at(fs, j)
        acc = :array.set(i, :array.get(i, acc) + contrib, acc)
        contrib2 = cov * Enum.at(fs, i)
        :array.set(j, :array.get(j, acc) + contrib2, acc)
      end)

    Enum.map(0..(m - 1), fn i ->
      elem(base, i) + :array.get(i, updates)
    end)
  end

  defp expected_return(mask, leg_probs, leg_odds) do
    p_win = Enum.reduce(0..(tuple_size(leg_probs) - 1), 1.0, fn i, acc ->
      if ((mask >>> i) &&& 1) == 1, do: acc * elem(leg_probs, i), else: acc
    end)

    o_prod = Enum.reduce(0..(tuple_size(leg_odds) - 1), 1.0, fn i, acc ->
      if ((mask >>> i) &&& 1) == 1, do: acc * elem(leg_odds, i), else: acc
    end)

    p_win * o_prod - 1.0
  end

  defp expected_product(mask_a, mask_b, leg_probs, leg_odds) do
    union = mask_a ||| mask_b
    leg_indices = for i <- 0..(tuple_size(leg_probs) - 1), ((union >>> i) &&& 1) == 1, do: i
    k = length(leg_indices)
    total = 1 <<< k

    Enum.reduce(0..(total - 1), 0.0, fn subset, acc ->
      {scenario_mask, prob} =
        Enum.reduce(Enum.with_index(leg_indices), {0, 1.0}, fn {leg_idx, bit_pos}, {m, p} ->
          win = ((subset >>> bit_pos) &&& 1) == 1
          leg_p = elem(leg_probs, leg_idx)
          {
            if(win, do: m ||| (1 <<< leg_idx), else: m),
            p * if(win, do: leg_p, else: 1.0 - leg_p)
          }
        end)

      pa = if (scenario_mask &&& mask_a) == mask_a, do: payoff_value(mask_a, leg_odds), else: -1.0
      pb = if (scenario_mask &&& mask_b) == mask_b, do: payoff_value(mask_b, leg_odds), else: -1.0

      acc + prob * pa * pb
    end)
  end

  defp payoff_value(mask, leg_odds) do
    prod = Enum.reduce(0..(tuple_size(leg_odds) - 1), 1.0, fn i, acc ->
      if ((mask >>> i) &&& 1) == 1, do: acc * elem(leg_odds, i), else: acc
    end)
    prod - 1.0
  end

  # ---------------------------------------------------------------------------
  # Combination generation
  # ---------------------------------------------------------------------------

  defp combinations(_list, 0), do: [[]]
  defp combinations([], _k), do: []

  defp combinations([h | t], k) do
    for(subset <- combinations(t, k - 1), do: [h | subset]) ++ combinations(t, k)
  end
end