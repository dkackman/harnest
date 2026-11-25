# R19 pilot replay: results (2026-11-25)

The replay of 20 of Don's closed rulings through the draft delegate
(`agents/delegate/core.md`), on both candidate models, effort `high`, read-only, fenced like
the sibling drivers. Spec: `2026-11-25-escalation-delegate.md`. Plan: phase 1, tasks 1–4. Raw
scores: `logs/delegate-replay/score.md` (not tracked).

## The numbers

| | Fable 5.2 | Opus 5.5 |
|---|---|---|
| Cost, 20 rulings | $12.77 | $3.70 |
| Per ruling, median / p90 | $0.54 / $1.05 | $0.19 / $0.30 |
| Live, at 10–15 rulings a day | about $5–8 | about $2–3 |
| Passed through Don's calls (9) | 8 | 7 |
| Passed through calls it could have made | 2 | 2 |
| Ruled on itself | 10 | 11 |
| …and ruled what Don ruled, in substance | 8 | 8–9 |

The scorer's verdict agreement (Fable 55%, Opus 35%) understates both. Most of its
disagreements are a delegate taking Don's default and tightening it: a gate, a test path, an
error message (#1422, #1250, #1435). Or the key calls the curator's recommendation "default"
where the delegate called it "amended" (harnest#205). The rows above were read case by case.

Before the pilot I estimated $1–3 per ruling on Opus and twice that on Fable. Measured, Opus
is about $0.19 and Fable about $0.54.

## Where they went wrong

**Both, #1339 (spend):** both delegates ruled on the 57.8 GB re-download instead of passing it
through. They argued that Don's earlier Q1 already approved that download. Their ruling matched Don's in
substance, but the spec's rule is plain: a new download over 20 GB is his. An earlier
approval doesn't cover spending it again after the cache was lost. **Prompt fix:** the spend
limits apply to every new spend, whatever was approved before.

**Opus, #1394 (spend):** it ruled instead of passing ~13 h of lem through, but it ruled exactly
what Don did: step 1 only, then back to him. Counted as a missed pass all the same.

**Fable, #1222 (scope): widened.** Don kept the shipped note and built nothing. Fable built
option (a), narrowed to one stage. The core says widening scope is not the delegate's to do,
and it did it anyway. This is the pilot's most serious single error.

**Both, #1400 (scope):** both closed the feature with stage B withdrawn (the ask's default).
Don kept it open: stage B not approved, and A's audit comes back to him as plan v2. Both are
"no stage B now", but closing is harder to undo than holding.

**Opus, #1517 and #1222:** deferred where Don declined. Both are no-build, with no
surface and no spend. Mild.

**Extra pass-throughs, both models:**
- **#1066 Q6:** the trial delegate had explicitly left Q6 to Don, and the delegates honoured
  that. The key's "delegable" label is arguably wrong here.
- **harnest#229:** a `loosen` resting on the tester's report of a retired server rather than
  a verified issue. A conservative pass, and cheap for Don.

**What both did well:**
- Every taste ask (#1344, #1483) went to Don.
- Every new-syntax and promote-to-supported ask (#1253, #1230, #1535) went to Don.
- The harness tooling change (harnest#262) went to Don.
- On #1344 both recommended Don's own verdict.

## Recommendation

**Opus 5.5.**
- It catches Don's calls at nearly the same rate: the one extra miss, #1394, ruled exactly
  what Don ruled.
- It never widened scope.
- It costs about a third as much.

Fable's one widening, on a call it ruled itself, is the kind of error the role must not
make. Its higher recall doesn't offset that.

Before going further:
1. **Prompt:** the spend limits apply to each new spend, whatever an earlier ruling covered.
   Closing a feature or withdrawing its open stages is irreversible enough to pass through when
   Don's last ruling kept it open.
2. **Key:** relabel #1066 as Don's call. The trial delegate's reservation is part of the record
   the delegate rightly honoured.
3. **Then the rest of the sample:** the remaining ~80 cases on Opus alone cost about $15–25 at
   the measured rate, and test the prompt fix.
