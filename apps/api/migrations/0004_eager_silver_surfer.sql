CREATE TABLE `notification` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`seq` integer DEFAULT 0 NOT NULL,
	`integration_id` text,
	`provider` text NOT NULL,
	`connection_label` text NOT NULL,
	`type_id` text NOT NULL,
	`severity` text DEFAULT 'info' NOT NULL,
	`title` text NOT NULL,
	`body` text,
	`amount` integer,
	`currency` text,
	`url` text,
	`occurred_at` integer NOT NULL,
	`dedupe_key` text NOT NULL,
	`read_at` integer,
	`alert` integer DEFAULT true NOT NULL,
	`source` text DEFAULT 'cron' NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`integration_id`) REFERENCES `integration`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE UNIQUE INDEX `notification_dedupe_idx` ON `notification` (`user_id`,`dedupe_key`);--> statement-breakpoint
CREATE INDEX `notification_feed_idx` ON `notification` (`user_id`,`seq`);--> statement-breakpoint
CREATE INDEX `notification_sweep_idx` ON `notification` (`created_at`);--> statement-breakpoint
CREATE TABLE `notification_cursor` (
	`subscription_id` text PRIMARY KEY NOT NULL,
	`last_event_id` text,
	`seen_through` integer,
	`provider_cursor` text,
	`last_value` real,
	`last_state` text,
	`fired_at` integer,
	`evaluated_at` integer,
	FOREIGN KEY (`subscription_id`) REFERENCES `notification_subscription`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `notification_state` (
	`user_id` text PRIMARY KEY NOT NULL,
	`seq` integer DEFAULT 0 NOT NULL,
	`unread` integer DEFAULT 0 NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`enabled` integer DEFAULT true NOT NULL,
	`quiet_from_minute` integer,
	`quiet_to_minute` integer,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `notification_subscription` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`integration_id` text NOT NULL,
	`type_id` text NOT NULL,
	`enabled` integer DEFAULT false NOT NULL,
	`params` text NOT NULL,
	`threshold` text,
	`min_interval_seconds` integer DEFAULT 3600 NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`integration_id`) REFERENCES `integration`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `notification_subscription_unique_idx` ON `notification_subscription` (`integration_id`,`type_id`);--> statement-breakpoint
CREATE INDEX `notification_subscription_enabled_idx` ON `notification_subscription` (`enabled`,`integration_id`);--> statement-breakpoint
CREATE INDEX `notification_subscription_user_idx` ON `notification_subscription` (`user_id`);