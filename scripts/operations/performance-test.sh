#!/bin/bash
# Blue-Green Deployment Performance Testing Script
# 배포 후 성능 검증을 위한 종합적인 테스트 스크립트

set -euo pipefail

# 색상 정의
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 기본 설정
readonly ALB_DNS_NAME="${ALB_DNS_NAME:-localhost}"
readonly BASE_URL="http://${ALB_DNS_NAME}"
readonly REPORT_FILE="/tmp/performance-test-report-$(date +%Y%m%d_%H%M%S).json"
readonly LOG_FILE="/tmp/performance-test-$(date +%Y%m%d_%H%M%S).log"

# 테스트 설정
CONCURRENT_USERS=${CONCURRENT_USERS:-10}
TEST_DURATION=${TEST_DURATION:-60}
RAMP_UP_TIME=${RAMP_UP_TIME:-30}
REQUEST_TIMEOUT=${REQUEST_TIMEOUT:-30}
THINK_TIME=${THINK_TIME:-1}

# 성능 임계값
MAX_RESPONSE_TIME=${MAX_RESPONSE_TIME:-2000}   # milliseconds
MAX_95TH_PERCENTILE=${MAX_95TH_PERCENTILE:-3000}
MAX_ERROR_RATE=${MAX_ERROR_RATE:-5}            # percentage
MIN_THROUGHPUT=${MIN_THROUGHPUT:-50}           # requests per second

# 테스트 결과 변수
declare -A TEST_RESULTS
declare -A ENDPOINTS

# 테스트할 엔드포인트 정의
ENDPOINTS=(
    ["health"]="/health"
    ["health-deep"]="/health/deep" 
    ["home"]="/"
    ["version"]="/version"
    ["deployment"]="/deployment"
)

# 로깅 함수
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

# 시스템 사전 요구사항 확인
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # 필수 도구 확인
    for tool in curl apache2-utils bc jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools:"
        log_info "Ubuntu/Debian: sudo apt-get install curl apache2-utils bc jq"
        log_info "CentOS/RHEL: sudo yum install curl httpd-tools bc jq"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# 기본 연결성 테스트
test_connectivity() {
    log_info "Testing basic connectivity to $BASE_URL..."
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 --max-time 30 \
        "${BASE_URL}/health" || echo "000")
    
    if [[ "$http_code" == "200" ]]; then
        log_success "Basic connectivity test passed (HTTP $http_code)"
        return 0
    else
        log_error "Basic connectivity test failed (HTTP $http_code)"
        return 1
    fi
}

# 단일 엔드포인트 성능 테스트
test_endpoint_performance() {
    local endpoint_name="$1"
    local endpoint_path="$2"
    local url="${BASE_URL}${endpoint_path}"
    
    log_info "Testing endpoint performance: $endpoint_name ($endpoint_path)"
    
    # Apache Bench를 사용한 성능 테스트
    local ab_output
    ab_output=$(ab -n 100 -c 10 -g /dev/null -q "$url" 2>&1 || echo "ERROR")
    
    if [[ "$ab_output" == "ERROR" ]]; then
        log_error "Performance test failed for $endpoint_name"
        TEST_RESULTS["${endpoint_name}_status"]="FAILED"
        return 1
    fi
    
    # 결과 파싱
    local mean_time=$(echo "$ab_output" | grep "Time per request" | head -1 | awk '{print $4}')
    local requests_per_sec=$(echo "$ab_output" | grep "Requests per second" | awk '{print $4}')
    local time_per_request_concurrent=$(echo "$ab_output" | grep "Time per request" | tail -1 | awk '{print $4}')
    local failed_requests=$(echo "$ab_output" | grep "Failed requests" | awk '{print $3}')
    
    # 결과 저장
    TEST_RESULTS["${endpoint_name}_mean_time"]=$mean_time
    TEST_RESULTS["${endpoint_name}_rps"]=$requests_per_sec
    TEST_RESULTS["${endpoint_name}_concurrent_time"]=$time_per_request_concurrent
    TEST_RESULTS["${endpoint_name}_failed"]=$failed_requests
    TEST_RESULTS["${endpoint_name}_status"]="PASSED"
    
    log_success "Endpoint $endpoint_name: ${mean_time}ms avg, ${requests_per_sec} RPS, ${failed_requests} failures"
}

