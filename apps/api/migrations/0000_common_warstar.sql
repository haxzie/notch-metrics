CREATE TABLE `account` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`account_id` text NOT NULL,
	`provider_id` text NOT NULL,
	`access_token` text,
	`refresh_token` text,
	`access_token_expires_at` integer,
	`refresh_token_expires_at` integer,
	`scope` text,
	`id_token` text,
	`password` text,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `account_user_idx` ON `account` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `account_provider_idx` ON `account` (`provider_id`,`account_id`);--> statement-breakpoint
CREATE TABLE `session` (
	`id` text PRIMARY KEY NOT NULL,
	`token` text NOT NULL,
	`user_id` text NOT NULL,
	`expires_at` integer NOT NULL,
	`ip_address` text,
	`user_agent` text,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `session_token_unique` ON `session` (`token`);--> statement-breakpoint
CREATE INDEX `session_user_idx` ON `session` (`user_id`);--> statement-breakpoint
CREATE TABLE `user` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text,
	`email` text NOT NULL,
	`email_verified` integer DEFAULT false NOT NULL,
	`image` text,
	`plan` text DEFAULT 'trial' NOT NULL,
	`timezone` text DEFAULT 'UTC' NOT NULL,
	`preferred_currency` text DEFAULT 'USD' NOT NULL,
	`trial_ends_at` integer,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `user_email_unique` ON `user` (`email`);--> statement-breakpoint
CREATE TABLE `verification` (
	`id` text PRIMARY KEY NOT NULL,
	`identifier` text NOT NULL,
	`value` text NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `verification_identifier_idx` ON `verification` (`identifier`);--> statement-breakpoint
CREATE TABLE `desktop_auth_code` (
	`code` text PRIMARY KEY NOT NULL,
	`challenge` text NOT NULL,
	`user_id` text NOT NULL,
	`expires_at` integer NOT NULL,
	`consumed_at` integer,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `desktop_auth_code_user_idx` ON `desktop_auth_code` (`user_id`);--> statement-breakpoint
CREATE TABLE `device_token` (
	`id` text PRIMARY KEY NOT NULL,
	`token_hash` text NOT NULL,
	`user_id` text NOT NULL,
	`label` text NOT NULL,
	`last_used_at` integer,
	`revoked_at` integer,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `device_token_token_hash_unique` ON `device_token` (`token_hash`);--> statement-breakpoint
CREATE INDEX `device_token_user_idx` ON `device_token` (`user_id`);--> statement-breakpoint
CREATE TABLE `integration` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`workspace_id` text,
	`provider` text NOT NULL,
	`label` text NOT NULL,
	`credential_ciphertext` text NOT NULL,
	`credential_iv` text NOT NULL,
	`credential_wrapped_dek` text NOT NULL,
	`key_version` integer NOT NULL,
	`credential_hint` text NOT NULL,
	`credential_fingerprint` text NOT NULL,
	`enabled_metrics` text NOT NULL,
	`available_metrics` text NOT NULL,
	`account_label` text,
	`account_currency` text,
	`status` text DEFAULT 'ok' NOT NULL,
	`last_error_code` text,
	`last_error_at` integer,
	`last_synced_at` integer,
	`next_allowed_at` integer DEFAULT 0 NOT NULL,
	`failure_count` integer DEFAULT 0 NOT NULL,
	`disabled_until` integer DEFAULT 0 NOT NULL,
	`refresh_offset_seconds` integer DEFAULT 0 NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `integration_user_idx` ON `integration` (`user_id`);--> statement-breakpoint
CREATE INDEX `integration_disabled_idx` ON `integration` (`disabled_until`);--> statement-breakpoint
CREATE INDEX `integration_next_allowed_idx` ON `integration` (`next_allowed_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `integration_fingerprint_idx` ON `integration` (`user_id`,`provider`,`credential_fingerprint`);--> statement-breakpoint
CREATE TABLE `metric_cache` (
	`cache_key` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`integration_id` text NOT NULL,
	`payload` text NOT NULL,
	`etag` text NOT NULL,
	`computed_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`source` text DEFAULT 'request' NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`integration_id`) REFERENCES `integration`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `metric_cache_user_idx` ON `metric_cache` (`user_id`);--> statement-breakpoint
CREATE INDEX `metric_cache_expiry_idx` ON `metric_cache` (`expires_at`);--> statement-breakpoint
CREATE INDEX `metric_cache_integration_idx` ON `metric_cache` (`integration_id`);--> statement-breakpoint
CREATE TABLE `rate_limit` (
	`subject` text NOT NULL,
	`window_start` integer NOT NULL,
	`count` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `rate_limit_subject_idx` ON `rate_limit` (`subject`,`window_start`);--> statement-breakpoint
CREATE TABLE `subscription` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`dodo_subscription_id` text,
	`dodo_customer_id` text,
	`status` text DEFAULT 'trialing' NOT NULL,
	`current_period_end` integer,
	`grace_until` integer,
	`cancel_at_period_end` integer DEFAULT false NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `subscription_user_id_unique` ON `subscription` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `subscription_dodo_subscription_id_unique` ON `subscription` (`dodo_subscription_id`);--> statement-breakpoint
CREATE INDEX `subscription_customer_idx` ON `subscription` (`dodo_customer_id`);--> statement-breakpoint
CREATE TABLE `webhook_event` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE TABLE `widget` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`workspace_id` text,
	`kind` text NOT NULL,
	`integration_id` text,
	`metric` text,
	`custom_metric_id` text,
	`title` text,
	`size` text DEFAULT '2x1' NOT NULL,
	`col` integer DEFAULT 0 NOT NULL,
	`row` integer DEFAULT 0 NOT NULL,
	`position` integer NOT NULL,
	`granularity` text DEFAULT 'day' NOT NULL,
	`range` text DEFAULT '30d' NOT NULL,
	`chart` text DEFAULT 'sparkline' NOT NULL,
	`visible` integer DEFAULT true NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`integration_id`) REFERENCES `integration`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `widget_user_visible_idx` ON `widget` (`user_id`,`visible`);--> statement-breakpoint
CREATE UNIQUE INDEX `widget_position_idx` ON `widget` (`user_id`,`position`);--> statement-breakpoint
CREATE TABLE `widget_revision` (
	`user_id` text PRIMARY KEY NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
