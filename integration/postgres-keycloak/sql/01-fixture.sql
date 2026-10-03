\set ON_ERROR_STOP on
ALTER ROLE postgres PASSWORD 'fixture-superuser-password';
CREATE ROLE fixture_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE alice LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE bob LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE DATABASE oauthdb_fixture OWNER fixture_owner;
REVOKE ALL ON DATABASE oauthdb_fixture FROM PUBLIC;
GRANT CONNECT ON DATABASE oauthdb_fixture TO alice, bob;
\connect oauthdb_fixture
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO alice, bob;
SET ROLE fixture_owner;
CREATE TABLE public.visible_rows (
  row_id integer PRIMARY KEY,
  owner_name text NOT NULL CHECK (owner_name IN ('alice', 'bob')),
  marker text NOT NULL
);
INSERT INTO public.visible_rows VALUES
  (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),
  (3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2');
ALTER TABLE public.visible_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visible_rows FORCE ROW LEVEL SECURITY;
CREATE POLICY visible_to_owner ON public.visible_rows FOR SELECT TO alice, bob
  USING (owner_name = current_user);
CREATE TABLE public.alice_only (marker text NOT NULL);
CREATE TABLE public.bob_only (marker text NOT NULL);
INSERT INTO public.alice_only VALUES ('alice-grant-only');
INSERT INTO public.bob_only VALUES ('bob-grant-only');
GRANT SELECT ON public.visible_rows TO alice, bob;
GRANT SELECT ON public.alice_only TO alice;
GRANT SELECT ON public.bob_only TO bob;
RESET ROLE;
