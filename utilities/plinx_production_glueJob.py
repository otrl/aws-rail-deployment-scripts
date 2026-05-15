import sys
import json
import datetime
import uuid
import time
import boto3

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "DB_SECRET_ARN",
        "DB_HOST",
        "DB_PORT",
        "OUTPUT_BUCKET",
        "OUTPUT_PREFIX"
    ]
)

JOB_NAME = args["JOB_NAME"]
DB_SECRET_ARN = args["DB_SECRET_ARN"]
DB_HOST = args["DB_HOST"]
DB_PORT = args["DB_PORT"]
OUTPUT_BUCKET = args["OUTPUT_BUCKET"]
OUTPUT_PREFIX = args["OUTPUT_PREFIX"].rstrip("/")

COCS_SCHEMA = "cocs_7202"

# Change these if the real schemas differ.
DIGITAL_RAILCARD_SCHEMA = "digital_railcards"
JOURNEY_ALERTS_SCHEMA = "ddm_alerts"
SMARTCARD_SCHEMA = "smartcard"
OTR_SCHEMA = "otr"

RUN_TS = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
RUN_DATE = datetime.datetime.utcnow().strftime("%Y-%m-%d")
RUN_ID = str(uuid.uuid4())

JDBC_NUM_PARTITIONS = 8

s3 = boto3.client("s3")
secretsmanager = boto3.client("secretsmanager")

spark = (
    SparkSession.builder
    .appName(JOB_NAME)
    .config("spark.sql.shuffle.partitions", str(JDBC_NUM_PARTITIONS))
    .getOrCreate()
)

# Avoid _SUCCESS marker files where possible.
spark.sparkContext._jsc.hadoopConfiguration().set(
    "mapreduce.fileoutputcommitter.marksuccessfuljobs",
    "false"
)

secret_value = secretsmanager.get_secret_value(SecretId=DB_SECRET_ARN)
secret_raw = secret_value["SecretString"]
secret = json.loads(secret_raw)

# Handles broken/odd secret format where the full JSON was stored as one key.
if isinstance(secret, dict) and len(secret.keys()) == 1:
    only_key = list(secret.keys())[0]
    if only_key.strip().startswith("{") and only_key.strip().endswith("}"):
        secret = json.loads(only_key)

DB_USER = secret.get("username") or secret.get("user")
DB_PASSWORD = secret.get("password")

if not DB_USER or not DB_PASSWORD:
    raise ValueError(f"Secret must contain username/user and password. Keys present: {list(secret.keys())}")

JDBC_URL = (
    f"jdbc:mysql://{DB_HOST}:{DB_PORT}/"
    "?useSSL=false"
    "&zeroDateTimeBehavior=convertToNull"
    "&connectTimeout=30000"
    "&socketTimeout=900000"
)

def qname(schema, table):
    return f"`{schema}`.`{table}`"

def alias_for(name):
    return name.replace("-", "_").replace(".", "_").replace("`", "").replace(" ", "_")

def list_s3_keys(bucket, prefix):
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            keys.append(item["Key"])
    return keys

def delete_prefix(bucket, prefix):
    keys = list_s3_keys(bucket, prefix)
    for i in range(0, len(keys), 1000):
        batch = keys[i:i+1000]
        if batch:
            s3.delete_objects(
                Bucket=bucket,
                Delete={"Objects": [{"Key": k} for k in batch]}
            )

def jdbc_reader_base():
    return (
        spark.read
        .format("jdbc")
        .option("url", JDBC_URL)
        .option("user", DB_USER)
        .option("password", DB_PASSWORD)
        .option("fetchsize", "20000")
    )

def read_query(sql_query):
    return (
        jdbc_reader_base()
        .option("query", sql_query)
        .load()
    )

def get_id_bounds(schema, table, where_clause=None):
    where_sql = f" WHERE {where_clause}" if where_clause else ""
    sql = f"""
        SELECT
            MIN(id) AS min_id,
            MAX(id) AS max_id
        FROM {qname(schema, table)}
        {where_sql}
    """

    row = read_query(sql).collect()[0]
    min_id = row["min_id"]
    max_id = row["max_id"]

    if min_id is None or max_id is None:
        return None, None

    return int(min_id), int(max_id)

