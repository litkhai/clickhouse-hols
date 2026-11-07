#!/usr/bin/env python3
"""Render a `claude -p --output-format stream-json` log into a short markdown transcript:
the prompt, every MCP tool call with its SQL and the first part of its result, and the final answer.
Usage: render_transcript.py LOG.jsonl ID CONTEXT PROMPT"""
import json, sys

log, pid, ctx, prompt = sys.argv[1:5]
calls, results, answer, meta = [], {}, "", {}
for line in open(log, encoding="utf-8"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    if ev.get("type") == "system" and ev.get("subtype") == "init":
        meta["model"] = ev.get("model")
        meta["claude_code"] = ev.get("claude_code_version")
    elif ev.get("type") == "assistant":
        for c in ev["message"].get("content", []):
            if c.get("type") == "tool_use":
                calls.append(c)
    elif ev.get("type") == "user":
        for c in ev["message"].get("content", []) if isinstance(ev["message"].get("content"), list) else []:
            if c.get("type") == "tool_result":
                body = c.get("content")
                if isinstance(body, list):
                    body = " ".join(b.get("text", "") for b in body if isinstance(b, dict))
                results[c["tool_use_id"]] = (bool(c.get("is_error")), str(body))
    elif ev.get("type") == "result":
        answer = ev.get("result", "")
        meta.update(cost_usd=round(ev.get("total_cost_usd") or 0, 4), turns=ev.get("num_turns"),
                    seconds=round((ev.get("duration_ms") or 0) / 1000, 1), stop=ev.get("subtype"))

print(f"## {pid} ({ctx})\n\n> {prompt}\n")
print(f"model `{meta.get('model')}` · Claude Code {meta.get('claude_code')} · {meta.get('turns')} turns · "
      f"{meta.get('seconds')} s · ${meta.get('cost_usd')} · {meta.get('stop')}\n")
for i, c in enumerate(calls, 1):
    inp = c.get("input", {})
    err, body = results.get(c["id"], (None, ""))
    status = "error" if err or "Query execution failed" in body[:200] or "timed out" in body[:200] else "ok"
    tool = c["name"].split("__")[-1]
    if not c["name"].startswith("mcp__"):   # Claude Code's own tools (e.g. ToolSearch loading the MCP tool schemas)
        print(f"### call {i}: `{tool}` (Claude Code, not MCP)\n\n`" + json.dumps(inp, ensure_ascii=False) + "`\n")
        continue
    print(f"### call {i}: `{tool}` → {status}\n")
    if c["name"].endswith("run_query") and "query" in inp:
        print("```sql\n" + inp["query"].strip() + "\n```\n")
    else:
        print("`" + json.dumps(inp, ensure_ascii=False) + "`\n")
    print("```text\n" + (body[:600] + (" …" if len(body) > 600 else "")) + "\n```\n")
print("### answer\n\n" + answer.strip() + "\n")
