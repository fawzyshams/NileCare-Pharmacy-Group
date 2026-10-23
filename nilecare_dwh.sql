CREATE SCHEMA dwh;
GO
CREATE TABLE dwh.dim_date (
    date_key INT PRIMARY KEY,
    full_date DATE NOT NULL,
    day_number INT,
    day_name NVARCHAR(20),
    week_number INT,
    month_number INT,
    month_name NVARCHAR(20),
    quarter_number INT,
    year_number INT,
    is_weekend BIT,
    is_ramadan BIT,
    is_eid BIT
);
WITH DateSeries AS (
    SELECT CAST('2023-01-01' AS DATE) AS full_date
    UNION ALL
    SELECT DATEADD(DAY, 1, full_date)
    FROM DateSeries
    WHERE full_date < '2024-12-31'
)
INSERT INTO dwh.dim_date (
    date_key, full_date, day_number, day_name, week_number,
    month_number, month_name, quarter_number, year_number,
    is_weekend, is_ramadan, is_eid
)
SELECT
    CONVERT(INT, FORMAT(full_date, 'yyyyMMdd'))                AS date_key,
    full_date,
    DAY(full_date)                                             AS day_number,
    DATENAME(WEEKDAY, full_date)                                AS day_name,
    DATEPART(WEEK, full_date)                                   AS week_number,
    MONTH(full_date)                                            AS month_number,
    DATENAME(MONTH, full_date)                                  AS month_name,
    DATEPART(QUARTER, full_date)                                AS quarter_number,
    YEAR(full_date)                                             AS year_number,
    CASE WHEN DATENAME(WEEKDAY, full_date) IN ('Friday','Saturday') THEN 1 ELSE 0 END AS is_weekend,
    CASE WHEN full_date BETWEEN '2023-03-23' AND '2023-04-20' THEN 1
         WHEN full_date BETWEEN '2024-03-11' AND '2024-04-08' THEN 1
         ELSE 0 END AS is_ramadan,
    CASE WHEN full_date BETWEEN '2023-04-21' AND '2023-04-23' THEN 1
         WHEN full_date BETWEEN '2024-04-09' AND '2024-04-11' THEN 1
         WHEN full_date BETWEEN '2023-06-27' AND '2023-06-30' THEN 1
         WHEN full_date BETWEEN '2024-06-15' AND '2024-06-18' THEN 1
         ELSE 0 END AS is_eid
FROM DateSeries
OPTION (MAXRECURSION 0);

SELECT COUNT(*) FROM dwh.dim_date;

CREATE TABLE dwh.dim_branch (
    branch_key INT IDENTITY(1,1) PRIMARY KEY,
    branch_id NVARCHAR(50) NOT NULL,
    branch_name NVARCHAR(200),
    city NVARCHAR(100),
    region NVARCHAR(100)
);

INSERT INTO dwh.dim_branch (branch_id, branch_name, city, region)
SELECT DISTINCT
    branch_id,
    branch_name,
    city,
    region
FROM staging.stg_pos
WHERE branch_id IS NOT NULL;

SELECT COUNT(*) FROM dwh.dim_branch;
SELECT * FROM dwh.dim_branch;

CREATE TABLE dwh.dim_product (
    product_key INT IDENTITY(1,1) PRIMARY KEY,
    product_id NVARCHAR(50) NOT NULL,
    product_name NVARCHAR(200),
    category NVARCHAR(100),
    pack_unit NVARCHAR(50),
    prescription_required NVARCHAR(10),
    storage_condition NVARCHAR(100),
    warehouse_zone NVARCHAR(100),
    shelf_life_months INT,
    supplier_key INT NULL
);

INSERT INTO dwh.dim_product (
    product_id, product_name, category, pack_unit,
    prescription_required, storage_condition, warehouse_zone, shelf_life_months
)
SELECT
    product_id,
    MAX(product_name)          AS product_name,
    MAX(category)               AS category,
    MAX(pack_unit)               AS pack_unit,
    MAX(prescription_required)   AS prescription_required,
    MAX(storage_condition)       AS storage_condition,
    MAX(warehouse_zone)          AS warehouse_zone,
    MAX(CAST(shelf_life_months AS INT)) AS shelf_life_months
FROM staging.stg_erp
WHERE product_id IS NOT NULL
GROUP BY product_id;

SELECT COUNT(*) FROM dwh.dim_product;

