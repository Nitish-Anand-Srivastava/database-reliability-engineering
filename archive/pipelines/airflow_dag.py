from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

from data_engineering.ingestion.ingest_api_data import fetch_data

default_args = {"start_date": datetime(2024, 1, 1)}

dag = DAG("etl_pipeline", schedule_interval="@daily", default_args=default_args)

task1 = PythonOperator(
    task_id="fetch_data",
    python_callable=fetch_data,
    dag=dag
)
