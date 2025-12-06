#!/usr/bin/env python3
"""
Generate sample Parquet file for data lake demonstration
"""

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime, timedelta
import random

def generate_orders_data(num_records=100):
    """Generate sample order data"""

    orders = []
    start_date = datetime(2023, 1, 1)

    products = [
        ("Laptop", 999.99),
        ("Mouse", 29.99),
        ("Keyboard", 79.99),
        ("Monitor", 299.99),
        ("Headphones", 149.99),
        ("USB Cable", 12.99),
        ("Webcam", 89.99),
        ("Desk Lamp", 45.99),
        ("Phone Case", 19.99),
        ("Charger", 34.99)
    ]

    statuses = ["pending", "processing", "shipped", "delivered", "cancelled"]

    for i in range(num_records):
        order_date = start_date + timedelta(days=random.randint(0, 365))
        product, price = random.choice(products)
        quantity = random.randint(1, 5)

        order = {
            "order_id": i + 1,
            "customer_id": random.randint(1, 10),
            "product_name": product,
            "quantity": quantity,
            "unit_price": price,
            "total_amount": price * quantity,
            "order_date": order_date.strftime("%Y-%m-%d"),
            "status": random.choice(statuses)
        }
        orders.append(order)

    return orders

def main():
    print("Generating sample orders data...")

    # Generate data
    orders = generate_orders_data(100)

    # Create DataFrame
    df = pd.DataFrame(orders)

    # Create PyArrow table
    table = pa.Table.from_pandas(df)

    # Write to Parquet file
    output_file = "sample-data/orders.parquet"
    pq.write_table(table, output_file)

    print(f"✓ Generated {output_file}")
    print(f"  Records: {len(orders)}")
    print(f"  Columns: {', '.join(df.columns)}")
    print(f"  File size: {pa.fs.LocalFileSystem().get_file_info(output_file).size} bytes")

    # Display sample
    print("\nSample data (first 5 rows):")
    print(df.head())

if __name__ == "__main__":
    main()
