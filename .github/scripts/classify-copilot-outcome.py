#!/usr/bin/env python3
"""Classify how a Copilot CLI programmatic session ended.

The agent workflows all run Copilot in programmatic mode and then parse the
model's answer out of the JSONL event stream. When that parse fails, the
useful question is never "was the JSON valid" -- it is *why* the JSON is not
there. A session that ran out of AI credits mid-answer and a model that
genuinely emitted garbage look identical at the parse site and need opposite
responses: raise the budget, versus fix the prompt.

This script separates those cases. It reads the session's evidence (exit
status, stderr, the JSONL stream) and writes a small verdict file the calling
workflow can branch on and quote back to the human.

Copilot CLI does not document an event or exit code for "the AI credit limit
stopped this session" (the docs say only that "the run ends when the limit is
reached"). So budget detection here is deliberately signal-based rather than
schema-based: a list of patterns, matched against the parts of the stream the
*harness* produces, never against text the model or the prompt authored. When
a new build starts phrasing the limit differently, extend BUDGET_PATTERNS --
that list is the whole contract, and every unmatched failure still lands in
the report with its raw evidence attached so the new phrasing is visible.

Usage:

    classify-copilot-outcome.py \
        --jsonl copilot-output.jsonl \
        --stderr copilot-error.txt \
        --exit-status 1 \
        --model claude-opus-5 \
        --credit-limit 75 \
        --out copilot-outcome.json
"""

import argparse
import json
import pathlib
import re


# Reasons, most specific first. The order here is the precedence order used
# by classify(): the first reason whose evidence is present wins.
HARNESS_ERROR = "harness_error"
MODEL_UNAVAILABLE = "model_unavailable"
BUDGET_EXHAUSTED = "budget_exhausted"
RATE_LIMITED = "rate_limited"
SESSION_ERROR = "session_error"
NO_ASSISTANT_OUTPUT = "no_assistant_output"
COMPLETED = "completed"


# Matched against harness-authored text only: stderr, and JSONL events that
# are not user or assistant message content. Keeping model-authored text out
# of the match set matters -- an assistant that muses about "the credit limit"
# must not be mistaken for the runner enforcing one.
BUDGET_PATTERNS = [
    r"max[-_ ]?ai[-_ ]?credits?",
    r"\bai credits?\b[^.\n]{0,60}\b(limit|exceed|exhaust|reach|remain|out of)",
    r"\b(credit|budget|spending|session)\s+(limit|cap)\b",
    r"\bpremium request",
    r"\bquota\b[^.\n]{0,60}\b(exceed|exhaust|reach)",
    r"\b(exceed|exhaust|reach)\w*\b[^.\n]{0,60}\bquota\b",
    r"\binsufficient (credits?|quota|budget)\b",
    r"\bbudget (exhaust|exceed|reach)\w*",
    r"\bHTTP 402\b|\bstatus 402\b",
]

# Rate limiting is a distinct failure with a distinct remedy (wait and retry,
# rather than raise the cap), so it does not get folded into the budget case.
RATE_LIMIT_PATTERNS = [
    r"\brate[-_ ]?limit",
    r"\btoo many requests\b",
    r"\bHTTP 429\b|\bstatus 429\b",
    r"\bretry[-_ ]after\b",
]

MODEL_UNAVAILABLE_PATTERNS = [
    r"from --model flag is not available",
    r"\bmodel\b[^.\n]{0,40}\bis not available\b",
    r"\bunknown model\b",
]

# Event types whose payload is authored by the harness rather than by the
# model or the prompt. Only these are pattern-matched.
MODEL_AUTHORED_EVENT_TYPES = {
    "user.message",
    "assistant.message",
    "assistant.message_delta",
    "assistant.message_start",
    "assistant.reasoning",
    "assistant.reasoning_delta",
}


