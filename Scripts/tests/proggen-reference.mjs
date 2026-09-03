// Dumps ProgGenie's own answers for the deterministic half of the progression
// engine, so MelGen's Swift port can be diffed against them.
//
// PORTING.md §7: `packages/proggen` has no `vectors/` directory, so nothing has
// ever checked that Swift and JS agree here. The scope is deliberately narrower
// than the engine. Three things are shareable and must match exactly:
//
//   · splitting a corpus label into numeral and suffix ("♯IVm7b5" → ♯IV + m7b5)
//   · the numeral's distance from the tonic in semitones
//   · realizing a label in a key — the spelled chord symbol, its root pitch
//     class, and whether the quality is one the dictionary knows at all
//
// Everything else is where the two implementations diverge ON PURPOSE and a
// vector would be wrong to insist: MelGen replaces ProgGenie's temperature with
// Surprise, adds Freshness, and ships a Reharm that is a deliberate superset.
// Sampling is not compared and should not be.
//
// One field carries a divergence rather than an agreement. ProgGenie realizes
// "IBass" to the symbol "CBass" with a null qualityKey; MelGen refuses it,
// because a generated progression has to be one the rest of the plug-in can
// actually play. So the vector records `playable: false` where ProgGenie's
// qualityKey is null, and the Swift side is expected to return nothing there.
// That is a contract, not a mismatch — but it only became one once it was
// written down.
//
//   MUSIC_SUITE=… node Scripts/tests/proggen-reference.mjs > reference.json

const suite = process.env.MUSIC_SUITE;
if (!suite) {
  console.error("set MUSIC_SUITE to a music-suite checkout");
  process.exit(2);
}
const { splitLabel, realizeLabel } = await import(`${suite}/packages/proggen/src/index.js`);
const { spelledToPc, parseSpelled } = await import(`${suite}/packages/theory/dist/spelling.js`);

// Labels the corpus actually contains, plus the shapes that have historically
// been parsed wrong: the longest-numeral rule (III must not read as II), both
// accidentals, a numeral that wraps below the tonic, and one piece of nonsense.
const labels = [
  "I", "Im7", "IM7", "I6", "I7",
  "IIm7", "II7", "IIm7b5", "IIø",
  "IIIm7", "III7", "IIIm7b5",
  "IV", "IVM7", "IVm7", "IV7", "IVm6",
  "V", "V7", "V7b9", "V7#5", "V7alt", "Vm7", "Vsus4",
  "VIm7", "VI7", "VIm7b5",
  "VIIm7b5", "VIIo7", "VII7",
  "♭II7", "♭IIM7", "♭IIIM7", "♭VIM7", "♭VII7", "♭VIIM7", "♭VIm7",
  "♯IVm7b5", "♯IVo7", "♯Vo7",
  "IBass", "banana", "", "VIII",
];

// Every label is realized in three keys: C (nothing to spell around), F (one
// flat — where a ♭VII has to come out B♭ and not A♯) and B (five sharps).
const keys = [
  { tonic: "C", pc: 0 },
  { tonic: "F", pc: 5 },
  { tonic: "B", pc: 11 },
];

const rows = [];
for (const label of labels) {
  const split = splitLabel(label);
  const row = {
    label,
    numeral: split ? split.numeral : null,
    suffix: split ? split.suffix : null,
    realized: {},
  };
  for (const key of keys) {
    const chord = split ? realizeLabel(label, { tonic: key.tonic, mode: "major" }) : null;
    if (!chord) {
      row.realized[key.tonic] = null;
      continue;
    }
    row.realized[key.tonic] = {
      // The chord as ProgGenie spells it, and where its root sits. Semitones
      // above the key's own tonic is the number MelGen computes directly from
      // the numeral, so it is the one field both sides derive independently.
      symbol: chord.symbol,
      rootPc: chord.rootPc,
      semitonesAboveTonic: ((chord.rootPc - key.pc) % 12 + 12) % 12,
      // Compared; the symbol is not. ProgGenie spells theoretically (E♯m7b5 as
      // the ♯IV of B major), MelGen spells by pitch class from flat names
      // (Fm7b5). Both are the same chord and only one of them is a leadsheet
      // MelGen's own parser reads back, so the contract is pitch class and
      // quality, not orthography.
      qualityKey: chord.qualityKey,
      // null quality = ProgGenie will still name it, MelGen will refuse it.
      playable: chord.qualityKey !== null,
    };
  }
  rows.push(row);
}

// A guard on the harness itself: if the two spelling helpers ever disagree with
// the realizer, the vector is measuring the wrong thing.
for (const key of keys) {
  if (spelledToPc(parseSpelled(key.tonic)) !== key.pc) {
    console.error(`harness: ${key.tonic} is not pitch class ${key.pc}`);
    process.exit(2);
  }
}

console.log(JSON.stringify(rows, null, 1));
