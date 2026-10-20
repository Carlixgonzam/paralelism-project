# Scoring

This page explains how a race is scored. The code is in
`platform/lib/wiki_race_platform/race/result.ex`.

## Points

Each crawler gets a score between 0.0 and 1.0. The highest score wins the race.

The score is the sum of five parts:

| Part        | Points     | How you get them                                                |
| ----------- | ---------- | --------------------------------------------------------------- |
| Found       | 0.40       | You find a valid path.                                          |
| First       | 0.15       | Your first valid path arrives before the other crawler's.       |
| Hops        | up to 0.20 | 0.20 × (length of the shortest path in the race / your length). |
| Time        | up to 0.15 | 0.15 × (fastest time in the race / your time).                  |
| Utilization | up to 0.10 | 0.10 × (how busy your schedulers were, from 0 to 1).            |

- The crawler with the shortest path gets the full 0.20 for hops. The fastest crawler
  gets the full 0.15 for time.
- Your time is the moment your shortest path arrives at the harness.
- First counts your first valid path, even if you send a shorter path later.
- Without a valid path, you only get the utilization points, so at most 0.10.
- In a bye (a race with one crawler), a finisher gets the full points for first, hops
  and time.

Speed matters more than path length. First and time together give 0.30, and hops gives
0.20. So the crawler that finds a valid path first usually wins.

## Example

Group A finds a path of 4 articles at 10 s. Group B finds a path of 4 articles at 12 s.
Both have a utilization of 0.5.

| Part        | Group A             | Group B              |
| ----------- | ------------------- | -------------------- |
| Found       | 0.40                | 0.40                 |
| First       | 0.15                | 0.00                 |
| Hops        | 0.20 × 4/4 = 0.20   | 0.20 × 4/4 = 0.20    |
| Time        | 0.15 × 10/10 = 0.15 | 0.15 × 10/12 = 0.125 |
| Utilization | 0.10 × 0.5 = 0.05   | 0.10 × 0.5 = 0.05    |
| **Score**   | **0.95**            | **0.775**            |

Group A wins.

## Wrong paths

If you report a path that the harness rejects, your score for the race is **-1.0**. The
other parts do not count. A path is rejected when:

- it does not start at the start article,
- it does not end at the target article,
- it visits an article twice, or
- it uses a link that does not exist in the snapshot.

A correct path sent later does not cancel the penalty. A crawler with a wrong path never
wins the race, and it cannot take the first points from the other crawler. A score of
-1.0 is worse than finding nothing.

## How it is measured

- A path counts when you call `WikiRace.Harness.report/1`, or when `status/1` returns
  `state: :found` with a path. The harness checks both in the same way.
- Times are measured with the clock of the harness, not the clock of your node.
- Utilization is measured on your node when your crawler starts and when the race ends,
  with `:erlang.statistics(:scheduler_wall_time_all)`. It counts all schedulers,
  including dirty schedulers. You do not need to send anything.
- The dashboard calls `status/1` every 250 ms to show your progress.
- The points come from the weights in `platform/config/config.exs`
  (`config :wiki_race_platform, :scoring`).
