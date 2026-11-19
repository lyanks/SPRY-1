-- Payments per hour of the day (UTC, by creation time).
SELECT hour(from_iso8601_timestamp(createdDate)) AS hour_utc, count(*) AS payments
FROM lab8.${TABLE}
GROUP BY 1
ORDER BY 1
