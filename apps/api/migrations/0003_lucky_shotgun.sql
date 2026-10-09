ALTER TABLE `integration` ADD `token_expires_at` integer;--> statement-breakpoint
ALTER TABLE `integration` ADD `last_refresh_attempt_at` integer;--> statement-breakpoint
ALTER TABLE `integration` ADD `refresh_failures` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
CREATE INDEX `integration_refresh_due_idx` ON `integration` (`provider`,`token_expires_at`);