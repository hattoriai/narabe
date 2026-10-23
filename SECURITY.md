# Security

## Reporting a vulnnarabelity

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnnarabelity](https://github.com/hattoriai/narabe/security/advisories/new).

Say what an attacker can do, and how: the picker, the option, the rule or
the event, and the steps or the payload. We answer within a week, agree
on a fix and a date, and credit you in the advisory unless you ask us
not to.

## Supported versions

Security fixes are made to the latest release. Narabe is before 1.0, so
a fix is not backported to an earlier minor version.

## What is in scope

A picker's values reach your server as form params, and its hook sends
events to your LiveView (`narabe:search`); any person can craft both. The
labels of options may come from anyone who writes to your database. A
problem is in scope when such a value, event or label can:

- pass `Narabe.Changeset.validate_choice/4` although it breaks the rules
  given to it (a value that is not an option, too many values, a new
  value that the pattern refuses);
- crash the LiveView or make the server do unbounded work: a search
  query, a page, or a list of values that is too large;
- run script in the page through what a picker shows: a label, a hint, a
  disabled option's reason, a color, an avatar's URL;
- make `Narabe.Live` run a search of another picker than the one named,
  or a function that is not a picker's `search`.

What a person may choose is decided by the app: the options it gives and
the rules a changeset checks are the app's job, and so is what a search
returns to whom. What the browser refuses is a convenience, not a check:
the server's rules are the check (see the Rules guide).
