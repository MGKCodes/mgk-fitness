# /wrap extras for mgk-fitness

Read by the `/wrap` skill. The routine every repo shares (the Raw inbox,
Knowledge, the Journal) lives in the skill and is not repeated here; this file
holds only the checks this repo has. Everything in it is read-only: report,
don't act.

The contract with the skill is this file's path, the `## Open` heading, and the
scope words below. Change any of those and the skill stops finding them.

## Scope

`/wrap open lift`, `/wrap open run` or `/wrap open mgkfitness`. No word means
`mgkfitness`.

| Scope        | Products in Notion       | Issues shown                                  | Store status   |
| ------------ | ------------------------ | --------------------------------------------- | -------------- |
| `lift`       | Lift, mgk-fitness        | labelled `lift`, or labelled neither app      | `lift`         |
| `run`        | Run, mgk-fitness         | labelled `run`, or labelled neither app       | `run`          |
| `mgkfitness` | mgk-fitness, Run, Lift   | all open issues                               | `lift`, `run`  |

An issue with neither app label is shared work (the coach, the database, the
site) and belongs to both apps, so it shows in either scope.

## Open

1. **Open issues.** Matthew files what he finds while using the apps as GitHub
   issues here: `lift` / `run` for the app, `p1` (fix next, blocks use or
   release) and `p2` (soon, not blocking). The command sorts p1 first.

   For `lift` (swap `lift` and `run` for the `run` scope):

   ```bash
   gh issue list --state open --limit 100 --json number,title,labels,createdAt --jq 'map({n: .number, t: .title, l: [.labels[].name], d: .createdAt[:10]}) | map(select((.l | any(. == "lift")) or (.l | any(. == "run") | not))) | sort_by(if (.l | any(. == "p1")) then 1 elif (.l | any(. == "p2")) then 2 else 3 end) | .[] | "#\(.n) \(.t) [\(.l | join(", "))] opened \(.d)"'
   ```

   For `mgkfitness`, drop the second `map(select(...))`.

   Say *"N open issues for Lift: ..."* with the lines as printed, p1s first.
   If there are none, say so in one line.

2. **Store review.** While a version is waiting on a store, how long it has
   waited is the thing to know.

   ```bash
   python scripts/store/stores.py status lift
   ```

   No `--ios` or `--android` reads both stores, and nothing changes without
   `--yes`. Report only versions that are not live yet (waiting for review,
   in review, rejected, ready to release), with the date they went in. If
   everything is live, say so in one line. The keys are in
   `C:\Users\matty\.mgk-fitness\`; if the script can't find them, say so and
   move on.
