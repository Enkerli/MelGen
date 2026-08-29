# MelGen — Design Brief

*Written 2026-08-25, after four device sessions in AUM. Purpose: MelGen's
**machinery works and its process doesn't**. Five sessions of playing it have
produced a consistent verdict — "still not the process I want" — and the
complaints are not about missing features. They're about a vocabulary the
interface never defines, an automation that can't be steered by hand, and two
libraries that look like one. We want the overall experience shaped, not
yes/no rulings on individual controls. "Design is how it works."*

*Companion documents: [README.md](README.md) for what exists,
[ROADMAP.md](ROADMAP.md) for planned work, [ISSUES.md](ISSUES.md) for what's
broken. This one is about the experience, and it is the only one that is.*

---

## What MelGen is

An **AUv3 MIDI plug-in** (iPadOS and macOS) that generates melodic lines and
comping over a chord progression, and helps you decide which ones were any
good. It sends MIDI to whatever instrument the host has; it makes no sound of
its own. The validation host is **AUM on an iPad**, not the bundled app.

It has eight sources of material, and they all produce the same thing — a
degree-relative `MelodyPattern`, which is a shape rather than a set of pitches,
so any of them fits any harmony. One source is Apple's on-device Foundation
Models, which costs about **1.8–2.4 seconds per note** — roughly four times
slower than real time. The other seven are deterministic and instant. That
asymmetry is the central fact of the design: the model is the slowest and most
interesting source, and everything else exists so there is something to listen
to while it thinks.

The user is a musician and teacher who thinks functionally, works on an M1 iPad
Pro, and is using this to find material rather than to render a finished part.

---

## The surfaces today

Two tabs, thirteen sections, one 3,600-line view. A previous design pass split
**Play** from **Decide**, which was right and made the view longer.

**Play**
| Section | What it holds |
|---|---|
| Setup | Named settings, one markable as default |
| Progression | The changes: text field, or generate them (7 controls) |
| Transport | Play/stop, direction, host sync, Auto toggle |
| Current take | Piano roll with playhead, notation summary |
| Auto interval | How often anything changes — 1/2/4/8 loops |
| Next take | Line-or-chords, voice leading, which source, one primary action, template picker |
| Texture | Density, temperature, note duration — *next take* |
| Drift · live | 5 probability sliders — *re-renders what plays now*, plus "Previous pass" and "Keep this pass" |
| More | Stored lines (16), listen to what I play, write a template, export/import history |

**Decide**
| Section | What it holds |
|---|---|
| Curation | 7 dispositions (3 shown, 4 behind "more"), aspects, tags, lineage, "keep as a line" |
| Variants | Up to 12 transforms of the current pattern, each judgeable, plus a morph dial |
| History | 250 takes, tap to reload, export/import |

Counts, for scale: **9 line templates, 6 chord templates, 16 stored lines**, 14
gesture rhythms, 10 contours, 6 voicing styles, 7 dispositions, 5 material
sources in line mode and 3 in chord mode.

---

## Problem 1 — five words, three of them overloaded

This is the one the user named first, and it is worse than a naming
inconsistency. **"Pass" means three unrelated things in the same interface.**

| Word | What the code means by it | Where it shows |
|---|---|---|
| **Take** | A stored artefact: notes, the settings that made them, measurements, and every judgement ever made about it. The unit curation is about. | "Current take", history, "new take every…" |
| **Loop** | One time round the form. | "New take every 2 loops" |
| **Pass** ①| A loop. The kernel's `currentPass` counts these. | "New take every 2 loops" (as "loops") |
| **Pass** ②| A **curation sweep**. Marks are stamped with it, so the same take can be answered differently on a later sweep. This is a genuinely good idea. | "Pass 1" above the rating buttons |
| **Pass** ③| A **drift re-roll**. `mutationPass` seeds the live mutation, so a performance you liked can be got back. Also good. | "Pass 3." in Drift, "Previous pass", "Keep this pass" |
| **Variation** | Informal. A take that records a parent. | "drift, pass 3 of …" |
| **Variant** | A *candidate* transform, listed but not yet a take. | Variants section |
| **Mutation** ①| One of 14 transforms that make variants. | Variants |
| **Mutation** ②| The **drift** — render-time, per-pass, never touches the take. | Drift section |

