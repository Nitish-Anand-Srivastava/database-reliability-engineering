-- Business validation queries for PostgreSQL migration
-- Author: Nitish Anand Srivastava

SELECT date_trunc('day', order_date) AS business_date,
       COUNT(*) AS order_count,
       SUM(total_amount) AS gross_sales
FROM public.orders
GROUP BY 1
ORDER BY 1 DESC;

SELECT customer_id,
       SUM(total_amount) AS revenue
FROM public.orders
GROUP BY customer_id
ORDER BY revenue DESC
LIMIT 50;
