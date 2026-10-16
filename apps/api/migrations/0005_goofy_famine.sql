CREATE TABLE `integration_event` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`integration_id` text NOT NULL,
	`at` integer NOT NULL,
	`kind` text NOT NULL,
	`outcome` text NOT NULL,
	`metric` text,
	`code` text,
	`reason` text,
	`http_status` integer,
	`duration_ms` integer,
	`calls` text,
	`detail` text,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`integration_id`) REFERENCES `integration`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `integration_event_integration_idx` ON `integration_event` (`integration_id`,`at`);--> statement-breakpoint
CREATE INDEX `integration_event_at_idx` ON `integration_event` (`at`);--> statement-breakpoint
CREATE INDEX `integration_event_user_idx` ON `integration_event` (`user_id`);--> statement-breakpoint
ALTER TABLE `integration` ADD `auth_failures` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `integration` ADD `reauth_required_at` integer;