So "Pass 1" in Decide and "Pass 3" in Drift are counting different things, and
neither is the loop count that "every 2 loops" refers to. A rating bug this week
turned out to be exactly this confusion arriving as code: a mark keyed on the
drift pass showed up on a different take.

**What we want from design:** a vocabulary of no more than four words that a
musician can hold, and a decision about which of these distinctions are worth
surfacing at all. Our instinct is that *curation pass* and *drift pass* are both
real but should not both be called "pass". We are not attached to any of the
current words.

---

## Problem 2 — automation you can't take the wheel from

**Auto** generates a new take every N loops. It works. What's missing is the
manual counterpart, and its absence makes the automatic version feel like
weather rather than an instrument.

- There **is** a way to make a take by hand: the primary action in "Next take".
  But it's labelled by *source* — "Generate a line", "Comp", "Draw from your
  style" — so it doesn't read as "next take", the thing Auto does.
- There is **no** way to re-roll the drift on demand. There's "Previous pass"
  and "Keep this pass", but no "again". So the one control that changes what
  you're hearing without costing a generation can only be waited for.
- Auto is a **toggle with one parameter**. The user asked for it to have several.
  Which ones is a design question: what should Auto be allowed to vary on its
  own — the take, the drift, the template, the voicing, the progression?

The underlying request, in the user's words: *"a button to advance to a new take
or to trigger drift. We could then have auto mode have some parameters."* Note
the ordering — **manual first, then automate the manual gestures**. Today it is
the other way round, and the manual gestures were never designed.

There is also a real tension here, and it is the reason this isn't just "add two
buttons": a take from the model costs 30–140 seconds, and a drift re-roll costs
nothing. Those two actions have wildly different costs and are currently
presented as if they were peers. The interface already knows the cost of
everything — every source says whether it answers now or in seconds per note —
so the information exists; it just isn't shaping the layout.

---

## Problem 3 — templates and stored lines look like one thing

Both are named, reusable, listed things you cycle through. The difference is
real and never stated:

| | **Template** | **Stored line** |
|---|---|---|
| What it is | A *character*: how dense, how airy, how syncopated, what shape | An *actual line*, as degrees |
| What it does | Shapes how the next take is **generated** | **Is** the take, fitted to the changes |
| Where it comes from | 9 hand-written, plus any the model authors | 16 seeds, plus any take you keep |
| Reused how | Every source consults it | Only the "Stored line" source plays it |

Two concrete symptoms:

1. In "Play a stored line" mode, the **stored lines don't appear in the template
   picker** — so there is no way to choose which one plays. They are a third
   list the picker doesn't show. (ROADMAP U9.)
2. Keeping a take as a line and authoring a template are both "save this for
   later", presented in different sections, with different words, and one of
   them is behind "More".

**What we want from design:** either one library with two kinds of thing in it,
or two libraries that are visibly different. Not the current state, where they
are neither.

---

## Problem 4 — template authoring is nearly exhausted, and measured

The user's report: *"I was eventually able to generate one… which was then
flagged for similarity with any new template I tried to generate. So maybe we've
reached the limit."*

Essentially right, and we now have the number. `TemplateGate` refuses a proposed
template that composes to within a bar of one you already have, where the bar is
the existing set's own median nearest-neighbour distance. Sweeping 3,240
characters across the four axes and greedily accepting the most distinctive
available one until nothing clears the bar:

| Mode | Built in | Authorable | Ceiling |
|---|---|---|---|
| **Line** | 9 | **4** | 13 |
| **Chords** | 6 | **8** | 14 |

And the squeeze is double: the bar *rises* as templates are added, because each
accepted one raises the median spacing. In line mode it went 0.036 → 0.055 →
0.080 over four acceptances. That 4 is also a *best case* — it assumes a
searcher hunting the most distinctive point in the space. A language model
proposing in prose finds far fewer, which is why the user got one.

Two consequences for the design:

- **Template authoring is a finite resource, and line mode is nearly out.** It
  should probably stop being presented as a repeatable action.
- **Chord mode has eight slots free and no way to reach them.** Authoring is
  gated to line mode entirely — `if state.mode == .line`. The user asked for
  more comping templates and the gate would happily accept them. This is the
  cheapest real win on this list.

