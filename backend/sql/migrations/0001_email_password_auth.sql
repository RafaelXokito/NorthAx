-- 0001 — switch users from Sign in with Apple to email/password.
--
-- Brings an EXISTING database (created from a pre-auth-change schema.sql) forward
-- to the current users shape. Fully idempotent: safe to re-run, and a no-op on a
-- fresh DB that schema.sql already built with the new columns.
--
-- Assumes a single-athlete (dev) deployment: any legacy row with a NULL email is
-- backfilled to the dev login. A multi-user deployment would need per-row emails.

ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- Legacy rows predate email/password — backfill so the NOT NULLs below can apply.
UPDATE users SET email = 'dev@northax.app' WHERE email IS NULL;
-- Placeholder credential for any pre-migration row: scrypt hash of 'northax-dev'
-- (the documented dev password). Real accounts set their own on register.
UPDATE users
   SET password_hash = 'scrypt$16384$8$1$5A1txmWWS0BKTYHHUk0Z1g==$fKTmYlEK1XawAfVSMtVG7J6t640AzWwX0Ug1MWIBbUc='
 WHERE password_hash IS NULL;

ALTER TABLE users ALTER COLUMN email SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_email_key') THEN
    ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);
  END IF;
END $$;

ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;

ALTER TABLE users DROP COLUMN IF EXISTS apple_id;
