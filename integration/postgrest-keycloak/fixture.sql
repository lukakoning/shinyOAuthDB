CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'fixture-authenticator-password';
CREATE ROLE alice NOLOGIN;
CREATE ROLE bob NOLOGIN;
GRANT alice, bob TO authenticator;
CREATE SCHEMA reporting;
GRANT USAGE ON SCHEMA reporting TO alice, bob;
CREATE TABLE reporting.visible_rows (id integer PRIMARY KEY, owner_name text NOT NULL, marker text NOT NULL);
INSERT INTO reporting.visible_rows VALUES
  (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),
  (3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2');
ALTER TABLE reporting.visible_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON reporting.visible_rows USING (owner_name = current_user);
GRANT SELECT ON reporting.visible_rows TO alice, bob;
CREATE FUNCTION reporting.own_rows() RETURNS TABLE(database_user text, marker text)
  LANGUAGE sql STABLE SECURITY INVOKER AS
  'SELECT current_user::text, marker FROM reporting.visible_rows ORDER BY id';
CREATE FUNCTION reporting.echo(value text) RETURNS text LANGUAGE sql IMMUTABLE AS 'SELECT value';
CREATE TABLE reporting.alice_only (marker text);
CREATE TABLE reporting.bob_only (marker text);
INSERT INTO reporting.alice_only VALUES ('alice-private');
INSERT INTO reporting.bob_only VALUES ('bob-private');
GRANT SELECT ON reporting.alice_only TO alice;
GRANT SELECT ON reporting.bob_only TO bob;
