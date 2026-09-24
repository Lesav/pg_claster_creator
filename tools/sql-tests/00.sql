-- Control script: run separately AFTER all six nested scripts.
-- The generated execution_no records insertion order, not the expected order.
\pset format unaligned
\pset tuples_only on
SELECT 'rows=' || count(*) || '; expected=6; actual_order=' ||
       coalesce(string_agg(expected_order::text, ',' ORDER BY execution_no), '')
FROM public.pgcc_sql_order_probe;

SELECT CASE WHEN count(*) = 6
    AND array_agg(expected_order ORDER BY execution_no) = ARRAY[1,2,3,4,5,6]
    AND array_agg(source_path ORDER BY execution_no) = ARRAY[
        '00_dir/10_dir/00.sql', '00_dir/11_dir/00.sql',
        '01_dir/10_dir/00.sql', '01_dir/11_dir/00.sql',
        '02_dir/10_dir/00.sql', '02_dir/11_dir/00.sql'
    ] THEN 'PASS' ELSE 'FAIL' END AS result
FROM public.pgcc_sql_order_probe;
