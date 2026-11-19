SELECT count(*)                       AS events_in_s3,
       count(DISTINCT invoiceId)      AS unique_payments,
       min(receivedAt)                AS first_received,
       max(receivedAt)                AS last_received
FROM lab8.stream_events
