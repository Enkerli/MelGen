#!/usr/bin/env python3
"""Converts the trained LSTM to a stateful Core ML model the AUv3 can run.

    python3 Scripts/training/export_coreml.py --corpus corpus \
        --weights corpus/melgen_lstm.pt --out corpus/MelGenLSTM.mlpackage

THE STATE

An LSTM remembers, and the memory has to survive between calls or the model
writes eight unrelated first notes. There are two ways to arrange that and they
are not equally good:

  · the old way — declare the hidden and cell states as extra *inputs* and
    *outputs*, and have Swift carry two MLMultiArrays back around the loop by
    hand. Portable, and it makes the audio-side code responsible for tensor
    bookkeeping it has no business doing.

  · what this script does — declare them as Core ML **states** (`ct.StateType`,
    iOS 18 and later; MelGen targets iOS 27, so there is no reason to reach for
    the older shape). The state lives inside Core ML. Swift asks the model for
    an `MLState`, passes it to each prediction, and throws it away to start a
    new line. Nothing is marshalled, nothing is copied per step, and "reset the
    model" stops being a thing anyone can forget to do.

ONE STEP PER CALL

The traced model takes a single event and returns the distribution over what
comes next. That is what generation needs — each note depends on the one before
it — and it costs nothing here, because MelGen does not generate on the audio
thread. Whole patterns are built ahead of the beat and handed to the scheduler
as `MelodyPattern`s, exactly as every other material source does.

WHAT COMES OUT

Logits, not a chosen note. Temperature and top-k belong on the Swift side, next
to the seed that makes a take reproducible — see COREML.md. The vocabulary
travels *inside* the `.mlpackage` as metadata, so weights and token dictionary
cannot be separated by a careless file copy, which is the failure that would
make the iPad play confident nonsense.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

import coremltools as ct
from train_lstm import CHANGE_SIZE, METRIC_SIZE, MOTION_SIZE, MelodyLSTM


class SingleStep(nn.Module):
    """One event in, one distribution out, with the recurrent state held in buffers.

    Core ML turns in-place buffer mutation into state updates, so the buffers
    declared here become the `MLState` Swift hands back on the next call.
    """

    def __init__(self, model: MelodyLSTM):
        super().__init__()
        self.model = model
        shape = (model.layers, 1, model.hidden)
        self.register_buffer("h", torch.zeros(shape))
        self.register_buffer("c", torch.zeros(shape))

    def forward(self, token, metric, phrase, quality, motion, change):
        features = torch.cat([
            self.model.token(token.long()),
            self.model.metric(metric.long()),
            self.model.phrase(phrase.long()),
            self.model.quality(quality.long()),
            self.model.motion(motion.long()),
            self.model.change(change.long()),
        ], dim=-1)
        output, (h, c) = self.model.lstm(features, (self.h, self.c))
        self.h.copy_(h)
        self.c.copy_(c)
        return self.model.out(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus", default="corpus")
    parser.add_argument("--weights", default="corpus/melgen_lstm.pt")
    parser.add_argument("--out", default="corpus/MelGenLSTM.mlpackage")
    args = parser.parse_args()

    directory = Path(args.corpus)
    vocab = json.loads((directory / "vocab.json").read_text())
    checkpoint = torch.load(args.weights, map_location="cpu", weights_only=False)

    digest = hashlib.sha256(json.dumps(vocab["tokens"], sort_keys=True).encode()).hexdigest()
    if checkpoint.get("vocabDigest") not in (None, digest):
        print("The weights were trained against a different vocabulary.")
        print("Re-run export-corpus.sh and train_lstm.py together, or the model")
        print("will index the wrong notes with total confidence.")
        return 1

    config = checkpoint["config"]
    model = MelodyLSTM(config["vocab_size"], config["quality_size"], config["phrase_size"],
                       hidden=config["hidden"], layers=config["layers"],
                       dropout=config["dropout"])
    model.load_state_dict(checkpoint["state"])
    model.eval()

    step = SingleStep(model).eval()
    example = tuple(torch.zeros(1, 1, dtype=torch.long) for _ in range(6))
    with torch.no_grad():
        traced = torch.jit.trace(step, example)

    def scalar(name):
        return ct.TensorType(name=name, shape=(1, 1), dtype=np.int32)

    state_shape = (config["layers"], 1, config["hidden"])
    converted = ct.convert(
        traced,
        inputs=[scalar("token"), scalar("metric"), scalar("phrase"),
                scalar("quality"), scalar("motion"), scalar("change")],
        outputs=[ct.TensorType(name="logits")],
        states=[
            ct.StateType(wrapped_type=ct.TensorType(shape=state_shape), name="h"),
            ct.StateType(wrapped_type=ct.TensorType(shape=state_shape), name="c"),
        ],
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    # Index order, so an argmax is a lookup rather than a search.
    by_index = sorted(vocab["tokens"].items(), key=lambda pair: pair[1])
    converted.short_description = (
        "Next-token melody model over MelGen's degree-relative pattern format. "
        "Conditioned on chord quality, root motion, bar position and phrase position."
    )
    metadata = converted.user_defined_metadata
    metadata["melgen.schemaVersion"] = str(vocab["schemaVersion"])
    metadata["melgen.tokenKeyFormat"] = vocab["tokenKeyFormat"]
    metadata["melgen.tokens"] = json.dumps([key for key, _ in by_index])
    metadata["melgen.qualities"] = json.dumps(vocab["qualities"])
    metadata["melgen.phrases"] = json.dumps(vocab["phrases"])
    metadata["melgen.digest"] = digest
    metadata["melgen.validationNLL"] = str(checkpoint.get("validationNLL", ""))

    converted.save(args.out)
    size = sum(f.stat().st_size for f in Path(args.out).rglob("*") if f.is_file())
    print(f"Wrote {args.out} — {size / 1e6:.1f} MB, {len(by_index)} tokens")
    print("Drag it into the MelGenExtension target in Xcode; see COREML.md for the")
    print("Swift side, which is a sampler and a cursor and nothing on the audio thread.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
