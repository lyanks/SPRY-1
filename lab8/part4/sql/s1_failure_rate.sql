-- The question of Part 3, answered over the data that came through Kinesis and Firehose.
WITH dedup AS (
  SELECT DISTINCT invoiceId, status, paymentMethod, modifiedDate
  FROM lab8.stream_events
  WHERE status IN ('success', 'failure')
)
SELECT paymentMethod,
       count(*)                                                       AS payments,
       count_if(status = 'failure')                                   AS failed,
       round(100.0 * count_if(status = 'failure') / count(*), 1)      AS failure_pct
FROM dedup
GROUP BY paymentMethod
ORDER BY failure_pct DESC
