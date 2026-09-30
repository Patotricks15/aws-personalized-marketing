"""send_emails: delivers a single personalized marketing email through SES
(Call API step in the pipeline)."""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
SENDER_EMAIL = os.environ["SENDER_EMAIL"]

ses = boto3.client(
    "ses",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    to_address = event.get("to_address")
    subject = event.get("subject")
    body_text = event.get("body_text")

    if not to_address or not subject or not body_text:
        return {"statusCode": 400, "body": json.dumps({"error": "'to_address', 'subject' and 'body_text' are required."})}

    response = ses.send_email(
        Source=SENDER_EMAIL,
        Destination={"ToAddresses": [to_address]},
        Message={
            "Subject": {"Data": subject},
            "Body": {"Text": {"Data": body_text}},
        },
    )

    return {"statusCode": 200, "body": json.dumps({"message_id": response.get("MessageId"), "to": to_address})}
