# PainStaking

Bet stake sizing in Elixir:

- Kelly Criterion
- Arbitrage

## Examples

```
PainStaking.kelly_size(20000,[{[prob: 0.50], [us: -110]}])
[0.0] # no edge, no bet
PainStaking.kelly_size(20000,[{[prob: 0.50], [us: +101]}])
[99.01]

PainStaking.arb_size(1000, [[us: "+100"], [eu: 2.00]])
{:error, "No arbitrage exists for these events."} # No arb
PainStaking.arb_size(1000, [[us: "+100"], [eu: 2.10]])
{:ok, [500.0, 476.19], 23.81} # Arb available, bet on each, net 23.81 regardless of outcome

PainStaking.sim_win_for(10,[{[prob: 0.80], [us: -110]}], 100)
3.0 # Or something close, depending on how the sim works out.
```
