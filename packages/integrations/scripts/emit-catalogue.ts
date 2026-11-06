/**
 * Writes `apps/mac/App/Resources/catalogue.json` — the connector catalogue,
 * compiled into the Mac app.
 *
 * The app had no catalogue until `GET /v1/connectors` answered, so with the
 * API unreachable the Integrations pane and the credentials form had nothing
 * to draw: no names, no fields, no setup steps. That was tolerable while the
 * server also held the credentials and did the fetching. It is not tolerable
 * now that neither is true — an app whose whole claim is that your keys never
 * leave this Mac cannot need a round trip to list what you may connect.
 *
 * Committed rather than fetched, for the same reason the connector marks are
 * (`scripts/sync-connector-icons.mjs`): a catalogue arriving over the network
 * makes that pane a column of grey boxes on a bad connection.
 *
 * The shape is exactly what the route served, so the Swift side decodes one
 * type either way and there is no second code path to keep in step.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { CONNECTOR_CATEGORY_LABELS } from "@notch/schemas";
import { catalogue, REGISTRY_VERSION } from "../src/registry.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const target = join(root, "apps", "mac", "App", "Resources", "catalogue.json");

const body = {
  version: REGISTRY_VERSION,
  categories: catalogue().map(({ category, connectors }) => ({
    id: category,
    label: CONNECTOR_CATEGORY_LABELS[category],
    // No `connections`: those belong to one user and this file ships to every
    // one of them. The app merges its own in at runtime.
    connectors: connectors.map((manifest) => ({ ...manifest, connections: [] })),
  })),
};

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, `${JSON.stringify(body, null, 2)}\n`);

const count = body.categories.reduce((n, group) => n + group.connectors.length, 0);
console.log(`catalogue.json -> ${count} connectors, version ${body.version}`);
