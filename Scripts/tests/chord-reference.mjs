// Dumps reference parse + chord-scale results from Music Suite's own TypeScript
// build, so MelGen's Swift port can be diffed against it.
const dist = process.env.MUSIC_SUITE_DIST;
const { parseChordSymbol } = await import(`${dist}/chordSymbol.js`);
const { findQualityByKey } = await import(`${dist}/chords.js`);
const { chordScaleFor } = await import(`${dist}/chordScale.js`);
const { spelledToPc } = await import(`${dist}/spelling.js`);

const symbols = [
  "C", "Cmaj7", "C∆", "CM7", "Cmaj9", "C6", "C69", "Cadd9", "Cadd11",
  "Cm", "Cmin", "C-", "Cm7", "Cmin7", "C-7", "Cm9", "Cm11", "Cm6", "CmM7", "CminMaj7",
  "C7", "C9", "C11", "C13", "C7sus4", "C7sus", "C9sus4", "C7b9", "C7#9", "C7#11",
  "C7b5", "C7#5", "C7b13", "C9b13", "C7alt", "Calt7",
  "Cdim", "Cdim7", "Co7", "Cm7b5", "Cø", "Ch7", "C+", "Caug", "CaugMaj7",
  "Csus2", "Csus4", "Csus", "C5", "Cquartal",
  "Cmaj13", "C∆9", "Cmaj#4", "CM7#11", "C69#11", "CM13#11",
  "Ebm7", "E♭m7", "F#7b9", "Bb∆", "A♭6", "Gm9", "D∆", "Dm7/G", "Cmaj7/E", "Bbmaj7/D",
  "Fmi7", "Fmin9", "Cm7add11", "C7add13", "Cphryg", "Csusb9",
];

const rows = [];
for (const symbol of symbols) {
  const parsed = parseChordSymbol(symbol);
  if (!parsed || !parsed.qualityKey) {
    rows.push({ symbol, error: parsed ? "unknownQuality" : "unparsed" });
    continue;
  }
  const quality = findQualityByKey(parsed.qualityKey);
  const rootPc = spelledToPc(parsed.root);
  const pcs = quality.pcs.map((i) => (rootPc + i) % 12);
  const cs = chordScaleFor(rootPc, pcs);
  rows.push({
    symbol,
    key: parsed.qualityKey,
    rootPc,
    tones: [...new Set(pcs)].sort((a, b) => a - b),
    scale: cs.scale,
    scalePcs: [...cs.scalePcs].sort((a, b) => a - b),
    avoid: [...cs.avoid].sort((a, b) => a - b),
    tensions: [...cs.tensions].sort((a, b) => a - b),
  });
}
console.log(JSON.stringify(rows, null, 0));
