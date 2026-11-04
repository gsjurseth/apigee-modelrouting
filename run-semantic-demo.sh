#!/usr/bin/env bash
# run-semantic-demo.sh -- Execute 3 prompts of varying complexity against the Semantic Routing Gateway
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-https://api.endpoints.apigee-product-demo.cloud.goog/v1/chat/semantic-router}"

echo "======================================================================="
echo " Apigee AI Gateway: Semantic Model Routing Demo (aft-demo-semantic-router)"
echo " Classifier : gemini-2.5-flash-lite (via llm-semantic-router.yaml)"
echo " Endpoint   : ${GATEWAY_URL}"
echo "======================================================================="

labels=(
  "Route 1: Simple Q&A Prompt -> Expected: SIMPLE_QA -> Gemini 2.5 Flash (Tier-1 Economy)"
  "Route 2: Coding Prompt     -> Expected: CODING -> Anthropic Claude 3.5 Sonnet (Auto-Transcoded)"
  "Route 3: Deep Reasoning    -> Expected: COMPLEX_REASONING -> OpenAI GPT-4o (Tier-3 Frontier)"
)

prompts=(
  "What is the capital of Sweden and what currency does it use?"
  "Write a Python decorator that implements exponential backoff retry for HTTP requests."
  "Analyze the game-theoretic Nash equilibrium of a multi-region cloud spot-instance pricing auction."
)

for i in 1 2 3; do
  label="${labels[$((i-1))]}"
  prompt="${prompts[$((i-1))]}"
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "▶ ${label}"
  echo "  Client sends: model=\"auto\", prompt=\"${prompt}\""
  echo "-----------------------------------------------------------------------"
  resp="$(curl -sS -i -X POST "${GATEWAY_URL}" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"auto\", \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}]}")"

  status_line="$(echo "${resp}" | head -n 1 | tr -d '\r')"
  classifier_hdr="$(echo "${resp}" | grep -i '^x-apigee-classifier-model:' | tr -d '\r' || true)"
  intent_hdr="$(echo "${resp}" | grep -i '^x-apigee-semantic-intent:' | tr -d '\r' || true)"
  selected_hdr="$(echo "${resp}" | grep -i '^x-apigee-selected-model:' | tr -d '\r' || true)"
  cost_hdr="$(echo "${resp}" | grep -i '^x-apigee-cost-tier:' | tr -d '\r' || true)"
  body="$(echo "${resp}" | awk 'BEGIN{RS="\r\n\r\n"} NR==2{print}')"

  echo "  Status    : ${status_line}"
  [ -n "${classifier_hdr}" ] && echo "  Header    : ${classifier_hdr}"
  [ -n "${intent_hdr}" ]     && echo "  Header    : ${intent_hdr}"
  [ -n "${selected_hdr}" ]   && echo "  Header    : ${selected_hdr}"
  [ -n "${cost_hdr}" ]       && echo "  Header    : ${cost_hdr}"
  echo "  Body      :"
  echo "${body}" | python3 -m json.tool | sed 's/^/    /'
done
