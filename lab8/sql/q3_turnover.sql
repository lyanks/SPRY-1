-- Turnover of successful payments by merchant and currency, in whole currency units.
SELECT merchantId, merchantName,
       CASE ccy WHEN 980 THEN 'UAH' WHEN 840 THEN 'USD' WHEN 978 THEN 'EUR' ELSE cast(ccy AS varchar) END AS currency,
       count(*)                       AS payments,
       round(sum(finalAmount) / 100.0, 2) AS turnover
FROM lab8.${TABLE}
WHERE status = 'success'
GROUP BY merchantId, merchantName, ccy
ORDER BY currency, turnover DESC
