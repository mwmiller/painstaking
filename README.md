# PainStaking

Bet stake sizing in Elixir:

- Kelly Criterion
- Arbitrage

## Examples

```
PainStaking.kelly_size(20000, { [prob: 0.54], [us: "-120"] })
{:error, "This is not an advantage situation."} # no edge, no bet
PainStaking.kelly_size(20000, { [prob: 0.55], [us: "-120"] })
{:ok, 200.0} # small edge, small bet

PainStaking.arb_size(1000, [[us: "+100"], [eu: 2.00]])
{:error, "No arbitrage exists for these events."} # No arb
PainStaking.arb_size(1000, [[us: "+100"], [eu: 2.10]])
{:ok, [500.0, 476.19], 23.81} # Arb available, bet on each, net 23.81 regardless of outcome
```
