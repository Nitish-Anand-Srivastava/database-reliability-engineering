import pyarrow as pa
import pyarrow.csv as pv
import pyarrow.parquet as pq
import os
from concurrent.futures import ThreadPoolExecutor

INPUT_DIR = "csv_data"
OUTPUT_DIR = "parquet_data"

def convert_file(file):
    table = pv.read_csv(os.path.join(INPUT_DIR, file))
    pq.write_table(table, os.path.join(OUTPUT_DIR, file.replace(".csv", ".parquet")))

def main():
    files = [f for f in os.listdir(INPUT_DIR) if f.endswith(".csv")]

    with ThreadPoolExecutor(max_workers=8) as executor:
        executor.map(convert_file, files)

if __name__ == "__main__":
    main()
