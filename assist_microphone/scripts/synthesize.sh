#!/usr/bin/env bash

###
# This script is used to send text to a Home Assistant webhook.
#
# It is intended to be used within the context of a wyoming-satellite
# --synthesize-command when text-to-speech text is returned on stdin.
#
# Author: https://github.com/AlfredJKwack
###

set -e

# Take text on stdin and JSON-encode it
text="$(cat | jq -R -s '.')"

# Set the default webhook name if not set in the configuration
if bashio::var.has_value "$(bashio::config 'webhook_id')"; then
  webhook_id="$(bashio::config 'webhook_id')"
else
  bashio::log.warning  "webhook_id is not set. Will set to default"
  webhook_id="synthesize-assist-microphone-response"
fi
bashio::log.debug  "webhook_id is set to : $(bashio::config 'webhook_id')"

# Check if SUPERVISOR_TOKEN is set
if [ -z "$SUPERVISOR_TOKEN" ]; then
    bashio::log.error "SUPERVISOR_TOKEN is not set. Exiting."
    exit 1
fi

# Get the IPv4 address from the first Home Assistant interface
ha_ip=$(curl -s -X GET \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    http://supervisor/network/info \
  | jq -r '.data.interfaces[0].ipv4.address[0]' \
  | cut -d'/' -f1)
if [ -z "$ha_ip" ]; then
  bashio::log.error "Failed to get Home Assistant IPv4 address."
  exit 1
fi  
bashio::log.debug  "Home Assistant IPv4 : $ha_ip"

# Determine if the HA host has SSL enabled.
ssl_enabled=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  http://supervisor/homeassistant/info \
  | jq -r '.data.ssl')
if [ -z "$ssl_enabled" ]; then
  bashio::log.error "Failed to determine if SSL is enabled."
  exit 1
fi  
bashio::log.debug "Home Assistant SSL enabled : $ssl_enabled"

# Construct webhook URL based on SSL state, IP and webhook
if [[ "$ssl_enabled" == "true" ]]; then
  webhookurl="https://${ha_ip}:8123/api/webhook/${webhook_id}"
else
  webhookurl="http://${ha_ip}:8123/api/webhook/${webhook_id}"
fi
bashio::log.debug  "webhookurl set to : $webhookurl"

# Send the text to the Home Assistant Webhook.
bashio::log.debug "Text to speech text: ${text} to $webhookurl"
json_payload="{\"response\": ${text}}"
bashio::log.debug "Payload: ${json_payload}"
response=$(curl -s -o /dev/null -w "%{http_code}" -k -X POST \
  -H "Content-Type: application/json" \
  -d "$json_payload" \
  "${webhookurl}")
if [ "$response" -ne 200 ]; then
  bashio::log.error "Failed to send text to webhook. HTTP status code: $response"
  exit 1
fi
bashio::log.debug "Successfully sent text to webhook."