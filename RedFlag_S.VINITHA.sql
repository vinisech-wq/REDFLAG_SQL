-- ===================================================================== 
-- RedFlag — Fraud Detection Submission 
-- Student: S.VINITHA  |  Batch: DATA-SCIENCE (JUNE)
-- ========================================================
USE redflag; 
-- ===================================================================== 
-- PATTERN 1- VELOCITY FRAUD 
-- Detect users who make 30 or more transactions on a single day.
-- ===================================================================== 
SELECT user_id, DATE(txn_time) AS transaction_date,COUNT(*) AS transaction_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY transaction_count DESC;
-- 50 suspects hving 30+ transcations per day returned
-- most transaction of 60 were done by user_id's 14569 and 14556

-- ===================================================================== 
-- PATTERN 2- Round-Amount Clustering
-- Finds users who has made multiple transactions with round amounts (100,200,1000 etc)
-- =====================================================================
SELECT user_id,COUNT(*) AS round_transactions
FROM transactions
WHERE amount IN (100,200,500,1000,2000,5000,10000)
GROUP BY user_id
HAVING COUNT(*)>=15
ORDER BY round_transactions DESC;
-- 25 suspects returned, the maximum transaction being 30 by 3 suspects

-- ===================================================================== 
-- PATTERN 3- CARD TESTING
-- it returns users with 30 or more transactions of low amount like RS.10 or Rs.15
-- ===================================================================== 
SELECT user_id,DATE(txn_time) AS transaction_date,COUNT(*) AS low_transactions
FROM transactions
WHERE amount<10
GROUP BY user_id,DATE(txn_time)
HAVING COUNT(*)>=30
ORDER BY low_transactions DESC;
-- 20 suspected transactions returned.
-- Maximum transaction of 60 was done by two suspects 14569 and 14556

-- ===================================================================== 
-- PATTERN 4- FAILED THEN SUCCEEDED
-- Query to find suspects having 20+ failed transactions followed by successful one.
SELECT user_id,COUNT(*) AS failed_transactions
FROM transactions
WHERE status='FAILED'
GROUP BY user_id
HAVING COUNT(*)>=20
ORDER BY failed_transactions DESC;
-- 25 records returned, user 14595 has 35 failed transaction

-- =====================================================================
-- PATTERN 5- ODD-HOUR CONCENTRATION
-- finds users who is active during 2AM to 5AM, with 30+ transactions.

SELECT user_id,COUNT(*) AS total_transactions,
SUM(CASE
	 WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
	 ELSE 0
	 END) AS midnight_transactions
FROM transactions
GROUP BY user_id
HAVING COUNT(*)>=30
AND SUM(CASE
		 WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
		 ELSE 0
		 END)/COUNT(*)>=0.80
ORDER BY midnight_transactions DESC;
-- user 14608 performed 58 out of 63 transactions during midnight

-- =====================================================================
-- PATTERN 6- MULE ACCOUNTS
-- query that returns transactions which was credited with amount and debited 70% of the same amount

SELECT user_id,COUNT(*) AS credit_transactions
FROM transactions
WHERE txn_type='CREDIT'
GROUP BY user_id
HAVING COUNT(*)>=8
ORDER BY credit_transactions DESC;

-- The query identified users with 8 or more CREDIT transactions

-- =====================================================================
-- PATTERN 7- REFUND ABUSE
-- query that returns users where 40% of their transactions were refunds

SELECT user_id,COUNT(*) AS total_transactions,
SUM(CASE WHEN txn_type='REFUND' THEN 1 ELSE 0 END) AS refund_transactions
FROM transactions
GROUP BY user_id
HAVING COUNT(*)>=20
AND SUM(CASE WHEN txn_type='REFUND' THEN 1 ELSE 0 END)/COUNT(*)>0.40
ORDER BY refund_transactions DESC;

-- returns 2 users.
-- user 14657 has 36 refund trnsactions out of 60 transactions

-- =====================================================================
-- PATTERN 8- MERCHANT COLLUSION
-- The query identified merchants where the top five users contributed more than 60% of the total transaction value.
-- AI assissted