def read_table_parallel(schema, table, partition_column="id"):
    reader = (
        jdbc_reader_base()
        .option("dbtable", qname(schema, table))
    )

    try:
        min_id, max_id = get_id_bounds(schema, table)

        if min_id is not None and max_id is not None and max_id > min_id:
            print(f"Parallel JDBC read for {schema}.{table}: {partition_column} {min_id} -> {max_id}")
            reader = (
                reader
                .option("partitionColumn", partition_column)
                .option("lowerBound", str(min_id))
                .option("upperBound", str(max_id + 1))
                .option("numPartitions", str(JDBC_NUM_PARTITIONS))
            )
            return reader.load()

        print(f"Non-partitioned JDBC read for {schema}.{table}: no usable id range")
        return reader.load()

    except Exception as exc:
        print(
            f"WARNING: Could not use partition column '{partition_column}' for {schema}.{table}. "
            f"Falling back to non-partitioned read. Reason: {exc}"
        )
        return reader.load()


def read_filtered_query_parallel(export):
    schema = export["schema"]
    table = export["table"]
    where_clause = export["where"]
    partition_column = export.get("partition_column", "id")

    try:
        min_id, max_id = get_id_bounds(schema, table, where_clause=where_clause)
    except Exception as exc:
        print(f"Could not get ID bounds for {schema}.{table}; falling back to query mode. Reason: {exc}")
        return read_query(export["query"])

    alias = alias_for(export["name"])
    dbtable = f"(SELECT * FROM {qname(schema, table)} WHERE {where_clause}) AS {alias}"

    reader = (
        jdbc_reader_base()
        .option("dbtable", dbtable)
    )

    if min_id is not None and max_id is not None and max_id > min_id:
        print(f"Parallel JDBC filtered read for {schema}.{table}: {partition_column} {min_id} -> {max_id}")
        reader = (
            reader
            .option("partitionColumn", partition_column)
            .option("lowerBound", str(min_id))
            .option("upperBound", str(max_id + 1))
            .option("numPartitions", str(JDBC_NUM_PARTITIONS))
        )
        return reader.load()

    print(f"Non-partitioned filtered JDBC read for {schema}.{table}")
    return read_query(export["query"])

def read_export_df(export):
    mode = export.get("mode", "query")

    if mode == "table":
        return read_table_parallel(
            export["schema"],
            export["table"],
            export.get("partition_column", "id")
        )

    if mode == "filtered_table":
        return read_filtered_query_parallel(export)

    return read_query(export["query"])

def write_export_to_parquet(export):
    started = time.time()

    export_name = export["name"]
    run_export_prefix = f"{OUTPUT_PREFIX}/runs/run_date={RUN_DATE}/run_ts={RUN_TS}/{export_name}/"
    output_path = f"s3://{OUTPUT_BUCKET}/{run_export_prefix}"

    print(f"Starting export: {export_name}")
    print(f"Parquet output path: {output_path}")

    df = read_export_df(export)

    (
        df.write
        .mode("overwrite")
        .option("compression", "snappy")
        .parquet(output_path)
    )

    duration_seconds = round(time.time() - started, 2)

    print(f"Finished export: {export_name} in {duration_seconds}s")

    return {
        "name": export_name,
        "run_prefix": run_export_prefix,
        "s3_path": output_path,
        "format": "parquet",
        "compression": "snappy",
        "duration_seconds": duration_seconds
    }

exports = []

# COCS_7202 full tables.
for table in [
    "order",
    "customer",
    "delivery",
    "address",
    "sundry",
    "fare",
    "trip",
    "journey",
    "leg_supplement",
    "leg",
    "supplement",
    "ticket",
    "discount",
    "refund",
    "amended_order_ticket",
    "device",
    "customer_address",
    "changeover_order",
    "changeover_order_ticket",
    "photocard",
    "passenger",
    "customer_station",
    "audit_trail"
]:
    exports.append({
        "name": f"cocs_7202_{table}",
        "mode": "table",
        "schema": COCS_SCHEMA,
        "table": table,
        "partition_column": "id"
    })

# Digital Railcard.
exports.append({
    "name": "digital_railcard_railcard",
    "mode": "filtered_table",
    "schema": DIGITAL_RAILCARD_SCHEMA,
    "table": "railcard",
    "where": "brand = 'transpennine'",
    "partition_column": "id",
    "query": f"""
        SELECT *
        FROM {qname(DIGITAL_RAILCARD_SCHEMA, "railcard")}
        WHERE brand = 'transpennine'
    """
})

