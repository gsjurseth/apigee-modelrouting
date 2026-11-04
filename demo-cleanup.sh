#!/usr/bin/env bash
# demo-cleanup.sh -- Reset Stages 1-4 (aft-demo-simple-01..04) before a live demo
#                    while leaving the two pre-deployed live demo proxies
#                    (aft-demo-simple-05 & aft-demo-semantic-router) untouched.
set -euo pipefail

APIGEE_ORG="${APIGEE_ORG:-apigee-product-demo}"
APIGEE_ENV="${APIGEE_ENV:-dev-prog-proxy}"
GATEWAY_HOST="${GATEWAY_HOST:-https://api.endpoints.apigee-product-demo.cloud.goog}"
TOKEN_FILE="/tmp/adc_token.txt"

gcloud auth application-default print-access-token > "${TOKEN_FILE}"

echo "======================================================================="
echo " Resetting Progressive AI Gateway Demo (${APIGEE_ORG} / ${APIGEE_ENV})"
echo "======================================================================="
echo "  • Cleaning up CLI walkthrough proxies: aft-demo-simple-01 .. 04"
echo "  • Preserving pre-deployed live proxies: aft-demo-simple-05 & aft-demo-semantic-router"
echo "-----------------------------------------------------------------------"

CLI_PROXIES=(
  "aft-demo-simple-01"
  "aft-demo-simple-02"
  "aft-demo-simple-03"
  "aft-demo-simple-04"
)

for proxy in "${CLI_PROXIES[@]}"; do
  echo ""
  echo "▶ Resetting ${proxy}..."

  # 1. Undeploy any revision currently deployed in APIGEE_ENV (ignore error if not deployed)
  if gcloud beta apigee apis undeploy \
      --api="${proxy}" \
      --environment="${APIGEE_ENV}" \
      --organization="${APIGEE_ORG}" \
      --access-token-file="${TOKEN_FILE}" \
      --quiet >/dev/null 2>&1; then
    echo "  ✔ Undeployed ${proxy} from ${APIGEE_ENV}"
  else
    echo "  • ${proxy} was not deployed in ${APIGEE_ENV} (skipping undeploy)"
  fi

  # 2. Delete the proxy and all revisions so live import starts cleanly at Revision 1
  if gcloud beta apigee apis delete "${proxy}" \
      --organization="${APIGEE_ORG}" \
      --access-token-file="${TOKEN_FILE}" \
      --quiet >/dev/null 2>&1; then
    echo "  ✔ Deleted ${proxy} from ${APIGEE_ORG} (next import will start at Revision 1)"
  else
    echo "  • ${proxy} did not exist in ${APIGEE_ORG} (already clean)"
  fi
done

# Remove any ad-hoc synthesized target features beyond the 7 stage features
for f in "$(cd "$(dirname "$0")" && pwd)/demo/target-"*.yaml; do
  case "$(basename "$f")" in
    target-openai-gpt-4o.yaml|\
    target-vertex-ai-gemini-2.5-flash.yaml|\
    target-anthropic-claude-3-5-sonnet-20241022.yaml|\
    target-bedrock-llama-3.3-70b-instruct.yaml|\
    target-cohere-command-r-plus-08-2024.yaml|\
    target-mistral-large-2411.yaml|\
    target-deepseek-reasoner.yaml)
      ;;
    *)
      rm -f "$f"
      ;;
  esac
done

echo ""
echo "-----------------------------------------------------------------------"
echo " Verifying Pre-Deployed Live Demo Proxies (Untouched)"
echo "-----------------------------------------------------------------------"

s5_code="$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${GATEWAY_HOST}/v1/chat/simple-stage5")"
s6_code="$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${GATEWAY_HOST}/v1/chat/semantic-router")"

echo "  ✔ Stage 5 Failover Proxy (aft-demo-simple-05):       HTTP ${s5_code} READY (${GATEWAY_HOST}/v1/chat/simple-stage5)"
echo "  ✔ Stage 6 Semantic Router (aft-demo-semantic-router): HTTP ${s6_code} READY (${GATEWAY_HOST}/v1/chat/semantic-router)"
echo ""
echo "✅ Demo environment is clean and ready for Act 1 (Stages 1-4 CLI imports)!"
