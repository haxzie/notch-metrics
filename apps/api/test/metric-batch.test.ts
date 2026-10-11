import { describe, expect, it } from "vitest";
import { runGrouped } from "../src/lib/metrics.ts";

describe("batching metrics across integrations", () => {
  /**
   * The silent failure. The Mac app zips the reply against the widgets it
   * asked for, so a reply ordered by *completion* rather than by request
   * shows every tile somebody else's number — a believable figure under the
   * wrong label, with nothing in the UI to suggest anything went wrong.
   */
  it("answers in request order however the groups finish", async () => {
    const log: string[] = [];
    const items = [
      { key: "slow", ms: 40, id: "a" },
      { key: "fast", ms: 1, id: "b" },
      { key: "medium", ms: 20, id: "c" },
    ];

    const results = await runGrouped(
      items,
      (item) => item.key,
      async (item) => {
        await new Promise((resolve) => setTimeout(resolve, item.ms));
        log.push(item.id);
        return item.id;
      },
    );

    expect(results).toEqual(["a", "b", "c"]);
    // And they really did race: completion order is not request order.
    expect(log).toEqual(["b", "c", "a"]);
  });

  /**
   * The one thing the old sequential loop actually bought. Two widgets on
   * one integration share credentials, so overlapping them races the token
   * refresh and doubles up on that provider's rate limit in the same
   * instant.
   */
  it("never overlaps two queries on the same integration", async () => {
    const log: string[] = [];
    await runGrouped(
      ["x1", "x2", "x3"],
      () => "same-integration",
      async (id) => {
        log.push(`start:${id}`);
        await new Promise((resolve) => setTimeout(resolve, 5));
        log.push(`end:${id}`);
      },
    );
    // Strictly alternating start/end means no two were ever in flight.
    expect(log).toEqual(["start:x1", "end:x1", "start:x2", "end:x2", "start:x3", "end:x3"]);
  });

  /** Different integrations have nothing to protect from each other. */
  it("overlaps queries on different integrations", async () => {
    const started: number[] = [];
    const begun = Date.now();
    await runGrouped(
      ["int_1", "int_2", "int_3"],
      (id) => id,
      async () => {
        started.push(Date.now() - begun);
        await new Promise((resolve) => setTimeout(resolve, 30));
      },
    );
    // All three left the gate before the first came back.
    expect(Math.max(...started)).toBeLessThan(30);
  });

  it("asks nothing when there is nothing to ask", async () => {
    let calls = 0;
    const results = await runGrouped(
      [],
      () => "k",
      async () => {
        calls += 1;
      },
    );
    expect(results).toEqual([]);
    expect(calls).toBe(0);
  });
});
