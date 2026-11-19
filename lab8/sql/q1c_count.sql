SELECT count(*) AS events, count(DISTINCT dt) AS partitions
FROM lab8.payment_events
