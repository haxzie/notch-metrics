import { index, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
import { boolean, createdAt, timestamp, updatedAt } from "./columns.ts";

/**
 * Better Auth's core tables, hand-written so drizzle and D1 agree on them.
 *
 * Deliberately *without* the organization plugin. Accounts here are
 * single-user: integrations, widgets and subscriptions all key off `user.id`.
 * The organization plugin writes an organisation and its membership in two
 * untransacted statements, and most of a reconciliation cron exists to clean up
 * after the gap between them.
 *
 * `workspace_id` is present, nullable and unused on every owned table, so a
 * future teams feature is a backfill rather than a redesign.
 *
 * `test/schema-matches-better-auth.test.ts` asserts these still match what the
 * installed version expects, so an upgrade fails in CI rather than at a user's
 * first sign-in.
 */
export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name"),
  email: text("email").notNull().unique(),
  emailVerified: boolean("email_verified").notNull().default(false),
  image: text("image"),

  // App columns, declared to Better Auth as `additionalFields` with
  // `input: false`. `plan` lives here rather than only on `subscription`
  // because it is read on nearly every request and a join for it would be a
  // second D1 round trip on the hot path.
  plan: text("plan").notNull().default("trial"),
  timezone: text("timezone").notNull().default("UTC"),
  preferredCurrency: text("preferred_currency").notNull().default("USD"),
  trialEndsAt: timestamp("trial_ends_at"),

  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const session = sqliteTable(
  "session",
  {
    id: text("id").primaryKey(),
    token: text("token").notNull().unique(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    expiresAt: timestamp("expires_at").notNull(),
    ipAddress: text("ip_address"),
    userAgent: text("user_agent"),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("session_user_idx").on(t.userId)],
);

export const account = sqliteTable(
  "account",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    accountId: text("account_id").notNull(),
    providerId: text("provider_id").notNull(),
    accessToken: text("access_token"),
    refreshToken: text("refresh_token"),
    accessTokenExpiresAt: timestamp("access_token_expires_at"),
    refreshTokenExpiresAt: timestamp("refresh_token_expires_at"),
    scope: text("scope"),
    idToken: text("id_token"),
    password: text("password"),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("account_user_idx").on(t.userId),
    uniqueIndex("account_provider_idx").on(t.providerId, t.accountId),
  ],
);

export const verification = sqliteTable(
  "verification",
  {
    id: text("id").primaryKey(),
    identifier: text("identifier").notNull(),
    value: text("value").notNull(),
    expiresAt: timestamp("expires_at").notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("verification_identifier_idx").on(t.identifier)],
);
