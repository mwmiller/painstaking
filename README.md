# PainStaking

Bet stake sizing in Elixir:

- Kelly Criterion
    - Simultanenous independent events are currently over-bet
- Arbitrage

Available in hex: `{:painstaking, "~> 0.2.0"}`

## Examples

```
PainStaking.kelly([{"loser", [prob: 0.50], [us: -110]}])
{:error, "No suitable positive expectation edges found."}
PainStaking.kelly([{"winner", [prob: 0.50], [us: "+101"]}], [bankroll: 20000])
{:ok, [{"winner", 99.01}]}

PainStaking.arb([[us: "+100"], [eu: 2.00]])
{:error, "No arbitrage exists for these events."} # No arb
PainStaking.arb([[us: "+100"], [eu: 2.10]], [independent: false])
{:error, "No arbitrage exists for these events."} # Arbitrage only on same event
PainStaking.arb([[us: "+100"], [eu: 2.10]], [bankroll: 1000])
{:ok, [500.0, 476.19], 23.81} # Arb available, bet on each, net 23.81 regardless of outcome

PainStaking.sim_win([{"big winner", [prob: 0.80], [us: -110]}], 100)
30.00 # Or something close, depending on how the sim works out.

PainStaking.ev([{"big winner", [prob: 0.80], [us: -110]}, {"winner", [prob: 0.50], [us: "+101"]}], [bankroll: 1])
{:ok, [{"big winner", 1.5272727272727273}, {"winner", 1.005}]}
```