# 부하 테스트 실행
run_load_test() {
    log_info "Starting load test..."
    log_info "Configuration:"
    log_info "  - Concurrent Users: $CONCURRENT_USERS"
    log_info "  - Duration: ${TEST_DURATION}s"
    log_info "  - Ramp-up: ${RAMP_UP_TIME}s"
    
    # Apache Bench를 사용한 부하 테스트
    local total_requests=$((CONCURRENT_USERS * TEST_DURATION / THINK_TIME))
    local ab_output
    
    ab_output=$(ab -n "$total_requests" -c "$CONCURRENT_USERS" -t "$TEST_DURATION" \
        -g "/tmp/ab_results.tsv" "${BASE_URL}/" 2>&1 || echo "ERROR")
    
    if [[ "$ab_output" == "ERROR" ]]; then
        log_error "Load test failed"
        TEST_RESULTS["load_test_status"]="FAILED"
        return 1
    fi
    
    # 결과 파싱
    local total_requests_completed=$(echo "$ab_output" | grep "Complete requests" | awk '{print $3}')
    local failed_requests=$(echo "$ab_output" | grep "Failed requests" | awk '{print $3}')
    local mean_time=$(echo "$ab_output" | grep "Time per request" | head -1 | awk '{print $4}')
    local requests_per_sec=$(echo "$ab_output" | grep "Requests per second" | awk '{print $4}')
    local p50_time=$(echo "$ab_output" | grep "50%" | awk '{print $2}')
    local p95_time=$(echo "$ab_output" | grep "95%" | awk '{print $2}')
    local p99_time=$(echo "$ab_output" | grep "99%" | awk '{print $2}')
    
    # 오류율 계산
    local error_rate=0
    if [[ "$total_requests_completed" -gt 0 ]]; then
        error_rate=$(bc -l <<< "scale=2; $failed_requests * 100 / $total_requests_completed")
    fi
    
    # 결과 저장
    TEST_RESULTS["total_requests"]=$total_requests_completed
    TEST_RESULTS["failed_requests"]=$failed_requests
    TEST_RESULTS["error_rate"]=$error_rate
    TEST_RESULTS["mean_time"]=$mean_time
    TEST_RESULTS["requests_per_sec"]=$requests_per_sec
    TEST_RESULTS["p50_time"]=$p50_time
    TEST_RESULTS["p95_time"]=$p95_time
    TEST_RESULTS["p99_time"]=$p99_time
    TEST_RESULTS["load_test_status"]="PASSED"
    
    log_success "Load test completed:"
    log_info "  - Total requests: $total_requests_completed"
    log_info "  - Failed requests: $failed_requests"
    log_info "  - Error rate: ${error_rate}%"
    log_info "  - Mean response time: ${mean_time}ms"
    log_info "  - Requests per second: $requests_per_sec"
    log_info "  - 95th percentile: ${p95_time}ms"
}