def find_signals(text, patterns):
    """Return [(pattern, matching line)] for every pattern that hits."""

    signals = []
    seen = set()

    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)

        if not match:
            continue

        # The whole line, not just the match, because the surrounding words
        # are what tell a human which limit was actually hit. Several
        # patterns commonly fire on the same line; report that line once.
        line_start = text.rfind("\n", 0, match.start()) + 1
        line_end = text.find("\n", match.end())

        if line_end == -1:
            line_end = len(text)

        excerpt = text[line_start:line_end].strip()[:400]

        if excerpt in seen:
            continue

        seen.add(excerpt)

        signals.append({"pattern": pattern, "excerpt": excerpt})

    return signals


def read_events(jsonl_path):
    """Parse the JSONL stream, tolerating partial or non-JSON lines."""

    events = []
    unparsable = 0

    if not jsonl_path.exists():
        return events, unparsable

    for raw_line in jsonl_path.read_text(errors="replace").splitlines():
        raw_line = raw_line.strip()

        if not raw_line:
            continue

        try:
            events.append(json.loads(raw_line))
        except json.JSONDecodeError:
            # A truncated final line is itself evidence: the process was cut
            # off mid-write rather than closing the stream cleanly.
            unparsable += 1

    return events, unparsable


def assistant_text(events):
    """Concatenate assistant.message content across the session.

    Copilot CLI has shipped both a bare string and a list of typed content
    blocks in this field, so both shapes are handled.
    """

    parts = []

    for event in events:
        if event.get("type") != "assistant.message":
            continue

        content = (event.get("data") or {}).get("content")

        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))

    return "\n".join(parts).strip()


def harness_authored_text(events):
    """Serialize the events the model did not author, for pattern matching."""

    lines = []

    for event in events:
        if event.get("type") in MODEL_AUTHORED_EVENT_TYPES:
            continue

        lines.append(json.dumps(event, default=str))

    return "\n".join(lines)


