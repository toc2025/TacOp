#!/bin/bash
# Tactical Server Continuous Monitoring Script
# Provides real-time monitoring and automatic recovery

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/tactical-monitor.log"
PID_FILE="/var/run/tactical-monitor.pid"
CHECK_INTERVAL=30
MAX_RESTART_ATTEMPTS=3
RESTART_COOLDOWN=300

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Service restart counters
declare -A restart_counts
declare -A last_restart_time

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

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if already running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            error "Monitor already running with PID $pid"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
}

# Create PID file
create_pid_file() {
    echo $$ > "$PID_FILE"
}

# Cleanup on exit
cleanup() {
    log "Stopping tactical server monitor..."
    rm -f "$PID_FILE"
    exit 0
}

# Signal handlers
trap cleanup SIGTERM SIGINT

# Check service health
check_service_health() {
    local service=$1
    
    cd "$SCRIPT_DIR"
    
    # Check if container is running
    if ! docker compose ps "$service" | grep -q "Up"; then
        return 1
    fi
    
    # Service-specific health checks
    case $service in
        "postgresql")
            docker compose exec -T postgresql pg_isready -U postgres >/dev/null 2>&1
            ;;
        "redis")
            docker compose exec -T redis redis-cli ping >/dev/null 2>&1
            ;;
        "nginx")
            curl -k -s -f --max-time 5 https://localhost/health >/dev/null 2>&1
            ;;
        "location-service")
            curl -s -f --max-time 5 http://localhost:3002/api/health >/dev/null 2>&1
            ;;
        "maps-service")
            curl -s -f --max-time 5 http://localhost:8080/health >/dev/null 2>&1
            ;;
        "mattermost")
            curl -k -s -f --max-time 5 https://localhost:3000/api/v4/system/ping >/dev/null 2>&1
            ;;
        "outline")
            curl -k -s -f --max-time 5 https://localhost:3001/health >/dev/null 2>&1
            ;;
        *)
            # Default: just check if container is running
            return 0
            ;;
    esac
}

# Restart service with cooldown and attempt limiting
restart_service() {
    local service=$1
    local current_time=$(date +%s)
    
    # Initialize counters if not set
    if [[ -z "${restart_counts[$service]:-}" ]]; then
        restart_counts[$service]=0
        last_restart_time[$service]=0
    fi
    
    # Check cooldown period
    local time_since_last=$((current_time - last_restart_time[$service]))
    if [[ $time_since_last -lt $RESTART_COOLDOWN ]]; then
        warning "Service $service in cooldown period (${time_since_last}s < ${RESTART_COOLDOWN}s)"
        return 1
    fi
    
    # Check restart attempt limit
    if [[ ${restart_counts[$service]} -ge $MAX_RESTART_ATTEMPTS ]]; then
        error "Service $service exceeded maximum restart attempts (${restart_counts[$service]})"
        return 1
    fi
    
    # Perform restart
    warning "Restarting service: $service (attempt $((restart_counts[$service] + 1))/$MAX_RESTART_ATTEMPTS)"
    
    cd "$SCRIPT_DIR"
    
    if docker compose restart "$service"; then
        restart_counts[$service]=$((restart_counts[$service] + 1))
        last_restart_time[$service]=$current_time
        
        # Wait for service to stabilize
        sleep 15
        
        # Verify restart was successful
        if check_service_health "$service"; then
            success "Service $service restarted successfully"
            return 0
        else
            error "Service $service failed to start properly after restart"
            return 1
        fi
    else
        error "Failed to restart service $service"
        return 1
    fi
}

# Reset restart counters for healthy services
reset_restart_counters() {
    local service=$1
    if [[ ${restart_counts[$service]:-0} -gt 0 ]]; then
        info "Resetting restart counter for healthy service: $service"
        restart_counts[$service]=0
    fi
}

