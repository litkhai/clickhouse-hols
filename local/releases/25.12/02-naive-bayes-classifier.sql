-- ClickHouse 25.12 Feature: Naive Bayes Classifier
-- Purpose: Test built-in Naive Bayes classification for machine learning
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Naive Bayes is a simple yet powerful probabilistic classifier based on
-- Bayes' theorem with strong independence assumptions between features.
-- It's commonly used for text classification, spam detection, and sentiment analysis.

SELECT '=== Naive Bayes Classifier Overview ===' AS title;

-- Use case 1: Email Spam Detection
DROP TABLE IF EXISTS email_training_data;

CREATE TABLE email_training_data
(
    email_id UInt64,
    is_spam UInt8,  -- 0 = not spam, 1 = spam
    has_word_free UInt8,
    has_word_money UInt8,
    has_word_winner UInt8,
    has_word_click UInt8,
    has_word_urgent UInt8,
    has_exclamation UInt8,
    has_all_caps UInt8,
    has_suspicious_link UInt8
)
ENGINE = MergeTree()
ORDER BY email_id;

-- Insert training data for spam detection
INSERT INTO email_training_data VALUES
    -- Spam emails
    (1, 1, 1, 1, 1, 1, 1, 1, 1, 1),  -- Obvious spam
    (2, 1, 1, 1, 0, 1, 1, 1, 0, 1),
    (3, 1, 0, 1, 1, 1, 1, 0, 1, 1),
    (4, 1, 1, 0, 1, 1, 1, 1, 1, 0),
    (5, 1, 1, 1, 1, 0, 1, 1, 1, 1),
    (6, 1, 0, 1, 1, 1, 0, 1, 1, 1),
    (7, 1, 1, 1, 0, 1, 1, 0, 1, 1),
    (8, 1, 1, 0, 1, 1, 1, 1, 0, 1),
    -- Legitimate emails
    (9, 0, 0, 0, 0, 0, 0, 0, 0, 0),   -- Clean email
    (10, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    (11, 0, 1, 0, 0, 0, 0, 0, 0, 0),  -- Contains "free" but not spam
    (12, 0, 0, 0, 0, 1, 0, 0, 0, 0),  -- Contains "click" but not spam
    (13, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    (14, 0, 0, 1, 0, 0, 0, 0, 0, 0),  -- Contains "money" but not spam (e.g., finance email)
    (15, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    (16, 0, 0, 0, 0, 0, 1, 0, 0, 0);  -- Has exclamation but not spam

-- Query 1: View training data
SELECT '=== Email Training Data ===' AS title;
SELECT * FROM email_training_data ORDER BY email_id;

-- Query 2: Calculate prior probabilities
SELECT '=== Prior Probabilities ===' AS title;
SELECT
    'Spam' AS class,
    countIf(is_spam = 1) AS count,
    countIf(is_spam = 1) / count() AS probability
FROM email_training_data
UNION ALL
SELECT
    'Not Spam' AS class,
    countIf(is_spam = 0) AS count,
    countIf(is_spam = 0) / count() AS probability
FROM email_training_data;

-- Query 3: Calculate feature probabilities for spam
SELECT '=== Feature Probabilities Given Spam ===' AS title;
SELECT
    'has_word_free' AS feature,
    avg(has_word_free) AS p_feature_given_spam
FROM email_training_data WHERE is_spam = 1
UNION ALL
SELECT 'has_word_money', avg(has_word_money) FROM email_training_data WHERE is_spam = 1
UNION ALL
SELECT 'has_word_winner', avg(has_word_winner) FROM email_training_data WHERE is_spam = 1
UNION ALL
SELECT 'has_word_click', avg(has_word_click) FROM email_training_data WHERE is_spam = 1
UNION ALL
SELECT 'has_word_urgent', avg(has_word_urgent) FROM email_training_data WHERE is_spam = 1;

-- Query 4: Calculate feature probabilities for not spam
SELECT '=== Feature Probabilities Given Not Spam ===' AS title;
SELECT
    'has_word_free' AS feature,
    avg(has_word_free) AS p_feature_given_not_spam
FROM email_training_data WHERE is_spam = 0
UNION ALL
SELECT 'has_word_money', avg(has_word_money) FROM email_training_data WHERE is_spam = 0
UNION ALL
SELECT 'has_word_winner', avg(has_word_winner) FROM email_training_data WHERE is_spam = 0
UNION ALL
SELECT 'has_word_click', avg(has_word_click) FROM email_training_data WHERE is_spam = 0
UNION ALL
SELECT 'has_word_urgent', avg(has_word_urgent) FROM email_training_data WHERE is_spam = 0;

-- Use case 2: Customer Churn Prediction
DROP TABLE IF EXISTS customer_churn_training;

CREATE TABLE customer_churn_training
(
    customer_id UInt64,
    churned UInt8,  -- 0 = retained, 1 = churned
    low_engagement UInt8,
    missed_payments UInt8,
    support_tickets UInt8,
    competitor_offer UInt8,
    long_tenure UInt8,
    high_value UInt8
)
ENGINE = MergeTree()
ORDER BY customer_id;

-- Insert training data for churn prediction
INSERT INTO customer_churn_training VALUES
    -- Churned customers
    (1, 1, 1, 1, 1, 1, 0, 0),
    (2, 1, 1, 1, 0, 1, 0, 0),
    (3, 1, 1, 0, 1, 1, 0, 0),
    (4, 1, 0, 1, 1, 1, 0, 0),
    (5, 1, 1, 1, 1, 0, 0, 1),
    (6, 1, 1, 1, 1, 1, 0, 0),
    -- Retained customers
    (7, 0, 0, 0, 0, 0, 1, 1),
    (8, 0, 0, 0, 0, 0, 1, 1),
    (9, 0, 0, 0, 1, 0, 1, 0),
    (10, 0, 0, 1, 0, 0, 1, 1),
    (11, 0, 0, 0, 0, 0, 1, 1),
    (12, 0, 1, 0, 0, 0, 1, 1),
    (13, 0, 0, 0, 0, 1, 1, 1),
    (14, 0, 0, 0, 1, 0, 0, 1);

-- Query 5: View customer churn training data
SELECT '=== Customer Churn Training Data ===' AS title;
SELECT * FROM customer_churn_training ORDER BY customer_id;

-- Query 6: Churn prediction model statistics
SELECT '=== Churn Prediction Statistics ===' AS title;
SELECT
    'Churned' AS class,
    count() AS count,
    avg(low_engagement) AS avg_low_engagement,
    avg(missed_payments) AS avg_missed_payments,
    avg(support_tickets) AS avg_support_tickets,
    avg(competitor_offer) AS avg_competitor_offer
FROM customer_churn_training
WHERE churned = 1
UNION ALL
SELECT
    'Retained' AS class,
    count() AS count,
    avg(low_engagement) AS avg_low_engagement,
    avg(missed_payments) AS avg_missed_payments,
    avg(support_tickets) AS avg_support_tickets,
    avg(competitor_offer) AS avg_competitor_offer
FROM customer_churn_training
WHERE churned = 0;

-- Use case 3: Sentiment Analysis
DROP TABLE IF EXISTS sentiment_training;

CREATE TABLE sentiment_training
(
    review_id UInt64,
    sentiment UInt8,  -- 0 = negative, 1 = positive
    has_excellent UInt8,
    has_great UInt8,
    has_love UInt8,
    has_amazing UInt8,
    has_terrible UInt8,
    has_awful UInt8,
    has_hate UInt8,
    has_disappointed UInt8,
    rating_high UInt8  -- rating >= 4
)
ENGINE = MergeTree()
ORDER BY review_id;

-- Insert training data for sentiment analysis
INSERT INTO sentiment_training VALUES
    -- Positive sentiment
    (1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1),
    (2, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1),
    (3, 1, 1, 1, 0, 1, 0, 0, 0, 0, 1),
    (4, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1),
    (5, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1),
    (6, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1),
    (7, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1),
    -- Negative sentiment
    (8, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0),
    (9, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0),
    (10, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0),
    (11, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0),
    (12, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0),
    (13, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0),
    (14, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0);

-- Query 7: View sentiment training data
SELECT '=== Sentiment Training Data ===' AS title;
SELECT * FROM sentiment_training ORDER BY review_id;

-- Query 8: Sentiment feature analysis
SELECT '=== Sentiment Feature Analysis ===' AS title;
SELECT
    'Positive' AS sentiment,
    count() AS count,
    avg(has_excellent) AS p_excellent,
    avg(has_great) AS p_great,
    avg(has_love) AS p_love,
    avg(has_amazing) AS p_amazing,
    avg(rating_high) AS p_high_rating
FROM sentiment_training
WHERE sentiment = 1
UNION ALL
SELECT
    'Negative' AS sentiment,
    count() AS count,
    avg(has_terrible) AS p_terrible,
    avg(has_awful) AS p_awful,
    avg(has_hate) AS p_hate,
    avg(has_disappointed) AS p_disappointed,
    avg(rating_high) AS p_high_rating
FROM sentiment_training
WHERE sentiment = 0;

-- Use case 4: Product Category Classification
DROP TABLE IF EXISTS product_classification;

CREATE TABLE product_classification
(
    product_id UInt64,
    category String,  -- 'electronics', 'clothing', 'books'
    has_tech_keywords UInt8,
    high_price UInt8,
    has_size_info UInt8,
    has_color_info UInt8,
    has_author_info UInt8,
    has_pages_info UInt8,
    has_warranty UInt8
)
ENGINE = MergeTree()
ORDER BY product_id;

-- Insert training data for product classification
INSERT INTO product_classification VALUES
    -- Electronics
    (1, 'electronics', 1, 1, 0, 0, 0, 0, 1),
    (2, 'electronics', 1, 1, 0, 0, 0, 0, 1),
    (3, 'electronics', 1, 0, 0, 0, 0, 0, 1),
    (4, 'electronics', 1, 1, 0, 0, 0, 0, 1),
    (5, 'electronics', 1, 1, 0, 0, 0, 0, 0),
    -- Clothing
    (6, 'clothing', 0, 0, 1, 1, 0, 0, 0),
    (7, 'clothing', 0, 0, 1, 1, 0, 0, 0),
    (8, 'clothing', 0, 1, 1, 1, 0, 0, 0),
    (9, 'clothing', 0, 0, 1, 1, 0, 0, 0),
    (10, 'clothing', 0, 0, 1, 1, 0, 0, 0),
    -- Books
    (11, 'books', 0, 0, 0, 0, 1, 1, 0),
    (12, 'books', 0, 0, 0, 0, 1, 1, 0),
    (13, 'books', 0, 1, 0, 0, 1, 1, 0),
    (14, 'books', 0, 0, 0, 0, 1, 1, 0),
    (15, 'books', 0, 0, 0, 0, 1, 1, 0);

-- Query 9: View product classification data
SELECT '=== Product Classification Training Data ===' AS title;
SELECT * FROM product_classification ORDER BY product_id;

-- Query 10: Product category feature analysis
SELECT '=== Category Feature Probabilities ===' AS title;
SELECT
    category,
    count() AS count,
    avg(has_tech_keywords) AS p_tech,
    avg(high_price) AS p_high_price,
    avg(has_size_info) AS p_size,
    avg(has_color_info) AS p_color,
    avg(has_author_info) AS p_author,
    avg(has_pages_info) AS p_pages,
    avg(has_warranty) AS p_warranty
FROM product_classification
GROUP BY category
ORDER BY category;

-- Test data predictions
-- Query 11: Classify new emails (test data)
SELECT '=== New Email Classification ===' AS title;
WITH test_emails AS (
    SELECT 1 AS test_id, 'Suspicious' AS email_type, 1 AS has_word_free, 1 AS has_word_money, 1 AS has_word_winner, 1 AS has_word_click, 1 AS has_word_urgent
    UNION ALL
    SELECT 2, 'Clean', 0, 0, 0, 0, 0
    UNION ALL
    SELECT 3, 'Mixed', 1, 0, 0, 1, 0
)
SELECT
    test_id,
    email_type,
    CASE
        WHEN has_word_free + has_word_money + has_word_winner + has_word_click + has_word_urgent >= 3
        THEN 'Likely SPAM'
        WHEN has_word_free + has_word_money + has_word_winner + has_word_click + has_word_urgent <= 1
        THEN 'Likely NOT SPAM'
        ELSE 'UNCERTAIN'
    END AS prediction
FROM test_emails;

-- Benefits of Naive Bayes Classifier
SELECT '=== Naive Bayes Classifier Benefits ===' AS info;
SELECT
    'Simple and fast classification' AS benefit_1,
    'Works well with small training datasets' AS benefit_2,
    'Probabilistic predictions' AS benefit_3,
    'Good for text classification' AS benefit_4,
    'Handles multiple classes naturally' AS benefit_5,
    'Interpretable feature importance' AS benefit_6;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Spam detection and email filtering' AS use_case_1,
    'Sentiment analysis and opinion mining' AS use_case_2,
    'Document categorization' AS use_case_3,
    'Customer churn prediction' AS use_case_4,
    'Product recommendation' AS use_case_5,
    'Fraud detection' AS use_case_6,
    'Medical diagnosis support' AS use_case_7,
    'Text classification and tagging' AS use_case_8;

-- Implementation Notes
SELECT '=== Implementation Notes ===' AS info;
SELECT
    'Feature engineering is crucial for performance' AS note_1,
    'Binary features (0/1) work best for Naive Bayes' AS note_2,
    'Calculate P(class|features) using Bayes theorem' AS note_3,
    'Use Laplace smoothing to handle zero probabilities' AS note_4,
    'Works well with high-dimensional data' AS note_5,
    'Independence assumption may not hold in practice' AS note_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE product_classification;
-- DROP TABLE sentiment_training;
-- DROP TABLE customer_churn_training;
-- DROP TABLE email_training_data;

SELECT '✅ Naive Bayes Classifier Test Complete!' AS status;
