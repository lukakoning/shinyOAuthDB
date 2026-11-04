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
CREATE FUNCTION reporting.roundtrip(value text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('text_value', value, 'null_value', NULL,
    'integer_value', 9223372036854775807::bigint,
    'time_value', '2020-02-29 12:34:56.123456+00'::timestamptz);
$$;
CREATE TABLE reporting.alice_only (marker text);
CREATE TABLE reporting.bob_only (marker text);
INSERT INTO reporting.alice_only VALUES ('alice-private');
INSERT INTO reporting.bob_only VALUES ('bob-private');
GRANT SELECT ON reporting.alice_only TO alice;
GRANT SELECT ON reporting.bob_only TO bob;
CREATE TABLE reporting.write_log (owner_name text NOT NULL DEFAULT current_user, operation_id text NOT NULL);
ALTER TABLE reporting.write_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_writes ON reporting.write_log USING (owner_name = current_user) WITH CHECK (owner_name = current_user);
GRANT SELECT, INSERT ON reporting.write_log TO alice, bob;
CREATE FUNCTION reporting.record_once(operation_id text) RETURNS integer LANGUAGE sql VOLATILE SECURITY INVOKER AS $$
  INSERT INTO reporting.write_log (operation_id) VALUES ($1) RETURNING 1;
$$;
CREATE FUNCTION reporting.record_then_fail(operation_id text) RETURNS integer LANGUAGE sql VOLATILE SECURITY INVOKER AS $$
  SELECT reporting.record_once($1);
$$;
CREATE FUNCTION reporting.write_count(operation_id text) RETURNS bigint LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT count(*) FROM reporting.write_log WHERE operation_id = $1;
$$;