WITH merchant_user_volume AS (
    SELECT merchant_id, user_id,SUM(amount) AS user_volume
    FROM transactions
    GROUP BY merchant_id,user_id),
ranked_users AS (
    SELECT merchant_id,user_id,user_volume,
           ROW_NUMBER() OVER(PARTITION BY merchant_id ORDER BY user_volume DESC) AS rn
    FROM merchant_user_volume
),
top5_volume AS (
    SELECT merchant_id,SUM(user_volume) AS top5_total
    FROM ranked_users
    WHERE rn<=5
    GROUP BY merchant_id
),
merchant_volume AS (
    SELECT merchant_id,SUM(amount) AS merchant_total
    FROM transactions
    GROUP BY merchant_id
)

SELECT m.merchant_id,m.merchant_total,t.top5_total
FROM merchant_volume m
JOIN top5_volume t
ON m.merchant_id=t.merchant_id
WHERE t.top5_total/m.merchant_total>0.60
ORDER BY m.merchant_id;

-- =====================================================================
-- PATTERN 9- JUST UNDER THRESHOLD
-- identifies users 10 or more transactions at exactly ₹9,999.00.
-- =====================================================================

SELECT user_id,COUNT(*) AS sus_transactions
FROM transactions
WHERE amount=9999.00
GROUP BY user_id
HAVING COUNT(*)>=10
ORDER BY sus_transactions DESC;

-- returns 20 suspects, user 14680 with maximum of 25 suspicious transactions

-- =====================================================================
-- PATTERN 10- DORMANT-THEN-ACTIVE
-- The query identifies users who remained inactive for at least 90 days
-- then performed 15 or more transaction after being active
-- =====================================================================

WITH user_activity AS (
    SELECT user_id,txn_time,LAG(txn_time) OVER(PARTITION BY user_id ORDER BY txn_time) AS previous_txn
    FROM transactions),
dormant_users AS (
    SELECT user_id,txn_time
    FROM user_activity
    WHERE TIMESTAMPDIFF(DAY,previous_txn,txn_time)>=90)
SELECT d.user_id,COUNT(*) AS transactions_after_gap
FROM dormant_users d
JOIN transactions t
ON d.user_id=t.user_id
AND t.txn_time>=d.txn_time
GROUP BY d.user_id
HAVING COUNT(*)>=15
ORDER BY transactions_after_gap DESC;

-- 26 users returned
-- user 14526 made 55 transactions after a gap, which is suspicious

-- =====================================================================
-- PATTERN 11- VELOCITY SPIKE
-- query identifies users with 20+ transactions higher than the monthly average
-- AI ASSISTED
-- ======================================================================
WITH monthly_transactions AS (
    SELECT user_id,
           DATE_FORMAT(txn_time,'%Y-%m') AS month,
           COUNT(*) AS monthly_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time,'%Y-%m')
),
user_summary AS (
    SELECT user_id,
           AVG(monthly_count) AS avg_monthly_transactions,
           MAX(monthly_count) AS peak_monthly_transactions
    FROM monthly_transactions
    GROUP BY user_id
)

SELECT user_id,
       ROUND(avg_monthly_transactions,2) AS avg_monthly_transactions,
       peak_monthly_transactions
FROM user_summary
WHERE peak_monthly_transactions >= 20
AND avg_monthly_transactions >= 2
AND peak_monthly_transactions >= avg_monthly_transactions * 5
ORDER BY peak_monthly_transactions DESC;

-- ======================================================================
-- PATTERN 12- GEOGRAPHIC IMPOSSIBILITY
-- identifies users who performed many different transactions at different plces in 60 minutes
-- ======================================================================
WITH location_history AS(
    SELECT user_id,city,txn_time,
           LAG(city) OVER(PARTITION BY user_id ORDER BY txn_time) AS previous_city,
           LAG(txn_time) OVER(PARTITION BY user_id ORDER BY txn_time) AS previous_time
    FROM transactions)
SELECT DISTINCT user_id
FROM location_history
WHERE previous_city IS NOT NULL
AND city<>previous_city
AND TIMESTAMPDIFF(MINUTE, previous_time, txn_time)<=60
ORDER BY user_id;
-- returned 15 users
-- =======================================================================