def classify(args):
    jsonl_path = pathlib.Path(args.jsonl)
    stderr_path = pathlib.Path(args.stderr)

    stderr_text = (
        stderr_path.read_text(errors="replace")
        if stderr_path.exists()
        else ""
    )

    events, unparsable_lines = read_events(jsonl_path)
    text = assistant_text(events)
    harness_text = harness_authored_text(events)

    searchable = stderr_text + "\n" + harness_text

    event_counts = {}

    for event in events:
        event_type = event.get("type") or "<untyped>"
        event_counts[event_type] = event_counts.get(event_type, 0) + 1

    # A turn that opened and never closed is the signature of a session cut
    # short -- by the credit cap, a timeout, or a crash. On its own it does
    # not name the cause, but it is what separates "stopped mid-answer" from
    # "answered fully, badly".
    turns_started = event_counts.get("assistant.turn_start", 0)
    turns_ended = event_counts.get("assistant.turn_end", 0)

    budget_signals = find_signals(searchable, BUDGET_PATTERNS)
    rate_signals = find_signals(searchable, RATE_LIMIT_PATTERNS)
    unavailable_signals = find_signals(
        stderr_text, MODEL_UNAVAILABLE_PATTERNS
    )

    error_events = [
        event
        for event in events
        if "error" in (event.get("type") or "").lower()
    ]

    outcome = {
        # Present so a caller reading either classifier's output can name the
        # vendor without knowing which one produced the file.
        "vendor": "copilot",
        "model": args.model,
        "exit_status": args.exit_status,
        "credit_limit": args.credit_limit,
        "assistant_text_chars": len(text),
        "event_counts": event_counts,
        "unparsable_jsonl_lines": unparsable_lines,
        "turns_started": turns_started,
        "turns_ended": turns_ended,
        "unfinished_turn": turns_started > turns_ended,
        "budget_signals": budget_signals,
        "rate_limit_signals": rate_signals,
        "model_unavailable_signals": unavailable_signals,
        "error_events": [
            json.dumps(event, default=str)[:600] for event in error_events[:5]
        ],
        "stderr_excerpt": stderr_text.strip()[-2000:],
    }

    # Precedence. Harness faults first: every model would hit them
    # identically, so blaming the model would send the reader the wrong way.
    if args.exit_status in (126, 127):
        outcome["reason"] = HARNESS_ERROR
        outcome["headline"] = (
            f"Could not execute the copilot binary (exit {args.exit_status})"
        )
        outcome["guidance"] = (
            "This is not a model failure and not a budget failure. Check "
            "that Copilot CLI installed on the runner, and that the prompt "
            "is fed on stdin rather than as a command-line argument."
        )
        outcome["retry_next_model"] = False

    elif unavailable_signals:
        outcome["reason"] = MODEL_UNAVAILABLE
        outcome["headline"] = (
            f"Model {args.model} is not available to this workflow identity"
        )
        outcome["guidance"] = (
            "Availability is resolved per requesting identity, so a model "
            "offered in your own picker can still be refused to the Actions "
            "GITHUB_TOKEN. The run will try the next candidate model."
        )
        outcome["retry_next_model"] = True

    elif budget_signals:
        outcome["reason"] = BUDGET_EXHAUSTED
        outcome["headline"] = (
            "Copilot stopped because it hit its AI credit limit"
            f" ({args.credit_limit} credits)"
        )
        outcome["guidance"] = (
            "The session ended on its budget, not on a model error. Anything "
            "the model had not finished writing is simply missing. Raise the "
            "credit cap for this workflow, or narrow the request, then retry. "
            "Retrying on a different model would hit the same cap."
        )
        outcome["retry_next_model"] = False

    elif rate_signals:
        outcome["reason"] = RATE_LIMITED
        outcome["headline"] = "Copilot was rate limited"
        outcome["guidance"] = (
            "The request was throttled rather than refused or exhausted. "
            "Retry the run later; no configuration change is needed."
        )
        outcome["retry_next_model"] = False

    elif error_events or (args.exit_status != 0 and not text):
        outcome["reason"] = SESSION_ERROR
        outcome["headline"] = (
            f"Copilot session failed on {args.model}"
            f" (exit {args.exit_status})"
        )
        outcome["guidance"] = (
            "The session errored for a reason this harness does not yet "
            "recognise. The raw stderr and event evidence are recorded "
            "below; if this turns out to be a new phrasing of a known limit, "
            "add it to BUDGET_PATTERNS in "
            ".github/scripts/classify-copilot-outcome.py."
        )
        outcome["retry_next_model"] = False

    elif not text:
        outcome["reason"] = NO_ASSISTANT_OUTPUT
        outcome["headline"] = (
            "Copilot exited cleanly but produced no assistant message"
        )
        outcome["guidance"] = (
            "The session ended without the model saying anything. This is "
            "usually a silently truncated session or a prompt the model "
            "declined. Check the event counts below."
        )
        outcome["retry_next_model"] = False

    else:
        outcome["reason"] = COMPLETED
        outcome["headline"] = f"Copilot session completed on {args.model}"
        outcome["guidance"] = ""
        outcome["retry_next_model"] = False

    # An unfinished turn alongside a nominally clean finish is worth saying
    # out loud, because it is the case where the answer is present but cut.
    if outcome["unfinished_turn"] and outcome["reason"] == COMPLETED:
        outcome["headline"] += " (with an unfinished turn)"

    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--exit-status", type=int, required=True)
    parser.add_argument("--model", default="unknown")
    parser.add_argument("--credit-limit", default="unknown")
    parser.add_argument("--out", required=True)

    args = parser.parse_args()

    outcome = classify(args)

    pathlib.Path(args.out).write_text(
        json.dumps(outcome, indent=2) + "\n"
    )

    print(f"reason:   {outcome['reason']}")
    print(f"headline: {outcome['headline']}")
    print(f"assistant text: {outcome['assistant_text_chars']} chars")
    print(f"events: {json.dumps(outcome['event_counts'])}")

    if outcome["unfinished_turn"]:
        print(
            "turns: "
            f"{outcome['turns_started']} started, "
            f"{outcome['turns_ended']} ended -- session was cut short"
        )

    for signal in outcome["budget_signals"] + outcome["rate_limit_signals"]:
        print(f"signal: {signal['excerpt']}")


if __name__ == "__main__":
    main()
