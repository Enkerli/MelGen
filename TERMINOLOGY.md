# TERMINOLOGY

One word per concept, one concept per word. Written because "pass" meant three
different things, two of them on the same screen.

Rules for this file: a term is defined once, here. Where the code's identifier
differs from the term, the identifier is named so the drift is visible rather
than discovered. A term marked **retired** must not appear in the interface.

---

## Collisions resolved

| Was | Now | Meaning |
|---|---|---|
| pass (kernel) | **lap** | One traversal of the loop |
| pass (drift) | **roll** | One re-roll of the drift dice |
| pass (curation) | **pass** | One sweep of judgement over the record |
| mutation (live) | **drift** | Render-time re-rolling, never written back |
| mutation (offline) | **variant** | A transform of a take, offered as a candidate |
| line (library item) | **stored line** | A take read back as scale degrees |
| line (mode) | **Line** | Monophonic output, as against Chords |

---

## Terms

**take** — One candidate, stored. Raw notes before expression, plus the setup
that made it, its measurement, its marks and its tags. The unit everything
downstream treats alike, whichever of the six sources produced it. Immutable in
its notes: a re-render is not a new take. `GenerationRecord`.

**setup** — Everything that decides what the next take will be like: mode,
source, template, progression, temperature, density, note duration. A take
records its setup. "Another like this" re-rolls it. A preset is a saved one.

**loop** — The region being repeated: the take's `lengthBeats`, which is the
progression's length. A place, not an event.

**lap** — One traversal of the loop. Backward reverses each lap; ping-pong
alternates them. Auto swaps a take in on a lap boundary; drift re-rolls on one.
Kernel-side: `currentPass` (identifier not yet renamed).

**pass** — One sweep of judgement over the record. Marks are stamped with the
pass they were made on and coexist across passes; starting a pass reopens
everything, including what was skipped. Judgement is provisional by
construction. `curationPass`.

**roll** — One draw of drift's dice, seeded by (take, roll) so a roll that
sounded good can be got back rather than being gone. `mutationPass`
(identifier not yet renamed).

**generate** — Ask Foundation Models. Costs about 1.8 seconds a note, roughly
four times slower than real time. Never used for anything instant; when the
model is unavailable the button must not say it.

**compose** — Assemble a line here and now from gestures, by the phrase grammar:
state, answer, land. Instant, and unlike a stored line it has never existed
before.

**template** — The character of the next take. Fifteen: nine melodic and six
comping figures, the mode choosing which half is in play. Carries a brief for
the model *and* gesture rhythms and contours for the deterministic path, so
choosing one means the same thing whichever source is asked.
`MelGenTemplate`. State identifiers still say `brief`
(`selectedBriefNames`, `briefCursor`, `briefMode`, `lockedBriefName`) —
outstanding rename.

**brief** — The prose inside a template that is handed to the model.
Interpreted, never executed: a sentence a machine could follow belongs in a
figure. Internal — never shown as a label.

**figure** — A pattern the deterministic path executes exactly. For comping, a
rhythm plus a voicing policy. The counterpart to a brief, and the distinction is
load-bearing: handing the model a figure pays 1.8s a note to reproduce what a
four-line function does instantly.

**stored line** — A take read back as scale degrees, so it plays over any
changes instantly with no model. Always two words. `MelodyPattern`.

**Line / Chords** — The mode. Line writes a monophonic part; Chords comps under
the changes. Explicit and visible because the receiving instrument differs — the
one setting that changes what you should plug the output into. It changes which
sources exist, not what one button does.

**comping** — Playing voicings under the changes. A *comp* is a take in Chords
mode. Voice-led across the whole progression before being rhythmicized.
**Retired sense:** "comping" as in assembling one good pass out of several is
not what MelGen does. If that ever exists here it is **splicing**.

**source** — Where a take's material comes from, of six, each carrying whose
vocabulary it is and what it costs. Filtered by mode rather than duplicated.

**variant** — A candidate produced by one named transform of an existing take,
offered with its scores side by side and never summed. Keeping one records it as
a take of its own, with its parent. **"Variation" is not a term.**

**morph** — A dial between two takes, in rhythm and in pitch separately. A
position on it becomes a take when kept.

**drift** — Probabilities re-rolled every lap, applied at render time and never
written back. A performance of a take, not a version of it. Five axes: note
order, accents, slides, skip, octaves.

**texture** — **Retired.** Was a heading over two groups whose real difference
is when they apply. Use **Next take** and **Now playing**.

**disposition** — What you want to happen to a take next, of seven, unranked
against each other and none terminal. Not a score. A mark is a disposition plus
the pass it was made on plus what it was heard after.

**rating** — The coarse three — yes, maybe, no — that most takes get. A rating
*is* a disposition, chosen for you: yes→keep, maybe→later, no→skip. Never shown
alongside the seven as a fourth option, and never stored as a number.

**facet** — Measured, fixed, never typed: density, placement, register, colour,
motion. How you find something on purpose.

**tag** — Typed, free, emergent. How a vocabulary you did not plan shows up. A
tag you keep reaching for is a facet waiting to be named.
