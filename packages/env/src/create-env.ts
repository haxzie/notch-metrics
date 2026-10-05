import { z } from "zod";

/**
 * Validated `process.env` for Node and Next.
 *
 * Deliberately *not* used by the Worker. A Worker's configuration arrives as a
 * binding object per request, not as a module-scope global, and reading
 * `process.env` there gets you `undefined` at deploy time with no error —
 * `apps/api/src/env.ts` declares that interface instead.
 */
export function createEnv<
  C extends Record<string, z.ZodType>,
  S extends Record<string, z.ZodType>,
>(config: {
  client: C;
  server: S;
  runtimeEnv: Record<string, string | undefined>;
}): z.infer<z.ZodObject<C & S>> {
  for (const key of Object.keys(config.client)) {
    if (!key.startsWith("NEXT_PUBLIC_")) {
      // Next inlines `NEXT_PUBLIC_*` into the browser bundle and nothing else.
      // A client variable without the prefix is `undefined` in the browser and
      // perfectly fine on the server, which is the worst possible failure shape.
      throw new Error(`client env ${key} must start with NEXT_PUBLIC_`);
    }
  }

  const schema = z.object({ ...config.client, ...config.server } as C & S);
  const parsed = schema.safeParse(config.runtimeEnv);

  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join(".") || "(root)"}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment:\n${issues}\n\nSee .env.example.`);
  }

  // Lazy, so importing this module in a context that happens not to need the
  // environment (a type-only import, a build-time tool) does not explode.
  return new Proxy(parsed.data as Record<string, unknown>, {
    get(target, prop: string) {
      if (!(prop in target)) throw new Error(`Unknown environment variable: ${prop}`);
      return target[prop];
    },
  }) as z.infer<z.ZodObject<C & S>>;
}