# Curl을 사용한 상세 성능 분석
analyze_response_times() {
    log_info "Analyzing detailed response times..."
    
    local test_url="${BASE_URL}/"
    local curl_format='{\
"time_namelookup": %{time_namelookup},\
"time_connect": %{time_connect},\
"time_appconnect": %{time_appconnect},\
"time_pretransfer": %{time_pretransfer},\
"time_redirect": %{time_redirect},\
"time_starttransfer": %{time_starttransfer},\
"time_total": %{time_total},\
"speed_download": %{speed_download},\
"speed_upload": %{speed_upload}\
}'
    
    local curl_result
    curl_result=$(curl -s -w "$curl_format" -o /dev/null "$test_url" || echo '{}')
    
    # JSON 결과를 변수에 저장
    TEST_RESULTS["dns_lookup"]=$(echo "$curl_result" | jq -r '.time_namelookup // "0"' | awk '{printf "%.0f", $1*1000}')
    TEST_RESULTS["tcp_connect"]=$(echo "$curl_result" | jq -r '.time_connect // "0"' | awk '{printf "%.0f", $1*1000}')
    TEST_RESULTS["ssl_handshake"]=$(echo "$curl_result" | jq -r '.time_appconnect // "0"' | awk '{printf "%.0f", $1*1000}')
    TEST_RESULTS["server_processing"]=$(echo "$curl_result" | jq -r '.time_starttransfer // "0"' | awk '{printf "%.0f", $1*1000}')
    TEST_RESULTS["content_transfer"]=$(echo "$curl_result" | jq -r '.time_total // "0"' | awk '{printf "%.0f", $1*1000}')
    TEST_RESULTS["download_speed"]=$(echo "$curl_result" | jq -r '.speed_download // "0"')
    
    log_info "Response time breakdown:"
    log_info "  - DNS lookup: ${TEST_RESULTS[dns_lookup]}ms"
    log_info "  - TCP connect: ${TEST_RESULTS[tcp_connect]}ms" 
    log_info "  - SSL handshake: ${TEST_RESULTS[ssl_handshake]}ms"
    log_info "  - Server processing: ${TEST_RESULTS[server_processing]}ms"
    log_info "  - Content transfer: ${TEST_RESULTS[content_transfer]}ms"
    log_info "  - Download speed: ${TEST_RESULTS[download_speed]} bytes/sec"
}

# 동시 연결 테스트
test_concurrent_connections() {
    log_info "Testing concurrent connections..."
    
    local concurrent_pids=()
    local results=()
    
    # 동시 요청 실행
    for i in $(seq 1 "$CONCURRENT_USERS"); do
        {
            local start_time=$(date +%s.%N)
            local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --connect-timeout 10 --max-time 30 "${BASE_URL}/")
            local end_time=$(date +%s.%N)
            local duration=$(bc <<< "scale=3; $end_time - $start_time")
            echo "${http_code}:${duration}" > "/tmp/concurrent_result_$i"
        } &
        concurrent_pids+=($!)
    done
    
    # 모든 요청 완료 대기
    for pid in "${concurrent_pids[@]}"; do
        wait "$pid"
    done
    
    # 결과 수집
    local successful_requests=0
    local failed_requests=0
    local total_time=0
    
    for i in $(seq 1 "$CONCURRENT_USERS"); do
        if [[ -f "/tmp/concurrent_result_$i" ]]; then
            local result=$(cat "/tmp/concurrent_result_$i")
            local http_code=$(echo "$result" | cut -d':' -f1)
            local duration=$(echo "$result" | cut -d':' -f2)
            
            if [[ "$http_code" == "200" ]]; then
                ((successful_requests++))
                total_time=$(bc <<< "scale=3; $total_time + $duration")
            else
                ((failed_requests++))
            fi
            
            rm -f "/tmp/concurrent_result_$i"
        fi
    done
    
    local avg_concurrent_time=0
    if [[ "$successful_requests" -gt 0 ]]; then
        avg_concurrent_time=$(bc <<< "scale=3; $total_time / $successful_requests * 1000")
    fi
    
    TEST_RESULTS["concurrent_successful"]=$successful_requests
    TEST_RESULTS["concurrent_failed"]=$failed_requests
    TEST_RESULTS["concurrent_avg_time"]=$avg_concurrent_time
    
    log_info "Concurrent connections test:"
    log_info "  - Successful: $successful_requests"
    log_info "  - Failed: $failed_requests"
    log_info "  - Average time: ${avg_concurrent_time}ms"
}