The deeper point, which the user reached empirically before we measured it: the
variety has not been coming from templates. It has been coming from **mutation,
morphing and drift** — *"with mutations and morphs, mono patterns are getting
more palatable as we go"*. Those are on the Decide tab, downstream of the
material, and they are where the process actually lives. The design should
probably reflect that the interesting loop is **vary → hear → judge**, not
**configure → generate**.

---

## The playflows, as they actually happen

Reconstructed from four sessions and the exported histories, not imagined.

**1. Set up a bed and let it run.** Generate a 4-bar progression (surprise 0.96,
bold, 2-chord context), chord mode, shuffle templates, 6 notes a bar, drift on,
Auto every 2 loops. Then listen for a long time. *This is the main flow.* It is
what "setups" was built for. Its failure mode is that everything changes at once
and nothing is stable long enough to judge.

**2. Find something, then work on it.** A take sounds promising → explore
variants → morph between two → keep the best as a line. The most productive
flow, and the one the user says is improving the material. Lives entirely on the
Decide tab, and requires leaving the tab where the music is playing.

**3. Judge a backlog.** Come back to 84 takes and sweep them in a curation pass.
Supported, and used — 40 of 84 takes marked in one session.

**4. Ask the model for something.** Slow (30–140s), used sparingly, and the
answer arrives while other things are playing. The whole hold-for-loop-boundary
machinery exists for this.

**5. Author a way of playing.** Ask the model for a template rather than a line.
One request, kept forever. Nearly exhausted in line mode; unavailable in chord
mode.

---

## Constraints design has to work inside

- **It's a plug-in window in AUM on an iPad**, often at half height, one hand,
  while other things are playing. Not a desktop app.
- **Music is usually already sounding.** Almost every action happens during
  playback, so anything that interrupts the transport is a bug, not a
  trade-off. We fixed three of those this week.
- **The model is slow and sometimes absent.** It doesn't exist in the Simulator,
  and it can be systemwide-unavailable. Every flow has to work without it.
- **Nothing may block the audio thread.** Generation is off-thread and swaps in
  on a loop boundary. This is settled and shouldn't be redesigned.
- **Everything produces a `MelodyPattern`.** A ninth source would be a file, not
  a subsystem. Design can rearrange the surface freely without touching this.
- **Light theme by default**, MelGen's own setting, on Music Suite's "paper and
  ink" tokens. 28 token pairings pass WCAG 2.1 AA in both themes and
  `Scripts/verify.sh contrast` fails if that stops being true.
- **Touch targets** are on the theme's own token, not a smaller one — WCAG 2.5.5
  is enforced, not aspirational.
- **The interface has outgrown its structure** (ISSUES §4.6): thirteen sections
  in a 3,600-line view, each feature having arrived as another section. Design
  is welcome to propose a structure rather than more sections.

---

## What we're asking for

In priority order, and the first is the one that unlocks the rest:

1. **A vocabulary.** Four words at most, for what are currently five words and
   nine meanings. Say which distinctions deserve to be visible and which are
   implementation detail. Everything else on this list depends on this.
2. **Manual gestures first, then automation over them.** What are the primitive
   actions — next take, re-roll, vary, judge? Design those as first-class
   controls, then say what Auto is allowed to do with them and which parameters
   it should expose.
3. **One answer to "where does my material live."** Templates, stored lines,
   kept takes, saved setups and refused templates are five stores with five
   presentations. Some of them are the same idea.
4. **Reflect where the value actually is.** The productive loop is vary → hear →
   judge, and it is split across two tabs with the piano roll on one of them.
5. **A structure**, not thirteen sections. What belongs together, what collapses,
   what is a sheet, what is always visible while music plays.

Two things we are **not** asking for: more generation features, and a verdict on
whether the seven curation dispositions are right. Those are settled and working.

---

## Where the evidence is

- **Four exported histories** are attached to the conversation this brief came
  from — 84, 6, 6 and 5 takes, with marks, lineage, timings and settings.
  `Scripts/analyse-history.sh` reads them.
- **[ISSUES.md](ISSUES.md) §3** is the fixed list, and it is worth reading as a
  record of which confusions have already caused bugs. Three of this week's
  fixes were the take/pass/loop distinction failing in code.
- **[ISSUES.md](ISSUES.md) §4** is what's still wrong; §4.6 is the structural
  one this brief is really about.
- **`Scripts/verify.sh`** is 24 suites and 2,300-odd checks. Design changes that
  break a measured claim will fail it, which is the intended behaviour.
