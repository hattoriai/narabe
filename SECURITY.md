# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/narabe/security/advisories/new).

Say what an attacker can do, and how: the component, the event, the
move or the query, and the steps or the payload. We answer within a week,
agree on a fix and a date, and credit you in the advisory unless you ask
us not to.

## Supported versions

Security fixes are made to the latest release. Narabe is before 1.0, so
a fix is not backported to an earlier minor version.

## What is in scope

A list's hook sends events to your LiveView (`on_move`, `on_expand`,
`on_rename`, `on_select`, and `narabe:place` with Issho); any person can
craft them, with any ids. The labels of items may come from anyone who
writes to your database. A problem is in scope when such an event or
label can:

- make `Narabe.Ecto.move/4` change a row outside the queryable it was
  given, put a row under a parent outside it, or break the rules it was
  given (`Narabe.Rules`: into itself, too deep, a kind a parent does not
  accept);
- make `Narabe.Move.parse/2` accept ids that are not of the schema's
  primary key type;
- crash the LiveView or make the server do unbounded work: a move of very
  many ids, a deep tree, a long position key;
- run script in the page through what a list shows: a label, a lock's
  name, a person's name or color (`Narabe.Issho`);
- with `Narabe.Issho`, put a place or a lock in a room that the person
  may not write to, or a lock on items of another document.

Who may move what is decided by the app: the queryable given to
`Narabe.Ecto` (one board's cards, one user's tasks) is its check. What
the browser refuses is a convenience, not a check: the server's rules
are the check (see the Rules guide).
