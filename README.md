# Blue/Green Deployment with Nginx Upstream Auto-Failover

This project implements a Blue/Green deployment pattern with automatic failover using Nginx upstream configuration.

## Architecture

- **Nginx** (port 8080): Main entry point for all requests
- **Blue App** (port 8081): Primary application instance
- **Green App** (port 8082): Backup application instance
- **Failover**: Automatic switching from Blue to Green on failure

## Environment Variables

Create a `.env` file with the following variables:

```bash
# Container Images (pre-built images, no builds)
BLUE_IMAGE=your-registry/blue-green-app:blue
GREEN_IMAGE=your-registry/blue-green-app:green

# Active Pool (controls which pool is primary in Nginx)
ACTIVE_POOL=blue

# Release IDs
RELEASE_ID_BLUE=release-v1.0.0-blue
RELEASE_ID_GREEN=release-v1.0.0-green

# Optional: Application Port (defaults to 3000)
PORT=3000
```

## Features

### 1. Automatic Failover
- **Primary/Backup Pattern**: Blue active, Green backup (or vice versa)
- **Health-based**: `max_fails=1` + `fail_timeout=3s` for quick detection
- **Request Retry**: On timeout or 5xx errors, retry to backup server
- **Zero Failed Requests**: Client sees successful 200 response

### 2. Headers
All responses include:
- `X-App-Pool`: The pool serving the request (blue/green)
- `X-Release-Id`: The release identifier for the pool

### 3. Timeouts
- `proxy_connect_timeout`: 1s
- `proxy_send_timeout`: 3s
- `proxy_read_timeout`: 3s
- Requests complete within 10s maximum

### 4. Endpoints

#### Main Service (via Nginx)
- `GET http://localhost:8080/` - Deployment status and pool info
- `GET http://localhost:8080/version` - Application info with headers
- `GET http://localhost:8080/healthz` - Load balancer health check

#### Direct Access (for chaos testing)
- `GET http://localhost:8081/version` - Blue app directly
- `GET http://localhost:8082/version` - Green app directly
- `POST http://localhost:8081/chaos/start?mode=error` - Trigger 500 errors on Blue
- `POST http://localhost:8081/chaos/start?mode=timeout` - Trigger timeouts on Blue
- `POST http://localhost:8081/chaos/stop` - Stop chaos mode

#### Chaos Modes
- `mode=error`: Returns 500 status codes
- `mode=timeout`: Simulates timeouts (no response)
- Default: `mode=error` if not specified

## Usage

### Start Services
```bash
docker-compose up -d
```

### Check Status
```bash
docker-compose ps
curl http://localhost:8080/version
```

### Test Failover

1. **Baseline Test** (all requests go to Blue):
```bash
curl http://localhost:8080/version
# Should show: X-App-Pool: blue
```

2. **Induce Failure on Blue**:
```bash
curl -X POST http://localhost:8081/chaos/start?mode=error
```

3. **Verify Failover** (next request should go to Green):
```bash
curl http://localhost:8080/version
# Should show: X-App-Pool: green
```

4. **Stop Chaos**:
```bash
curl -X POST http://localhost:8081/chaos/stop
```

### Automated Testing

Run multiple requests to verify 0 failures during failover:
```bash
# Start chaos
curl -X POST http://localhost:8081/chaos/start?mode=error

# Make 100 requests
for i in {1..100}; do
  curl -s http://localhost:8080/version | jq '.pool'
done

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

Expected: All 100 requests return successfully (200), ≥95% should be from green.

## Configuration Details

### Nginx Upstream Configuration
```nginx
upstream blue_pool {
    server app-blue:3000 max_fails=1 fail_timeout=3s;
    server app-green:3000 backup;
}
```

- `max_fails=1`: Mark server down after 1 failed request
- `fail_timeout=3s`: Keep server down for 3 seconds
- `backup`: Only use if primary fails

### Retry Logic
```nginx
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
proxy_next_upstream_tries 2;
proxy_next_upstream_timeout 10s;
```

- Retry on errors, timeouts, or 5xx responses
- Try up to 2 upstreams (primary + backup)
- Complete within 10 seconds

## Files

- `docker-compose.yaml`: Service orchestration
- `nginx.conf.template`: Nginx configuration with env substitution
- `.env`: Environment variables (not committed, use `.env.example`)
- `app.js`: Node.js application
- `Dockerfile`: Application container build

## Troubleshooting

### Check Logs
```bash
docker-compose logs nginx
docker-compose logs app-blue
docker-compose logs app-green
```

### Verify Nginx Config
```bash
docker exec nginx-lb cat /etc/nginx/nginx.conf
```

### Manual Pool Switch
Edit `.env` and change `ACTIVE_POOL=green`, then restart:
```bash
docker-compose down
docker-compose up -d
```

## Constraints Met

✅ Docker Compose orchestration (no K8s/Swarm)  
✅ Nginx templated from ACTIVE_POOL  
✅ Blue/Green on 8081/8082 for chaos testing  
✅ No image builds (uses pre-built images)  
✅ All traffic through Nginx main endpoint  
✅ Zero failed requests during failover  
✅ Requests complete within 10s  
✅ Headers forwarded unchanged  
