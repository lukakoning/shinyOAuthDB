CREATE DATABASE reporting;
CREATE TABLE reporting.rows (id UInt32, owner_name String, marker String) ENGINE = MergeTree ORDER BY id;
INSERT INTO reporting.rows VALUES (1, 'alice', 'alice-visible-1'), (2, 'alice', 'alice-visible-2'),
    (3, 'bob', 'bob-visible-1'), (4, 'bob', 'bob-visible-2');
CREATE TABLE reporting.writes (operation String) ENGINE = MergeTree ORDER BY operation;
CREATE USER alice IDENTIFIED WITH no_password;
CREATE USER bob IDENTIFIED WITH no_password;
GRANT SELECT ON reporting.rows TO alice, bob;
GRANT SELECT, INSERT ON reporting.writes TO alice;
CREATE ROW POLICY own_rows ON reporting.rows FOR SELECT USING owner_name = currentUser() TO alice, bob;
