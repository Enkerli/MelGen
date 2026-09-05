# TESTING

*Written 2026-08-26. What `Scripts/verify.sh` cannot answer, and how to answer it
on a device in about forty minutes.*

`verify.sh` checks 34 suites and none of them can hear anything. It cannot tell
you whether a line is worth keeping, whether a control is findable, or whether a
sentence means what it says. This document is the other half, and it is
deliberately short: a long test plan is one nobody runs.

**The rule that makes this worth doing:** write down what you expect *before* you
look. A session that only records what happened produces impressions; a session
that records a prediction and then contradicts it produces findings. Every
failure in [ISSUES.md](ISSUES.md) that turned out to matter came from a
contradicted expectation — the model that "wasn't on the device" and had been
working for a week, the templates that "obviously" differentiated and measured
0.04 apart.

---

## 1. What can't be checked any other way

Four things, in order of how much they cost to get wrong.

| # | Claim | Why no suite can check it |
|---|---|---|
| 1 | **A take is worth keeping** | Musical judgement. The measurements say *varied*, not *good* |
| 2 | **A control is findable when it's wanted** | Findability is about a person's state, not the view's |
| 3 | **The model earns its 1.8 seconds a note** | Foundation Models is absent from the Simulator |
| 4 | **A sentence means what it says** | `terminology` checks vocabulary, not comprehension |

Everything below is one of those four.

---

## 2. Setup

- **Hardware, not the Simulator.** Foundation Models doesn't exist there, and
  `verify.sh` covers everything that doesn't need it.
- **A host, not the standalone app**, for anything about playing — AUM or
  Logic. The standalone is for the picker and the panel.
- **Check Settings ▸ Apple Intelligence & Siri first.** A third-party model
  extension redirects requests away from the on-device model and generation
  fails with an error about content, which is not what it is
  ([ISSUES.md](ISSUES.md), F12b). This cost a session once.
- **Export the history afterwards.** `Scripts/analyse-history.sh` turns a session
  into numbers. An exported history is the difference between "the takes felt
  samey" and "60 distinct lines behind 98 takes".

---

## 3. The scenarios

Five, about eight minutes each. Do them in order — each assumes the last.

### S1 · Cold start

*Open the plug-in in a host with no saved session and make something you'd keep.*

Predict first: **how many taps** to hear the first take, and **which control**
you will reach for first.

Watch for: whether the next-step line is read at all or scrolled past; whether
"Set the changes" is understood as the blocking thing it is; whether the source
list's costs (`~1.8s a note` vs `instant`) change which one is chosen.

> **Under test:** does the interface open in the right place, and does the
> guidance line get read or ignored? A line nobody reads is furniture, and the
> whole design bet in `NextStep.swift` is that it won't be.

### S2 · A sweep

*Generate eight takes with Auto on at 2 laps. Rate every one as it goes by.*

Predict first: **how many you expect to keep**, and whether you will use the
three coarse answers or reach for the seven.

Watch for: whether Yes/Maybe/No is enough; whether the swipe is discovered
without being told; whether "another like this" and "something else" reliably
differ *to the ear* — the `advance` suite proves they differ structurally, which
is not the same claim.

> **Under test:** claim 1, and whether the rating strip made the sweep faster or
> merely shorter. ISSUES §4 predicts the seven are still wanted for `tweak` and
> `partial`; contradict that if you can.

### S3 · The drawers

*Keep going until the next-step line points at **Your material**, then at
**Setup**. Follow each.*

Predict first: **what you expect to find** behind each, before you tap.

Watch for: whether the learned readout means anything to you (it's the feedback
that says whether keeping takes does anything); whether "Setup" reads as *the
current settings* or as *saved ones* — the name promises the first and delivers
the second, which is half of why it was inscrutable.

> **Under test:** claims 2 and 4, and the guidance line's whole reason for
> existing. If following the line still lands you somewhere confusing, the
> problem is the destination, not the pointer.

### S4 · Round trip

*Export a take as MIDI. Open it in MIDIcurator or a DAW. Import it back.*

Predict first: **what you expect to survive** the trip.

Watch for: whether the chord markers show in the other app; whether the changes
come back in the field; whether the line joins the stored lines and plays over
*different* changes. Then the other direction — import something MIDIcurator
exported and check which harmony tier it used (the status line says).

> **Under test:** the one thing `verify.sh midifile` structurally cannot reach —
> the document picker and another application's reader. The codec round trip is
> proven; the *interchange* is not.

### S5 · Read the changes

*Play a chord progression in on a keyboard with Listen on. Tap **Read the
changes**. Then do it again with a single-note line.*

Predict first: **what you expect the line to produce.**

Watch for: whether the button's subtitle told you the answer before you tapped;
whether "inferred from a line" was noticed and understood. A melody always spells
*something* — the design bet is that saying so is enough.

> **Under test:** claim 4, on the one place where the app is knowingly guessing.

---

## 4. Recording it

One line per finding, in this shape, straight into [ISSUES.md](ISSUES.md) §4:

```
Expected X. Got Y. (scenario, build, host)
```

Two rules, both learned the hard way:

- **A number beats an adjective.** "Samey" is unactionable; "six of eight takes
  shared a contour" is a bug report. `Scripts/analyse-history.sh` produces the
  numbers, so prefer running it to arguing from memory.
- **A diagnosis that contradicts the evidence is wrong, however plausible.**
  Before writing down a cause, check what the app already recorded —
  `modelHasWorkedHere`, the take's own source, the generation time. F12b is in
  ISSUES because a confident explanation was believed over a fact the app was
  already storing.

Anything about *what to build* goes to [ROADMAP.md](ROADMAP.md) instead; anything
about *vocabulary* to [TERMINOLOGY.md](TERMINOLOGY.md). Keeping them apart is
what stops a finding being written down three times and fixed none.

---

## 5. What is still not covered

Said plainly so it isn't mistaken for coverage:

- **Nothing here is repeatable across people.** These are structured sessions,
  not a protocol. Two people running S2 will disagree about which takes were
  worth keeping, and that disagreement is data rather than noise.
- **No timing is measured.** "How long to the first take" is a prediction to
  contradict, not a metric.
- **Multi-instance and multi-host behaviour is untested.** Two MelGens in one
  session share `UserDefaults` for the library and the setups
  ([ISSUES.md](ISSUES.md) §4, the App Group item) and nothing has probed what
  that feels like.
- **VoiceOver is a separate pass** (ROADMAP U5), not folded in here — running it
  alongside a musical judgement gets both done badly.
