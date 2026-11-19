-- One row per payment: the exact duplicates are removed first (DISTINCT), then
-- row_number() keeps the event with the latest EVENT time (modifiedDate).
-- Ties (two statuses in the same second) go to the later stage of the payment.
CREATE OR REPLACE VIEW lab8.payments AS
WITH uniq AS (
  SELECT DISTINCT
    invoiceId, status, failureReason, amount, finalAmount, ccy, reference,
    createdDate, modifiedDate, receivedAt, merchantId, merchantName, mcc,
    customerId, paymentMethod, device, dt
  FROM lab8.payment_events
),
ranked AS (
  SELECT *,
    row_number() OVER (
      PARTITION BY invoiceId
      ORDER BY modifiedDate DESC,
               CASE status WHEN 'success' THEN 3 WHEN 'failure' THEN 3
                           WHEN 'processing' THEN 2 ELSE 1 END DESC,
               receivedAt DESC
    ) AS rn
  FROM uniq
)
SELECT invoiceId, status, failureReason, amount, finalAmount, ccy, reference,
       createdDate, modifiedDate, receivedAt, merchantId, merchantName, mcc,
       customerId, paymentMethod, device, dt
FROM ranked
WHERE rn = 1
