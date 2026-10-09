-- Add is_public column to buckets table for public/image-hosting mode
ALTER TABLE buckets ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0;
