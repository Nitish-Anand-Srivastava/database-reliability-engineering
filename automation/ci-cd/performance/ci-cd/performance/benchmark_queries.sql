SELECT region, SUM(revenue)
FROM daily_revenue
GROUP BY region;

SELECT *
FROM orders
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '7 days';
