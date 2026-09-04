#!/usr/bin/env python3
"""Classify how a Claude Code programmatic session ended.

The Claude counterpart of `classify-copilot-outcome.py`, and it writes the
same verdict schema on purpose: `run-agent-session` dispatches on vendor and
every caller downstream reads one outcome file without knowing which vendor
produced it. If these two scripts ever disagree about a key, the workflows
start branching on the vendor again, which is the duplication the shared
action exists to remove.

What differs is the evidence, not the verdict. Copilot CLI emits a JSONL
event stream; `claude -p --output-format json` emits one JSON object with the
answer in `.result`. So there are no per-event counts to report here, and the
fields that describe a stream are present but zeroed rather than dropped --
a caller that prints `.event_counts` must not get `null` because the vendor
changed.

Detection is signal-based against harness-authored text only -- the exit
status, stderr, and the envelope's own `is_error`/`subtype` -- never against
`.result`. `.result` is model-authored (and on an in-run failure Claude Code
puts the failure message there too), so matching patterns against it would
let a model that merely *discusses* a rate limit be classified as one.

Usage:

    classify-claude-outcome.py \
        --json claude-output.json \
        --stderr claude-error.txt \
        --exit-status 1 \
        --model claude-opus-5 \
        --out agent-outcome.json
"""

import argparse
import json
import pathlib
import re

# Same vocabulary as classify-copilot-outcome.py, in the same precedence
# order. Callers branch on these strings; they are the contract.
HARNESS_ERROR = "harness_error"
MODEL_UNAVAILABLE = "model_unavailable"
BUDGET_EXHAUSTED = "budget_exhausted"
RATE_LIMITED = "rate_limited"
SESSION_ERROR = "session_error"
NO_ASSISTANT_OUTPUT = "no_assistant_output"
COMPLETED = "completed"

# Matched against harness text only (stderr, and the envelope's own error
# fields). Claude Code names a bad model directly; the OAuth line is here
# because `--bare` never reads OAuth credentials, so a run configured with
# CLAUDE_CODE_OAUTH_TOKEN instead of ANTHROPIC_API_KEY fails exactly this way
# and the message should say so rather than blaming the model.
UNAVAILABLE_PATTERNS = [
    r"\bmodel[_ ]not[_ ]found\b",
    r"\bunknown model\b",
    r"\binvalid model\b",
    r"\bmodel\b[^.\n]{0,40}\b(not found|does not exist|is not available)",
    r"\bnot permitted by\b[^.\n]{0,40}\bavailableModels\b",
]

RATE_LIMIT_PATTERNS = [
    r"\brate[_ ]limit",
    r"\b429\b",
    r"\boverloaded\b",
    r"\busage limit\b",
]

BUDGET_PATTERNS = [
    r"\bmax[_ ]turns\b",
    r"\bbilling[_ ]error\b",
    r"\bcredit balance\b",
    r"\bquota\b",
]

AUTH_PATTERNS = [
    r"\bauthentication[_ ]failed\b",
    r"\binvalid[_ ]api[_ ]key\b",
    r"\bANTHROPIC_API_KEY\b",
    r"\bnot logged in\b",
    r"\boauth\b[^.\n]{0,40}\b(expired|invalid|required)",
]


def _hits(patterns, text):
    return [p for p in patterns if re.search(p, text, re.IGNORECASE)]


