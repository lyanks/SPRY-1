-- Scale: how many payments, how many duplicate events, how late did events arrive.
-- An exact duplicate = the same payment, status, event time and arrival time twice.
SELECT
  count(*)                                                        AS total_events,
  count(DISTINCT invoiceId)                                       AS unique_payments,
  count(*) - count(DISTINCT concat(invoiceId, '|', status, '|', modifiedDate, '|', receivedAt))
                                                                  AS duplicate_events,
  count_if(late_s > 60)                                           AS late_over_60s,
  round(100.0 * count_if(late_s > 60) / count(*), 2)              AS pct_late_over_60s,
  count_if(late_s > 3600)                                         AS late_over_1h,
  round(100.0 * count_if(late_s > 3600) / count(*), 4)            AS pct_late_over_1h
FROM (
  SELECT *, date_diff('second', from_iso8601_timestamp(modifiedDate),
                                from_iso8601_timestamp(receivedAt)) AS late_s
  FROM lab8.payment_events
)
