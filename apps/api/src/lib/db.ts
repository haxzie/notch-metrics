import { drizzle } from "drizzle-orm/d1";
import { schema } from "@notch/db";
import type { Env } from "../env.ts";

export type Database = ReturnType<typeof createDb>;

export function createDb(env: Env) {
  return drizzle(env.DB, { schema });
}
