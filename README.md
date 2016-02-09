# PainStaking

Bet stake sizing in Elixir:

- Kelly staking
- Arbitrage
- Monte Carlo simulated wins
- Mathematical expectation

## Dependencies

- Exoddic

## Installation

```
# add dependencies in mix.exs
defp deps do
  [
    {:painstaking, "~> 0.5"}
  ]
end

# and fetch
$ mix deps.get
```

## Examples

```
iex> PainStaking.kelly([{"loser", [prob: 0.50], [us: -110]}])
{:error, "No suitable positive expectation edges found."}
iex> PainStaking.kelly([{"winner", [prob: 0.50], [us: "+101"]}], bankroll: 20_000)
{:ok, [{"winner", 99.01}]}

iex> PainStaking.arb([{"lions", [prob: 0.55], [us: "+100"]}, {"bears", [prob: 0.45], [eu: 2.00]}])
{:error, "No arbitrage exists for these events."} # No arb
iex> PainStaking.arb([{"lions", [prob: 0.55], [us: "+100"]}, {"bears", [prob: 0.45], [eu: 2.10]}], independent: true)
{:error, "No arbitrage exists for these events."} # Arbitrage only on different results for same event
iex> PainStaking.arb([{"lions", [prob: 0.55], [us: "+100"]}, {"bears", [prob: 0.45], [eu: 2.10]}], bankroll: 1_000)
{:ok, [{"lions", 512.20}, {"bears", 487.80}], 24.39} # Arb available, bet on each, net 24.39 regardless of outcome

iex> PainStaking.sim_win([{"big winner", [prob: 0.80], [us: -110]}])
{:ok, 30.00} # Or something close, depending on how the sim works out.

iex> PainStaking.ev([{"big winner", [prob: 0.80], [us: -110]}, {"winner", [prob: 0.50], [us: "+101"]}], bankroll: 1)
{:ok, [{"big winner", 1.5272727272727273}, {"winner", 1.005}]}
```
