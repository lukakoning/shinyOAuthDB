-- Replace fixture-project, oauthdb_fixture and both email addresses.
-- Run as the fixture administrator, separately from the package acceptance.
CREATE SCHEMA IF NOT EXISTS `fixture-project.oauthdb_fixture`
OPTIONS(location = 'EU', default_table_expiration_days = 7);

CREATE OR REPLACE TABLE `fixture-project.oauthdb_fixture.visible_rows` AS
SELECT 'a@example.org' AS owner_email, 'A-first' AS visible_marker UNION ALL
SELECT 'a@example.org', 'A-second' UNION ALL
SELECT 'b@example.org', 'B-first' UNION ALL
SELECT 'b@example.org', 'B-second';

CREATE OR REPLACE ROW ACCESS POLICY own_rows
ON `fixture-project.oauthdb_fixture.visible_rows`
GRANT TO ('user:a@example.org', 'user:b@example.org')
FILTER USING (owner_email = SESSION_USER());

CREATE OR REPLACE TABLE `fixture-project.oauthdb_fixture.forbidden_rows` AS
SELECT 'administrator-only' AS marker;
-- Grant A/B query-job creation and metadata access, and data access only to
-- visible_rows. Do not grant dataset-wide dataViewer or any forbidden_rows access.
