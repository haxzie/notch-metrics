ALTER TABLE `widget` ADD `app_id` text DEFAULT 'unknown' NOT NULL;--> statement-breakpoint
ALTER TABLE `widget_revision` ADD `rows` integer DEFAULT 2 NOT NULL;--> statement-breakpoint
ALTER TABLE `widget_revision` ADD `display` text DEFAULT 'grid' NOT NULL;