# 성능 기준 검증
validate_performance_criteria() {
    log_info "Validating performance criteria..."
    
    local validation_passed=true
    local issues=()
    
    # 평균 응답 시간 검증
    local mean_time_ms=$(bc <<< "scale=0; ${TEST_RESULTS[mean_time]:-0}")
    if (( mean_time_ms > MAX_RESPONSE_TIME )); then
        validation_passed=false
        issues+=("Average response time (${mean_time_ms}ms) exceeds threshold (${MAX_RESPONSE_TIME}ms)")
    fi
    
    # 95th percentile 검증
    local p95_time_ms=$(bc <<< "scale=0; ${TEST_RESULTS[p95_time]:-0}")
    if (( p95_time_ms > MAX_95TH_PERCENTILE )); then
        validation_passed=false
        issues+=("95th percentile (${p95_time_ms}ms) exceeds threshold (${MAX_95TH_PERCENTILE}ms)")
    fi
    
    # 오류율 검증
    local error_rate=${TEST_RESULTS[error_rate]:-0}
    if (( $(echo "$error_rate > $MAX_ERROR_RATE" | bc -l) )); then
        validation_passed=false
        issues+=("Error rate (${error_rate}%) exceeds threshold (${MAX_ERROR_RATE}%)")
    fi
    
    # 처리량 검증
    local throughput=${TEST_RESULTS[requests_per_sec]:-0}
    if (( $(echo "$throughput < $MIN_THROUGHPUT" | bc -l) )); then
        validation_passed=false
        issues+=("Throughput (${throughput} RPS) below threshold (${MIN_THROUGHPUT} RPS)")
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "All performance criteria passed"
        TEST_RESULTS["validation_status"]="PASSED"
    else
        log_error "Performance validation failed:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        TEST_RESULTS["validation_status"]="FAILED"
        TEST_RESULTS["validation_issues"]="${issues[*]}"
    fi
    
    return $([ "$validation_passed" == "true" ])
}

# JSON 보고서 생성
generate_json_report() {
    log_info "Generating performance test report..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)
    
    cat > "$REPORT_FILE" << EOF
{
  "metadata": {
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "target_url": "$BASE_URL",
    "test_configuration": {
      "concurrent_users": $CONCURRENT_USERS,
      "test_duration": $TEST_DURATION,
      "ramp_up_time": $RAMP_UP_TIME,
      "request_timeout": $REQUEST_TIMEOUT
    },
    "thresholds": {
      "max_response_time_ms": $MAX_RESPONSE_TIME,
      "max_95th_percentile_ms": $MAX_95TH_PERCENTILE,
      "max_error_rate_percent": $MAX_ERROR_RATE,
      "min_throughput_rps": $MIN_THROUGHPUT
    }
  },
  "results": {
    "load_test": {
      "total_requests": ${TEST_RESULTS[total_requests]:-0},
      "failed_requests": ${TEST_RESULTS[failed_requests]:-0},
      "error_rate_percent": ${TEST_RESULTS[error_rate]:-0},
      "mean_response_time_ms": ${TEST_RESULTS[mean_time]:-0},
      "requests_per_second": ${TEST_RESULTS[requests_per_sec]:-0},
      "percentiles_ms": {
        "50th": ${TEST_RESULTS[p50_time]:-0},
        "95th": ${TEST_RESULTS[p95_time]:-0},
        "99th": ${TEST_RESULTS[p99_time]:-0}
      }
    },
    "response_time_breakdown_ms": {
      "dns_lookup": ${TEST_RESULTS[dns_lookup]:-0},
      "tcp_connect": ${TEST_RESULTS[tcp_connect]:-0},
      "ssl_handshake": ${TEST_RESULTS[ssl_handshake]:-0},
      "server_processing": ${TEST_RESULTS[server_processing]:-0},
      "content_transfer": ${TEST_RESULTS[content_transfer]:-0}
    },
    "concurrent_test": {
      "successful_requests": ${TEST_RESULTS[concurrent_successful]:-0},
      "failed_requests": ${TEST_RESULTS[concurrent_failed]:-0},
      "average_time_ms": ${TEST_RESULTS[concurrent_avg_time]:-0}
    },
    "validation": {
      "status": "${TEST_RESULTS[validation_status]:-UNKNOWN}",
      "issues": "${TEST_RESULTS[validation_issues]:-}"
    }
  }
}
EOF
    
    log_success "Report generated: $REPORT_FILE"
}