# Monitor system resources
monitor_resources() {
    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    if (( $(echo "$mem_usage > 95" | bc -l) )); then
        error "Critical memory usage: ${mem_usage}%"
    elif (( $(echo "$mem_usage > 85" | bc -l) )); then
        warning "High memory usage: ${mem_usage}%"
    fi
    
    # Disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 95 ]]; then
        error "Critical disk usage: ${disk_usage}%"
    elif [[ $disk_usage -gt 85 ]]; then
        warning "High disk usage: ${disk_usage}%"
    fi
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    if (( $(echo "$load_avg > $(echo "$cpu_cores * 2" | bc)" | bc -l) )); then
        warning "High load average: $load_avg (cores: $cpu_cores)"
    fi
}

# Monitor Docker daemon
monitor_docker() {
    if ! systemctl is-active --quiet docker; then
        error "Docker daemon is not running"
        systemctl start docker
        sleep 10
    fi
}

# Monitor ZeroTier
monitor_zerotier() {
    if command -v zerotier-cli >/dev/null 2>&1; then
        local zt_status=$(zerotier-cli info 2>/dev/null | awk '{print $4}' || echo "OFFLINE")
        if [[ "$zt_status" != "ONLINE" ]]; then
            warning "ZeroTier is offline: $zt_status"
            systemctl restart zerotier-one
        fi
    fi
}

# Main monitoring loop
monitor_loop() {
    local services=("postgresql" "redis" "zerotier-controller" "location-service" "maps-service" "openmaptiles" "outline" "mattermost" "filebrowser" "nginx")
    local cycle=0
    
    log "Starting tactical server monitoring (PID: $$)"
    log "Check interval: ${CHECK_INTERVAL}s"
    log "Max restart attempts: $MAX_RESTART_ATTEMPTS"
    log "Restart cooldown: ${RESTART_COOLDOWN}s"
    
    while true; do
        cycle=$((cycle + 1))
        info "Monitoring cycle $cycle started"
        
        # Monitor system resources every 10 cycles (5 minutes)
        if [[ $((cycle % 10)) -eq 0 ]]; then
            monitor_resources
        fi
        
        # Monitor Docker daemon
        monitor_docker
        
        # Monitor ZeroTier every 5 cycles
        if [[ $((cycle % 5)) -eq 0 ]]; then
            monitor_zerotier
        fi
        
        # Check each service
        local failed_services=0
        for service in "${services[@]}"; do
            if check_service_health "$service"; then
                reset_restart_counters "$service"
            else
                error "Service $service health check failed"
                ((failed_services++))
                
                # Attempt restart
                if restart_service "$service"; then
                    info "Service $service recovered"
                else
                    error "Service $service recovery failed"
                fi
            fi
        done
        
        if [[ $failed_services -eq 0 ]]; then
            success "All services healthy (cycle $cycle)"
        else
            warning "Failed services in cycle $cycle: $failed_services"
        fi
        
        # Log resource usage every hour
        if [[ $((cycle % 120)) -eq 0 ]]; then
            info "System status after $cycle cycles:"
            info "  Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
            info "  Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
            info "  Load: $(uptime | awk -F'load average:' '{print $2}')"
            info "  Uptime: $(uptime -p)"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Start monitoring
start_monitor() {
    check_running
    create_pid_file
    monitor_loop
}

# Stop monitoring
stop_monitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping monitor (PID: $pid)"
            kill "$pid"
            rm -f "$PID_FILE"
            success "Monitor stopped"
        else
            warning "Monitor not running"
            rm -f "$PID_FILE"
        fi
    else
        warning "Monitor not running (no PID file)"
    fi
}

# Show status
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            success "Monitor running (PID: $pid)"
            
            # Show recent log entries
            if [[ -f "$LOG_FILE" ]]; then
                echo ""
                echo "Recent log entries:"
                tail -10 "$LOG_FILE"
            fi
        else
            error "Monitor not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        info "Monitor not running"
    fi
}

# Main function
main() {
    case "${1:-start}" in
        start)
            start_monitor
            ;;
        stop)
            stop_monitor
            ;;
        restart)
            stop_monitor
            sleep 2
            start_monitor
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status}"
            echo ""
            echo "Commands:"
            echo "  start    Start the monitoring service"
            echo "  stop     Stop the monitoring service"
            echo "  restart  Restart the monitoring service"
            echo "  status   Show monitoring service status"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"