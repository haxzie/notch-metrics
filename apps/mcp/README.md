# @notch/mcp

An MCP server that lets Claude Code — or any MCP client — author custom metrics
for the [Notch Metrics](https://notchmetrics.com) macOS app.

```bash
claude mcp add notch-metrics -- npx -y notch-metrics-mcp
```

A custom metric is one ES module stored on your Mac under
`~/Library/Application Support/NotchMetrics/metrics/<id>/`. The app runs it on a
schedule and draws the number in your notch. Nothing is uploaded: the code, the
API keys and the results stay on the machine.

## Tools

| Tool                              | What it does                                                                                   |
| --------------------------------- | ---------------------------------------------------------------------------------------------- |
| `describe_runtime`                | The context shape, the return shape and the network policy. Call this first.                   |
| `list_providers`                  | Built-in integrations, so you can suggest one instead of writing code.                         |
| `list_metrics` · `get_metric`     | What exists, and its source.                                                                   |
| `test_metric`                     | Runs a metric — saved or inline — and reports the value, timing, every HTTP call and the logs. |
| `create_metric` · `update_metric` | Stages, test-runs, and only publishes on success.                                              |
| `set_metric_secret`               | Stores a declared secret in the macOS Keychain.                                                |
| `delete_metric`                   | Removes a metric.                                                                              |

## Safety

- API keys are **declared** in the manifest and stored in the Keychain, never
  written into the metric file. A source containing anything key-shaped is
  refused.
- Every metric declares `allowedHosts`. `fetch` is unavailable; `ctx.http` is
  the only egress, it requires https, and it refuses private and loopback
  addresses.
- A new metric is not executed until you enable it in the app's settings.

This is a containment boundary, not a sandbox: a metric runs with your own
privileges, like a shell script you wrote. Read what your agent writes.
