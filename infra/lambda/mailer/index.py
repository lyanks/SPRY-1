import logging
from email.message import EmailMessage
from os import environ
from urllib.parse import unquote_plus

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)


def handler(event, context):
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = unquote_plus(record["s3"]["object"]["key"])
    log.info("report-mailer trigger=s3 bucket=%s key=%s", bucket, key)

    body = boto3.client("s3").get_object(Bucket=bucket, Key=key)["Body"].read()
    week = key.rsplit("/", 1)[-1].removesuffix(".csv")

    msg = EmailMessage()
    msg["Subject"] = f"Spry weekly meetings report {week}"
    msg["From"] = environ["SENDER"]
    msg["To"] = environ["RECIPIENT"]
    msg.set_content(f"Your weekly meetings report for {week} is attached.")
    msg.add_attachment(body, maintype="text", subtype="csv", filename=f"{week}.csv")

    boto3.client("sesv2").send_email(Content={"Raw": {"Data": msg.as_bytes()}})
    log.info("report-mailer sent %s to %s", key, environ["RECIPIENT"])
