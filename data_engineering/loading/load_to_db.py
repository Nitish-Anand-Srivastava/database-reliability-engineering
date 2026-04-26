import pandas as pd
from sqlalchemy import create_engine

engine = create_engine("postgresql://user:password@localhost:5432/db")

def load():
    df = pd.read_csv("transformed_data.csv")
    df.to_sql("posts", engine, if_exists="replace", index=False)

if __name__ == "__main__":
    load()
