#!/bin/bash
# health-check.sh

APP_URL="http://localhost:80"
WEBHOOK_URL="your-slack-webhook-url"

while true; do
    if ! curl -f $APP_URL > /dev/null 2>&1; then
        echo "Application is down! Sending alert..."
        curl -X POST -H 'Content-type: application/json' \
            --data '{"text":"🚨 React Application is DOWN!"}' \
            $WEBHOOK_URL
    fi
    sleep 60
done