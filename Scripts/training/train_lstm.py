#!/usr/bin/env python3
"""Trains a next-token LSTM over MelGen's tokenized corpus, and says whether it earned its place.

Run after `Scripts/export-corpus.sh`, which produces the three files this reads:
`corpus.jsonl`, `vocab.json`, and `baseline.json`.

    python3 Scripts/training/train_lstm.py --corpus corpus --out corpus/melgen_lstm.pt

WHAT IT PREDICTS, AND WHAT IT IS ALLOWED TO KNOW

At step *t* the model predicts the token at *t*, given every token before it and
the *conditioning of step t itself*. That asymmetry is the whole design and it
is not a leak: when this runs on the iPad the progression is already on screen,
so the harmony, the bar position and the phrase position of the slot about to be
filled are all known before anything is generated. What is not known is the
note. The cursor is causal too — it advances by the previous token's own span
(`lengthEighths + restAfterEighths`), so the metric position of step *t* falls
out of the tokens already emitted.

    input at t   = embed(token[t-1]) ⊕ embed(metric[t], phrase[t], quality[t],
                                             rootMotion[t], eighthsToChange[t])
    target at t  = token[t]

WHY THIS MODEL AND NOT THE ONE THAT ALREADY SHIPS

`MelodyChain` — a variable-order Markov chain with backoff — already does this
job in microseconds, with no download and no conversion step. The honest case
for a neural model is one thing only: the chain's state cannot afford to include
the harmony. Adding chord quality and root motion to an n-gram context
multiplies its state space by a hundred and turns every context into one seen
exactly once, which the chain's own trust threshold then correctly refuses to
use. An LSTM conditions on all of it for the price of a wider input vector.

So the gate at the end of this script compares held-out loss against the chain's,
measured by the chain itself on the same split. If the LSTM does not win, the
result is not "train longer" — it is that this corpus does not support a neural
model, and `MelodyChain` stays the answer.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset

PAD, BOS, EOS = 0, 1, 2
# Root motion is folded to −6…5 by the exporter; shifted here into 0…11 so it
# can index an embedding table.
MOTION_OFFSET = 6
MOTION_SIZE = 12
CHANGE_SIZE = 17  # 0…16 eighths until the harmony moves
METRIC_SIZE = 8


class Corpus(Dataset):
    """One example per pattern: a line, its harmony, and where it sits in the bar."""

    def __init__(self, items, vocab):
        self.items = items
        self.tokens = vocab["tokens"]
        self.qualities = vocab["qualities"]
        self.phrases = {name: index for index, name in enumerate(vocab["phrases"])}

    def __len__(self):
        return len(self.items)

    def __getitem__(self, index):
        item = self.items[index]
        ids = [self.tokens[key] for key in item["tokens"]]
        length = len(ids)

        # The input is shifted by one: the model is told what it just played and
        # asked what comes next. <bos> opens; <eos> is what it must learn to say
        # instead of running past the end of the form.
        inputs = [BOS] + ids
        targets = ids + [EOS]

        def column(values, size, extend):
            out = list(values) + [extend]
            return [min(max(0, int(v)), size - 1) for v in out]

        return {
            "inputs": torch.tensor(inputs, dtype=torch.long),
            "targets": torch.tensor(targets, dtype=torch.long),
            "metric": torch.tensor(column(item["metric"], METRIC_SIZE, item["metric"][-1]),
                                   dtype=torch.long),
            "phrase": torch.tensor(column([self.phrases.get(p, 1) for p in item["phrase"]],
                                          len(self.phrases), 2), dtype=torch.long),
            "quality": torch.tensor(column([self.qualities.get(q, 0) for q in item["quality"]],
                                           max(1, len(self.qualities)), 0), dtype=torch.long),
            "motion": torch.tensor(column([v + MOTION_OFFSET for v in item["rootMotion"]],
                                          MOTION_SIZE, MOTION_OFFSET), dtype=torch.long),
            "change": torch.tensor(column(item["eighthsToChange"], CHANGE_SIZE, 0),
                                   dtype=torch.long),
            "length": length + 1,
        }


def collate(batch):
    width = max(item["length"] for item in batch)
    out = {}
    for key in ("inputs", "targets", "metric", "phrase", "quality", "motion", "change"):
        padded = torch.full((len(batch), width), PAD, dtype=torch.long)
        for row, item in enumerate(batch):
            values = item[key]
            padded[row, :len(values)] = values
        out[key] = padded
    out["lengths"] = torch.tensor([item["length"] for item in batch], dtype=torch.long)
    return out


class MelodyLSTM(nn.Module):
    """Embeddings for what was played and what it is being played over, then an LSTM.

    Kept deliberately small. The corpus is a personal one even when it includes a
    found MIDI collection, and the failure mode of a large model on a small
    corpus is not bad music — it is *your own material played back at you*, which
    is worse, because it looks like success.
    """

    def __init__(self, vocab_size, quality_size, phrase_size,
                 token_dim=96, context_dim=40, hidden=256, layers=1, dropout=0.2):
        super().__init__()
        self.token = nn.Embedding(vocab_size, token_dim, padding_idx=PAD)
        self.metric = nn.Embedding(METRIC_SIZE, 8)
        self.phrase = nn.Embedding(max(1, phrase_size), 4)
        self.quality = nn.Embedding(max(1, quality_size), 16)
        self.motion = nn.Embedding(MOTION_SIZE, 8)
        self.change = nn.Embedding(CHANGE_SIZE, 4)
        assert 8 + 4 + 16 + 8 + 4 == context_dim

        self.dropout = nn.Dropout(dropout)
        self.lstm = nn.LSTM(token_dim + context_dim, hidden, num_layers=layers,
                            batch_first=True,
                            dropout=dropout if layers > 1 else 0.0)
        self.out = nn.Linear(hidden, vocab_size)
        self.hidden, self.layers = hidden, layers

    def forward(self, batch, state=None):
        features = torch.cat([
            self.token(batch["inputs"]),
            self.metric(batch["metric"]),
            self.phrase(batch["phrase"]),
            self.quality(batch["quality"]),
            self.motion(batch["motion"]),
            self.change(batch["change"]),
        ], dim=-1)
        output, state = self.lstm(self.dropout(features), state)
        return self.out(self.dropout(output)), state


def run_epoch(model, loader, criterion, device, optimizer=None):
    training = optimizer is not None
    model.train(training)
    total_loss = total_correct = total_events = 0

    with torch.set_grad_enabled(training):
        for batch in loader:
            batch = {key: value.to(device) for key, value in batch.items()}
            logits, _ = model(batch)
            loss = criterion(logits.reshape(-1, logits.size(-1)),
                             batch["targets"].reshape(-1))

            if training:
                optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optimizer.step()

            mask = batch["targets"] != PAD
            events = int(mask.sum())
            total_loss += float(loss) * events
            total_correct += int((logits.argmax(-1)[mask] == batch["targets"][mask]).sum())
            total_events += events

    if total_events == 0:
        return 0.0, 0.0
    return total_loss / total_events, total_correct / total_events


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus", default="corpus", help="directory written by export-corpus.sh")
    parser.add_argument("--out", default="corpus/melgen_lstm.pt")
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--batch", type=int, default=32)
    parser.add_argument("--hidden", type=int, default=256)
    parser.add_argument("--layers", type=int, default=1)
    parser.add_argument("--dropout", type=float, default=0.2)
    parser.add_argument("--lr", type=float, default=2e-3)
    parser.add_argument("--patience", type=int, default=12)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    torch.manual_seed(args.seed)
    random.seed(args.seed)

    directory = Path(args.corpus)
    vocab = json.loads((directory / "vocab.json").read_text())
    items = [json.loads(line) for line in
             (directory / "corpus.jsonl").read_text().splitlines() if line.strip()]
    baseline = {}
    if (directory / "baseline.json").exists():
        baseline = json.loads((directory / "baseline.json").read_text())

    train = [i for i in items if i["split"] == "train"]
    validation = [i for i in items if i["split"] == "validation"]
    if not train or not validation:
        print("Need both splits. Re-run export-corpus.sh.")
        return 1

    device = ("mps" if torch.backends.mps.is_available()
              else "cuda" if torch.cuda.is_available() else "cpu")
    print(f"{len(train)} train / {len(validation)} held out, "
          f"{len(vocab['tokens'])} token types, on {device}")

    train_loader = DataLoader(Corpus(train, vocab), batch_size=args.batch,
                              shuffle=True, collate_fn=collate)
    validation_loader = DataLoader(Corpus(validation, vocab), batch_size=args.batch,
                                   shuffle=False, collate_fn=collate)

    model = MelodyLSTM(len(vocab["tokens"]), len(vocab["qualities"]),
                       len(vocab["phrases"]), hidden=args.hidden,
                       layers=args.layers, dropout=args.dropout).to(device)
    criterion = nn.CrossEntropyLoss(ignore_index=PAD)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)

    best = math.inf
    best_accuracy = 0.0
    waiting = 0
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    for epoch in range(1, args.epochs + 1):
        train_loss, train_accuracy = run_epoch(model, train_loader, criterion, device, optimizer)
        loss, accuracy = run_epoch(model, validation_loader, criterion, device)
        flag = ""
        if loss < best - 1e-4:
            best, best_accuracy, waiting, flag = loss, accuracy, 0, "  ←"
            torch.save({
                "state": model.state_dict(),
                "config": {"vocab_size": len(vocab["tokens"]),
                           "quality_size": len(vocab["qualities"]),
                           "phrase_size": len(vocab["phrases"]),
                           "hidden": args.hidden, "layers": args.layers,
                           "dropout": args.dropout},
                # Pins the weights to the vocabulary they were trained against.
                # Loading one with the other is the single most likely way for
                # this pipeline to produce confident nonsense on the device.
                "vocabDigest": hashlib.sha256(
                    json.dumps(vocab["tokens"], sort_keys=True).encode()).hexdigest(),
                "validationNLL": loss,
                "validationTop1": accuracy,
            }, out)
        else:
            waiting += 1

        print(f"  epoch {epoch:3d}  train {train_loss:.4f}/{train_accuracy*100:4.1f}%   "
              f"held out {loss:.4f}/{accuracy*100:4.1f}%{flag}")
        if waiting >= args.patience:
            print(f"  stopped early: {args.patience} epochs without improvement")
            break

    print()
    print("── did it earn its place? ─────────────────────────")
    print(f"  LSTM         loss {best:.4f}   perplexity {math.exp(best):6.1f}   "
          f"top-1 {best_accuracy*100:.1f}%")
    if baseline:
        chain = baseline["chainNLL"]
        print(f"  MelodyChain  loss {chain:.4f}   perplexity {math.exp(chain):6.1f}   "
              f"top-1 {baseline['chainTop1']*100:.1f}%")
        print()
        if best < chain:
            margin = (1 - math.exp(best) / math.exp(chain)) * 100
            print(f"  The LSTM wins by {margin:.0f}% perplexity. Worth converting.")
        else:
            print("  The chain wins. This corpus does not support a neural model —")
            print("  more material, not more epochs, and MelodyChain stays the answer.")
    else:
        print("  No baseline.json — run export-corpus.sh to get the number to beat.")

    print(f"\n  Weights written to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
