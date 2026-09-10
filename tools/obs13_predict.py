#!/usr/bin/env python3
"""obs13_predict — OBS-13's gate numbers, before its run.

Christian, naming the systems question and calling it the more
consequential one:

    Is overcompleteness actually advantageous during acquisition, even if
    consolidation produces the better final representation?

    grow -> fit -> consolidate -> resume learning

    Plasticity benefits from excess representational capacity; inference
    benefits from consolidation.  That would make redundancy not waste,
    but temporary scaffolding.

and the experiment, essentially verbatim:

    Start from the same trained overcomplete model.  Produce its
    consolidated child.  Then expose both to the same new data stream,
    with equal work budget and births allowed under the same policy.

    python3 tools/obs13_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-13 — scaffolding or baggage?  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE SETUP, AND WHAT IT REUSES RATHER THAN INVENTS

  parent      a MARL trained on the campaign's own truth
  child       its consolidated form: r_eff budget (OBS-10), target-
              conditioned selection (OBS-10), synthesis (OBS-11), at half
              the parent's population
  new regime  `TruthParams.shift = {0, -0.10, 0}` -- the campaign's OWN
              modest move, used by MARL-6 through MARL-9, so old and new
              structure stay comparable and nothing here needs a new
              constant

**The child is consolidated against the PARENT'S OWN PREDICTIONS, not
against the truth.**  That is the difference between sleep and cheating: a
consolidation reorganises what the model HAS, and a child handed the truth
on probes would start the new regime knowing something its parent had to
learn.  OBS-11 used the truth as its target and was right to -- it was
measuring representational quality, not a lifecycle.

Both arms then stream the same exemplars against the moved truth, with
births on and identical options.  Scored on held-out probes drawn against
the MOVED truth.

(2) A SECOND REGISTERED DISAGREEMENT

Christian's hypothesis is that redundancy is SCAFFOLDING: the overcomplete
parent should adapt faster, because excess capacity is what plasticity
runs on.

The agent expects the opposite, and the grounds are the campaign's own:

  MARL-6   after a move, 91% of pre-move child kernels end OUTSIDE the
           current band.  Committed capacity does not point where the new
           world is; it points where the old one was.
  MARL-1   capacity you cannot train is worse than capacity you do not
           have -- five sightings, and the parent carries twice as much of
           it into a regime that has moved under it.
  MARL-9   capacity is paid per THING LEARNED.  Both arms must buy the new
           structure; neither can inherit it.

    PREDICTED (agent)     final held-out RMS, child <= parent x 1.05
    PREDICTED (Christian) parent clearly ahead on adaptation rate

    The agent lost the last such disagreement (OBS-12) by reasoning from a
    property of the members rather than of the operation.  Recorded because
    that is exactly the failure mode to watch for here: "the parent has
    more capacity" is a property of the population, and what matters is
    whether that capacity is WHERE THE NEW EVIDENCE IS.

(3) THE THIRD OUTCOME, WHICH IS THE MOST INFORMATIVE

Christian: "if the child immediately regrows the same kinds of kernels
that sleep removed, then the consolidation criterion is too myopic or the
environment genuinely requires them."

    PREDICTED  the child regrows: final population >= 1.5x its post-sleep
               size, per MARL-7's ~1000 kernels a move at flat accuracy

    Regrowth alone does not decide between the two readings, and the
    predictor says so before the run: a child that regrows to the parent's
    size AND matches its accuracy has demonstrated the cycle is neutral;
    one that regrows and ends BETTER has demonstrated it is a ratchet.

(4) THE NULLS

    PREDICTED  both arms consume exactly the same exemplar count, and the
               initial error on the new regime is within 1.25x between
               them -- the child starts with half the kernels, so it may
               be worse, but if it starts MUCH worse the consolidation
               damaged what transferred and the adaptation comparison is
               confounded from step zero.

    PREDICTED  the child's post-sleep population is close to half the
               parent's, since that is the budget it was given

(5) WHAT WOULD MAKE THIS DECISIVE EITHER WAY

  parent faster, child better after a SECOND sleep   a real
      plasticity/consolidation CYCLE, and the strongest possible result
  child equal or faster                              redundancy was
      baggage, not scaffolding
  child regrows exactly what sleep removed           the criterion is
      myopic -- which is the objective's fault and not consolidation's,
      and points straight at the replay measure OBS-11 recorded and did
      not build

A second sleep is NOT run here. One cycle first, so that the adaptation
comparison is not entangled with a second consolidation's own gain.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
