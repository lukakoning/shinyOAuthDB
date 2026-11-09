CREATE DATABASE oauth_fixture;
CREATE TABLE oauth_fixture.alice_rows (id INT, label TEXT);
INSERT INTO oauth_fixture.alice_rows VALUES (1, 'alice-visible');
CREATE TABLE oauth_fixture.bob_rows (id INT, label TEXT);
INSERT INTO oauth_fixture.bob_rows VALUES (2, 'bob-visible');
CREATE USER 'alice'@'%' IDENTIFIED WITH authentication_jwt REQUIRE SSL;
CREATE USER 'bob'@'%' IDENTIFIED WITH authentication_jwt REQUIRE SSL;
GRANT SELECT ON oauth_fixture.alice_rows TO 'alice'@'%';
GRANT SELECT ON oauth_fixture.bob_rows TO 'bob'@'%';
