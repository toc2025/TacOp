#!/bin/bash
# Tactical Server Health Check Script
# Monitors all services and reports status

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/tactical-health.log"
ALERT_EMAIL=""
SERVICES=("postgresql" "redis" "zerotier-controller" "location-service" "maps-service" "openmaptiles" "outline" "mattermost" "filebrowser" "nginx")
ENDPOINTS=(
    "https://localhost/health"
    "https://localhost:3000/api/v4/system/ping"
    "https://localhost:3001/health"
    "http://localhost:3002/api/health"
    "http://localhost:8080/health"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

# Check Docker service status
check_docker_service() {
    local service=$1
    local status
    
    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps "$service" | grep -q "Up"; then
        status="healthy"
        success "Service $service is running"
        return 0
    else
        status="unhealthy"
        error "Service $service is not running"
        return 1
    fi
}

# Check HTTP endpoint
check_endpoint() {
    local url=$1
    local timeout=10
    
    if curl -k -s -f --max-time "$timeout" "$url" >/dev/null 2>&1; then
        success "Endpoint $url is responding"
        return 0
    else
        error "Endpoint $url is not responding"
        return 1
    fi
}

# Check system resources
check_system_resources() {
    log "Checking system resources..."
    
    # Check memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        warning "High memory usage: ${mem_usage}%"
    else
        success "Memory usage: ${mem_usage}%"
    fi
    
    # Check disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        warning "High disk usage: ${disk_usage}%"
    else
        success "Disk usage: ${disk_usage}%"
    fi
    
    # Check load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    if (( $(echo "$load_avg > $cpu_cores" | bc -l) )); then
        warning "High load average: $load_avg (cores: $cpu_cores)"
    else
        success "Load average: $load_avg (cores: $cpu_cores)"
    fi
}

# Check ZeroTier connectivity
check_zerotier() {
    log "Checking ZeroTier connectivity..."
    
    if command -v zerotier-cli >/dev/null 2>&1; then
        local zt_status=$(zerotier-cli info 2>/dev/null | awk '{print $4}' || echo "OFFLINE")
        if [[ "$zt_status" == "ONLINE" ]]; then
            success "ZeroTier is online"
            
            # Check network membership
            local networks=$(zerotier-cli listnetworks 2>/dev/null | tail -n +2 | wc -l)
            if [[ $networks -gt 0 ]]; then
                success "ZeroTier networks joined: $networks"
            else
                warning "No ZeroTier networks joined"
            fi
        else
            error "ZeroTier is offline: $zt_status"
        fi
    else
        error "ZeroTier CLI not available"
    fi
}

# Check database connectivity
check_database() {
    log "Checking database connectivity..."
    
    cd "$SCRIPT_DIR"
    
    # Check PostgreSQL
    if docker compose exec -T postgresql pg_isready -U postgres >/dev/null 2>&1; then
        success "PostgreSQL is responding"
        
        # Check database sizes
        local db_sizes=$(docker compose exec -T postgresql psql -U postgres -t -c "
            SELECT datname, pg_size_pretty(pg_database_size(datname)) 
            FROM pg_database 
            WHERE datname IN ('tactical_location', 'tactical_maps', 'outline', 'mattermost');" 2>/dev/null)
        
        if [[ -n "$db_sizes" ]]; then
            log "Database sizes:"
            echo "$db_sizes" | while read -r line; do
                [[ -n "$line" ]] && log "  $line"
            done
        fi
    else
        error "PostgreSQL is not responding"
    fi
    
    # Check Redis
    if docker compose exec -T redis redis-cli ping >/dev/null 2>&1; then
        success "Redis is responding"
        
        # Check Redis memory usage
        local redis_memory=$(docker compose exec -T redis redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        if [[ -n "$redis_memory" ]]; then
            log "Redis memory usage: $redis_memory"
        fi
    else
        error "Redis is not responding"
    fi
}

# Generate health report
generate_report() {
    local failed_services=0
    local failed_endpoints=0
    
    log "=== Tactical Server Health Check Report ==="
    log "Timestamp: $(date)"
    log "Hostname: $(hostname)"
    log "Uptime: $(uptime -p)"
    
    # Check all Docker services
    log ""
    log "Docker Services Status:"
    for service in "${SERVICES[@]}"; do
        if ! check_docker_service "$service"; then
            ((failed_services++))
        fi
    done
    
    # Check all endpoints
    log ""
    log "Endpoint Health:"
    for endpoint in "${ENDPOINTS[@]}"; do
        if ! check_endpoint "$endpoint"; then
            ((failed_endpoints++))
        fi
    done
    
    # Check system resources
    log ""
    check_system_resources
    
    # Check ZeroTier
    log ""
    check_zerotier
    
    # Check databases
    log ""
    check_database
    
    # Summary
    log ""
    log "=== Health Check Summary ==="
    log "Failed services: $failed_services/${#SERVICES[@]}"
    log "Failed endpoints: $failed_endpoints/${#ENDPOINTS[@]}"
    
    if [[ $failed_services -eq 0 && $failed_endpoints -eq 0 ]]; then
        success "All systems operational"
        return 0
    else
        error "System issues detected"
        return 1
    fi
}

# Send alert email (if configured)
send_alert() {
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        local subject="Tactical Server Health Alert - $(hostname)"
        local body="Health check failed at $(date). Check logs at $LOG_FILE"
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
        log "Alert email sent to $ALERT_EMAIL"
    fi
}

# Restart failed services
restart_failed_services() {
    log "Attempting to restart failed services..."
    
    cd "$SCRIPT_DIR"
    
    for service in "${SERVICES[@]}"; do
        if ! docker compose ps "$service" | grep -q "Up"; then
            log "Restarting service: $service"
            docker compose restart "$service"
            sleep 10
            
            if docker compose ps "$service" | grep -q "Up"; then
                success "Service $service restarted successfully"
            else
                error "Failed to restart service $service"
            fi
        fi
    done
}

# Main execution
main() {
    # Parse command line arguments
    local auto_restart=false
    local send_alerts=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-restart)
                auto_restart=true
                shift
                ;;
            --send-alerts)
                send_alerts=true
                shift
                ;;
            --alert-email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --auto-restart    Automatically restart failed services"
                echo "  --send-alerts     Send email alerts on failures"
                echo "  --alert-email     Email address for alerts"
                echo "  --help           Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run health check
    if ! generate_report; then
        if [[ "$auto_restart" == true ]]; then
            restart_failed_services
            sleep 30
            # Re-run health check after restart
            generate_report
        fi
        
        if [[ "$send_alerts" == true ]]; then
            send_alert
        fi
        
        exit 1
    fi
    
    exit 0
}

# Run main function
main "$@"