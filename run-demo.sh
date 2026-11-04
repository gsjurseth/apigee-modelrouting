#!/usr/bin/env bash
# run-demo.sh -- Execute the 3 live failover requests against Stage 5 (aft-demo-simple-05)
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-https://api.endpoints.apigee-product-demo.cloud.goog/v1/chat/simple-stage5}"
CLIENT_ID="demo-$(date +%s)"

echo "======================================================================="
echo " Apigee AI Gateway Live Failover Verification (Stage 5: aft-demo-simple-05)"
echo " Endpoint : ${GATEWAY_URL}"
echo " Client ID: ${CLIENT_ID} (Quota: 2 requests / minute on Primary GPT-4o)"
echo "======================================================================="

prompts=(
  "Explain progressive delivery in software architecture."
  "What is the primary benefit of canary deployments?"
  "Explain how automated failover guarantees client uptime when rate limits trip."
)

for i in 1 2 3; do
  prompt="${prompts[$((i-1))]}"
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "▶ Call ${i}/3: Sending OpenAI Chat Completion request (model: gpt-4o)"
  echo "  Prompt: \"${prompt}\""
  echo "-----------------------------------------------------------------------"
  resp="$(curl -sS -i -X POST "${GATEWAY_URL}" \
    -H "Content-Type: application/json" \
    -H "x-demo-client-id: ${CLIENT_ID}" \
    -d "{\"model\": \"gpt-4o\", \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}]}")"

  status_line="$(echo "${resp}" | head -n 1 | tr -d '\r')"
  apigee_model="$(echo "${resp}" | grep -i '^x-apigee-model:' | tr -d '\r' || true)"
  apigee_fallback="$(echo "${resp}" | grep -i '^x-apigee-fallback:' | tr -d '\r' || true)"
  apigee_transcoded="$(echo "${resp}" | grep -i '^x-apigee-transcoded:' | tr -d '\r' || true)"
  body="$(echo "${resp}" | awk 'BEGIN{RS="\r\n\r\n"} NR==2{print}')"

  echo "  Status    : ${status_line}"
  [ -n "${apigee_model}" ] && echo "  Header    : ${apigee_model}"
  [ -n "${apigee_fallback}" ] && echo "  Header    : ${apigee_fallback}"
  [ -n "${apigee_transcoded}" ] && echo "  Header    : ${apigee_transcoded}"
  echo "  Body      :"
  echo "${body}" | python3 -m json.tool | sed 's/^/    /'
done
