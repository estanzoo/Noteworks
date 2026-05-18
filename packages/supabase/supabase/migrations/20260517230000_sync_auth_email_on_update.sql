-- Keep `public.users.email` in lockstep with `auth.users.email` whenever a
-- user's auth identity is updated (e.g. after the change-email OTP flow
-- in the Profile → Security Settings popup completes successfully).
--
-- Without this trigger the Profile screen would still show the old
-- email after the new address was confirmed, because `get-user-profile`
-- reads from `public.users`, while the OTP confirmation only rotates
-- `auth.users`.

CREATE OR REPLACE FUNCTION public.handle_auth_user_email_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    UPDATE public.users
       SET email = NEW.email,
           updated_at = now()
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_update ON auth.users;

CREATE TRIGGER on_auth_user_email_update
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auth_user_email_update();
