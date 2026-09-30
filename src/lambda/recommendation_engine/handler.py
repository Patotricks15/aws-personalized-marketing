"""recommendation_engine: reads historical customer interactions from S3, runs a
lightweight recommendation pass, turns the output into a generation prompt (prompt
engineering), asks a Bedrock foundation model to draft a personalized marketing
email, then hands the result off to the send_emails function (Call API).
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
DATA_BUCKET = os.environ["DATA_BUCKET"]
GENERATION_MODEL_ARN = os.environ["GENERATION_MODEL_ARN"]
SEND_EMAILS_FUNCTION_NAME = os.environ["SEND_EMAILS_FUNCTION_NAME"]

ENDPOINT_URL = "http://localhost:4566"
_CLIENT_KWARGS = {
    "region_name": REGION,
    "endpoint_url": ENDPOINT_URL,
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}

s3 = boto3.client("s3", **_CLIENT_KWARGS)
bedrock_runtime = boto3.client("bedrock-runtime", **_CLIENT_KWARGS)
lambda_client = boto3.client("lambda", **_CLIENT_KWARGS)


def lambda_handler(event, context):
    customers = _load_json("customers.json")
    interactions = _load_json("historical_interactions.json")

    campaigns = []
    for customer in customers:
        recommendation = _recommend(customer, interactions)
        prompt = _build_prompt(customer, recommendation)
        email = _generate_email(prompt)

        lambda_client.invoke(
            FunctionName=SEND_EMAILS_FUNCTION_NAME,
            InvocationType="Event",
            Payload=json.dumps(
                {
                    "to_address": customer["email"],
                    "subject": email["subject"],
                    "body_text": email["body"],
                }
            ).encode("utf-8"),
        )
        campaigns.append({"customer_id": customer["customer_id"], "subject": email["subject"]})

    return {"statusCode": 200, "body": json.dumps({"campaigns_sent": len(campaigns), "details": campaigns})}


def _load_json(key):
    obj = s3.get_object(Bucket=DATA_BUCKET, Key=key)
    return json.loads(obj["Body"].read())


def _recommend(customer, interactions):
    # Recommendation engine: pick the category with the highest interaction weight for this customer.
    tally = {}
    for event in interactions:
        if event["customer_id"] != customer["customer_id"]:
            continue
        tally[event["category"]] = tally.get(event["category"], 0) + event["weight"]

    if not tally:
        return customer.get("preferences", ["new arrivals"])[0]
    return max(tally, key=tally.get)


def _build_prompt(customer, recommendation):
    # Prompt engineering: turn the recommendation output and customer metadata into a generation prompt.
    return (
        f"Write a short, friendly marketing email for {customer['name']}. "
        f"They recently showed strong interest in the '{recommendation}' category. "
        "Recommend one or two relevant products, mention a limited-time offer, and keep it under 120 words. "
        "Respond as JSON with only 'subject' and 'body' fields."
    )


def _generate_email(prompt):
    response = bedrock_runtime.invoke_model(
        modelId=GENERATION_MODEL_ARN,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 300,
                "messages": [{"role": "user", "content": prompt}],
            }
        ),
    )
    payload = json.loads(response["body"].read())
    text = payload.get("content", [{}])[0].get("text", "{}")

    try:
        parsed = json.loads(text)
        return {
            "subject": parsed.get("subject", "A special offer for you"),
            "body": parsed.get("body", text),
        }
    except json.JSONDecodeError:
        return {"subject": "A special offer for you", "body": text}
