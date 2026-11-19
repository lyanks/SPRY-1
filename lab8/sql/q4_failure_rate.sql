-- Share of failed payments per payment method and device, highest first.
SELECT paymentMethod, device,
       count(*)                                  AS payments,
       count_if(status = 'failure')              AS failed,
       round(100.0 * count_if(status = 'failure') / count(*), 2) AS failure_pct
FROM lab8.${TABLE}
GROUP BY paymentMethod, device
ORDER BY failure_pct DESC
