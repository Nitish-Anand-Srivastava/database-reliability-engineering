CREATE TABLE orders (
 id int,
 created_at date
) PARTITION BY RANGE (created_at);