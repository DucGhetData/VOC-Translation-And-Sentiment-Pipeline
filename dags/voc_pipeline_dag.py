"""
Placeholder DAG for VOC Pipeline.
Will be expanded in later phases.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator


default_args = {
    "owner": "voc-pipeline",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=2),
}


def _placeholder_task(task_name: str) -> None:
    """Placeholder — replace with real implementation in each phase."""
    print(f"[{task_name}] Placeholder — not yet implemented")


with DAG(
    dag_id="voc_pipeline",
    description="VOC Translation & Sentiment Pipeline — Main DAG",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["voc", "nlp", "etl"],
) as dag:

    start = EmptyOperator(task_id="start")
    end = EmptyOperator(task_id="end")

    # ── Phase 3: Ingestion ────────────────────────────────────────────────────
    check_source = PythonOperator(
        task_id="check_source",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "check_source"},
    )
    upload_raw = PythonOperator(
        task_id="upload_raw",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "upload_raw"},
    )

    # ── Phase 4: ETL ─────────────────────────────────────────────────────────
    etl_bronze = PythonOperator(
        task_id="etl_bronze",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "etl_bronze"},
    )
    etl_silver = PythonOperator(
        task_id="etl_silver",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "etl_silver"},
    )

    # ── Phase 5: Quality ─────────────────────────────────────────────────────
    data_quality = PythonOperator(
        task_id="data_quality",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "data_quality"},
    )

    # ── Phase 6: NLP ──────────────────────────────────────────────────────────
    load_nlp_tracking = PythonOperator(
        task_id="load_nlp_tracking",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "load_nlp_tracking"},
    )
    language_detection = PythonOperator(
        task_id="language_detection",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "language_detection"},
    )
    translation = PythonOperator(
        task_id="translation",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "translation"},
    )
    sentiment = PythonOperator(
        task_id="sentiment",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "sentiment"},
    )
    update_nlp_tracking = PythonOperator(
        task_id="update_nlp_tracking",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "update_nlp_tracking"},
    )

    # ── Phase 7: Gold ─────────────────────────────────────────────────────────
    build_gold = PythonOperator(
        task_id="build_gold",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "build_gold"},
    )
    repair_athena_partitions = PythonOperator(
        task_id="repair_athena_partitions",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "repair_athena_partitions"},
    )
    final_quality_check = PythonOperator(
        task_id="final_quality_check",
        python_callable=_placeholder_task,
        op_kwargs={"task_name": "final_quality_check"},
    )

    # ── Task Dependencies ─────────────────────────────────────────────────────
    (
        start
        >> check_source
        >> upload_raw
        >> etl_bronze
        >> etl_silver
        >> data_quality
        >> load_nlp_tracking
        >> language_detection
        >> translation
        >> sentiment
        >> update_nlp_tracking
        >> build_gold
        >> repair_athena_partitions
        >> final_quality_check
        >> end
    )
