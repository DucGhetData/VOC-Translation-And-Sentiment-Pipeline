ARG AIRFLOW_VERSION=2.11.2
FROM apache/airflow:${AIRFLOW_VERSION}-python3.12

ARG AIRFLOW_VERSION

# Keep Airflow pinned while adding project runtime dependencies. Installing as
# the airflow user is required by the official image.
COPY --chown=airflow:root requirements.txt /opt/airflow/requirements.txt
RUN pip install --no-cache-dir \
    "apache-airflow==${AIRFLOW_VERSION}" \
    -r /opt/airflow/requirements.txt \
    && pip check