# HTML 보고서 생성
generate_html_report() {
    local html_file="${REPORT_FILE%.json}.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Blue-Green Deployment Performance Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 20px; margin-bottom: 30px; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #007bff; border-left: 4px solid #007bff; padding-left: 10px; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }
        .metric-card { background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; }
        .metric-card.warning { border-left-color: #ffc107; }
        .metric-card.danger { border-left-color: #dc3545; }
        .metric-label { font-weight: bold; color: #555; }
        .metric-value { font-size: 1.2em; color: #333; }
        .status-passed { color: #28a745; font-weight: bold; }
        .status-failed { color: #dc3545; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #007bff; color: white; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Blue-Green Deployment Performance Test Report</h1>
            <p>Generated on: <span id="timestamp"></span></p>
            <p>Target: <span id="target_url"></span></p>
        </div>

        <div class="section">
            <h2>📊 Test Summary</h2>
            <div class="metric-grid">
                <div class="metric-card">
                    <div class="metric-label">Total Requests</div>
                    <div class="metric-value" id="total_requests">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Success Rate</div>
                    <div class="metric-value" id="success_rate">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Average Response Time</div>
                    <div class="metric-value" id="avg_response_time">- ms</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Throughput</div>
                    <div class="metric-value" id="throughput">- RPS</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>⏱️ Response Time Analysis</h2>
            <table>
                <thead>
                    <tr>
                        <th>Percentile</th>
                        <th>Response Time (ms)</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>50th (Median)</td>
                        <td id="p50">-</td>
                        <td id="p50_status">-</td>
                    </tr>
                    <tr>
                        <td>95th</td>
                        <td id="p95">-</td>
                        <td id="p95_status">-</td>
                    </tr>
                    <tr>
                        <td>99th</td>
                        <td id="p99">-</td>
                        <td id="p99_status">-</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>🔍 Response Time Breakdown</h2>
            <div class="metric-grid">
                <div class="metric-card">
                    <div class="metric-label">DNS Lookup</div>
                    <div class="metric-value" id="dns_lookup">- ms</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">TCP Connect</div>
                    <div class="metric-value" id="tcp_connect">- ms</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">SSL Handshake</div>
                    <div class="metric-value" id="ssl_handshake">- ms</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Server Processing</div>
                    <div class="metric-value" id="server_processing">- ms</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>✅ Validation Results</h2>
            <div class="metric-card" id="validation_card">
                <div class="metric-label">Overall Status</div>
                <div class="metric-value" id="validation_status">-</div>
                <div id="validation_issues" style="margin-top: 10px;"></div>
            </div>
        </div>

        <div class="footer">
            <p>Blue-Green Deployment Performance Testing Tool</p>
            <p>Report generated automatically after deployment validation</p>
        </div>
    </div>

    <script>
        // JSON 데이터를 여기에 삽입
        const reportData = JSON_DATA_PLACEHOLDER;
        
        // 데이터로 HTML 업데이트
        document.getElementById('timestamp').textContent = reportData.metadata.timestamp;
        document.getElementById('target_url').textContent = reportData.metadata.target_url;
        document.getElementById('total_requests').textContent = reportData.results.load_test.total_requests.toLocaleString();
        document.getElementById('success_rate').textContent = ((reportData.results.load_test.total_requests - reportData.results.load_test.failed_requests) / reportData.results.load_test.total_requests * 100).toFixed(1) + '%';
        document.getElementById('avg_response_time').textContent = reportData.results.load_test.mean_response_time_ms.toFixed(1) + ' ms';
        document.getElementById('throughput').textContent = reportData.results.load_test.requests_per_second.toFixed(1) + ' RPS';
        
        // 응답 시간 분석
        document.getElementById('p50').textContent = reportData.results.load_test.percentiles_ms['50th'] + ' ms';
        document.getElementById('p95').textContent = reportData.results.load_test.percentiles_ms['95th'] + ' ms';
        document.getElementById('p99').textContent = reportData.results.load_test.percentiles_ms['99th'] + ' ms';
        
        // 상태 표시
        const p95Status = reportData.results.load_test.percentiles_ms['95th'] <= reportData.metadata.thresholds.max_95th_percentile_ms ? 'PASSED' : 'FAILED';
        document.getElementById('p95_status').innerHTML = '<span class="status-' + (p95Status === 'PASSED' ? 'passed' : 'failed') + '">' + p95Status + '</span>';
        
        // 응답 시간 분석
        document.getElementById('dns_lookup').textContent = reportData.results.response_time_breakdown_ms.dns_lookup + ' ms';
        document.getElementById('tcp_connect').textContent = reportData.results.response_time_breakdown_ms.tcp_connect + ' ms';
        document.getElementById('ssl_handshake').textContent = reportData.results.response_time_breakdown_ms.ssl_handshake + ' ms';
        document.getElementById('server_processing').textContent = reportData.results.response_time_breakdown_ms.server_processing + ' ms';
        
        // 검증 결과
        const validationStatus = reportData.results.validation.status;
        document.getElementById('validation_status').innerHTML = '<span class="status-' + (validationStatus === 'PASSED' ? 'passed' : 'failed') + '">' + validationStatus + '</span>';
        
        if (validationStatus === 'FAILED' && reportData.results.validation.issues) {
            document.getElementById('validation_issues').innerHTML = '<strong>Issues:</strong><ul><li>' + reportData.results.validation.issues.split(',').join('</li><li>') + '</li></ul>';
        }
        
        // 카드 색상 설정
        const validationCard = document.getElementById('validation_card');
        if (validationStatus === 'PASSED') {
            validationCard.style.borderLeftColor = '#28a745';
        } else {
            validationCard.style.borderLeftColor = '#dc3545';
        }
    </script>
</body>
</html>
EOF
    
    # JSON 데이터를 HTML에 삽입
    local json_data=$(cat "$REPORT_FILE")
    sed -i "s/JSON_DATA_PLACEHOLDER/${json_data}/g" "$html_file" 2>/dev/null || \
    sed -i '' "s/JSON_DATA_PLACEHOLDER/${json_data}/g" "$html_file"
    
    log_success "HTML report generated: $html_file"
}

# 결과 요약 출력
show_summary() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}           PERFORMANCE TEST SUMMARY${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    
    echo -e "${BLUE}Test Configuration:${NC}"
    echo "├── Target URL: $BASE_URL"
    echo "├── Concurrent Users: $CONCURRENT_USERS"
    echo "├── Test Duration: ${TEST_DURATION}s"
    echo "└── Total Requests: ${TEST_RESULTS[total_requests]:-N/A}"
    echo ""
    
    echo -e "${BLUE}Key Metrics:${NC}"
    echo "├── Success Rate: $(bc <<< "scale=1; (${TEST_RESULTS[total_requests]:-0} - ${TEST_RESULTS[failed_requests]:-0}) * 100 / ${TEST_RESULTS[total_requests]:-1}")%"
    echo "├── Average Response Time: ${TEST_RESULTS[mean_time]:-N/A}ms"
    echo "├── 95th Percentile: ${TEST_RESULTS[p95_time]:-N/A}ms"
    echo "├── Throughput: ${TEST_RESULTS[requests_per_sec]:-N/A} RPS"
    echo "└── Error Rate: ${TEST_RESULTS[error_rate]:-N/A}%"
    echo ""
    
    echo -e "${BLUE}Validation Result:${NC}"
    local validation_status="${TEST_RESULTS[validation_status]:-UNKNOWN}"
    if [[ "$validation_status" == "PASSED" ]]; then
        echo -e "└── ${GREEN}✅ PASSED${NC} - All performance criteria met"
    else
        echo -e "└── ${RED}❌ FAILED${NC} - Performance criteria not met"
    fi
    echo ""
    
    echo -e "${BLUE}Reports Generated:${NC}"
    echo "├── JSON Report: $REPORT_FILE"
    echo "├── HTML Report: ${REPORT_FILE%.json}.html"
    echo "└── Log File: $LOG_FILE"
    echo ""
    
    echo -e "${CYAN}================================================================${NC}"
}

# 도움말 표시
show_help() {
    cat << EOF
Blue-Green Deployment Performance Testing Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --alb-dns-name NAME           ALB DNS name to test (default: localhost)
    --concurrent-users NUM        Number of concurrent users (default: 10)
    --test-duration SECONDS       Test duration in seconds (default: 60)
    --ramp-up-time SECONDS        Ramp-up time in seconds (default: 30)
    --max-response-time MS        Maximum allowed response time (default: 2000)
    --max-95th-percentile MS      Maximum allowed 95th percentile (default: 3000)
    --max-error-rate PERCENT      Maximum allowed error rate (default: 5)
    --min-throughput RPS          Minimum required throughput (default: 50)
    --output-dir DIR              Output directory for reports
    --help                        Show this help message

EXAMPLES:
    $0                                           # Basic test
    $0 --concurrent-users 20 --test-duration 120 # Extended test
    $0 --alb-dns-name my-alb.elb.amazonaws.com   # Specific target
    $0 --max-response-time 1000 --min-throughput 100 # Custom thresholds

DESCRIPTION:
    Performs comprehensive performance testing including:
    - Basic connectivity testing
    - Individual endpoint performance
    - Load testing with configurable parameters
    - Response time breakdown analysis
    - Concurrent connection testing
    - Performance criteria validation
    - Detailed JSON and HTML reporting

EXIT CODES:
    0 - All tests passed and performance criteria met
    1 - Tests failed or performance criteria not met
EOF
}

# 메인 실행 함수
main() {
    # 파라미터 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --alb-dns-name)
                ALB_DNS_NAME="$2"
                BASE_URL="http://$2"
                HEALTH_ENDPOINT="http://$2/health/deep"
                shift 2
                ;;
            --concurrent-users)
                CONCURRENT_USERS="$2"
                shift 2
                ;;
            --test-duration)
                TEST_DURATION="$2"
                shift 2
                ;;
            --ramp-up-time)
                RAMP_UP_TIME="$2"
                shift 2
                ;;
            --max-response-time)
                MAX_RESPONSE_TIME="$2"
                shift 2
                ;;
            --max-95th-percentile)
                MAX_95TH_PERCENTILE="$2"
                shift 2
                ;;
            --max-error-rate)
                MAX_ERROR_RATE="$2"
                shift 2
                ;;
            --min-throughput)
                MIN_THROUGHPUT="$2"
                shift 2
                ;;
            --output-dir)
                local output_dir="$2"
                REPORT_FILE="$output_dir/performance-test-report-$(date +%Y%m%d_%H%M%S).json"
                LOG_FILE="$output_dir/performance-test-$(date +%Y%m%d_%H%M%S).log"
                mkdir -p "$output_dir"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Blue-Green Deployment Performance Test"
    log_info "Target: $BASE_URL"
    
    # 테스트 실행
    check_prerequisites || exit 1
    test_connectivity || exit 1
    
    # 개별 엔드포인트 테스트
    for endpoint_name in "${!ENDPOINTS[@]}"; do
        test_endpoint_performance "$endpoint_name" "${ENDPOINTS[$endpoint_name]}" || true
    done
    
    # 종합 성능 테스트
    run_load_test || exit 1
    analyze_response_times || true
    test_concurrent_connections || true
    
    # 성능 기준 검증
    local validation_result=0
    validate_performance_criteria || validation_result=1
    
    # 보고서 생성
    generate_json_report
    generate_html_report
    
    # 결과 요약
    show_summary
    
    exit $validation_result
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi