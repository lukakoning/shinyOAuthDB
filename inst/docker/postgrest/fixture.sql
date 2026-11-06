CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'demo-authenticator-password';
CREATE ROLE alice NOLOGIN;
CREATE ROLE bob NOLOGIN;
GRANT alice, bob TO authenticator;
CREATE TABLE public.visible_rows (row_id integer PRIMARY KEY, owner_name text, marker text);
INSERT INTO public.visible_rows VALUES
  (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),
  (3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2');
ALTER TABLE public.visible_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON public.visible_rows FOR SELECT TO alice, bob USING (owner_name = current_user);
GRANT USAGE ON SCHEMA public TO alice, bob;
GRANT SELECT ON public.visible_rows TO alice, bob;
