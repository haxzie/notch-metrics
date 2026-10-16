ALTER TABLE `integration_event` ADD `request_id` text;--> statement-breakpoint
CREATE INDEX `integration_event_request_idx` ON `integration_event` (`request_id`);