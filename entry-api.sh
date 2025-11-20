#!/bin/sh -e

[ -z "$RESOLVER" ] || sed -i "s|resolver 127.0.0.11|resolver $RESOLVER|" /etc/nginx/conf.d/default.conf

# Add IP addresses to geo block for rate limit exclusion
if [ -n "$TRUSTED_IPS" ]; then
    # Split IPs by comma and add each one to geo block
    for ip in $(echo "$TRUSTED_IPS" | tr ',' ' '); do
        # Remove any whitespace
        ip=$(echo "$ip" | tr -d ' ')
        if [ -n "$ip" ]; then
            # Insert the IP before the default line in geo block
            sed -i "/default \$binary_remote_addr;/i\\        $ip \"\";" /etc/nginx/nginx.conf
        fi
    done
fi

# Replace TRUSTED_IPS placeholder in uwsgi_param with actual value
if [ -n "$TRUSTED_IPS" ]; then
    sed -i "s|TRUSTED_IPS_PLACEHOLDER|$TRUSTED_IPS|g" /etc/nginx/nginx.conf
else
    sed -i "s|TRUSTED_IPS_PLACEHOLDER||g" /etc/nginx/nginx.conf
fi

# Disable rate limiting if ENABLE_RATE_LIMIT is not set to true
if [ "$ENABLE_RATE_LIMIT" != "true" ]; then
    # Comment out limit_req_zone directive
    sed -i 's/limit_req_zone/#limit_req_zone/' /etc/nginx/nginx.conf

    # Comment out limit_req directive in server block
    sed -i 's/limit_req zone/#limit_req zone/' /etc/nginx/nginx.conf

    # Comment out limit_req_status and limit_req_log_level
    sed -i 's/limit_req_status/#limit_req_status/' /etc/nginx/nginx.conf
    sed -i 's/limit_req_log_level/#limit_req_log_level/' /etc/nginx/nginx.conf
fi

nginx -g "daemon off;"