CREATE TABLE dwh.dim_supplier (
    supplier_key INT IDENTITY(1,1) PRIMARY KEY,
    supplier_id NVARCHAR(50) NOT NULL,
    supplier_name NVARCHAR(200),
    supplier_country NVARCHAR(100),
    supplier_type NVARCHAR(50)
);

INSERT INTO dwh.dim_supplier (supplier_id, supplier_name, supplier_country, supplier_type)
SELECT
    supplier_id,
    MAX(supplier_name)     AS supplier_name,
    MAX(supplier_country)  AS supplier_country,
    MAX(supplier_type)     AS supplier_type
FROM staging.stg_erp
WHERE supplier_id IS NOT NULL
GROUP BY supplier_id;

SELECT COUNT(*) FROM dwh.dim_supplier;

;WITH ProductSupplier AS (
    SELECT
        product_id,
        supplier_id,
        COUNT(*) AS cnt,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY COUNT(*) DESC) AS rn
    FROM staging.stg_erp
    WHERE product_id IS NOT NULL AND supplier_id IS NOT NULL
    GROUP BY product_id, supplier_id
)


UPDATE dp
SET dp.supplier_key = ds.supplier_key
FROM dwh.dim_product dp
JOIN ProductSupplier ps ON ps.product_id = dp.product_id AND ps.rn = 1
JOIN dwh.dim_supplier ds ON ds.supplier_id = ps.supplier_id;

SELECT COUNT(*) FROM dwh.dim_product WHERE supplier_key IS NULL;

CREATE TABLE dwh.dim_campaign (
    campaign_key INT IDENTITY(1,1) PRIMARY KEY,
    campaign_id NVARCHAR(50) NOT NULL,
    campaign_name NVARCHAR(200),
    channel NVARCHAR(100),
    target_category NVARCHAR(100),
    target_region NVARCHAR(100),
    discount_percentage_offered INT
);

INSERT INTO dwh.dim_campaign (
    campaign_id, campaign_name, channel, target_category, target_region, discount_percentage_offered
)
SELECT
    campaign_id,
    MAX(campaign_name)      AS campaign_name,
    MAX(channel)             AS channel,
    MAX(target_category)     AS target_category,
    MAX(target_region)       AS target_region,
    MAX(CAST(discount_percentage_offered AS INT)) AS discount_percentage_offered
FROM staging.stg_marketing
WHERE campaign_id IS NOT NULL
GROUP BY campaign_id;

INSERT INTO dwh.dim_campaign (campaign_id, campaign_name, channel, target_category, target_region, discount_percentage_offered)
VALUES ('NONE', 'No Campaign / Organic Sale', 'N/A', 'N/A', 'N/A', 0);

SELECT COUNT(*) FROM dwh.dim_campaign;

