-- The view must hold exactly one row per payment.
SELECT count(*) AS rows_in_view, count(DISTINCT invoiceId) AS unique_payments,
       count_if(status = 'success') AS success, count_if(status = 'failure') AS failure,
       count_if(status NOT IN ('success', 'failure')) AS unfinished
FROM lab8.payments
