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
| changes (harmony) | **progression** | The chords a take is played against |
| variant (bass) | **seed** | One of eight draws of one setting, not a transform |

---

## Terms

**take** — One candidate, stored. Raw notes before expression, plus the setup
that made it, its measurement, its marks and its tags. The unit everything
downstream treats alike, whichever of the seven sources produced it. Immutable in
its notes: a re-render is not a new take. `GenerationRecord`.

**setup** — Everything that decides what the next take will be like: mode,
source, template, progression, temperature, density, note duration. A take
records its setup. "Another like this" re-rolls it. A *saved* setup is still a
setup — it has a name and one can be the default a new instance starts from.
`MelGenSetup`. **"Preset" is retired**: it was used here for the saved kind, and
one concept with two words is what this file exists to stop. Corrected
2026-08-26, after the drawer labelled "Setup" was found to be inscrutable partly
because the documentation called its contents something else.

**progression** — The chords a take is played against, as leadsheet text.
`ChordProgression`, `progressionText`. **"Changes" is retired from the
interface**, and the reason is on record from the second device session: *"New
changes" only parses if you already read "changes" as a progression.* It is what
one musician says to another who already knows, and every label in a plug-in is
read by someone who doesn't yet. The verb is untouched — "re-roll changes what
you are hearing" is ordinary English, and `Scripts/verify.sh terminology` only
fires on a determiner or a preposition, which is what makes the word a noun.

Settled 2026-08-23 (`b78dd44`) and back in a dozen strings by 2026-08-28,
because the decision lived in a commit message, never reached this file, and
nothing checked it. That is the whole argument for this file having a test
attached: a clarification nobody can run is a clarification with a half-life.

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

**template** — The character of the next take. Twenty-three: nine melodic, six
comping figures and eight bass figures, the mode choosing which set is in play.
A melodic template carries a brief for the model *and* gesture rhythms and
contours for the deterministic path, so choosing one means the same thing
whichever source is asked. A bass template is narrower and honestly so: it
carries a figure and no brief, because the model is not the thing drawing that.
`MelGenTemplate`. State identifiers still say `brief`
(`selectedBriefNames`, `briefCursor`, `briefMode`, `lockedBriefName`) —
outstanding rename.

**brief** — The prose inside a template that is handed to the model.
Interpreted, never executed: a sentence a machine could follow belongs in a
figure. Internal — never shown as a label.

**figure** — A pattern the deterministic path executes rather than interprets.
For comping, a rhythm plus a voicing policy, played exactly. For bass, per-slot
onset chances, lengths and accents over one bar — executed as written, though
what is written is a probability, which is what lets two of them be *mixed*
rather than switched between. The counterpart to a brief, and the distinction is
load-bearing: handing the model a figure pays 1.8s a note to reproduce what a
four-line function does instantly.

**stored line** — A take read back as scale degrees, so it plays over any
changes instantly with no model. Always two words. `MelodyPattern`.

**Line / Chords / Bass** — The mode. Line writes a monophonic part; Chords comps
under the changes; Bass draws a bass part inside a stated register. Explicit and
visible because the receiving instrument differs — the one setting that changes
what you should plug the output into. It changes which sources exist, not what
one button does. `PlayMode.isPolyphonic` is the question to ask about a mode;
comparing against `.comping` is how a third mode broke a dozen decisions that
had never considered one.

**comping** — Playing voicings under the changes. A *comp* is a take in Chords
mode. Voice-led across the whole progression before being rhythmicized.
**Retired sense:** "comping" as in assembling one good pass out of several is
not what MelGen does. If that ever exists here it is **splicing**.

**source** — Where a take's material comes from, of seven, each carrying whose
vocabulary it is and what it costs. Filtered by mode rather than duplicated.

**variant** — A candidate produced by one named transform of an existing take,
offered with its scores side by side and never summed. Keeping one records it as
a take of its own, with its parent. **"Variation" is not a term**, and neither is
a variant one of Bass's eight draws — those are **seeds**.

**seed** — The number every random choice in a draw comes from, so a draw that
sounded good can be got back rather than being gone. Mostly invisible; in Bass
eight of them are offered as a row, because a bass part is something you audition
several of. Nothing is stored behind them — a draw *is* its seed — which is why
there are eight rather than as many as will fit.

**pad** — The two-axis control in Bass. Left to right is the **balance** between
the on-beat layer and the off-beat one — only the first at the west edge, only
the second at the east, both at full in the middle. Up and down is the
**selection**: which pair of figures, walking both banks from sparsest to
busiest, blended between entries. Square rather than diamond-shaped, because the
two axes mean independent things and a shape that traded one against the other
made a straight walking bass unreachable. `BasslinePad`. **"Diamond" is retired**
— it named the first version, which mixed four corner figures barycentrically.

**shift** — Moving a bass figure along the bar, wrapping. In eighths. The same
notes, in different places: an on-beat figure shifted by one is an off-beat one.

**vamp** — A progression with one chord in it, written `C(dorian)` and held for
as many bars as you want. Not a separate kind of harmony and not a mode of the
plug-in: there is one progression field and a vamp is something you can put in
it. `DiatonicHarmony.vamp(key:scale:bars:)` writes one. **"Diatonic mode" is
retired** — it named a switch that no longer exists, and named it as a mode when
Line, Chords and Bass are the modes.

**draw** — Making a bass part. Instant, and in Bass it happens whenever a control
is released rather than only when asked for, because the part can change before
the finger lifts. Every release is a take. Distinct from **generate**, which
means the model and costs 1.8 seconds a note, and from **compose**, which is the
phrase grammar.

**layer** — One of the two things a bass part is made of at once: the on-beat
figure and the off-beat figure, merged into a single monophonic line. What the
pad's horizontal balances. Not a voice — a bass part has one.

**reach** — How far up the note stack a line goes: root, fifth, third, seventh,
eleventh, ninth, thirteenth, in that order, because that is the order an
improviser arrives in and therefore the order of how often each is played. One
dial across all seven, not seven settings. Not to be confused with **range**,
which is register.

**minorness** — Where a key sits on the modal brightness ladder: Lydian at
nought, Dorian at half, Locrian at one, each rung one flattened degree darker
than the one above it. A dial rather than a major/minor switch, because the thing
between them is where most of the music is.

**outside** — Weight given to the notes the scale doesn't contain. Small, always:
at three per cent an outside note is colour and at thirty it is a wrong note.

**side-slip** — The pentatonic on the third of the chord, and the one a semitone
above it, which shares no note with the chord's scale and lands anyway. A dial
between the two.

**morph** — A dial between two lines, in rhythm and in pitch separately. A
position on it becomes a take when kept. In Bass it dials between one seed's draw
and the next on one axis, because what it is between is two draws of one setting
rather than two takes with independent rhythms.

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

**next step** — The single line above both tabs saying what to do now, derived
from state and never scripted. It names an action, the fact that makes it the
action, and where that lives; it goes quiet when nothing is outstanding. Not a
tour, not a tooltip, not a checklist — those all keep talking. `NextStep`.

**facet** — Measured, fixed, never typed: density, placement, register, colour,
motion. How you find something on purpose.

**tag** — Typed, free, emergent. How a vocabulary you did not plan shows up. A
tag you keep reaching for is a facet waiting to be named.
