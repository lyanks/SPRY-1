-- Events that arrived more than 60 seconds after they happened (receivedAt - modifiedDate).
SELECT count(*) AS events,
       count_if(late_s > 60) AS late_over_60s,
       round(100.0 * count_if(late_s > 60) / count(*), 2) AS pct_late
FROM (
  SELECT date_diff('second', from_iso8601_timestamp(modifiedDate),
                             from_iso8601_timestamp(receivedAt)) AS late_s
  FROM lab8.payment_events
)
