/* =====================================================================
   Olist project - Stage 1: on-prem SQL Server source
   Creates database olist_src and loads the 3 SQL Server datasets:
     orders, order_items, order_payments
   Requires SQL Server 2017 or later (BULK INSERT ... FORMAT = 'CSV').

   SOURCE FOLDER: C:\Users\ybsvi\Downloads\
     olist_orders_dataset.csv
     olist_order_items_dataset.csv
     olist_order_payments_dataset.csv

   If BULK INSERT fails with "Operating system error 5 (Access is denied)",
   the SQL Server service account can't read your Downloads folder. Either:
     - grant it read access (run in an admin Command Prompt):
         icacls "C:\Users\ybsvi\Downloads" /grant "NT Service\MSSQLSERVER":(OI)(CI)R
       (for a named instance use "NT Service\MSSQL$<InstanceName>"), or
     - copy the 3 files to C:\olist\ and change @path below.
   ===================================================================== */

IF DB_ID('olist_src') IS NULL
    CREATE DATABASE olist_src;
GO
USE olist_src;
GO

/* ---------- 1. Tables ---------- */
DROP TABLE IF EXISTS dbo.order_payments;
DROP TABLE IF EXISTS dbo.order_items;
DROP TABLE IF EXISTS dbo.orders;
GO

CREATE TABLE dbo.orders (
    order_id                       CHAR(32)      NOT NULL,
    customer_id                    CHAR(32)      NOT NULL,
    order_status                   VARCHAR(20)   NOT NULL,
    order_purchase_timestamp       DATETIME2(0)  NOT NULL,
    order_approved_at              DATETIME2(0)  NULL,   -- 160 empty
    order_delivered_carrier_date   DATETIME2(0)  NULL,   -- 1,783 empty
    order_delivered_customer_date  DATETIME2(0)  NULL,   -- 2,965 empty
    order_estimated_delivery_date  DATETIME2(0)  NOT NULL,
    CONSTRAINT pk_orders PRIMARY KEY (order_id)
);

CREATE TABLE dbo.order_items (
    order_id             CHAR(32)       NOT NULL,
    order_item_id        INT            NOT NULL,
    product_id           CHAR(32)       NOT NULL,
    seller_id            CHAR(32)       NOT NULL,
    shipping_limit_date  DATETIME2(0)   NOT NULL,
    price                DECIMAL(10,2)  NOT NULL,
    freight_value        DECIMAL(10,2)  NOT NULL,
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE dbo.order_payments (
    order_id              CHAR(32)       NOT NULL,
    payment_sequential    INT            NOT NULL,
    payment_type          VARCHAR(20)    NOT NULL,
    payment_installments  INT            NOT NULL,
    payment_value         DECIMAL(10,2)  NOT NULL,
    CONSTRAINT pk_order_payments PRIMARY KEY (order_id, payment_sequential)
);
GO

/* ---------- 2. Load the CSV files ----------
   The files use LF line endings, a header row, and some quoted values.
   Empty date fields are loaded as NULL (KEEPNULLS).
   BULK INSERT needs a literal path, so dynamic SQL is used for @path. */
DECLARE @path NVARCHAR(260) = N'C:\Users\ybsvi\Downloads\';
DECLARE @opts NVARCHAR(400) = N' WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'',
      FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'',
      KEEPNULLS, TABLOCK);';
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'BULK INSERT dbo.orders FROM ''' + @path + N'olist_orders_dataset.csv''' + @opts;
EXEC (@sql);

SET @sql = N'BULK INSERT dbo.order_items FROM ''' + @path + N'olist_order_items_dataset.csv''' + @opts;
EXEC (@sql);

SET @sql = N'BULK INSERT dbo.order_payments FROM ''' + @path + N'olist_order_payments_dataset.csv''' + @opts;
EXEC (@sql);
GO

/* ---------- 3. Foreign keys (added after the load) ----------
   Every order_items and order_payments row has a matching order. */
ALTER TABLE dbo.order_items
    ADD CONSTRAINT fk_items_orders FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
ALTER TABLE dbo.order_payments
    ADD CONSTRAINT fk_payments_orders FOREIGN KEY (order_id) REFERENCES dbo.orders (order_id);
GO

/* ---------- 4. Check the load ----------
   Expected: orders 99,441 | order_items 112,650 | order_payments 103,886 */
SELECT 'orders' AS table_name, COUNT(*) AS row_count, 99441 AS expected FROM dbo.orders
UNION ALL SELECT 'order_items', COUNT(*), 112650 FROM dbo.order_items
UNION ALL SELECT 'order_payments', COUNT(*), 103886 FROM dbo.order_payments;

/* Expected NULL counts: 160 | 1,783 | 2,965 */
SELECT
    SUM(CASE WHEN order_approved_at             IS NULL THEN 1 ELSE 0 END) AS null_approved,
    SUM(CASE WHEN order_delivered_carrier_date  IS NULL THEN 1 ELSE 0 END) AS null_carrier,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_delivered
FROM dbo.orders;

/* Expected status counts: delivered 96,478 | shipped 1,107 | canceled 625 | unavailable 609
   | invoiced 314 | processing 301 | created 5 | approved 2 */
SELECT order_status, COUNT(*) AS orders
FROM dbo.orders
GROUP BY order_status
ORDER BY orders DESC;
GO
