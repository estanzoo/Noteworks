-- Create notes-pdfs bucket for PDF attachments (one per note, owner-only, 50 MB max)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('notes-pdfs', 'notes-pdfs', false, 52428800, ARRAY['application/pdf']);

-- Owner can upload (insert) to their own folder. Path: {user_id}/{note_id}.pdf
CREATE POLICY "Owner can upload PDF"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'notes-pdfs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner can read (download) their own files
CREATE POLICY "Owner can read own PDFs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'notes-pdfs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner can overwrite (update) their own files
CREATE POLICY "Owner can update own PDFs"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'notes-pdfs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner can delete their own files
CREATE POLICY "Owner can delete own PDFs"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'notes-pdfs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
