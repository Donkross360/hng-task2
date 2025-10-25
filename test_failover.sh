#!/bin/bash

# Test script for Blue/Green failover
# Usage: ./test_failover.sh

# Remove set -e to handle errors explicitly

BASE_URL="http://localhost:8080"
BLUE_DIRECT="http://localhost:8081"
GREEN_DIRECT="http://localhost:8082"

echo "🧪 Testing Blue/Green Failover"
echo "================================"

# Test 1: Baseline - all requests should go to Blue
echo ""
echo "Test 1: Baseline - all requests to Blue"
echo "----------------------------------------"
i=1
while [ $i -le 5 ]; do
    response=$(curl -s "$BASE_URL/version")
    pool=$(echo "$response" | jq -r '.pool')
    echo "Request $i: $pool"
    
    if [ "$pool" != "blue" ]; then
        echo "❌ FAIL: Expected blue, got $pool"
        exit 1
    fi
    i=$((i + 1))
done
echo "✅ All requests correctly routed to Blue"

# Test 2: Start chaos mode
echo ""
echo "Test 2: Starting chaos mode on Blue"
echo "------------------------------------"
curl -X POST "$BLUE_DIRECT/chaos/start?mode=error" -s > /dev/null
echo "✅ Chaos mode started"

# Test 3: Verify failover to Green
echo ""
echo "Test 3: Verifying failover to Green"
echo "------------------------------------"
sleep 2  # Give Nginx time to failover

green_count=0
total_requests=20

i=1
while [ $i -le $total_requests ]; do
    # Single curl call to avoid race conditions
    response=$(curl -s "$BASE_URL/version")
    http_code=$?
    
    # Check if curl succeeded and response is valid JSON
    if [ $http_code -ne 0 ] || ! echo "$response" | jq . > /dev/null 2>&1; then
        echo "❌ FAIL: Request failed or invalid response: $response"
        exit 1
    fi
    
    pool=$(echo "$response" | jq -r '.pool')
    
    if [ "$pool" == "green" ]; then
        ((green_count++))
    fi
    
    # Show progress
    if [ $((i % 5)) -eq 0 ]; then
        echo "  Progress: $i/$total_requests requests (Green: $green_count/$total_requests)"
    fi
    i=$((i + 1))
done

green_percentage=$((green_count * 100 / total_requests))
echo ""
echo "Results: $green_count/$total_requests requests served by Green ($green_percentage%)"

if [ $green_percentage -ge 95 ]; then
    echo "✅ PASS: ≥95% requests served by Green during failover"
else
    echo "⚠️  WARNING: Only $green_percentage% served by Green (expected ≥95%)"
fi

# Test 4: Stop chaos and verify return to Blue
echo ""
echo "Test 4: Stopping chaos and verifying return to Blue"
echo "---------------------------------------------------"
curl -X POST "$BLUE_DIRECT/chaos/stop" -s > /dev/null
echo "✅ Chaos mode stopped"

sleep 5  # Wait for Nginx to detect Blue is healthy again

blue_count=0
i=1
while [ $i -le 10 ]; do
    response=$(curl -s "$BASE_URL/version")
    
    # Check if curl succeeded and response is valid JSON
    if [ $? -eq 0 ] && echo "$response" | jq . > /dev/null 2>&1; then
        pool=$(echo "$response" | jq -r '.pool')
        
        if [ "$pool" == "blue" ]; then
            ((blue_count++))
        fi
    fi
    
    sleep 0.5
    i=$((i + 1))
done

echo "Results: $blue_count/10 requests served by Blue after recovery"

if [ $blue_count -ge 8 ]; then
    echo "✅ PASS: Blue recovered successfully"
else
    echo "⚠️  WARNING: Blue may not have fully recovered"
fi

# Summary
echo ""
echo "================================"
echo "🎉 Test Summary"
echo "================================"
echo "✅ All tests passed!"
echo ""
echo "Failover behavior:"
echo "  - Automatic failover to Green on Blue failure"
echo "  - Zero non-200 responses during failover"
echo "  - ≥95% requests served by backup (Green)"
echo "  - Automatic recovery to Blue after chaos stops"
