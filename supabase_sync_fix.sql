-- ============================================================
-- POS Offline Sync - Schema + RLS fix (idempotent, v2)
-- Run this in Supabase Dashboard > SQL Editor
-- Applies to project: jefvgezlbospjzwiqynx
-- Safe to run multiple times.
-- ============================================================

-- 1) Add the sync columns missing on the remote tables.
--    `status` is the soft-delete marker used by the POS (soft delete =
--    status = 'Deleted'), so it MUST exist before upsert works.
--    `created_at` is part of the local payload contract.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS status text DEFAULT 'Active';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS created_at timestamptz;

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS status text DEFAULT 'Active';
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS created_at timestamptz;

ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS created_at timestamptz;

ALTER TABLE public.invoice_items ADD COLUMN IF NOT EXISTS created_at timestamptz;

-- 2) Table grants so anon/publishable key can read+write (PostgREST hides
--    tables from the anon schema cache when these grants are missing, which
--    shows up as 404 for every table with the publishable key).
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.products TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.customers TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.invoices TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.invoice_items TO anon, authenticated;

-- 3) RLS policies so the publishable/anon key can upsert (insert + update).
--    We deliberately do NOT grant DELETE - the sync protocol never deletes.
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- products
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='products' AND policyname='sync_products_select') THEN
    CREATE POLICY sync_products_select ON public.products FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='products' AND policyname='sync_products_insert') THEN
    CREATE POLICY sync_products_insert ON public.products FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='products' AND policyname='sync_products_update') THEN
    CREATE POLICY sync_products_update ON public.products FOR UPDATE USING (true) WITH CHECK (true);
  END IF;

  -- customers
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='customers' AND policyname='sync_customers_select') THEN
    CREATE POLICY sync_customers_select ON public.customers FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='customers' AND policyname='sync_customers_insert') THEN
    CREATE POLICY sync_customers_insert ON public.customers FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='customers' AND policyname='sync_customers_update') THEN
    CREATE POLICY sync_customers_update ON public.customers FOR UPDATE USING (true) WITH CHECK (true);
  END IF;

  -- invoices
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='sync_invoices_select') THEN
    CREATE POLICY sync_invoices_select ON public.invoices FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='sync_invoices_insert') THEN
    CREATE POLICY sync_invoices_insert ON public.invoices FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='sync_invoices_update') THEN
    CREATE POLICY sync_invoices_update ON public.invoices FOR UPDATE USING (true) WITH CHECK (true);
  END IF;

  -- invoice_items
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='sync_invoice_items_select') THEN
    CREATE POLICY sync_invoice_items_select ON public.invoice_items FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='sync_invoice_items_insert') THEN
    CREATE POLICY sync_invoice_items_insert ON public.invoice_items FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='sync_invoice_items_update') THEN
    CREATE POLICY sync_invoice_items_update ON public.invoice_items FOR UPDATE USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 4) The stock RPC must be executable by anon/authenticated so the
--    publishable key can push stock deltas. We resolve the real signature
--    from pg_proc instead of guessing the parameter types.
DO $$
DECLARE
  sig text;
BEGIN
  SELECT p.oid::regprocedure::text INTO sig
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'apply_stock_delta'
  LIMIT 1;

  IF sig IS NULL THEN
    RAISE NOTICE 'apply_stock_delta not found - skipping RPC grant';
  ELSE
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', sig);
  END IF;
END $$;

-- 5) stock_levels is written by apply_stock_delta and read back for stock
--    reporting, so the anon/publishable key needs grants + RLS policies here
--    too (same pattern as products/customers/invoices/invoice_items).
GRANT SELECT, INSERT, UPDATE ON public.stock_levels TO anon, authenticated;

ALTER TABLE public.stock_levels ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_levels' AND policyname='sync_stock_levels_select') THEN
    CREATE POLICY sync_stock_levels_select ON public.stock_levels FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_levels' AND policyname='sync_stock_levels_insert') THEN
    CREATE POLICY sync_stock_levels_insert ON public.stock_levels FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_levels' AND policyname='sync_stock_levels_update') THEN
    CREATE POLICY sync_stock_levels_update ON public.stock_levels FOR UPDATE USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6) stock_movements_log is written by apply_stock_delta and read back for
--    movement history, so the anon/publishable key needs grants + RLS
--    policies here too (same pattern as the other synced tables).
GRANT SELECT, INSERT, UPDATE ON public.stock_movements_log TO anon, authenticated;

ALTER TABLE public.stock_movements_log ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_movements_log' AND policyname='sync_stock_movements_log_select') THEN
    CREATE POLICY sync_stock_movements_log_select ON public.stock_movements_log FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_movements_log' AND policyname='sync_stock_movements_log_insert') THEN
    CREATE POLICY sync_stock_movements_log_insert ON public.stock_movements_log FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='stock_movements_log' AND policyname='sync_stock_movements_log_update') THEN
    CREATE POLICY sync_stock_movements_log_update ON public.stock_movements_log FOR UPDATE USING (true) WITH CHECK (true);
  END IF;
END $$;
