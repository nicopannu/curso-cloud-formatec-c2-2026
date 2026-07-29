#!/usr/bin/env python3
import json
import sys


def output_value(outputs, name):
    item = outputs.get(name)
    if not isinstance(item, dict) or "value" not in item:
        raise SystemExit(f"Falta output requerido: {name}")
    value = item["value"]
    if not isinstance(value, str) or not value:
        raise SystemExit(f"Output inválido: {name}")
    return value


def quote(value):
    return json.dumps(value)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Uso: render_inventory.py tf-outputs.json ansible/inventory.generated.yml")

    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        outputs = json.load(fh)

    instance_id = output_value(outputs, "instance_id")
    region = output_value(outputs, "aws_region")
    bucket = output_value(outputs, "ansible_bucket")

    inventory = "\n".join([
        "---",
        "all:",
        "  children:",
        "    banco_patacon:",
        "      hosts:",
        f"        {instance_id}:",
        f"          ansible_host: {quote(instance_id)}",
        "          ansible_connection: community.aws.aws_ssm",
        "          ansible_user: ec2-user",
        f"          ansible_aws_ssm_region: {quote(region)}",
        f"          ansible_aws_ssm_bucket_name: {quote(bucket)}",
        "          ansible_aws_ssm_s3_addressing_style: virtual",
        "",
    ])

    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        fh.write(inventory)


if __name__ == "__main__":
    main()