CREATE TABLE dwh.dim_customer (
    customer_key INT IDENTITY(1,1) PRIMARY KEY,
    customer_id NVARCHAR(50) NOT NULL,
    full_name NVARCHAR(200),
    gender NVARCHAR(10),
    age INT,
    date_of_birth DATE,
    city NVARCHAR(100),
    phone_number NVARCHAR(20),
    home_branch_id NVARCHAR(50),
    registration_date DATE,
    referral_source NVARCHAR(100),
    loyalty_tier NVARCHAR(20),
    loyalty_points INT,
    total_visits INT,
    total_lifetime_spend_egp DECIMAL(12,2),
    avg_basket_value_egp DECIMAL(10,2),
    first_purchase_date DATE,
    last_purchase_date DATE,
    preferred_branch_id NVARCHAR(50),
    preferred_payment_method NVARCHAR(50),
    favorite_category NVARCHAR(100),
    has_prescription_history NVARCHAR(10),
    chronic_disease_flag NVARCHAR(10),
    membership_status NVARCHAR(20),
    marketing_opt_in NVARCHAR(10),
    preferred_contact_channel NVARCHAR(50)


    INSERT INTO dwh.dim_customer (
    customer_id, full_name, gender, age, date_of_birth, city, phone_number,
    home_branch_id, registration_date, referral_source, loyalty_tier, loyalty_points,
    total_visits, total_lifetime_spend_egp, avg_basket_value_egp,
    first_purchase_date, last_purchase_date, preferred_branch_id, preferred_payment_method,
    favorite_category, has_prescription_history, chronic_disease_flag,
    membership_status, marketing_opt_in, preferred_contact_channel
)
SELECT
    customer_id,
    full_name,
    gender,
    TRY_CAST(age AS INT),
    TRY_CAST(date_of_birth AS DATE),
    city,
    phone_number,
    home_branch_id,
    TRY_CAST(registration_date AS DATE),
    referral_source,
    loyalty_tier,
    TRY_CAST(loyalty_points AS INT),
    TRY_CAST(total_visits AS INT),
    TRY_CAST(total_lifetime_spend_egp AS DECIMAL(12,2)),
    TRY_CAST(avg_basket_value_egp AS DECIMAL(10,2)),
    TRY_CAST(NULLIF(first_purchase_date, '') AS DATE),
    TRY_CAST(NULLIF(last_purchase_date, '') AS DATE),
    preferred_branch_id,
    preferred_payment_method,
    favorite_category,
    has_prescription_history,
    chronic_disease_flag,
    membership_status,
    marketing_opt_in,
    preferred_contact_channel
FROM staging.stg_crm;

INSERT INTO dwh.dim_customer (customer_id, full_name, membership_status)
VALUES ('WALKIN', 'Walk-in / Unregistered Customer', 'N/A');

SELECT COUNT(*) FROM dwh.dim_customer;

CREATE TABLE dwh.fact_sales (
    sales_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_id NVARCHAR(50),
    line_item_id NVARCHAR(50),
    date_key INT NOT NULL,
    branch_key INT NOT NULL,
    product_key INT NOT NULL,
    customer_key INT NOT NULL,
    campaign_key INT NOT NULL,
    cashier_id NVARCHAR(50),
    payment_method NVARCHAR(50),
    quantity INT,
    unit_price_egp DECIMAL(10,2),
    discount_percentage INT,
    line_total_egp DECIMAL(12,2),
    is_promotion NVARCHAR(10),
    prescription_required NVARCHAR(10),
    FOREIGN KEY (date_key) REFERENCES dwh.dim_date(date_key),
    FOREIGN KEY (branch_key) REFERENCES dwh.dim_branch(branch_key),
    FOREIGN KEY (product_key) REFERENCES dwh.dim_product(product_key),
    FOREIGN KEY (customer_key) REFERENCES dwh.dim_customer(customer_key),
    FOREIGN KEY (campaign_key) REFERENCES dwh.dim_campaign(campaign_key)
);

INSERT INTO dwh.fact_sales (
    transaction_id, line_item_id, date_key, branch_key, product_key,
    customer_key, campaign_key, cashier_id, payment_method,
    quantity, unit_price_egp, discount_percentage, line_total_egp,
    is_promotion, prescription_required
)
SELECT
    p.transaction_id,
    p.line_item_id,
    CONVERT(INT, FORMAT(TRY_CAST(p.[date] AS DATE), 'yyyyMMdd'))   AS date_key,
    db.branch_key,
    dp.product_key,
    ISNULL(dc.customer_key, dc_walkin.customer_key)                AS customer_key,
    ISNULL(dcamp.campaign_key, dcamp_none.campaign_key)             AS campaign_key,
    p.cashier_id,
    p.payment_method,
    TRY_CAST(p.quantity AS INT),
    TRY_CAST(p.unit_price_egp AS DECIMAL(10,2)),
    TRY_CAST(p.discount_percentage AS INT),
    TRY_CAST(p.line_total_egp AS DECIMAL(12,2)),
    p.is_promotion,
    p.prescription_required
FROM staging.stg_pos p
JOIN dwh.dim_branch db   ON db.branch_id = p.branch_id
JOIN dwh.dim_product dp  ON dp.product_id = p.product_id
LEFT JOIN dwh.dim_customer dc ON dc.customer_id = NULLIF(p.customer_id, '')
LEFT JOIN dwh.dim_campaign dcamp ON dcamp.campaign_id = NULLIF(p.campaign_id, '')
CROSS JOIN (SELECT customer_key FROM dwh.dim_customer WHERE customer_id = 'WALKIN') dc_walkin
CROSS JOIN (SELECT campaign_key FROM dwh.dim_campaign WHERE campaign_id = 'NONE') dcamp_none;

SELECT COUNT(*) FROM dwh.fact_sales;

CREATE TABLE dwh.fact_procurement (
    procurement_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    po_id NVARCHAR(50),
    order_date_key INT NOT NULL,
    expected_delivery_date DATE,
    received_date DATE,
    delivery_status NVARCHAR(20),
    lead_time_days INT,
    branch_key INT NOT NULL,
    product_key INT NOT NULL,
    supplier_key INT NOT NULL,
    quantity_ordered INT,
    quantity_received INT NULL,
    unit_cost_egp DECIMAL(10,2),
    total_cost_egp DECIMAL(14,2),
    batch_number NVARCHAR(50),
    manufacture_date DATE,
    expiry_date DATE,
    reorder_level INT,
    stock_before_delivery DECIMAL(10,1),
    stock_after_delivery DECIMAL(10,1),
    stockout_risk NVARCHAR(10),
    FOREIGN KEY (order_date_key) REFERENCES dwh.dim_date(date_key),
    FOREIGN KEY (branch_key) REFERENCES dwh.dim_branch(branch_key),
    FOREIGN KEY (product_key) REFERENCES dwh.dim_product(product_key),
    FOREIGN KEY (supplier_key) REFERENCES dwh.dim_supplier(supplier_key)
);

INSERT INTO dwh.fact_procurement (
    po_id, order_date_key, expected_delivery_date, received_date,
    delivery_status, lead_time_days, branch_key, product_key, supplier_key,
    quantity_ordered, quantity_received, unit_cost_egp, total_cost_egp,
    batch_number, manufacture_date, expiry_date, reorder_level,
    stock_before_delivery, stock_after_delivery, stockout_risk
)
SELECT
    e.po_id,
    CONVERT(INT, FORMAT(TRY_CAST(e.order_date AS DATE), 'yyyyMMdd'))  AS order_date_key,
    TRY_CAST(e.expected_delivery_date AS DATE),
    TRY_CAST(NULLIF(e.received_date, '') AS DATE),
    e.delivery_status,
    TRY_CAST(e.lead_time_days AS INT),
    db.branch_key,
    dp.product_key,
    ds.supplier_key,
    TRY_CAST(e.quantity_ordered AS INT),
    TRY_CAST(NULLIF(e.quantity_received, '') AS INT),
    TRY_CAST(e.unit_cost_egp AS DECIMAL(10,2)),
    TRY_CAST(e.total_cost_egp AS DECIMAL(14,2)),
    e.batch_number,
    TRY_CAST(e.manufacture_date AS DATE),
    TRY_CAST(e.expiry_date AS DATE),


    SELECT COUNT(*) FROM dwh.fact_procurement;

   CREATE TABLE dwh.fact_marketing (
    marketing_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    record_id NVARCHAR(50),
    date_key INT NOT NULL,
    campaign_key INT NOT NULL,
    impressions INT,
    clicks INT,
    ctr_percent DECIMAL(6,2),
    spend_egp DECIMAL(12,2),
    conversions INT,
    revenue_egp DECIMAL(12,2),
    cpc_egp DECIMAL(10,2),
    cpa_egp DECIMAL(10,2),
    roas DECIMAL(10,2),
    FOREIGN KEY (date_key) REFERENCES dwh.dim_date(date_key),
    FOREIGN KEY (campaign_key) REFERENCES dwh.dim_campaign(campaign_key)
);

INSERT INTO dwh.fact_marketing (
    record_id, date_key, campaign_key, impressions, clicks, ctr_percent,
    spend_egp, conversions, revenue_egp, cpc_egp, cpa_egp, roas
)
SELECT
    m.record_id,
    CONVERT(INT, FORMAT(TRY_CAST(m.[date] AS DATE), 'yyyyMMdd'))  AS date_key,
    dcamp.campaign_key,
    TRY_CAST(m.impressions AS INT),
    TRY_CAST(m.clicks AS INT),
    TRY_CAST(m.ctr_percent AS DECIMAL(6,2)),
    TRY_CAST(m.spend_egp AS DECIMAL(12,2)),
    TRY_CAST(m.conversions AS INT),
    TRY_CAST(m.revenue_egp AS DECIMAL(12,2)),
    TRY_CAST(m.cpc_egp AS DECIMAL(10,2)),
    TRY_CAST(m.cpa_egp AS DECIMAL(10,2)),
    TRY_CAST(m.roas AS DECIMAL(10,2))
FROM staging.stg_marketing m
JOIN dwh.dim_campaign dcamp ON dcamp.campaign_id = m.campaign_id;


SELECT COUNT(*) FROM dwh.fact_marketing;

















);









































