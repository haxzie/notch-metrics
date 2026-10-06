CREATE TABLE `connect_link` (
	`id` text PRIMARY KEY NOT NULL,
	`token_hash` text NOT NULL,
	`user_id` text NOT NULL,
	`connector_id` text NOT NULL,
	`oauth_state` text,
	`pending_ciphertext` text,
	`pending_iv` text,
	`pending_wrapped_dek` text,
	`pending_key_version` integer,
	`integration_id` text,
	`completed_at` integer,
	`expires_at` integer NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `connect_link_token_hash_unique` ON `connect_link` (`token_hash`);--> statement-breakpoint
CREATE INDEX `connect_link_user_idx` ON `connect_link` (`user_id`);--> statement-breakpoint
CREATE INDEX `connect_link_expiry_idx` ON `connect_link` (`expires_at`);