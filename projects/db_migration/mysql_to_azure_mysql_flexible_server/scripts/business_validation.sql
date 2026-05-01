-- Business validation queries for MySQL migration
-- Author: Nitish Anand Srivastava

SELECT DATE(order_date) AS business_date, COUNT(*) AS order_count, SUM(total_amount) AS gross_sales
FROM orders
GROUP BY DATE(order_date)
ORDER BY business_date DESC;

SELECT customer_id, SUM(total_amount) AS revenue
FROM orders
GROUP BY customer_id
ORDER BY revenue DESC
LIMIT 50;
