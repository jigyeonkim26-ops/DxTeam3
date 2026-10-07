-- Draft only: review and apply manually in the team's migration workflow.
-- Codex must not execute this file against the live database.
-- Existing users and existing group rows are not changed or deleted.

ALTER TABLE group_members
    ADD COLUMN custom_name VARCHAR(100) NULL,
    ADD COLUMN notifications_enabled TINYINT(1) NOT NULL DEFAULT 1,
    ADD COLUMN pin_color_value BIGINT NULL;
