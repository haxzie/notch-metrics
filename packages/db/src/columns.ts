import { sql } from "drizzle-orm";
import { integer, text } from "drizzle-orm/sqlite-core";

/** Unix seconds, defaulted in SQL so an insert cannot forget it. */
export const createdAt = () =>
  integer("created_at", { mode: "timestamp" })
    .notNull()
    .default(sql`(unixepoch())`);

export const updatedAt = () =>
  integer("updated_at", { mode: "timestamp" })
    .notNull()
    .default(sql`(unixepoch())`);

export const timestamp = (name: string) => integer(name, { mode: "timestamp" });

/** SQLite has no boolean. Store 0/1 and let drizzle do the coercion. */
export const boolean = (name: string) => integer(name, { mode: "boolean" });

/** JSON columns are text. Typed at the call site, validated by zod at the edge. */
export const json = <T>(name: string) => text(name, { mode: "json" }).$type<T>();
