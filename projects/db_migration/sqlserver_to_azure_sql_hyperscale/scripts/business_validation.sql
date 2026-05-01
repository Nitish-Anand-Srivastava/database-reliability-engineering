-- Business validation queries for SQL Server -> Azure SQL Hyperscale migration
-- Author: Nitish Anand Srivastava

SET NOCOUNT ON;

-- Replace with domain-specific entities used by the application
-- The purpose is to validate business-level parity, not only technical parity

PRINT 'Business Validation: Daily Sales Totals';
SELECT
    CAST(order_date AS DATE) AS business_date,
    COUNT(*) AS order_count,
    SUM(total_amount) AS gross_sales
FROM dbo.orders
GROUP BY CAST(order_date AS DATE)
ORDER BY business_date DESC;

PRINT 'Business Validation: Top Customers by Revenue';
SELECT TOP 50
    customer_id,
    SUM(total_amount) AS revenue
FROM dbo.orders
GROUP BY customer_id
ORDER BY revenue DESC;

PRINT 'Business Validation: Open Order Backlog';
SELECT
    status,
    COUNT(*) AS orders
FROM dbo.orders
WHERE status IN ('OPEN', 'PENDING', 'BACKORDER')
GROUP BY status
ORDER BY status;