# Journey Alerts.
exports.append({
    "name": "journey_alerts_customer",
    "mode": "filtered_table",
    "schema": JOURNEY_ALERTS_SCHEMA,
    "table": "customer",
    "where": "toc = 'transpennine'",
    "partition_column": "id",
    "query": f"""
        SELECT *
        FROM {qname(JOURNEY_ALERTS_SCHEMA, "customer")}
        WHERE toc = 'transpennine'
    """
})

exports.append({
    "name": "journey_alerts_alert_notification",
    "mode": "query",
    "query": f"""
        SELECT an.*
        FROM {qname(JOURNEY_ALERTS_SCHEMA, "alert_notification")} an
        INNER JOIN {qname(JOURNEY_ALERTS_SCHEMA, "customer")} c
            ON c.id = an.customer_id
        WHERE c.toc = 'transpennine'
    """
})

exports.append({
    "name": "journey_alerts_journey_alert",
    "mode": "query",
    "query": f"""
        SELECT DISTINCT ja.*
        FROM (
            SELECT *
            FROM {qname(JOURNEY_ALERTS_SCHEMA, "journey_alert")}
            WHERE last_updated >= UTC_TIMESTAMP() - INTERVAL 20 MINUTE
               OR submitted_date >= UTC_TIMESTAMP() - INTERVAL 20 MINUTE
        ) ja
        INNER JOIN {qname(JOURNEY_ALERTS_SCHEMA, "subscriber")} s
            ON s.journey_alert_id = ja.id
        INNER JOIN {qname(JOURNEY_ALERTS_SCHEMA, "customer")} c
            ON c.id = s.customer_id
        WHERE c.toc = 'transpennine'
    """
})

# Reference / lookup tables.
exports.append({
    "name": "otr_fulfilment_method",
    "mode": "table",
    "schema": OTR_SCHEMA,
    "table": "fulfilment_method",
    "partition_column": "id"
})

exports.append({
    "name": "otr_ticket_type",
    "mode": "query",
    "query": f"""
        SELECT ticket_code, description, display_name
        FROM {qname(OTR_SCHEMA, "ticket_type")}
    """
})

exports.append({
    "name": "otr_location",
    "mode": "query",
    "query": f"""
        SELECT end_date, description, nlc_code
        FROM {qname(OTR_SCHEMA, "location")}
    """
})

# Smartcard.
exports.append({
    "name": "smartcard_smartcard",
    "mode": "query",
    "query": f"""
        SELECT *
        FROM {qname(SMARTCARD_SCHEMA, "smartcard")}
        WHERE NLC = 7202
    """
})

manifest = {
    "job_name": JOB_NAME,
    "run_id": RUN_ID,
    "run_ts_utc": RUN_TS,
    "run_date_utc": RUN_DATE,
    "output_bucket": OUTPUT_BUCKET,
    "output_prefix": OUTPUT_PREFIX,
    "format": "parquet",
    "compression": "snappy",
    "jdbc_num_partitions": JDBC_NUM_PARTITIONS,
    "exports": []
}

job_started = time.time()
run_root_prefix = f"{OUTPUT_PREFIX}/runs/run_date={RUN_DATE}/run_ts={RUN_TS}/"

try:
    for export in exports:
        result = write_export_to_parquet(export)
        manifest["exports"].append(result)

    total_duration_seconds = round(time.time() - job_started, 2)
    manifest["total_duration_seconds"] = total_duration_seconds

    manifest_key = f"{run_root_prefix}manifest.json"
    latest_manifest_key = f"{OUTPUT_PREFIX}/latest/manifest.json"
    latest_pointer_key = f"{OUTPUT_PREFIX}/latest/LATEST_RUN_PREFIX.txt"
    success_key = f"{run_root_prefix}_SUCCESS"

    manifest_body = json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8")

    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=manifest_key,
        Body=manifest_body,
        ContentType="application/json"
    )

    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=latest_manifest_key,
        Body=manifest_body,
        ContentType="application/json"
    )

    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=latest_pointer_key,
        Body=run_root_prefix.encode("utf-8"),
        ContentType="text/plain"
    )

    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=success_key,
        Body=b"",
        ContentType="text/plain"
    )

    print("Export completed successfully.")
    print(f"Total duration: {total_duration_seconds}s")
    print(f"Manifest: s3://{OUTPUT_BUCKET}/{manifest_key}")

except Exception as exc:
    print(f"Export failed: {str(exc)}")
    raise
