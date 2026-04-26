import pandas as pd


def ingest(path: str = "../../datasets/retail_sales.csv") -> pd.DataFrame:
    df = pd.read_csv(path, parse_dates=["order_date"])
    return df


if __name__ == "__main__":
    df = ingest()
    print(df.head())
