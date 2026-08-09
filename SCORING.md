# Scoring

Published before anyone writes a crawler, so the rules are never a surprise
on race day. The mechanism lives in
`platform/lib/wiki_race_platform/race/result.ex`. This page is the same
thing in plain words.

## The score

Every crawler in a race gets one number: the score. Highest wins, full
stop. There is no separate tiebreak step, since the score already accounts
for everything. It is a weighted sum of four parts, each between 0.0 and
1.0:

| Term | What it measures |
| --- | --- |
| Found | 1.0 if you reported a path the harness could verify, else 0.0 |
| Hops | The best finisher's path length divided by yours |
| Time | The best finisher's elapsed time divided by yours |
| Utilization | Your BEAM's scheduler utilization across the whole race |

Found, hops, and time are all zero if you never found a valid path. There
is no partial credit for a claimed-but-unverified path, and no extra
penalty for taking longer or searching deeper than the winner. Hops and
time are ratios against the best finisher in that race, not fixed
constants. So the better of two crawlers always scores 1.0 on that axis
and the other scores less. A slow VM or a noisy network can't decide a
race by itself. A solo time trial (a bye) scores 1.0 on both, since there
is no other finisher to compare against.

Utilization is measured for every crawler, win or lose. That is on
purpose: if both crawlers fail to find a path, the race is not a coin
flip. It is decided by which one made better use of the concurrency
primitives the course actually teaches. The harness reads this straight
from the BEAM's own scheduler accounting. Nothing about it comes from you,
and `WikiRace.Crawler`, `WikiRace.Status`, and `WikiRace.Harness` need no
changes for it to work.

The total score is a weighted sum of these four terms. Current weights,
from `platform/config/config.exs`
(`config :wiki_race_platform, :scoring, weights: ...`):

| Term | Weight |
| --- | ---: |
| Found | 0.5 |
| Hops | 0.3 |
| Time | 0.1 |
| Utilization | 0.1 |

With these weights, finding a valid path is worth more than everything
else combined: any finisher scores at least 0.5, any non-finisher at most
0.1. But the ranking is not gated on "found > hops > time > utilization"
in order. It is one number, and the weights are what make finding a path
dominate in practice.

## Reporting a path that isn't real

One exception to all of the above: if you ever report a path the
harness's verifier rejects, because it doesn't actually start where you
said, doesn't end at the target, or claims a link between two articles
that doesn't exist on the snapshot, your score for that race is a flat
-1.0, full stop. Found, hops, time, and utilization all stop mattering the
moment that happens. There is no blend, no partial credit, and no way for
a good utilization number or a fast time to buy it back.

This is worse than every honest outcome, including finding nothing at all
(0.0-0.1). Searching hard and coming up empty is a real result. Claiming a
path you didn't actually walk is not, and the score reflects that
difference on purpose. A crawler that reports one bad path and later
reports a real, verified one still gets the flat -1.0 for that race. The
penalty is for the act of reporting something false, and getting it right
afterward does not undo it. It is never credited as the winner either,
even if the other crawler found nothing.

## What's measured, and how

- Found, hops, and time all come from `WikiRace.Harness.report/1`, see
  `WikiRace.Crawler`'s docs. The harness timestamps a report's arrival on
  its own clock, not whatever your node's clock says when you called it.
  `status/1`'s `path` and `state: :found` fields are for the dashboard
  only. They don't decide anything.
- `status/1` is polled roughly every 250ms for the whole race, purely to
  drive the live dashboard. It never affects the score.
- Scheduler utilization is sampled twice per race: once the moment your
  crawler starts, once the moment the race ends, via
  `:erlang.statistics(:scheduler_wall_time_all)`, read remotely by the
  harness. It is the fraction of total scheduler time your node spent
  actually running code (across all schedulers, including dirty ones)
  between those two snapshots, not a continuous trace.
- The moment a race ends (both crawlers settled, or the time limit hit),
  the harness scores it against everything reported and measured up to
  that instant. A crawler that never reports and never returns a usable
  `status/1` is scored as not having found a path, the same as reporting
  nothing.
