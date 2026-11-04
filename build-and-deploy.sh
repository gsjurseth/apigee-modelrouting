#!/usr/bin/env bash
# build-and-deploy.sh -- Import and deploy all 6 stages of the progressive AI Gateway demo using gcloud
set -euo pipefail

APIGEE_ORG="${APIGEE_ORG:-apigee-product-demo}"
APIGEE_ENV="${APIGEE_ENV:-dev-prog-proxy}"
RUNTIME_SA="${RUNTIME_SA:-apigee-runtime@${APIGEE_ORG}.iam.gserviceaccount.com}"
DEMO_DIR="$(cd "$(dirname "$0")/demo" && pwd)"
TOKEN_FILE="/tmp/adc_token.txt"

gcloud auth application-default print-access-token > "${TOKEN_FILE}"

echo "======================================================================="
echo " Importing & Deploying 6-Stage Progressive AI Gateway (${APIGEE_ORG} / ${APIGEE_ENV})"
echo "======================================================================="

STAGES=(
  "1|aft-demo-simple-01|01-single-model.yaml"
  "2|aft-demo-simple-02|02-add-vertex-gemini.yaml"
  "3|aft-demo-simple-03|03-add-anthropic-claude.yaml"
  "4|aft-demo-simple-04|04-expand-model-catalog.yaml"
  "5|aft-demo-simple-05|05-failover-gateway.yaml"
  "6|aft-demo-semantic-router|06-semantic-routing.yaml"
)

for entry in "${STAGES[@]}"; do
  IFS='|' read -r stage_num proxy_name tmpl_file <<< "${entry}"
  echo ""
  echo "▶ [Stage ${stage_num}/6] Importing ${proxy_name} from demo/${tmpl_file}..."
  import_out="$(gcloud beta apigee apis import "${proxy_name}" \
    --from-template="${DEMO_DIR}/${tmpl_file}" \
    --organization="${APIGEE_ORG}" \
    --access-token-file="${TOKEN_FILE}" \
    --format='value(revision)')"
  rev="$(echo "${import_out}" | grep -oE '[0-9]+' | tail -n1)"
  echo "  ✔ Imported ${proxy_name} revision ${rev}"

  echo "▶ [Stage ${stage_num}/6] Deploying ${proxy_name} (rev ${rev}) to ${APIGEE_ENV}..."
  gcloud beta apigee apis deploy "${rev}" \
    --api="${proxy_name}" \
    --environment="${APIGEE_ENV}" \
    --organization="${APIGEE_ORG}" \
    --service-account="${RUNTIME_SA}" \
    --override \
    --access-token-file="${TOKEN_FILE}" \
    --quiet
  echo "  ✔ Deployed ${proxy_name} revision ${rev}"
done

echo ""
echo "✔ All 6 stages imported and deployed successfully!"
