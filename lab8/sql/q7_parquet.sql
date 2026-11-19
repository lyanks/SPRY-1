-- The deduplicated payments as Parquet, partitioned by day, under curated/.
CREATE TABLE lab8.payments_parquet
WITH (
  format = 'PARQUET',
  parquet_compression = 'SNAPPY',
  external_location = 's3://${BUCKET}/curated/',
  partitioned_by = ARRAY['dt']
) AS
SELECT invoiceId, status, failureReason, amount, finalAmount, ccy, reference,
       createdDate, modifiedDate, receivedAt, merchantId, merchantName, mcc,
       customerId, paymentMethod, device, dt
FROM lab8.payments
