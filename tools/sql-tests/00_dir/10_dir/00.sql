-- First script: create the probe and record the first execution.
CREATE TABLE public.pgcc_sql_order_probe (
    execution_no bigserial PRIMARY KEY,
    expected_order integer NOT NULL,
    source_path text NOT NULL
);
INSERT INTO public.pgcc_sql_order_probe (expected_order, source_path)
VALUES (1, '00_dir/10_dir/00.sql');
