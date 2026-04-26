import pandas as pd
from sqlalchemy import create_engine


def load(df: pd.DataFrame, url: str = "postgresql://user:password@localhost:5432/db"):
    engine = create_engine(url)
    df.to_sql("daily_revenue", engine, if_exists="replace", index=False)


if __name__ == "__main__":
    from ingest import ingest
    from transform import transform

    df = ingest()
    out = transform(df)
    load(out)
    print("Loaded to database")
