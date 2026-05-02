#!/bin/bash
PORT=3838
while ss -ltn | grep -q ":$PORT "; do
  PORT=$((PORT+1))
done
echo "Chosen port is $PORT"

# Update .env
sed -i "s/^APP_PORT=.*/APP_PORT=$PORT/" /home/micu/r/.env
