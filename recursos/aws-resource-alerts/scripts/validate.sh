#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${root_dir}/resource-alerts-stack.yaml"

command -v python3 >/dev/null || { printf 'Falta python3.\n' >&2; exit 1; }

python3 - "$template" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
errors = []

for marker in ("AWS::SNS::Topic", "AWS::SNS::Subscription", "AWS::Lambda::Function", "AWS::IAM::Role", "AWS::Events::Rule", "AWS::Lambda::Permission"):
    if marker not in text:
        errors.append(f"falta recurso {marker}")

if text.count("Type: String") != 1 or "NotificationEmail:" not in text:
    errors.append("debe existir solamente el parametro de email NotificationEmail")
if "ScheduleExpression: rate(1 day)" not in text:
    errors.append("falta el schedule diario")
if "ZipFile:" not in text:
    errors.append("la Lambda debe estar inline con ZipFile")
if "Action: s3:*" in text or "Action: ec2:*" in text or "Action: iam:*" in text:
    errors.append("no se permiten wildcard de servicio en las policies")
if re.search(r"\b(delete|terminate|stop|put|create|update|modify)\w*", text, re.I):
    # Ignore explanatory prose inside Description/README is not scanned here; this is the template.
    # Explicit destructive AWS API names are the relevant check.
    for forbidden in ("Delete", "Terminate", "StopInstances", "DeleteBucket", "DeleteDBInstance", "PutObject", "CreateBucket"):
        if forbidden in text:
            errors.append(f"aparece API potencialmente destructiva {forbidden}")
if "sns:Publish" not in text or "Resource: !Ref ResourceAlertTopic" not in text:
    errors.append("la publicacion SNS no esta limitada al topic del stack")
for action in ("ec2:DescribeInstances", "ec2:DescribeVolumes", "elasticloadbalancing:DescribeLoadBalancers", "rds:DescribeDBInstances", "s3:ListAllMyBuckets", "ce:GetCostAndUsage", "ce:GetCostForecast"):
    if action not in text:
        errors.append(f"falta permiso de lectura {action}")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)
print("Template resource-alerts: estructura local OK")
PY

if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint "$template"
else
  printf 'Aviso: cfn-lint no esta instalado; se ejecuto la validacion estructural local.\n'
fi
