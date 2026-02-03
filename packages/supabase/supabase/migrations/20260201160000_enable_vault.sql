-- Enable Supabase Vault extension for encrypted secrets in Postgres (Cloud only).
-- Secrets are used in functions, triggers, webhooks via vault.decrypted_secrets.
-- Vault is not available in local Supabase; this block runs only when the extension exists.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vault') THEN
    CREATE EXTENSION IF NOT EXISTS vault WITH SCHEMA vault;
    REVOKE ALL ON vault.decrypted_secrets FROM PUBLIC;
    GRANT SELECT ON vault.decrypted_secrets TO postgres;
  END IF;
END $$;