def classify(args):
    envelope = {}
    raw = ""

    path = pathlib.Path(args.json)
    if path.exists():
        raw = path.read_text(errors="replace").strip()
        if raw:
            try:
                envelope = json.loads(raw)
            except json.JSONDecodeError:
                envelope = {}

    if not isinstance(envelope, dict):
        envelope = {}

    stderr_text = ""
    stderr_path = pathlib.Path(args.stderr)
    if stderr_path.exists():
        stderr_text = stderr_path.read_text(errors="replace")

    text = str(envelope.get("result") or "").strip()
    is_error = bool(envelope.get("is_error"))
    subtype = str(envelope.get("subtype") or "")

    # The harness-authored match set. `.result` is normally excluded -- see
    # the module docstring -- with one narrow exception.
    #
    # Claude Code "prints the failure as the result on stdout" when a failure
    # happens inside the run, and a missing key is exactly that. So on a run
    # the envelope itself marks as failed, `.result` is harness-authored
    # rather than model-authored and is safe to match. Gating on `is_error`
    # is what keeps the discipline intact: a model that merely discusses an
    # API key in a *successful* run still cannot be mistaken for one.
    #
    # Without this, a missing key degrades to `session_error` -- not
    # dangerous, but it reports "unrecognised failure" for the one failure
    # this harness most wants to name.
    harness_text = "\n".join([stderr_text, subtype] + ([text] if is_error else []))

    unavailable_signals = _hits(UNAVAILABLE_PATTERNS, harness_text)
    rate_signals = _hits(RATE_LIMIT_PATTERNS, harness_text)
    budget_signals = _hits(BUDGET_PATTERNS, harness_text)
    auth_signals = _hits(AUTH_PATTERNS, harness_text)

    outcome = {
        "vendor": "claude",
        "model": args.model,
        "exit_status": args.exit_status,
        "credit_limit": None,
        "assistant_text_chars": len(text),
        # Present and empty rather than absent: a caller that renders these
        # must not get `null` merely because this vendor has no event stream.
        "event_counts": {},
        "unparsable_jsonl_lines": 0 if envelope or not raw else 1,
        "turns_started": int(envelope.get("num_turns") or 0),
        "turns_ended": int(envelope.get("num_turns") or 0),
        "unfinished_turn": subtype == "error_max_turns",
        "budget_signals": budget_signals,
        "rate_limit_signals": rate_signals,
        "model_unavailable_signals": unavailable_signals,
        "error_events": [subtype] if is_error and subtype else [],
        "stderr_excerpt": stderr_text.strip()[-2000:],
        "session_id": envelope.get("session_id"),
        "total_cost_usd": envelope.get("total_cost_usd"),
    }

    # Precedence matches classify-copilot-outcome.py: harness faults first,
    # because every model would hit them identically and blaming the model
    # sends the reader the wrong way.
    if args.exit_status in (126, 127):
        outcome["reason"] = HARNESS_ERROR
        outcome["headline"] = (
            f"Could not execute the claude binary (exit {args.exit_status})"
        )
        outcome["guidance"] = (
            "This is not a model failure. The CLI was not installed or not "
            "on PATH. Check the install step in "
            ".github/actions/run-agent-session/action.yml."
        )
        outcome["retry_next_model"] = False

    elif auth_signals:
        # Authentication is a harness fault, not a model one, so it must not
        # walk the preference list -- every candidate would fail identically.
        outcome["reason"] = HARNESS_ERROR
        outcome["headline"] = "Claude Code could not authenticate"
        outcome["guidance"] = (
            "`--bare` never reads OAuth credentials or the system keychain, "
            "so CLAUDE_CODE_OAUTH_TOKEN does not authenticate this path. Set "
            "the ANTHROPIC_API_KEY repository secret."
        )
        outcome["retry_next_model"] = False

    elif unavailable_signals:
        outcome["reason"] = MODEL_UNAVAILABLE
        outcome["headline"] = f"{args.model} is not available to this account"
        outcome["guidance"] = (
            "Availability is resolved per account. Check the model id "
            "spelling -- Claude Code ids use dashes (claude-opus-4-8), not "
            "the dotted Copilot CLI form -- then set the relevant "
            "CLAUDE_*_MODELS repository variable."
        )
        outcome["retry_next_model"] = True

    elif budget_signals or subtype == "error_max_turns":
        outcome["reason"] = BUDGET_EXHAUSTED
        outcome["headline"] = f"Claude session hit a limit on {args.model}"
        outcome["guidance"] = (
            "The session stopped at a turn or spend limit rather than "
            "finishing. Raise --max-turns for this role, or narrow the task. "
            "Any partial text it produced is still recorded."
        )
        outcome["retry_next_model"] = False

    elif rate_signals:
        outcome["reason"] = RATE_LIMITED
        outcome["headline"] = f"Claude rate-limited on {args.model}"
        outcome["guidance"] = (
            "This is a throughput limit, not an availability one. Re-run "
            "rather than changing the model list."
        )
        outcome["retry_next_model"] = False

    elif is_error or (args.exit_status != 0 and not text):
        outcome["reason"] = SESSION_ERROR
        outcome["headline"] = (
            f"Claude session failed on {args.model}"
            f" (exit {args.exit_status}"
            + (f", {subtype}" if subtype else "")
            + ")"
        )
        outcome["guidance"] = (
            "The session errored for a reason this harness does not yet "
            "recognise. The raw stderr is recorded below; if this turns out "
            "to be a new phrasing of a known limit, add it to the pattern "
            "lists in .github/scripts/classify-claude-outcome.py."
        )
        outcome["retry_next_model"] = False

    elif not text:
        outcome["reason"] = NO_ASSISTANT_OUTPUT
        outcome["headline"] = (
            "Claude exited cleanly but produced no result text"
        )
        outcome["guidance"] = (
            "The session ended without an answer in `.result`. This is "
            "usually a prompt the model declined, or a run cut off before "
            "the final message."
        )
        outcome["retry_next_model"] = False

    else:
        outcome["reason"] = COMPLETED
        outcome["headline"] = f"Claude session completed on {args.model}"
        outcome["guidance"] = ""
        outcome["retry_next_model"] = False

    if outcome["unfinished_turn"] and outcome["reason"] == COMPLETED:
        outcome["headline"] += " (with an unfinished turn)"

    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--exit-status", type=int, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    outcome = classify(args)
    pathlib.Path(args.out).write_text(json.dumps(outcome, indent=2) + "\n")

    print(f"reason:   {outcome['reason']}")
    print(f"headline: {outcome['headline']}")


if __name__ == "__main__":
    main()
